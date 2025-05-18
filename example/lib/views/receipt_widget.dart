import 'package:flutter/material.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// A UI widget that displays a parsed [RecognizedReceipt] visually.
///
/// Shows the store name, all scanned line items, and the total amount
/// in a stylized receipt layout with a zigzag top/bottom border.
class ReceiptWidget extends StatelessWidget {
  /// The recognized receipt data to render.
  final RecognizedReceipt receipt;

  const ReceiptWidget({super.key, required this.receipt});

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
                    Text(
                      receipt.company?.formattedValue ?? 'Unknown Store',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const Divider(),
                    ...receipt.positions.map((position) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              position.product.formattedValue,
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

/// A decorative zigzag edge used at the top and bottom of the receipt display.
class ZigzagEdgeWidget extends StatelessWidget {
  final bool isTop;
  final double zigzagWidth;
  final double zigzagHeight;
  final Color triangleColor;
  final double height;

  /// Creates a zigzag border widget for use in [ReceiptWidget].
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

/// Internal painter class that draws a row of zigzag triangles.
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
