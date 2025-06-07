import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Dummy implementation of TextLine for tests.
///
/// Required because RecognizedEntity expects a real `TextLine`.
class DummyTextLine extends TextLine {
  DummyTextLine() : super(
    text: '',
    recognizedLanguages: [],
    boundingBox: Rect.zero,
    cornerPoints: [],
    elements: [],
    confidence: null,
    angle: null,
  );
}
