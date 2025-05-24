import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// A model class representing the horizontal bounds of a receipt.
///
/// Encapsulates the leftmost and rightmost boundaries (`minLeft` and `maxRight`)
/// for text lines in a receipt.
class RecognizedBounds {
  final double minLeft;
  final double maxRight;

  // Constructor
  RecognizedBounds({required this.minLeft, required this.maxRight});

  // Null-safe implementation of fromLines
  static RecognizedBounds fromLines(List<TextLine> lines) {
    if (lines.isEmpty) {
      // Return a default ReceiptBounds object if no lines are found
      return RecognizedBounds(minLeft: 0.0, maxRight: 0.0);
    }

    // Calculate minLeft and maxRight based on boundingBox of lines
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
