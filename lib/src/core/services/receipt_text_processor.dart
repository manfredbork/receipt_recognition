import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// A utility class to offload OCR text processing to a background isolate.
///
/// This class provides methods for parsing recognized text into structured
/// receipt data more efficiently by utilizing `compute`.
class ReceiptTextProcessor {
  /// Parses recognized text into structured receipt data using an isolate.
  ///
  /// Offloads heavy OCR-to-model conversion to a background isolate,
  /// allowing smoother performance on the main thread.
  static Future<RecognizedReceipt?> processText(RecognizedText text) async {
    return compute(_parseTextInBackground, text);
  }

  /// Synchronously parses recognized text.
  static RecognizedReceipt? _parseTextInBackground(RecognizedText text) {
    return ReceiptParser.processText(text);
  }
}
