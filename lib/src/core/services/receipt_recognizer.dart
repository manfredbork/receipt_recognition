import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// A high-level interface that manages receipt recognition from camera input.
///
/// Handles throttling of image streams, delegates OCR via ML Kit,
/// processes recognition in isolates, and applies optimization.
///
/// Emits callbacks during scanning and on successful receipt completion.
final class ReceiptRecognizer {
  final TextRecognizer _textRecognizer;
  final Optimizer _optimizer;
  final bool _videoFeed;
  final int _minValidScans;
  final Duration _scanInterval;
  final Duration _scanTimeout;
  final VoidCallback? _onScanTimeout;
  final Function(RecognizedReceipt)? _onScanComplete;
  final Function(ScanProgress)? _onScanUpdate;

  int _validScans;
  DateTime? _initializedScan;
  DateTime? _lastScan;

  /// Creates a [ReceiptRecognizer] with optional dependencies and behavior.
  ///
  /// You can provide a custom [Optimizer], control timeouts and scanning
  /// intervals, and respond to scan updates or finalization via callbacks.
  ReceiptRecognizer({
    TextRecognizer? textRecognizer,
    Optimizer? optimizer,
    TextRecognitionScript script = TextRecognitionScript.latin,
    bool videoFeed = true,
    int minValidScans = 5,
    Duration scanInterval = const Duration(milliseconds: 10),
    Duration scanTimeout = const Duration(seconds: 30),
    VoidCallback? onScanTimeout,
    Function(ScanProgress)? onScanUpdate,
    Function(RecognizedReceipt)? onScanComplete,
  }) : _textRecognizer = textRecognizer ?? TextRecognizer(script: script),
       _optimizer = optimizer ?? ReceiptOptimizer(),
       _videoFeed = videoFeed,
       _scanInterval = scanInterval,
       _scanTimeout = scanTimeout,
       _onScanTimeout = onScanTimeout,
       _onScanUpdate = onScanUpdate,
       _onScanComplete = onScanComplete,
       _minValidScans = minValidScans,
       _validScans = 0;

  /// Processes a single [InputImage] and returns a [RecognizedReceipt]
  /// if valid and complete, otherwise returns `null`.
  ///
  /// Skips processing if called too frequently within [_scanInterval].
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

    if (kDebugMode) {
      _printDebugInfo(optimizedReceipt);
    }

    if (optimizedReceipt.isValid) {
      _validScans++;
      if (_videoFeed && _validScans < _minValidScans) {
        return _handleIncompleteReceipt(now, optimizedReceipt);
      }
      return _handleValidReceipt(optimizedReceipt);
    } else {
      return _handleIncompleteReceipt(now, optimizedReceipt);
    }
  }

  int? _calculatePercentage(RecognizedReceipt optimizedReceipt) {
    final numerator = optimizedReceipt.calculatedSum.value;
    final denominator = optimizedReceipt.sum?.value;

    if (denominator != null) {
      return (numerator < denominator
              ? (numerator / denominator * 100)
              : (denominator / numerator * 100))
          .toInt();
    }
    return null;
  }

  /// Releases underlying ML resources (e.g. text recognizer and optimizer).
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
  ) {
    final addedPositions =
        receipt.positions.where((p) => p.operation == Operation.added).toList();
    final updatedPositions =
        receipt.positions
            .where((p) => p.operation == Operation.updated)
            .toList();
    final estimatedPercentage = _calculatePercentage(receipt);

    _initializedScan ??= now;
    _onScanUpdate?.call(
      ScanProgress(
        addedPositions: addedPositions,
        updatedPositions: updatedPositions,
        estimatedPercentage: estimatedPercentage,
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
}
