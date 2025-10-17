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
      canvas.drawRect(rectProduct, paintPosition);
      canvas.drawRect(rectPrice, paintPosition);
    }

    if (store != null) {
      canvas.drawRect(_scale(store!.line.boundingBox), paintStore);
    }
    if (totalLabel != null) {
      canvas.drawRect(_scale(totalLabel!.line.boundingBox), paintTotalLabel);
    }
    if (total != null) {
      canvas.drawRect(_scale(total!.line.boundingBox), paintTotal);
    }
    if (purchaseDate != null) {
      canvas.drawRect(
        _scale(purchaseDate!.line.boundingBox),
        paintPurchaseDate,
      );
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
