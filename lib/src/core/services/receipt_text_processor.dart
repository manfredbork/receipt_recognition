import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

class ReceiptTextProcessor {
  static Future<RecognizedReceipt?> processText(RecognizedText text) async {
    return compute(_parseTextInBackground, text);
  }
  
  static RecognizedReceipt? _parseTextInBackground(RecognizedText text) {
    return ReceiptParser.processText(text);
  }
}
