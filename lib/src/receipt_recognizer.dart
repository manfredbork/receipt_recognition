import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'receipt_models.dart';
import 'receipt_optimizer.dart';
import 'receipt_parser.dart';

/// A receipt recognizer that scans a receipt from [InputImage].
class ReceiptRecognizer {
  /// Use [TextRecognizer] from Google's ML Kit.
  final TextRecognizer _textRecognizer;

  /// Use any optimizer implementing [Optimizer].
  final Optimizer _optimizer;

  /// Duration for scan timeout
  final Duration _scanTimeout;

  /// Different callback methods
  final VoidCallback? _onScanTimeout;
  final Function(RecognizedReceipt)? _onScanComplete;
  final Function(RecognizedReceipt)? _onScanUpdate;

  /// Time of last scan
  DateTime? _lastScan;

  /// Constructor to create an instance of [ReceiptRecognizer].
  ReceiptRecognizer({
    TextRecognizer? textRecognizer,
    Optimizer? optimizer,
    videoFeed = true,
    scanTimeout = const Duration(seconds: 30),
    onScanTimeout,
    onScanUpdate,
    onScanComplete,
  }) : _textRecognizer =
           textRecognizer ??
           TextRecognizer(script: TextRecognitionScript.latin),
       _optimizer =
           optimizer ?? videoFeed
               ? ReceiptOptimizer()
               : ReceiptOptimizer(minScansForTrustworthiness: 1),
       _scanTimeout = scanTimeout,
       _onScanTimeout = onScanTimeout,
       _onScanUpdate = onScanUpdate,
       _onScanComplete = onScanComplete;

  /// Processes the [InputImage]. Returns a [RecognizedReceipt].
  Future<RecognizedReceipt?> processImage(InputImage inputImage) async {
    final now = DateTime.now();
    final text = await _textRecognizer.processImage(inputImage);
    final receipt = ReceiptParser.processText(text);

    if (receipt == null) return null;

    final optimizedReceipt = _optimizer.optimize(receipt);

    if (optimizedReceipt.isValid) {
      _lastScan = null;
      _optimizer.init();
      _onScanComplete?.call(optimizedReceipt);

      return optimizedReceipt;
    } else {
      _onScanUpdate?.call(optimizedReceipt);

      _lastScan ??= now;

      if (now.difference(_lastScan ?? now) > _scanTimeout) {
        _lastScan = null;
        _optimizer.init();
        _onScanTimeout?.call();
      }

      return null;
    }
  }

  /// Closes the scanner and releases its resources.
  Future<void> close() async {
    _textRecognizer.close();
    _optimizer.close();
  }
}
