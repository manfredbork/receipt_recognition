import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Represents the bounding box boundaries of a recognized receipt.
///
/// Provides minimum left and maximum right coordinates to help with
/// determining the position of text elements on the receipt.
class RecognizedBounds {
  /// The minimum left coordinate across all text lines.
  final double minLeft;

  /// The maximum right coordinate across all text lines.
  final double maxRight;

  /// Creates bounds with [minLeft] and [maxRight] values.
  RecognizedBounds({required this.minLeft, required this.maxRight});

  /// Creates bounds from a list of text lines by finding minimum left and maximum right coordinates.
  ///
  /// Returns default values (0.0) for an empty list of lines.
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
