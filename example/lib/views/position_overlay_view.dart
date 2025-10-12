import 'package:flutter/material.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// A widget that overlays bounding boxes for recognized receipt elements.
///
/// Displays visual rectangles on top of a camera or image preview to indicate
/// the positions of products, the store, and the total sum.
class PositionOverlayView extends StatelessWidget {
  /// List of recognized product-price positions to display.
  final List<RecognizedPosition> positions;

  /// Optionally highlights the recognized store information.
  final RecognizedStore? store;

  /// Optionally highlights the recognized sum label.
  final RecognizedSumLabel? sumLabel;

  /// Optionally highlights the recognized total sum.
  final RecognizedSum? sum;

  /// Optionally highlights the recognized purchase date.
  final RecognizedPurchaseDate? purchaseDate;

  /// Original size of the scanned image.
  final Size imageSize;

  /// Target screen size to scale the bounding boxes onto.
  final Size screenSize;

  /// Creates a [PositionOverlayView] to visualize recognized receipt data.
  const PositionOverlayView({
    super.key,
    required this.positions,
    required this.imageSize,
    required this.screenSize,
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
  final RecognizedStore? store;
  final RecognizedSumLabel? sumLabel;
  final RecognizedSum? sum;
  final RecognizedPurchaseDate? purchaseDate;
  final Size imageSize;
  final Size screenSize;

  _PositionPainter({
    required this.positions,
    required this.imageSize,
    required this.screenSize,
    this.store,
    this.sumLabel,
    this.sum,
    this.purchaseDate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintProduct =
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
      final productBox = _scaleRect(position.product.line.boundingBox);
      final priceBox = _scaleRect(position.price.line.boundingBox);
      canvas.drawRect(productBox, paintProduct);
      canvas.drawRect(priceBox, paintProduct);
    }

    if (store != null) {
      final rect = _scaleRect(store!.line.boundingBox);
      canvas.drawRect(rect, paintStore);
    }

    if (sumLabel != null) {
      final rect = _scaleRect(sumLabel!.line.boundingBox);
      canvas.drawRect(rect, paintTotalLabel);
    }

    if (sum != null) {
      final rect = _scaleRect(sum!.line.boundingBox);
      canvas.drawRect(rect, paintTotal);
    }

    if (purchaseDate != null) {
      final rect = _scaleRect(purchaseDate!.line.boundingBox);
      canvas.drawRect(rect, paintPurchaseDate);
    }
  }

  Rect _scaleRect(Rect rect) {
    final scaleX = screenSize.width / imageSize.width;
    final scaleY = screenSize.height / imageSize.height;
    return Rect.fromLTRB(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.right * scaleX,
      rect.bottom * scaleY,
    );
  }

  @override
  bool shouldRepaint(covariant _PositionPainter oldDelegate) => true;
}
