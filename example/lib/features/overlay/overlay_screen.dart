import 'package:flutter/material.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

class OverlayScreen extends StatelessWidget {
  final List<RecognizedPosition> positions;
  final RecognizedStore? store;
  final RecognizedTotalLabel? totalLabel;
  final RecognizedTotal? total;
  final RecognizedPurchaseDate? purchaseDate;
  final Size imageSize;
  final Size screenSize;

  const OverlayScreen({
    super.key,
    required this.positions,
    required this.imageSize,
    required this.screenSize,
    this.store,
    this.totalLabel,
    this.total,
    this.purchaseDate,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PositionPainter(
        positions: positions,
        imageSize: imageSize,
        screenSize: screenSize,
        store: store,
        totalLabel: totalLabel,
        total: total,
        purchaseDate: purchaseDate,
      ),
    );
  }
}

class _PositionPainter extends CustomPainter {
  final List<RecognizedPosition> positions;
  final RecognizedStore? store;
  final RecognizedTotalLabel? totalLabel;
  final RecognizedTotal? total;
  final RecognizedPurchaseDate? purchaseDate;
  final Size imageSize;
  final Size screenSize;

  _PositionPainter({
    required this.positions,
    required this.imageSize,
    required this.screenSize,
    this.store,
    this.totalLabel,
    this.total,
    this.purchaseDate,
  });

  void _fillHatched(
    Canvas canvas,
    Rect rect,
    Color color, {
    double spacing = 6.0,
    double strokeWidth = 1.0,
  }) {
    if (rect.isEmpty) return;
    final paint =
        Paint()
          ..color = color.withAlpha(192)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth;

    canvas.save();
    canvas.clipRect(rect);

    final startX = rect.left - rect.height;
    final endX = rect.right + rect.height;
    for (double x = startX; x <= endX; x += spacing) {
      final p1 = Offset(x, rect.top);
      final p2 = Offset(x + rect.height, rect.bottom);
      canvas.drawLine(p1, p2, paint);
    }

    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paintPosition =
        Paint()
          ..color = Colors.orange.withAlpha(192)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    final paintStore =
        Paint()
          ..color = Colors.blueAccent.withAlpha(192)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    final paintTotalLabel =
        Paint()
          ..color = Colors.deepPurpleAccent.withAlpha(192)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    final paintTotal =
        Paint()
          ..color = Colors.green.withAlpha(192)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    final paintPurchaseDate =
        Paint()
          ..color = Colors.amber.withAlpha(192)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    for (final position in positions) {
      final rectProduct = _scale(position.product.line.boundingBox);
      final rectPrice = _scale(position.price.line.boundingBox);

      _fillHatched(canvas, rectProduct, Colors.orange);
      _fillHatched(canvas, rectPrice, Colors.orange);

      canvas.drawRect(rectProduct, paintPosition);
      canvas.drawRect(rectPrice, paintPosition);
    }

    if (store != null) {
      final r = _scale(store!.line.boundingBox);
      _fillHatched(canvas, r, Colors.blueAccent);
      canvas.drawRect(r, paintStore);
    }

    if (totalLabel != null) {
      final r = _scale(totalLabel!.line.boundingBox);
      _fillHatched(canvas, r, Colors.deepPurpleAccent);
      canvas.drawRect(r, paintTotalLabel);
    }

    if (total != null) {
      final r = _scale(total!.line.boundingBox);
      _fillHatched(canvas, r, Colors.green);
      canvas.drawRect(r, paintTotal);
    }

    if (purchaseDate != null) {
      final r = _scale(purchaseDate!.line.boundingBox);
      _fillHatched(canvas, r, Colors.amber);
      canvas.drawRect(r, paintPurchaseDate);
    }
  }

  Rect _scale(Rect r) {
    final sx = screenSize.width / imageSize.width;
    final sy = screenSize.height / imageSize.height;
    return Rect.fromLTRB(r.left * sx, r.top * sy, r.right * sx, r.bottom * sy);
  }

  @override
  bool shouldRepaint(covariant _PositionPainter old) =>
      old.positions != positions ||
      old.imageSize != imageSize ||
      old.screenSize != screenSize ||
      old.store != store ||
      old.totalLabel != totalLabel ||
      old.total != total ||
      old.purchaseDate != purchaseDate;
}
