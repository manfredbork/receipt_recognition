import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Deskews coordinates by rotating them by -angleDeg around the origin (0,0).
/// If |angleDeg| < 0.5, rotation is skipped (fast path).
class ReceiptRotator {
  final double angleDeg;
  final double sinA;
  final double cosA;
  final bool hasRotation;

  ReceiptRotator(this.angleDeg)
      : hasRotation = angleDeg.abs() >= 0.5,
        sinA = math.sin(-angleDeg * math.pi / 180.0),
        cosA = math.cos(-angleDeg * math.pi / 180.0);

  /// Rotates a point by -angleDeg around (0,0).
  Offset rotatePoint(Offset p) {
    if (!hasRotation) return p;
    final rx = p.dx * cosA - p.dy * sinA;
    final ry = p.dx * sinA + p.dy * cosA;
    return Offset(rx, ry);
  }

  /// Deskews a rect by rotating its corners and returning the AABB.
  Rect deskewRect(Rect r) {
    if (!hasRotation) return r;

    final p1 = rotatePoint(Offset(r.left, r.top));
    final p2 = rotatePoint(Offset(r.right, r.top));
    final p3 = rotatePoint(Offset(r.left, r.bottom));
    final p4 = rotatePoint(Offset(r.right, r.bottom));

    final minX = math.min(math.min(p1.dx, p2.dx), math.min(p3.dx, p4.dx));
    final maxX = math.max(math.max(p1.dx, p2.dx), math.max(p3.dx, p4.dx));
    final minY = math.min(math.min(p1.dy, p2.dy), math.min(p3.dy, p4.dy));
    final maxY = math.max(math.max(p1.dy, p2.dy), math.max(p3.dy, p4.dy));

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Returns the deskewed AABB for a line’s bounding box.
  Rect deskewLineBox(TextLine line) => deskewRect(line.boundingBox);

  /// Returns the deskewed X of a line’s center.
  double xCenter(TextLine l) {
    final c = l.boundingBox.center;
    if (!hasRotation) return c.dx;
    return c.dx * cosA - c.dy * sinA;
  }

  /// Returns the deskewed Y of a line’s center.
  double yCenter(TextLine l) {
    final c = l.boundingBox.center;
    if (!hasRotation) return c.dy;
    return c.dx * sinA + c.dy * cosA;
  }

  /// Returns the deskewed X at the line’s center-left.
  double xAtCenterLeft(TextLine l) {
    final p = l.boundingBox.centerLeft;
    if (!hasRotation) return p.dx;
    return p.dx * cosA - p.dy * sinA;
  }

  /// Returns the deskewed X at the line’s center-right.
  double xAtCenterRight(TextLine l) {
    final p = l.boundingBox.centerRight;
    if (!hasRotation) return p.dx;
    return p.dx * cosA - p.dy * sinA;
  }

  /// Returns the deskewed Y at the line’s top-center.
  double yAtTopCenter(TextLine l) {
    final p = l.boundingBox.topCenter;
    if (!hasRotation) return p.dy;
    return p.dx * sinA + p.dy * cosA;
  }

  /// Returns the deskewed Y at the line’s bottom-center.
  double yAtBottomCenter(TextLine l) {
    final p = l.boundingBox.bottomCenter;
    if (!hasRotation) return p.dy;
    return p.dx * sinA + p.dy * cosA;
  }

  /// Returns the minimum deskewed X of a rect.
  double minXOf(Rect r) {
    if (!hasRotation) return r.left;
    final a = (r.left * cosA - r.top * sinA);
    final b = (r.right * cosA - r.top * sinA);
    final c = (r.left * cosA - r.bottom * sinA);
    final d = (r.right * cosA - r.bottom * sinA);
    return math.min(math.min(a, b), math.min(c, d));
  }

  /// Returns the maximum deskewed X of a rect.
  double maxXOf(Rect r) {
    if (!hasRotation) return r.right;
    final a = (r.left * cosA - r.top * sinA);
    final b = (r.right * cosA - r.top * sinA);
    final c = (r.left * cosA - r.bottom * sinA);
    final d = (r.right * cosA - r.bottom * sinA);
    return math.max(math.max(a, b), math.max(c, d));
  }

  /// Returns the deskewed X of a rect’s center.
  double xOfCenter(Rect r) {
    final c = r.center;
    if (!hasRotation) return c.dx;
    return c.dx * cosA - c.dy * sinA;
  }

  /// Returns the deskewed Y of a rect’s center.
  double yOfCenter(Rect r) {
    final c = r.center;
    if (!hasRotation) return c.dy;
    return c.dx * sinA + c.dy * cosA;
  }
}
