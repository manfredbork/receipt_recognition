import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

final class ReceiptRecognizer {
  final TextRecognizer _textRecognizer;
  final Optimizer _optimizer;
  final bool _videoFeed;
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
    bool videoFeed = true,
    int minValidScans = 3,
    int nearlyCompleteThreshold = 95,
    Duration scanInterval = const Duration(milliseconds: 10),
    Duration scanTimeout = const Duration(seconds: 60),
    VoidCallback? onScanTimeout,
    Function(ScanProgress)? onScanUpdate,
    Function(RecognizedReceipt)? onScanComplete,
  }) : _textRecognizer = textRecognizer ?? TextRecognizer(script: script),
       _optimizer = optimizer ?? ReceiptOptimizer(),
       _videoFeed = videoFeed,
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
      _printDebugInfo(optimizedReceipt);
      print('Validation status: ${validation.status}');
      print('Message: ${validation.message}');
    }

    switch (validation.status) {
      case ReceiptCompleteness.complete:
        _validScans++;
        if (_videoFeed && _validScans < _minValidScans) {
          return _handleIncompleteReceipt(now, optimizedReceipt, validation);
        }
        return _handleValidReceipt(optimizedReceipt);

      case ReceiptCompleteness.nearlyComplete:
      case ReceiptCompleteness.incomplete:
      case ReceiptCompleteness.invalid:
        return _handleIncompleteReceipt(now, optimizedReceipt, validation);
    }
  }

  Future<void> close() async {
    _textRecognizer.close();
    _optimizer.close();
  }

  bool _shouldThrottle(DateTime now) {
    if (_videoFeed &&
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
        print('Recognized sum: ${optimizedReceipt.sum?.formattedValue}');
        print(
          'Calculated sum: ${optimizedReceipt.calculatedSum.formattedValue}',
        );
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
      final bestMatch = ReceiptNormalizer.normalizeByAllValues(
        _optimizer.possibleValues(position.product),
      );
      normalizedPositions.add(
        position.copyWith(product: position.product.copyWith(value: bestMatch)),
      );
    }
    return receipt.copyWith(positions: normalizedPositions);
  }

  // Method to validate a receipt using the configurable threshold
  ValidationResult validateReceipt(RecognizedReceipt receipt) {
    // Basic validation checks...

    // Calculate match percentage
    final calculatedSum = receipt.calculatedSum.value;
    final declaredSum = receipt.sum!.value;
    final percentage =
        (calculatedSum < declaredSum)
            ? (calculatedSum / declaredSum * 100)
            : (declaredSum / calculatedSum * 100);

    if (percentage == 100) {
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

  RecognizedReceipt acceptReceipt(RecognizedReceipt receipt) {
    _initializedScan = null;
    _optimizer.init();
    _validScans = 0;
    return _normalizeReceipt(receipt);
  }
}
