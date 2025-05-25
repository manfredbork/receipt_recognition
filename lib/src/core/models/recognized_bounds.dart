import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// A model class representing the horizontal bounds of a receipt.
///
/// Encapsulates the leftmost and rightmost boundaries (`minLeft` and `maxRight`)
/// for text lines in a receipt.
class RecognizedBounds {
  final double minLeft;
  final double maxRight;

  RecognizedBounds({required this.minLeft, required this.maxRight});

  static RecognizedBounds fromLines(List<TextLine> lines) {
    if (lines.isEmpty) {
      return RecognizedBounds(minLeft: 0.0, maxRight: 0.0);
    }

    final minLeft = lines
        .map((line) {
          return line.boundingBox.left;
        })
        .fold<double>(
          double.infinity,
          (previous, current) => current < previous ? current : previous,
        );

    final maxRight = lines
        .map((line) {
          return line.boundingBox.right;
        })
        .fold<double>(
          double.negativeInfinity,
          (previous, current) => current > previous ? current : previous,
        );

    return RecognizedBounds(minLeft: minLeft, maxRight: maxRight);
  }
}
