import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Processes OCR text into structured receipt data using background isolates.
///
/// Offloads parsing work to a separate isolate to avoid blocking the UI thread
/// during computationally intensive parsing operations.
class ReceiptTextProcessor {
  /// Processes recognized text into a receipt structure in a background isolate.
  static Future<RecognizedReceipt> processText(
      RecognizedText text,
      ReceiptOptions options,
      ) {
    return compute(
      _parseTextInBackground,
      _ParseArgs(text, options),
    );
  }

  /// Background processing function that runs in the isolate.
  static RecognizedReceipt _parseTextInBackground(_ParseArgs args) {
    return ReceiptParser.processText(args.text, args.options);
  }
}

/// Simple typed container for passing data to the isolate.
class _ParseArgs {
  final RecognizedText text;
  final ReceiptOptions options;

  const _ParseArgs(this.text, this.options);
}
