import 'package:flutter/material.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// A widget that visually displays a recognized receipt.
///
/// Shows the company name, a list of recognized product positions with prices,
/// and the total sum if available. An optional close button can be shown.
class ReceiptWidget extends StatelessWidget {
  /// The recognized receipt data to display.
  final RecognizedReceipt receipt;

  /// Optional callback triggered when the close icon is tapped.
  final VoidCallback? onClose;

  /// Creates a [ReceiptWidget] with a given [receipt] and optional [onClose] handler.
  const ReceiptWidget({super.key, required this.receipt, this.onClose});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 30.0),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              ZigzagEdgeWidget(isTop: true),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(color: Colors.white),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          receipt.company?.formattedValue ?? 'Unknown Store',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        if (onClose != null)
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.black),
                            tooltip: 'Close receipt',
                            onPressed: onClose,
                          ),
                      ],
                    ),
                    const Divider(),
                    ...receipt.positions.map((position) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              position.product.normalizedText,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black,
                              ),
                            ),
                            Text(
                              position.price.formattedValue,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(),
                    if (receipt.sum != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              receipt.sum!.formattedValue,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              ZigzagEdgeWidget(isTop: false),
            ]),
          ),
        ),
      ],
    );
  }
}

/// A decorative widget that renders a zigzag edge like a receipt tear.
///
/// Can be positioned at the top or bottom of a receipt block.
class ZigzagEdgeWidget extends StatelessWidget {
  /// Whether the zigzag is rendered at the top (`true`) or bottom (`false`).
  final bool isTop;

  /// Width of each zigzag triangle base.
  final double zigzagWidth;

  /// Height of each zigzag triangle.
  final double zigzagHeight;

  /// Color used to fill the zigzag triangles.
  final Color triangleColor;

  /// Height of the overall painted area.
  final double height;

  /// Creates a [ZigzagEdgeWidget] with configurable styling and placement.
  const ZigzagEdgeWidget({
    super.key,
    this.isTop = false,
    this.zigzagWidth = 5.0,
    this.zigzagHeight = 5.0,
    this.triangleColor = Colors.white,
    this.height = 5.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ZigzagEdgePainter(
        isTop: isTop,
        zigzagWidth: zigzagWidth,
        zigzagHeight: zigzagHeight,
        triangleColor: triangleColor,
      ),
      child: SizedBox(height: height),
    );
  }
}

class _ZigzagEdgePainter extends CustomPainter {
  final bool isTop;
  final double zigzagWidth;
  final double zigzagHeight;
  final Color triangleColor;

  _ZigzagEdgePainter({
    required this.isTop,
    required this.zigzagWidth,
    required this.zigzagHeight,
    required this.triangleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trianglePaint = Paint()..color = triangleColor;

    for (double x = 0; x < size.width; x += zigzagWidth) {
      final trianglePath = Path();
      if (isTop) {
        trianglePath.moveTo(x, size.height);
        trianglePath.lineTo(x + zigzagWidth / 2, size.height - zigzagHeight);
        trianglePath.lineTo(x + zigzagWidth, size.height);
      } else {
        trianglePath.moveTo(x, 0);
        trianglePath.lineTo(x + zigzagWidth / 2, zigzagHeight);
        trianglePath.lineTo(x + zigzagWidth, 0);
      }
      trianglePath.close();
      canvas.drawPath(trianglePath, trianglePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
