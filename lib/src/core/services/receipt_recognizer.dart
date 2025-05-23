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
  final Duration _scanInterval;
  final Duration _scanTimeout;
  final VoidCallback? _onScanTimeout;
  final Function(RecognizedReceipt)? _onScanComplete;
  final Function(ScanProgress)? _onScanUpdate;

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
    Duration scanInterval = const Duration(milliseconds: 10),
    Duration scanTimeout = const Duration(seconds: 30),
    VoidCallback? onScanTimeout,
    Function(ScanProgress)? onScanUpdate,
    Function(RecognizedReceipt)? onScanComplete,
  }) : _textRecognizer = textRecognizer ?? TextRecognizer(script: script),
       _optimizer = optimizer ?? ReceiptOptimizer(videoFeed: videoFeed),
       _videoFeed = videoFeed,
       _scanInterval = scanInterval,
       _scanTimeout = scanTimeout,
       _onScanTimeout = onScanTimeout,
       _onScanUpdate = onScanUpdate,
       _onScanComplete = onScanComplete;

  /// Processes a single [InputImage] and returns a [RecognizedReceipt]
  /// if valid and complete, otherwise returns `null`.
  ///
  /// Skips processing if called too frequently within [_scanInterval].
  Future<RecognizedReceipt?> processImage(InputImage inputImage) async {
    final now = DateTime.now();

    if (_videoFeed &&
        _lastScan != null &&
        now.difference(_lastScan!) < _scanInterval) {
      return null;
    }

    _lastScan = now;

    final text = await _textRecognizer.processImage(inputImage);
    final receipt = await processTextIsolate(text);

    if (receipt == null) return null;

    final optimizedReceipt = _optimizer.optimize(receipt);

    if (kDebugMode) {
      if (optimizedReceipt.positions.isNotEmpty) {
        print('-' * 50);
        print('Supermarket: ${optimizedReceipt.company?.value ?? 'N/A'}');
        for (final position in optimizedReceipt.positions) {
          print(
            '${position.product.value} ${position.price.formattedValue} ${position.trustworthiness}',
          );
        }
        print('Recognized sum: ${optimizedReceipt.sum?.formattedValue}');
        print(
          'Calculated sum: ${optimizedReceipt.calculatedSum.formattedValue}',
        );
      }
    }

    if (optimizedReceipt.isValid) {
      _initializedScan = null;
      _optimizer.init();
      _onScanComplete?.call(optimizedReceipt);
      return optimizedReceipt;
    } else {
      final addedPositions =
          optimizedReceipt.positions
              .where((p) => p.operation == Operation.added)
              .toList();
      final updatedPositions =
          optimizedReceipt.positions
              .where((p) => p.operation == Operation.updated)
              .toList();
      final estimatedPercentage = _calculatePercentage(optimizedReceipt);

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
      }

      return null;
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
}
