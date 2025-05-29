import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Processes OCR text into structured receipt data using background isolates.
///
/// Offloads parsing work to a separate isolate to avoid blocking the UI thread
/// during computationally intensive parsing operations.
class ReceiptTextProcessor {
  /// Processes recognized text into a receipt structure in a background isolate.
  ///
  /// Uses Dart's compute function to run the parsing on a separate thread.
  static Future<RecognizedReceipt?> processText(RecognizedText text) async {
    return compute(_parseTextInBackground, text);
  }

  /// Background processing function that runs in the isolate.
  static RecognizedReceipt? _parseTextInBackground(RecognizedText text) {
    return ReceiptParser.processText(text);
  }
}
