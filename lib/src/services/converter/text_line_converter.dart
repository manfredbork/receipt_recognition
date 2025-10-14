import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'text_line_grid.dart';

/// Converts Google ML Kit `RecognizedText` into a coarse grid (`TextLineGrid`)
/// by bucketing `TextLine`s into row/column cells derived from average
/// line height and estimated column width.
///
/// Notes:
/// - Rows use average bounding-box height as the unit.
/// - Columns are inferred from total width divided by the densest vertical bucket.
final class TextLineConverter {
  /// Converts a `RecognizedText` payload into a `TextLineGrid`.
  ///
  /// Walks all text lines, computes grid cell size (row height, column width),
  /// then assigns each line to a grid cell.
  static TextLineGrid processText(RecognizedText text) {
    final lines = _convertToLines(text);
    final grid = _convertToGrid(lines);
    return grid;
  }

  /// Flattens all `block.lines` from `RecognizedText` into a single list.
  static List<TextLine> _convertToLines(RecognizedText text) {
    return text.blocks.expand((block) => block.lines).toList();
  }

  /// Builds a `TextLineGrid` from a list of `TextLine`s by computing
  /// row/column cell sizes and assigning each line to its (row, col).
  static TextLineGrid _convertToGrid(List<TextLine> lines) {
    if (lines.isEmpty) return TextLineGrid();

    final grid = TextLineGrid();
    final boxes = lines.map((l) => l.boundingBox).toList();
    final rowHeight = _rowHeight(boxes);
    final colWidth = _colWidth(boxes);

    for (final line in lines) {
      final row = (line.boundingBox.bottom - line.boundingBox.top) ~/ rowHeight;
      final col = (line.boundingBox.right - line.boundingBox.left) ~/ colWidth;
      grid.addLine(row, col, line);
    }

    return grid;
  }

  /// Returns the average bounding-box height (rounded to int).
  static int _rowHeight(List<Rect> boxes) {
    if (boxes.isEmpty) return 0;
    final height =
        boxes.fold<double>(0.0, (h, b) => h + b.height) ~/ boxes.length;
    return height;
  }

  /// Estimates the column width by:
  /// 1) Finding the densest vertical bucket (based on center.y with row tolerance),
  /// 2) Dividing total width by that max bucket size.
  static int _colWidth(List<Rect> boxes) {
    if (boxes.isEmpty) return 0;

    final tolerance = _rowTolerance(boxes);
    final counts = <int, int>{};
    var best = 0;

    for (final box in boxes) {
      final key = (box.center.dy ~/ tolerance) * tolerance; // snap to bucket
      final count = (counts[key] = (counts[key] ?? 0) + 1);
      if (count > best) best = count;
    }

    final left = _minLeft(boxes);
    final right = _maxRight(boxes);
    final width = right - left;

    return width ~/ best;
  }

  /// Minimum left x among boxes (floored).
  static int _minLeft(List<Rect> boxes) {
    return boxes.map((b) => b.left).reduce(math.min).floor();
  }

  /// Maximum right x among boxes (ceiled).
  static int _maxRight(List<Rect> boxes) {
    return boxes.map((b) => b.right).reduce(math.max).ceil();
  }

  /// Row tolerance (in pixels) derived from average row height and π.
  static int _rowTolerance(List<Rect> boxes) {
    return _rowHeight(boxes) ~/ math.pi;
  }
}
