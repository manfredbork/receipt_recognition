import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Screen that displays the final recognized receipt details.
class ResultScreen extends StatelessWidget {
  final RecognizedReceipt receipt;

  const ResultScreen({super.key, required this.receipt});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              vertical: 25.0,
              horizontal: 25.0,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate(<Widget>[
                const ZigzagEdgeWidget(isTop: true),
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
                            receipt.store?.formattedValue ?? 'Unknown Store',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.black),
                            tooltip: 'Close receipt',
                            onPressed: () => context.goNamed('info'),
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
                              Expanded(
                                child: Text(
                                  position.product.normalizedText,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
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
                      if (receipt.total != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                receipt.totalLabel != null
                                    ? receipt.totalLabel!.formattedValue
                                    : 'Total',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                receipt.total!.formattedValue,
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
                const ZigzagEdgeWidget(isTop: false),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Decorative zigzag separator widget for the receipt card edges.
class ZigzagEdgeWidget extends StatelessWidget {
  final bool isTop;
  final double zigzagWidth;
  final double zigzagHeight;
  final Color triangleColor;
  final double height;

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

/// Painter that draws a horizontal zigzag edge.
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
