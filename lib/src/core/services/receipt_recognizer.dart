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
  final bool _singleScan;
  final int _minValidScans;
  final int _nearlyCompleteThreshold;
  final Duration _scanInterval;
  final Duration _scanTimeout;
  final Duration _scanCompleteDelay;
  final VoidCallback? _onScanTimeout;
  final Function(ScanProgress)? _onScanUpdate;
  final Function(RecognizedReceipt)? _onScanComplete;

  int _validScans;
  DateTime? _initializedScan;
  DateTime? _lastScan;

  /// Creates a receipt recognizer with configurable parameters and callbacks.
  ///
  /// Parameters:
  /// - [textRecognizer]: Custom text recognizer (uses default if not provided)
  /// - [optimizer]: Custom optimizer (uses default if not provided)
  /// - [script]: Script type for text recognition
  /// - [singleScan]: Whether to use single-scan mode or continuous scanning
  /// - [minValidScans]: Number of valid scans required for acceptance
  /// - [nearlyCompleteThreshold]: Percentage threshold for nearly complete receipts
  /// - [scanInterval]: Minimum time between scans
  /// - [scanTimeout]: Maximum time for a scanning session
  /// - [scanCompleteDelay]: Delay time when scan is completed
  /// - [onScanTimeout]: Called when scanning times out
  /// - [onScanUpdate]: Called with updates during scanning
  /// - [onScanComplete]: Called when a valid receipt is recognized
  ReceiptRecognizer({
    TextRecognizer? textRecognizer,
    Optimizer? optimizer,
    TextRecognitionScript script = TextRecognitionScript.latin,
    bool singleScan = false,
    int minValidScans = 3,
    int nearlyCompleteThreshold = 95,
    Duration scanInterval = const Duration(milliseconds: 50),
    Duration scanTimeout = const Duration(seconds: 30),
    Duration scanCompleteDelay = const Duration(milliseconds: 500),
    VoidCallback? onScanTimeout,
    Function(ScanProgress)? onScanUpdate,
    Function(RecognizedReceipt)? onScanComplete,
  }) : _textRecognizer = textRecognizer ?? TextRecognizer(script: script),
       _optimizer = optimizer ?? ReceiptOptimizer(),
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

    final receipt = await _recognizeReceipt(inputImage);
    if (receipt == null) return null;

    final optimizedReceipt = _optimizer.optimize(receipt);

    if (optimizedReceipt.isValid) {
      _validScans++;
    }

    final validation = _validateReceipt(optimizedReceipt);

    _printDebugInfo(optimizedReceipt, validation);

    final finalReceipt = _handleValidationResult(
      now,
      optimizedReceipt,
      validation,
    );

    if (validation.matchPercentage == 100) {
      return Future.delayed(_scanCompleteDelay, () => finalReceipt);
    }

    return finalReceipt;
  }

  Future<RecognizedReceipt?> _recognizeReceipt(InputImage inputImage) async {
    final text = await _textRecognizer.processImage(inputImage);
    return await ReceiptTextProcessor.processText(text);
  }

  RecognizedReceipt? _handleValidationResult(
    DateTime now,
    RecognizedReceipt receipt,
    ValidationResult validation,
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

  ValidationResult _validateReceipt(RecognizedReceipt receipt) {
    if (receipt.positions.isEmpty || receipt.sum == null) {
      return ValidationResult(
        status: ReceiptCompleteness.invalid,
        matchPercentage: 0,
        message: 'Receipt missing critical information',
      );
    }

    final percentage = _calculateMatchPercentage(receipt);

    if (percentage.round() == 100) {
      return ValidationResult(
        status: ReceiptCompleteness.complete,
        matchPercentage: 100,
        message: 'Receipt complete',
      );
    } else if (percentage >= _nearlyCompleteThreshold) {
      return ValidationResult(
        status: ReceiptCompleteness.nearlyComplete,
        matchPercentage: percentage.toInt(),
        message: 'Receipt nearly complete (${percentage.toInt()}%)',
      );
    } else {
      return ValidationResult(
        status: ReceiptCompleteness.incomplete,
        matchPercentage: percentage.toInt(),
        message: 'Receipt incomplete (${percentage.toInt()}%)',
      );
    }
  }

  double _calculateMatchPercentage(RecognizedReceipt receipt) {
    final totalValidScans = _singleScan ? 1 : _minValidScans;
    final calculatedNumerator = receipt.calculatedSum.value + _validScans;
    final calculatedDenominator = receipt.sum!.value + totalValidScans;
    return (calculatedNumerator < calculatedDenominator)
        ? (calculatedNumerator / calculatedDenominator * 100)
        : (calculatedDenominator / calculatedNumerator * 100);
  }

  /// Manually accepts a receipt that doesn't meet automatic validation criteria.
  ///
  /// Use this when a receipt is nearly complete and should be accepted despite
  /// validation discrepancies. Resets the optimizer and scan counters.
  RecognizedReceipt acceptReceipt(RecognizedReceipt receipt) {
    _initializedScan = null;
    _optimizer.init();
    _validScans = 0;
    return receipt;
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

  void _printDebugInfo(
    RecognizedReceipt optimizedReceipt,
    ValidationResult validation,
  ) {
    if (kDebugMode) {
      if (optimizedReceipt.positions.isNotEmpty) {
        print('🧾${'-' * 48}');
        print('✅ Validation status: ${validation.status}');
        print('💬 Message: ${validation.message}');
        print('🧾${'-' * 48}');
        print('🏪 Supermarket: ${optimizedReceipt.company?.value ?? 'N/A'}');
        const int totalWidth = 40;
        for (final position in optimizedReceipt.positions) {
          final product = position.product.text;
          final price = position.price.formattedValue;
          print('${'🛍️  $product'.padRight(totalWidth)}💰 $price');
        }
        print(
          '🧮 Calculated sum: ${optimizedReceipt.calculatedSum.formattedValue}',
        );
        print('🧾 Sum in receipt: ${optimizedReceipt.sum?.formattedValue}');
        print(
          '📌 Optimizer final sum label: ${optimizedReceipt.sumLabel?.formattedValue}',
        );
      }
    }
  }

  RecognizedReceipt _handleValidReceipt(
    RecognizedReceipt receipt,
    ValidationResult validationResult,
  ) {
    _handleOnScanUpdate(receipt, validationResult);

    _initializedScan = null;
    _optimizer.init();
    _onScanComplete?.call(receipt);
    _validScans = 0;
    return receipt;
  }

  RecognizedReceipt? _handleIncompleteReceipt(
    DateTime now,
    RecognizedReceipt receipt,
    ValidationResult validationResult,
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
    ValidationResult validationResult,
  ) {
    final positions =
        receipt.positions.where((p) => p.operation != Operation.none).toList();
    final addedPositions =
        positions.where((p) => p.operation == Operation.added).toList();
    final updatedPositions =
        positions.where((p) => p.operation == Operation.updated).toList();

    _onScanUpdate?.call(
      ScanProgress(
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
