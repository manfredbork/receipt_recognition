import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ReceiptRotator {
  final double angleDeg;
  final double sinA;
  final double cosA;
  final bool hasRotation;

  ReceiptRotator(this.angleDeg)
    : hasRotation = angleDeg.abs() >= 0.5,
      sinA = math.sin(-angleDeg * math.pi / 180.0),
      cosA = math.cos(-angleDeg * math.pi / 180.0);

  double xOf(TextLine l) {
    final c = l.boundingBox.center;
    if (!hasRotation) return c.dx.toDouble();
    return c.dx * cosA - c.dy * sinA;
  }

  double xCenterLeftOf(TextLine l) {
    final c = l.boundingBox.centerLeft;
    if (!hasRotation) return c.dx.toDouble();
    return c.dx * cosA - c.dy * sinA;
  }

  double xCenterRightOf(TextLine l) {
    final c = l.boundingBox.centerRight;
    if (!hasRotation) return c.dx.toDouble();
    return c.dx * cosA - c.dy * sinA;
  }

  double yOf(TextLine l) {
    final c = l.boundingBox.center;
    if (!hasRotation) return c.dy.toDouble();
    return c.dx * sinA + c.dy * cosA;
  }

  double yTopCenterOf(TextLine l) {
    final c = l.boundingBox.topCenter;
    if (!hasRotation) return c.dy.toDouble();
    return c.dx * sinA + c.dy * cosA;
  }

  double yBottomCenterOf(TextLine l) {
    final c = l.boundingBox.bottomCenter;
    if (!hasRotation) return c.dy.toDouble();
    return c.dx * sinA + c.dy * cosA;
  }

  double xLeftOf(Rect r) {
    if (!hasRotation) return r.left.toDouble();
    final pts = [
      Offset(r.left, r.top),
      Offset(r.right, r.top),
      Offset(r.left, r.bottom),
      Offset(r.right, r.bottom),
    ];
    return pts.map((p) => p.dx * cosA - p.dy * sinA).reduce(math.min);
  }

  double xRightOf(Rect r) {
    if (!hasRotation) return r.right.toDouble();
    final pts = [
      Offset(r.left, r.top),
      Offset(r.right, r.top),
      Offset(r.left, r.bottom),
      Offset(r.right, r.bottom),
    ];
    return pts.map((p) => p.dx * cosA - p.dy * sinA).reduce(math.max);
  }

  double xOfCenter(Rect r) {
    final c = r.center;
    if (!hasRotation) return c.dy.toDouble();
    return c.dx * cosA - c.dy * sinA;
  }

  double yOfCenter(Rect r) {
    final c = r.center;
    if (!hasRotation) return c.dy.toDouble();
    return c.dx * sinA + c.dy * cosA;
  }
}
