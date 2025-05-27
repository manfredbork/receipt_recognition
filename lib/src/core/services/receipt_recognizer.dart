import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

final class ReceiptRecognizer {
  final TextRecognizer _textRecognizer;
  final Optimizer _optimizer;
  final bool _singleScan;
  final int _minValidScans;
  final int _nearlyCompleteThreshold;
  final Duration _scanInterval;
  final Duration _scanTimeout;
  final VoidCallback? _onScanTimeout;
  final Function(RecognizedReceipt)? _onScanComplete;
  final Function(ScanProgress)? _onScanUpdate;

  int _validScans;
  DateTime? _initializedScan;
  DateTime? _lastScan;

  ReceiptRecognizer({
    TextRecognizer? textRecognizer,
    Optimizer? optimizer,
    TextRecognitionScript script = TextRecognitionScript.latin,
    bool singleScan = false,
    int minValidScans = 3,
    int nearlyCompleteThreshold = 95,
    Duration scanInterval = const Duration(milliseconds: 10),
    Duration scanTimeout = const Duration(seconds: 30),
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
       _onScanTimeout = onScanTimeout,
       _onScanUpdate = onScanUpdate,
       _onScanComplete = onScanComplete,
       _validScans = 0;

  Future<RecognizedReceipt?> processImage(InputImage inputImage) async {
    final now = DateTime.now();

    if (_shouldThrottle(now)) {
      return null;
    }

    _lastScan = now;

    final text = await _textRecognizer.processImage(inputImage);
    final receipt = await ReceiptTextProcessor.processText(text);

    if (receipt == null) return null;

    final optimizedReceipt = _optimizer.optimize(receipt);
    final validation = validateReceipt(optimizedReceipt);

    if (kDebugMode) {
      print('-' * 50);
      print('Validation status: ${validation.status}');
      print('Message: ${validation.message}');
      _printDebugInfo(optimizedReceipt);
    }

    switch (validation.status) {
      case ReceiptCompleteness.complete:
        _validScans++;
        if (!_singleScan && _validScans < _minValidScans) {
          return _handleIncompleteReceipt(now, optimizedReceipt, validation);
        }
        return _handleValidReceipt(optimizedReceipt);

      case ReceiptCompleteness.nearlyComplete:
      case ReceiptCompleteness.incomplete:
      case ReceiptCompleteness.invalid:
        return _handleIncompleteReceipt(now, optimizedReceipt, validation);
    }
  }

  RecognizedReceipt acceptReceipt(RecognizedReceipt receipt) {
    _initializedScan = null;
    _optimizer.init();
    _validScans = 0;
    return _normalizeReceipt(receipt);
  }

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

  void _printDebugInfo(RecognizedReceipt optimizedReceipt) {
    if (kDebugMode) {
      if (optimizedReceipt.positions.isNotEmpty) {
        print('-' * 50);
        print('Supermarket: ${optimizedReceipt.company?.value ?? 'N/A'}');
        for (final position in optimizedReceipt.positions) {
          print(
            '${position.product.formattedValue} ${position.price.formattedValue}',
          );
        }
        print(
          'Calculated sum: ${optimizedReceipt.calculatedSum.formattedValue}',
        );
        print('Recognized sum: ${optimizedReceipt.sum?.formattedValue}');
      }
    }
  }

  RecognizedReceipt _handleValidReceipt(RecognizedReceipt receipt) {
    _initializedScan = null;
    _optimizer.init();
    _onScanComplete?.call(receipt);
    _validScans = 0;
    return _normalizeReceipt(receipt);
  }

  RecognizedReceipt? _handleIncompleteReceipt(
    DateTime now,
    RecognizedReceipt receipt,
    ValidationResult validation,
  ) {
    final addedPositions =
        receipt.positions.where((p) => p.operation == Operation.added).toList();
    final updatedPositions =
        receipt.positions
            .where((p) => p.operation == Operation.updated)
            .toList();

    _initializedScan ??= now;
    _onScanUpdate?.call(
      ScanProgress(
        addedPositions: addedPositions,
        updatedPositions: updatedPositions,
        estimatedPercentage: validation.matchPercentage,
        mergedReceipt: receipt,
        nearlyComplete: validation.status == ReceiptCompleteness.nearlyComplete,
      ),
    );

    if (_initializedScan != null &&
        now.difference(_initializedScan!) >= _scanTimeout) {
      _initializedScan = null;
      _optimizer.init();
      _onScanTimeout?.call();
      _validScans = 0;
    }

    return null;
  }

  RecognizedReceipt _normalizeReceipt(RecognizedReceipt receipt) {
    final List<RecognizedPosition> normalizedPositions = [];
    for (final position in receipt.positions) {
      final bestMatch = ReceiptNormalizer.normalizeByAlternativeTexts(
        position.product.value,
        _optimizer.possibleProductValues(position.product),
      );
      normalizedPositions.add(
        position.copyWith(product: position.product.copyWith(value: bestMatch)),
      );
    }
    return receipt.copyWith(positions: normalizedPositions);
  }

  ValidationResult validateReceipt(RecognizedReceipt receipt) {
    if (receipt.positions.isEmpty || receipt.sum == null) {
      return ValidationResult(
        status: ReceiptCompleteness.invalid,
        matchPercentage: 0,
        message: 'Receipt missing critical information',
      );
    }

    final calculatedSum = receipt.calculatedSum.value;
    final declaredSum = receipt.sum!.value;
    final percentage =
        (calculatedSum < declaredSum)
            ? (calculatedSum / declaredSum * 100)
            : (declaredSum / calculatedSum * 100);

    if (receipt.isValid) {
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
}
