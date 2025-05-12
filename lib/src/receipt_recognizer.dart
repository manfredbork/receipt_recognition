import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'receipt_core.dart';
import 'core/receipt_models.dart';
import 'receipt_optimizer.dart';
import 'receipt_parser.dart';

class ReceiptRecognizer {
  final TextRecognizer _textRecognizer;

  final Optimizer _optimizer;

  final bool _videoFeed;

  final Duration _scanInterval;

  final Duration _scanTimeout;

  final VoidCallback? _onScanTimeout;

  final Function(RecognizedReceipt)? _onScanComplete;

  final Function(Progress)? _onScanUpdate;

  DateTime? _initializedScan;

  DateTime? _lastScan;

  ReceiptRecognizer({
    TextRecognizer? textRecognizer,
    Optimizer? optimizer,
    script = TextRecognitionScript.latin,
    videoFeed = true,
    scanInterval = const Duration(milliseconds: 100),
    scanTimeout = const Duration(seconds: 30),
    onScanTimeout,
    onScanUpdate,
    onScanComplete,
  }) : _textRecognizer = textRecognizer ?? TextRecognizer(script: script),
       _optimizer = optimizer ?? ReceiptOptimizer(videoFeed: videoFeed),
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
      final addedPositions = List<RecognizedPosition>.from(
        optimizedReceipt.positions.where((p) => p.operation == Operation.added),
      );

      final updatedPositions = List<RecognizedPosition>.from(
        optimizedReceipt.positions.where(
          (p) => p.operation == Operation.updated,
        ),
      );

      int? estimatedPercentage;

      final numerator = optimizedReceipt.calculatedSum.value;
      final denominator = optimizedReceipt.sum?.value;

      if (denominator != null) {
        estimatedPercentage =
            numerator < denominator
                ? (numerator / denominator * 100).toInt()
                : (denominator / numerator * 100).toInt();
      }

      _initializedScan ??= now;
      _onScanUpdate?.call(
        Progress(
          addedPositions: addedPositions,
          updatedPositions: updatedPositions,
          estimatedPercentage: denominator != null ? estimatedPercentage : null,
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

  Future<void> close() async {
    _textRecognizer.close();
    _optimizer.close();
  }
}
