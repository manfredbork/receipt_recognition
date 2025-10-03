import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Dummy implementation of [TextLine] for tests.
///
/// Used in cases where a real OCR line is required but not available.
class DummyTextLine extends TextLine {
  /// Creates a dummy [TextLine] with empty/default values.
  DummyTextLine()
    : super(
        text: '',
        recognizedLanguages: [],
        boundingBox: Rect.zero,
        cornerPoints: [],
        elements: [],
        confidence: null,
        angle: null,
      );
}
