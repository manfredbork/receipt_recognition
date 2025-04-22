import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

import 'receipt_models.dart';
import 'receipt_parser.dart';

/// A receipt recognizer that scans a receipt from [InputImage].
class ReceiptRecognizer {
  /// Uses [TextRecognizer] from Google's ML Kit.
  final TextRecognizer _textRecognizer;

  /// Uses package internal [ReceiptParser].
  final ReceiptParser _receiptParser;

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
    script = TextRecognitionScript.latin,
    scanTimeout = const Duration(seconds: 15),
    onScanTimeout,
    onScanUpdate,
    onScanComplete,
  }) : _textRecognizer = TextRecognizer(script: script),
       _receiptParser = ReceiptParser(),
       _scanTimeout = scanTimeout,
       _onScanTimeout = onScanTimeout,
       _onScanUpdate = onScanUpdate,
       _onScanComplete = onScanComplete;

  /// Processes the [InputImage]. Returns a [RecognizedReceipt].
  Future<RecognizedReceipt?> processImage(InputImage inputImage) async {
    final now = DateTime.now();
    final text = await _textRecognizer.processImage(inputImage);
    final entities = _receiptParser.processText(text);
    final receipt = _receiptParser.buildReceipt(entities);
    _lastScan ??= now;
    if (now.difference(_lastScan ?? now) > _scanTimeout) {
      _onScanTimeout?.call();
      _lastScan = null;
    }
    if (receipt == null) return null;
    if (_isValidReceipt(receipt)) {
      _onScanComplete?.call(receipt);
      _lastScan = null;
      return receipt;
    } else {
      _onScanUpdate?.call(receipt);
      return null;
    }
  }

  /// Closes the scanner and releases its resources.
  Future<void> close() => _textRecognizer.close();

  /// Checks if [RecognizedReceipt] is valid. Returns a [bool].
  bool _isValidReceipt(RecognizedReceipt receipt) {
    return _sum(receipt.positions) == receipt.sum?.formattedValue;
  }

  /// Adds up prices of positions and formats sum. Returns a [String].
  String _sum(Iterable<RecognizedPosition> positions) {
    return NumberFormat.decimalPatternDigits(
      locale: Intl.defaultLocale,
      decimalDigits: 2,
    ).format(positions.fold(0.0, (a, b) => a + b.price.value));
  }
}
