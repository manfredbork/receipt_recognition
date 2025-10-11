import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Main class for recognizing receipts from images.
///
/// Orchestrates the OCR and parsing processes, manages optimizations,
/// and provides callbacks for scan progress and completion.
final class ReceiptRecognizer {
  final TextRecognizer _textRecognizer;
  final Optimizer _optimizer;

  /// Typed options used by the parser.
  final ReceiptOptions _options;

  final bool _singleScan;
  final int _minValidScans;
  final int _nearlyCompleteThreshold;
  final Duration _scanInterval;
  final Duration _scanTimeout;
  final Duration _scanCompleteDelay;
  final VoidCallback? _onScanTimeout;
  final Function(RecognizedScanProgress)? _onScanUpdate;
  final Function(RecognizedReceipt)? _onScanComplete;

  int _validScans;
  DateTime? _initializedScan;
  DateTime? _lastScan;

  /// Creates a receipt recognizer with configurable parameters and callbacks.
  ///
  /// Parameters:
  /// - [textRecognizer]: Optional custom text recognizer (defaults to ML Kit Latin script).
  /// - [optimizer]: Optional custom optimizer (defaults to [ReceiptOptimizer]).
  /// - [script]: Script type for text recognition.
  /// - [options]: Optional parsing options. If omitted, [ReceiptOptions.empty()]
  ///   is used and built-in defaults ([ReceiptPatterns]) will apply.
  /// - [singleScan]: Whether to perform only a single scan or keep scanning until valid.
  /// - [highPrecision]: Enables larger cache sizes and stricter thresholds
  ///   in the optimizer for improved accuracy on difficult receipts.
  /// - [minValidScans]: Number of valid scans required before a receipt is accepted.
  /// - [nearlyCompleteThreshold]: Percentage threshold for considering a receipt nearly complete.
  /// - [scanInterval]: Minimum time between scans.
  /// - [scanTimeout]: Maximum duration for a scanning session before timeout.
  /// - [scanCompleteDelay]: Delay before returning the final recognized receipt.
  /// - [onScanTimeout]: Callback invoked when scanning times out.
  /// - [onScanUpdate]: Callback invoked with scan progress updates.
  /// - [onScanComplete]: Callback invoked when a valid receipt is recognized.
  ReceiptRecognizer({
    TextRecognizer? textRecognizer,
    Optimizer? optimizer,
    TextRecognitionScript script = TextRecognitionScript.latin,
    ReceiptOptions? options,
    bool singleScan = false,
    bool highPrecision = false,
    int minValidScans = 3,
    int nearlyCompleteThreshold = 95,
    Duration scanInterval = const Duration(milliseconds: 100),
    Duration scanTimeout = const Duration(seconds: 30),
    Duration scanCompleteDelay = const Duration(milliseconds: 100),
    VoidCallback? onScanTimeout,
    Function(RecognizedScanProgress)? onScanUpdate,
    Function(RecognizedReceipt)? onScanComplete,
  }) : _textRecognizer = textRecognizer ?? TextRecognizer(script: script),
       _optimizer = optimizer ?? ReceiptOptimizer(highPrecision: highPrecision),
       _options = options ?? ReceiptOptions.empty(),
       _singleScan = singleScan,
       _minValidScans = minValidScans,
       _nearlyCompleteThreshold = nearlyCompleteThreshold,
       _scanInterval = scanInterval,
       _scanTimeout = scanTimeout,
       _scanCompleteDelay = scanCompleteDelay,
       _onScanTimeout = onScanTimeout,
       _onScanUpdate = onScanUpdate,
       _onScanComplete = onScanComplete,
       _validScans = 0;

  /// Processes an image and attempts to recognize a receipt from it.
  ///
  /// This is the main entry point for receipt recognition.
  /// Returns a recognized receipt if validation passes, or null otherwise.
  Future<RecognizedReceipt?> processImage(InputImage inputImage) async {
    final now = DateTime.now();

    if (_shouldThrottle(now)) {
      return null;
    }

    _lastScan = now;

    final receipt = await _recognizeReceipt(inputImage, _options);

    final optimizedReceipt = _optimizer.optimize(receipt);

    if (optimizedReceipt.isValid) {
      _validScans++;
    }

    final validation = _validateReceipt(optimizedReceipt);

    final finalReceipt = _handleValidationResult(
      now,
      optimizedReceipt,
      validation,
    );

    if (finalReceipt != null && finalReceipt.isValid) {
      ReceiptLogger.logReceipt(finalReceipt, validation);
      return Future.delayed(_scanCompleteDelay, () => finalReceipt);
    } else {
      ReceiptLogger.logReceipt(optimizedReceipt, validation);
    }

    return _singleScan ? optimizedReceipt : null;
  }

  Future<RecognizedReceipt> _recognizeReceipt(
    InputImage inputImage,
    ReceiptOptions options,
  ) async {
    final text = await _textRecognizer.processImage(inputImage);
    return await ReceiptTextProcessor.processText(text, options);
  }

  RecognizedReceipt? _handleValidationResult(
    DateTime now,
    RecognizedReceipt receipt,
    ReceiptValidationResult validation,
  ) {
    switch (validation.status) {
      case ReceiptCompleteness.complete:
        return _handleValidReceipt(receipt, validation);

      case ReceiptCompleteness.nearlyComplete:
      case ReceiptCompleteness.incomplete:
      case ReceiptCompleteness.invalid:
        return _handleIncompleteReceipt(now, receipt, validation);
    }
  }

  ReceiptValidationResult _validateReceipt(RecognizedReceipt receipt) {
    if (receipt.positions.isEmpty || receipt.sum == null) {
      return ReceiptValidationResult(
        status: ReceiptCompleteness.invalid,
        matchPercentage: 0,
        message: 'Receipt missing critical information',
      );
    }

    final percentage = _calculateMatchPercentage(receipt);

    if (percentage == 100) {
      return ReceiptValidationResult(
        status: ReceiptCompleteness.complete,
        matchPercentage: 100,
        message: 'Receipt complete',
      );
    } else if (percentage >= _nearlyCompleteThreshold) {
      return ReceiptValidationResult(
        status: ReceiptCompleteness.nearlyComplete,
        matchPercentage: percentage,
        message: 'Receipt nearly complete ($percentage%)',
      );
    } else {
      return ReceiptValidationResult(
        status: ReceiptCompleteness.incomplete,
        matchPercentage: percentage,
        message: 'Receipt incomplete ($percentage%)',
      );
    }
  }

  int _calculateMatchPercentage(RecognizedReceipt receipt) {
    final calculatedNumerator = receipt.calculatedSum.value;
    final calculatedDenominator = receipt.sum!.value;
    final calculateRatio =
        calculatedNumerator < calculatedDenominator
            ? calculatedNumerator / calculatedDenominator * 100
            : calculatedDenominator / calculatedNumerator * 100;
    return calculateRatio.clamp(0, 100).toInt() - _minValidScans + _validScans;
  }

  /// Manually accepts a receipt that doesn't meet automatic validation criteria.
  ///
  /// Use this when a receipt is nearly complete and should be accepted despite
  /// validation discrepancies. Resets the optimizer and scan counters.
  RecognizedReceipt acceptReceipt(RecognizedReceipt receipt) {
    init();
    return receipt;
  }

  /// Reinitializes the recognizer for a new scan session.
  ///
  /// Clears internal state, resets scan counters, and reinitializes the optimizer.
  /// Call this before starting a new receipt scan to avoid carrying over data
  /// from a previous session.
  void init() {
    _initializedScan = null;
    _lastScan = null;
    _validScans = 0;
    _optimizer.init();
  }

  /// Releases all resources used by the recognizer.
  ///
  /// Must be called when the recognizer is no longer needed.
  Future<void> close() async {
    _textRecognizer.close();
    _optimizer.close();
  }

  bool _shouldThrottle(DateTime now) {
    if (!_singleScan &&
        _lastScan != null &&
        now.difference(_lastScan!) < _scanInterval) {
      return true;
    }
    return false;
  }

  RecognizedReceipt _handleValidReceipt(
    RecognizedReceipt receipt,
    ReceiptValidationResult validationResult,
  ) {
    _handleOnScanUpdate(receipt, validationResult);

    if (_validScans >= _minValidScans || _singleScan) {
      _initializedScan = null;
      _optimizer.init();
      _onScanComplete?.call(receipt);
    }
    return receipt;
  }

  RecognizedReceipt? _handleIncompleteReceipt(
    DateTime now,
    RecognizedReceipt receipt,
    ReceiptValidationResult validationResult,
  ) {
    _handleOnScanUpdate(receipt, validationResult);

    _initializedScan ??= now;

    if (_initializedScan != null &&
        now.difference(_initializedScan!) >= _scanTimeout) {
      _initializedScan = null;
      _optimizer.init();
      _onScanTimeout?.call();
      _validScans = 0;
    }

    return null;
  }

  void _handleOnScanUpdate(
    RecognizedReceipt receipt,
    ReceiptValidationResult validationResult,
  ) {
    final positions =
        receipt.positions.where((p) => p.operation != Operation.none).toList();
    final addedPositions =
        positions.where((p) => p.operation == Operation.added).toList();
    final updatedPositions =
        positions.where((p) => p.operation == Operation.updated).toList();

    _onScanUpdate?.call(
      RecognizedScanProgress(
        positions: positions,
        addedPositions: addedPositions,
        updatedPositions: updatedPositions,
        validationResult: validationResult,
        estimatedPercentage: validationResult.matchPercentage,
        mergedReceipt: receipt,
      ),
    );
  }
}
