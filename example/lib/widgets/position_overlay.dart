import 'package:flutter/material.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// A widget that overlays bounding boxes for recognized receipt elements.
///
/// Displays visual rectangles on top of a camera or image preview to indicate
/// the positions of products, the store/company, and the total sum.
class PositionOverlay extends StatelessWidget {
  /// List of recognized product-price positions to display.
  final List<RecognizedPosition> positions;

  /// Optionally highlights the recognized store/company information.
  final RecognizedCompany? company;

  /// Optionally highlights the recognized total sum.
  final RecognizedSum? sum;

  /// Original size of the scanned image.
  final Size imageSize;

  /// Target screen size to scale the bounding boxes onto.
  final Size screenSize;

  /// Creates a [PositionOverlay] to visualize recognized receipt data.
  const PositionOverlay({
    super.key,
    required this.positions,
    required this.imageSize,
    required this.screenSize,
    this.company,
    this.sum,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PositionPainter(
        positions: positions,
        imageSize: imageSize,
        screenSize: screenSize,
        company: company,
        sum: sum,
      ),
    );
  }
}

class _PositionPainter extends CustomPainter {
  final List<RecognizedPosition> positions;
  final RecognizedCompany? company;
  final RecognizedSum? sum;
  final Size imageSize;
  final Size screenSize;

  _PositionPainter({
    required this.positions,
    required this.imageSize,
    required this.screenSize,
    this.company,
    this.sum,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintProduct =
        Paint()
          ..color = Colors.orange.withAlpha(192)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    final paintCompany =
        Paint()
          ..color = Colors.blueAccent.withAlpha(192)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    final paintTotal =
        Paint()
          ..color = Colors.green.withAlpha(192)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    for (final position in positions) {
      final productBox = _scaleRect(position.product.line.boundingBox);
      final priceBox = _scaleRect(position.price.line.boundingBox);
      canvas.drawRect(productBox, paintProduct);
      canvas.drawRect(priceBox, paintProduct);
    }

    if (company != null) {
      final rect = _scaleRect(company!.line.boundingBox);
      canvas.drawRect(rect, paintCompany);
    }

    if (sum != null) {
      final rect = _scaleRect(sum!.line.boundingBox);
      canvas.drawRect(rect, paintTotal);
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
