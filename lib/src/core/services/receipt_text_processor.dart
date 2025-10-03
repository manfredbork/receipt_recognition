import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Parses OCR text into structured receipt data on a background isolate.
class ReceiptTextProcessor {
  /// Runs parsing off the UI thread and returns a structured receipt.
  static Future<RecognizedReceipt> processText(
      RecognizedText text,
      ReceiptOptions options,
      ) {
    return compute<_ParseArgs, RecognizedReceipt>(
      _parseTextInBackground,
      _ParseArgs(text, options),
    );
  }

  /// Isolate entry that delegates to the parser.
  static RecognizedReceipt _parseTextInBackground(_ParseArgs args) {
    return ReceiptParser.processText(args.text, args.options);
  }
}

/// Typed container for isolate arguments.
class _ParseArgs {
  final RecognizedText text;
  final ReceiptOptions options;

  const _ParseArgs(this.text, this.options);
}
