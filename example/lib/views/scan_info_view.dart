import 'package:flutter/material.dart';

/// A screen that provides guidance on how to scan receipts effectively.
///
/// Displays best practices for scanning, such as lighting, alignment,
/// and stability, with a call-to-action button to start scanning.
class ScanInfoView extends StatelessWidget {
  /// Callback triggered when the user taps the "Start scanning" button.
  final VoidCallback onStartScan;

  /// Creates a [ScanInfoView] with a required [onStartScan] callback.
  const ScanInfoView({super.key, required this.onStartScan});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Best Practices',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                _infoRow(
                  icon: Icons.light_mode,
                  title: 'Lighting',
                  description:
                      'Ensure bright, even lighting with minimal shadows.',
                ),
                _infoRow(
                  icon: Icons.crop_rotate,
                  title: 'Alignment',
                  description:
                      'Hold your phone flat above the receipt, ideally at 90°.',
                ),
                _infoRow(
                  icon: Icons.vertical_align_bottom,
                  title: 'Scan Direction',
                  description:
                      'Start from the top and slowly move downward toward the total.',
                ),
                _infoRow(
                  icon: Icons.fullscreen,
                  title: 'Full Receipt in View',
                  description:
                      'If the whole receipt fits, just hold still for 1–2 seconds with everything visible.',
                ),
                _infoRow(
                  icon: Icons.vertical_align_top,
                  title: 'Long Receipts',
                  description:
                      'For long receipts, slowly return back to the top and repeat scanning.',
                ),
                _infoRow(
                  icon: Icons.stay_current_portrait,
                  title: 'Stability',
                  description:
                      'Hold steady for 1–2 seconds when the receipt is framed clearly.',
                ),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: SizedBox(
                      width: 240,
                      child: ElevatedButton.icon(
                        onPressed: onStartScan,
                        icon: const Icon(Icons.document_scanner_outlined),
                        label: const Text(
                          'Start scanning',
                          style: TextStyle(fontSize: 18),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(fontSize: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _infoRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
