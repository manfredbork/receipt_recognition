import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';
import 'package:receipt_recognition/src/services/optimizer/index.dart';
import 'package:receipt_recognition/src/utils/configuration/index.dart';

/// Main orchestrator for recognizing receipts from images.
///
/// Coordinates OCR, parsing, optimization, validation, and progress callbacks.
final class ReceiptRecognizer {
  final TextRecognizer _textRecognizer;
  final Optimizer _optimizer;

  /// Parser options.
  final ReceiptOptions _options;

  final int _nearlyCompleteThreshold;
  final Duration _scanInterval;
  final Duration _scanTimeout;
  final Duration _scanCompleteDelay;
  final VoidCallback? _onScanTimeout;
  final Function(RecognizedScanProgress)? _onScanUpdate;
  final Function(RecognizedReceipt)? _onScanComplete;

  DateTime? _initializedScan;
  DateTime? _lastScan;
  RecognizedReceipt _lastReceipt;

  /// Creates a receipt recognizer with configurable parameters and callbacks.
  ReceiptRecognizer({
    TextRecognizer? textRecognizer,
    Optimizer? optimizer,
    TextRecognitionScript script = TextRecognitionScript.latin,
    ReceiptOptions? options,
    bool highPrecision = false,
    @Deprecated('No longer used; auto-completion is handled internally.')
    bool singleScan = false,
    @Deprecated('No longer used; stability/confirmation rules replace it.')
    int minValidScans = 3,
    int nearlyCompleteThreshold = 95,
    Duration scanInterval = const Duration(milliseconds: 100),
    Duration scanTimeout = const Duration(seconds: 30),
    Duration scanCompleteDelay = const Duration(milliseconds: 100),
    VoidCallback? onScanTimeout,
    Function(RecognizedScanProgress)? onScanUpdate,
    Function(RecognizedReceipt)? onScanComplete,
  }) : _textRecognizer = textRecognizer ?? TextRecognizer(script: script),
       _optimizer = optimizer ?? ReceiptOptimizer(),
       _options = options ?? ReceiptOptions.defaults(),
       _nearlyCompleteThreshold = nearlyCompleteThreshold,
       _scanInterval = scanInterval,
       _scanTimeout = scanTimeout,
       _scanCompleteDelay = scanCompleteDelay,
       _onScanTimeout = onScanTimeout,
       _onScanUpdate = onScanUpdate,
       _onScanComplete = onScanComplete,
       _lastReceipt = RecognizedReceipt.empty();

  /// Processes an image and returns a recognized receipt.
  Future<RecognizedReceipt> processImage(InputImage inputImage) async {
    final now = DateTime.now();
    if (_shouldThrottle(now)) return _lastReceipt;

    _lastScan = now;

    final receipt = await _recognizeReceipt(inputImage, _options);
    final optimized = _optimizer.optimize(receipt, _options);
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
    init();
    return receipt;
  }

  /// Reinitializes the recognizer for a fresh scan session.
  void init() {
    _initializedScan = null;
    _lastScan = null;
    _lastReceipt = RecognizedReceipt.empty();
    _optimizer.init();
  }

  /// Releases all resources used by the recognizer.
  Future<void> close() async {
    _textRecognizer.close();
    _optimizer.close();
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
    _initializedScan ??= now;
    if (_initializedScan != null &&
        now.difference(_initializedScan!) >= _scanTimeout) {
      init();
      _onScanTimeout?.call();
    }
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
