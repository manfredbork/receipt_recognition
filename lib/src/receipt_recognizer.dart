import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'receipt_core.dart';
import 'receipt_parser.dart';

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

  ReceiptRecognizer({
    TextRecognizer? textRecognizer,
    Optimizer? optimizer,
    TextRecognitionScript script = TextRecognitionScript.latin,
    bool videoFeed = true,
    Duration scanInterval = const Duration(milliseconds: 100),
    Duration scanTimeout = const Duration(seconds: 30),
    VoidCallback? onScanTimeout,
    Function(ScanProgress)? onScanUpdate,
    Function(RecognizedReceipt)? onScanComplete,
  }) : _textRecognizer = textRecognizer ?? TextRecognizer(script: script),
       _optimizer = optimizer ?? DefaultOptimizer(videoFeed: videoFeed),
       _videoFeed = videoFeed,
       _scanInterval = scanInterval,
       _scanTimeout = scanTimeout,
       _onScanTimeout = onScanTimeout,
       _onScanUpdate = onScanUpdate,
       _onScanComplete = onScanComplete;

  Future<RecognizedReceipt?> processImage(InputImage inputImage) async {
    final now = DateTime.now();

    if (_videoFeed &&
        _lastScan != null &&
        now.difference(_lastScan!) < _scanInterval) {
      return null;
    }

    _lastScan = now;

    final text = await _textRecognizer.processImage(inputImage);
    final receipt = ReceiptParser.processText(text);

    if (receipt == null) {
      return null;
    }

    final optimizedReceipt = _optimizer.optimize(receipt);

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

  Future<void> close() async {
    _textRecognizer.close();
    _optimizer.close();
  }
}
