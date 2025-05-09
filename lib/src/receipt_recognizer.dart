import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'receipt_models.dart';
import 'receipt_optimizer.dart';
import 'receipt_parser.dart';

class ReceiptRecognizer {
  final TextRecognizer _textRecognizer;

  final Optimizer _optimizer;

  final Duration _scanTimeout;

  final VoidCallback? _onScanTimeout;
  final Function(RecognizedReceipt)? _onScanComplete;
  final Function(RecognizedReceipt)? _onScanUpdate;

  DateTime? _lastScan;

  ReceiptRecognizer({
    TextRecognizer? textRecognizer,
    Optimizer? optimizer,
    script = TextRecognitionScript.latin,
    videoFeed = true,
    scanTimeout = const Duration(seconds: 30),
    onScanTimeout,
    onScanUpdate,
    onScanComplete,
  }) : _textRecognizer = textRecognizer ?? TextRecognizer(script: script),
       _optimizer = optimizer ?? ReceiptOptimizer(videoFeed: videoFeed),
       _scanTimeout = scanTimeout,
       _onScanTimeout = onScanTimeout,
       _onScanUpdate = onScanUpdate,
       _onScanComplete = onScanComplete;

  Future<RecognizedReceipt?> processImage(InputImage inputImage) async {
    final now = DateTime.now();
    final text = await _textRecognizer.processImage(inputImage);
    final receipt = ReceiptParser.processText(text);

    if (receipt == null) {
      return null;
    }

    final optimizedReceipt = _optimizer.optimize(receipt);

    if (optimizedReceipt.isValid) {
      _lastScan = null;
      _optimizer.init();
      _onScanComplete?.call(optimizedReceipt);

      return optimizedReceipt;
    } else {
      _lastScan ??= now;
      _onScanUpdate?.call(optimizedReceipt);

      if (now.difference(_lastScan ?? now) > _scanTimeout) {
        _lastScan = null;
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
