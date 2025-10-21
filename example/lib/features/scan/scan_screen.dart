import 'package:camera/camera.dart';
import 'package:example/features/overlay/overlay_screen.dart';
import 'package:example/features/scan/scan_controller.dart';
import 'package:example/services/camera_handler_mixin.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with CameraHandlerMixin<ScanScreen> {
  late final ScanController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = ScanController();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final cameras = await availableCameras();
      await initCamera(cameras);
      await startLiveFeed(_handleInputImage);
      _ctrl.resetBestPercent();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    stopLiveFeed();
    _ctrl.disposeAsync();
    super.dispose();
  }

  Future<void> _handleInputImage(InputImage input) async {
    if (await _guardIfAccepted()) return;
    await _ctrl.processImage(input);
  }

  Future<bool> _guardIfAccepted() async {
    if (_ctrl.isAccepted) {
      if (!mounted) return false;
      await stopLiveFeed();
      _goAcceptedRoute();
      return true;
    }
    return false;
  }

  void _goAcceptedRoute() {
    ReceiptLogger.logReceipt(_ctrl.receipt);
    GoRouter.of(context).goNamed('result', extra: _ctrl.receipt);
  }

  Size? _previewImageSizePortrait() {
    final cc = cameraController;
    if (cc == null || !cc.value.isInitialized) return null;

    final s = cc.value.previewSize;
    if (s == null) return null;

    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    return isPortrait ? Size(s.height, s.width) : Size(s.width, s.height);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final cc = cameraController;
        final pct = _ctrl.bestPercent;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (cc != null && cc.value.isInitialized) ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final imageSize = _previewImageSizePortrait();
                    if (imageSize == null) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final receipt = _ctrl.receipt;
                    final positions = _ctrl.positions;
                    final scene = SizedBox(
                      width: imageSize.width,
                      height: imageSize.height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(cc),
                          OverlayScreen(
                            positions: positions,
                            imageSize: imageSize,
                            screenSize: imageSize,
                            store: receipt.store,
                            totalLabel: receipt.totalLabel,
                            total: receipt.total,
                            purchaseDate: receipt.purchaseDate,
                          ),
                        ],
                      ),
                    );
                    return FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: scene,
                    );
                  },
                ),
              ] else
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: pct == 0 ? null : pct / 100.0,
                      minHeight: 6,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Progress: ${pct.toStringAsFixed(0)}%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton:
              pct >= _ctrl.nearlyCompleteThreshold
                  ? const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: _AcceptFab(),
                  )
                  : null,
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
        );
      },
    );
  }
}

class _AcceptFab extends StatelessWidget {
  const _AcceptFab();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_ScanScreenState>()!;
    return FloatingActionButton.extended(
      key: const ValueKey('accept'),
      onPressed: state._ctrl.acceptCurrent,
      icon: const Icon(Icons.done),
      label: const Text('Manually Accept'),
    );
  }
}
