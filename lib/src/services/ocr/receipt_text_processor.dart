import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/parser/index.dart';
import 'package:receipt_recognition/src/utils/configuration/index.dart';

/// Parses OCR text into structured receipt data on a background isolate.
///
/// This utility offloads parsing work from the UI thread. Prefer using
/// [ReceiptTextProcessor.processText] rather than calling the private isolate
/// entry point directly.
final class ReceiptTextProcessor {
  /// Runs parsing off the UI thread and returns a structured receipt.
  ///
  /// Uses `compute` to execute parsing on a background isolate with the
  /// provided [text] and [options].
  static Future<RecognizedReceipt> processText(
    RecognizedText text,
    ReceiptOptions options,
  ) {
    return compute<_ParseArgs, RecognizedReceipt>(
      _parseTextInBackground,
      _ParseArgs(text, options),
    );
  }

  /// Isolate entry point that performs parsing.
  ///
  /// Not part of the public API; prefer [processText].
  static RecognizedReceipt _parseTextInBackground(_ParseArgs args) {
    return ReceiptParser.processText(args.text, args.options);
  }
}

/// Typed container for isolate arguments.
final class _ParseArgs {
  /// OCR result to be parsed on the background isolate.
  final RecognizedText text;

  /// Options used to guide parsing and tuning during isolate work.
  final ReceiptOptions options;

  /// Creates an immutable bundle of parsing inputs for the isolate.
  const _ParseArgs(this.text, this.options);
}
