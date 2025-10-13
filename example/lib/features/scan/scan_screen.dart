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

  bool get _isStreamingNow =>
      cameraController?.value.isStreamingImages ?? false;

  bool get _isReceiptFullyScanned =>
      _ctrl.lastReceipt.isValid && _ctrl.lastReceipt.isConfirmed;

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
    if (_isReceiptFullyScanned) return;

    final receipt = await _ctrl.processImage(input);

    if (_isReceiptFullyScanned) {
      await stopLiveFeed();
      if (!mounted) return;
      GoRouter.of(context).goNamed('result', extra: receipt);
    }
  }

  Future<void> _resume() async {
    try {
      await startLiveFeed(_handleInputImage);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start camera: $e')));
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _pause() async {
    try {
      await stopLiveFeed();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to stop camera: $e')));
    } finally {
      if (mounted) setState(() {});
    }
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final cc = cameraController;
          final pct = _ctrl.progressPercent.clamp(0, 100);

          return Stack(
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

                    final progress = _ctrl.progress;
                    final merged = progress?.mergedReceipt;
                    final positions =
                        merged?.positions ?? const <RecognizedPosition>[];
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
                            store: merged?.store,
                            sumLabel: merged?.sumLabel,
                            sum: merged?.sum,
                            purchaseDate: merged?.purchaseDate,
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
          );
        },
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder:
              (child, anim) => FadeTransition(opacity: anim, child: child),
          child:
              _isStreamingNow
                  ? FloatingActionButton.extended(
                    key: const ValueKey('pauseFab'),
                    onPressed: _pause,
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  )
                  : FloatingActionButton.extended(
                    key: const ValueKey('resumeFab'),
                    onPressed: _resume,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
