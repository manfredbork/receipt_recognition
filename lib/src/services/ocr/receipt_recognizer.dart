import 'dart:async';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';
import 'package:receipt_recognition/src/services/optimizer/index.dart';
import 'package:receipt_recognition/src/utils/configuration/index.dart';

/// Main orchestrator for recognizing receipts from images.
///
/// Coordinates OCR, parsing, optimization, validation, and progress callbacks.
final class ReceiptRecognizer {
  /// OCR engine used to extract text from images.
  final TextRecognizer _textRecognizer;

  /// Aggregator that stabilizes and optimizes recognition across frames.
  final Optimizer _optimizer;

  /// Tunable options for OCR, parsing, and validation behavior.
  final ReceiptOptions _options;

  /// If true, optimizations assume a single-frame scan (no cross-frame stabilization).
  final bool _singleScan;

  /// Percentage at/above which a receipt is treated as nearly complete.
  final int _nearlyCompleteThreshold;

  /// Minimum time gap enforced between consecutive scans (throttle).
  final Duration _scanInterval;

  /// Maximum duration allowed for a scan session before timing out.
  final Duration _scanTimeout;

  /// Optional delay before emitting a completed receipt result.
  final Duration _scanCompleteDelay;

  /// Callback invoked on intermediate recognition/validation updates.
  final Function(RecognizedScanProgress)? _onScanUpdate;

  /// Callback invoked when a receipt is finalized and accepted.
  final Function(RecognizedReceipt)? _onScanComplete;

  /// Callback invoked when a scan session reaches timeout.
  final Function(RecognizedReceipt)? _onScanTimeout;

  /// Timer to enforce scan timeout even if no further frames arrive.
  Timer? _scanTimeoutTimer;

  /// Whether a full reinit is needed.
  bool _shouldInitialize = false;

  /// Timestamp when the current scan session was initialized.
  DateTime? _initializedScan;

  /// Timestamp of the most recent scan attempt.
  DateTime? _lastScan;

  /// Latest recognized/optimized receipt snapshot.
  RecognizedReceipt _lastReceipt;

  /// Creates a receipt recognizer with configurable parameters and callbacks.
  ReceiptRecognizer({
    TextRecognizer? textRecognizer,
    Optimizer? optimizer,
    TextRecognitionScript script = TextRecognitionScript.latin,
    ReceiptOptions? options,
    bool singleScan = false,
    int nearlyCompleteThreshold = 95,
    Duration scanInterval = const Duration(milliseconds: 50),
    Duration scanTimeout = const Duration(seconds: 20),
    Duration scanCompleteDelay = Duration.zero,
    Function(RecognizedScanProgress)? onScanUpdate,
    Function(RecognizedReceipt)? onScanComplete,
    Function(RecognizedReceipt)? onScanTimeout,
  }) : _textRecognizer = textRecognizer ?? TextRecognizer(script: script),
       _optimizer = optimizer ?? ReceiptOptimizer(),
       _options = options ?? _defaultOptionsForScript(script),
       _singleScan = singleScan,
       _nearlyCompleteThreshold = nearlyCompleteThreshold,
       _scanInterval = scanInterval,
       _scanTimeout = scanTimeout,
       _scanCompleteDelay = scanCompleteDelay,
       _onScanUpdate = onScanUpdate,
       _onScanComplete = onScanComplete,
       _onScanTimeout = onScanTimeout,
       _lastReceipt = RecognizedReceipt.empty();

  /// Returns the default [ReceiptOptions] for the given [script].
  static ReceiptOptions _defaultOptionsForScript(
    TextRecognitionScript script,
  ) =>
      switch (script) {
        TextRecognitionScript.japanese => ReceiptOptions.japanese(),
        _ => ReceiptOptions.defaults(),
      };

  /// Processes an image and returns a recognized receipt.
  Future<RecognizedReceipt> processImage(InputImage inputImage) async {
    _initializeIfNeeded();

    final now = DateTime.now();
    if (_shouldThrottle(now)) return _lastReceipt;
    _lastScan = now;

    final receipt = await _recognizeReceipt(inputImage, _options);

    final optimized = _optimizer.optimize(
      receipt,
      _options,
      singleScan: _singleScan,
    );

    final validation = _validateReceipt(optimized);
    final accepted = _handleValidationResult(now, optimized, validation);

    if (accepted.isValid && accepted.isConfirmed) {
      _lastReceipt = accepted;
      return Future.delayed(_scanCompleteDelay, () => accepted);
    }

    _lastReceipt = optimized;

    return optimized;
  }

  /// Manually accepts a receipt and resets internal state.
  RecognizedReceipt acceptReceipt(RecognizedReceipt receipt) {
    _optimizer.accept(receipt, _options);
    init();
    return receipt;
  }

  /// Marks the recognizer for reinitialization on next recognition.
  void init() {
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
    _shouldInitialize = true;
  }

  /// Releases all resources used by the recognizer.
  Future<void> close() async {
    _textRecognizer.close();
    _optimizer.close();
  }

  /// Clears caches and resets internal state if flagged.
  void _initializeIfNeeded() {
    if (!_shouldInitialize) return;
    _initializedScan = null;
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
    _lastScan = null;
    _lastReceipt = RecognizedReceipt.empty();
    _optimizer.init();
    _shouldInitialize = false;
  }

  /// Starts a one-time timeout timer that fires even if no further scan frames arrive.
  void _scheduleTimeoutIfNeeded(DateTime now) {
    _initializedScan ??= now;
    _scanTimeoutTimer ??= Timer(_scanTimeout, () {
      final receipt = _lastReceipt;
      init();
      _onScanTimeout?.call(receipt);
    });
  }

  /// Runs OCR + parse for [inputImage] using [options].
  Future<RecognizedReceipt> _recognizeReceipt(
    InputImage inputImage,
    ReceiptOptions options,
  ) async {
    final text = await _textRecognizer.processImage(inputImage);
    return ReceiptTextProcessor.processText(text, options);
  }

  /// Routes based on [validation] to either final acceptance or continued scanning.
  RecognizedReceipt _handleValidationResult(
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

  /// Computes validation result for [receipt].
  ReceiptValidationResult _validateReceipt(RecognizedReceipt receipt) {
    if (receipt.positions.isEmpty || receipt.total == null) {
      return const ReceiptValidationResult(
        status: ReceiptCompleteness.invalid,
        matchPercentage: 0,
        message: 'Receipt missing critical information',
      );
    }

    final pct = _calculateMatchPercentage(receipt);
    if (pct == 100) {
      return const ReceiptValidationResult(
        status: ReceiptCompleteness.complete,
        matchPercentage: 100,
        message: 'Receipt complete',
      );
    }
    if (pct >= _nearlyCompleteThreshold) {
      return ReceiptValidationResult(
        status: ReceiptCompleteness.nearlyComplete,
        matchPercentage: pct,
        message: 'Receipt nearly complete ($pct%)',
      );
    }
    return ReceiptValidationResult(
      status: ReceiptCompleteness.incomplete,
      matchPercentage: pct,
      message: 'Receipt incomplete ($pct%)',
    );
  }

  /// Calculates the match percentage between calculated and recognized totals.
  int _calculateMatchPercentage(RecognizedReceipt receipt) {
    final calc = receipt.calculatedTotal.value.toDouble();
    final decl = (receipt.total?.value ?? 0).toDouble();
    if (calc <= 0 || decl <= 0) return 0;

    final ratio = calc < decl ? (calc / decl) : (decl / calc);
    final pct = (ratio * 100).clamp(0.0, 100.0).toInt();
    return pct;
  }

  /// Returns whether a scan should be throttled due to [_scanInterval].
  bool _shouldThrottle(DateTime now) =>
      _lastScan != null && now.difference(_lastScan!) < _scanInterval;

  /// Handles a valid receipt: emits updates, possibly completes the session.
  RecognizedReceipt _handleValidReceipt(
    RecognizedReceipt receipt,
    ReceiptValidationResult validation,
  ) {
    _handleOnScanUpdate(receipt, validation);
    if (receipt.isValid && receipt.isConfirmed) {
      init();
      _onScanComplete?.call(receipt);
    }
    return receipt;
  }

  /// Handles an incomplete/invalid receipt: updates progress and enforces timeout.
  RecognizedReceipt _handleIncompleteReceipt(
    DateTime now,
    RecognizedReceipt receipt,
    ReceiptValidationResult validation,
  ) {
    _handleOnScanUpdate(receipt, validation);
    _lastReceipt = receipt;
    _scheduleTimeoutIfNeeded(now);
    return receipt;
  }

  /// Emits a progress update via [_onScanUpdate].
  void _handleOnScanUpdate(
    RecognizedReceipt receipt,
    ReceiptValidationResult validation,
  ) {
    final changed =
        receipt.positions.where((p) => p.operation != Operation.none).toList();
    final added = changed.where((p) => p.operation == Operation.added).toList();
    final updated =
        changed.where((p) => p.operation == Operation.updated).toList();

    _onScanUpdate?.call(
      RecognizedScanProgress(
        positions: changed,
        addedPositions: added,
        updatedPositions: updated,
        validationResult: validation,
        estimatedPercentage: validation.matchPercentage,
        mergedReceipt: receipt,
      ),
    );
  }
}
