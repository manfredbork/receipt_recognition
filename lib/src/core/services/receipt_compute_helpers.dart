import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Parses recognized text into structured receipt data using an isolate.
///
/// Offloads heavy OCR-to-model conversion to a background isolate,
/// allowing smoother performance on the main thread.
Future<RecognizedReceipt?> processTextIsolate(RecognizedText text) async {
  return compute(_parseTextInIsolate, text);
}

/// Synchronously parses recognized text and marks it as video feed input.
RecognizedReceipt? _parseTextInIsolate(RecognizedText text) {
  final parsed = ReceiptParser.processText(text);
  return parsed?.fromVideoFeed(true);
}

/// Resolves the most likely order of receipt items using an isolate.
///
/// Uses a topological sort via [PositionGraph] to reconstruct logical item order
/// from fragmented scan groups.
Future<List<RecognizedPosition>> resolveGraphInIsolate(
  List<PositionGroup> groups,
) async {
  return compute(_resolveGraph, groups);
}

/// Synchronously sorts positions from grouped scan data using topological logic.
List<RecognizedPosition> _resolveGraph(List<PositionGroup> groups) {
  final graph = PositionGraph(groups);
  return graph.resolveOrder();
}
