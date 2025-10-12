import 'package:flutter/material.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

class OverlayScreen extends StatelessWidget {
  final List<RecognizedPosition> positions;
  final Set<RecognizedPosition> added;
  final RecognizedStore? store;
  final RecognizedSumLabel? sumLabel;
  final RecognizedSum? sum;
  final RecognizedPurchaseDate? purchaseDate;
  final Size imageSize;
  final Size screenSize;

  const OverlayScreen({
    super.key,
    required this.positions,
    required this.imageSize,
    required this.screenSize,
    this.added = const {},
    this.store,
    this.sumLabel,
    this.sum,
    this.purchaseDate,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PositionPainter(
        positions: positions,
        added: added,
        imageSize: imageSize,
        screenSize: screenSize,
        store: store,
        sumLabel: sumLabel,
        sum: sum,
        purchaseDate: purchaseDate,
      ),
    );
  }
}

class _PositionPainter extends CustomPainter {
  final List<RecognizedPosition> positions;
  final Set<RecognizedPosition> added;
  final RecognizedStore? store;
  final RecognizedSumLabel? sumLabel;
  final RecognizedSum? sum;
  final RecognizedPurchaseDate? purchaseDate;
  final Size imageSize;
  final Size screenSize;

  _PositionPainter({
    required this.positions,
    required this.added,
    required this.imageSize,
    required this.screenSize,
    this.store,
    this.sumLabel,
    this.sum,
    this.purchaseDate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintDefault =
        Paint()
          ..color = Colors.orange.withAlpha(192)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    final paintAdded =
        Paint()
          ..color = Colors.greenAccent.withAlpha(220)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;

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
      final p = added.contains(position) ? paintAdded : paintDefault;
      canvas.drawRect(rectProduct, p);
      canvas.drawRect(rectPrice, p);
    }

    if (store != null) {
      canvas.drawRect(_scale(store!.line.boundingBox), paintStore);
    }
    if (sumLabel != null) {
      canvas.drawRect(_scale(sumLabel!.line.boundingBox), paintTotalLabel);
    }
    if (sum != null) {
      canvas.drawRect(_scale(sum!.line.boundingBox), paintTotal);
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
      old.added != added ||
      old.imageSize != imageSize ||
      old.screenSize != screenSize ||
      old.store != store ||
      old.sumLabel != sumLabel ||
      old.sum != sum ||
      old.purchaseDate != purchaseDate;
}
