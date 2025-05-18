import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

Future<RecognizedReceipt?> processTextIsolate(RecognizedText text) async {
  return compute(_parseTextInIsolate, text);
}

RecognizedReceipt? _parseTextInIsolate(RecognizedText text) {
  final parsed = ReceiptParser.processText(text);
  return parsed?.fromVideoFeed(true);
}

Future<List<RecognizedPosition>> resolveGraphInIsolate(
  List<PositionGroup> groups,
) async {
  return compute(_resolveGraph, groups);
}

List<RecognizedPosition> _resolveGraph(List<PositionGroup> groups) {
  final graph = PositionGraph(groups);
  return graph.resolveOrder();
}
