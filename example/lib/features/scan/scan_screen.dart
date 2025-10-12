import 'package:camera/camera.dart';
import 'package:example/features/scan/scan_controller.dart';
import 'package:example/services/camera_handler_mixin.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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

  @override
  void initState() {
    super.initState();
    _ctrl = ScanController();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final cameras = await availableCameras();
      await initCamera(cameras);
      await startLiveFeed(_handleInputImage);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    stopLiveFeed();
    _ctrl.disposeAsync();
    super.dispose();
  }

  /// Called for every camera frame as an MLKit [InputImage].
  Future<void> _handleInputImage(InputImage input) async {
    final receipt = await _ctrl.processImage(input);
    if (!mounted) return;

    if (receipt.isValid && receipt.isConfirmed) {
      context.goNamed('result', extra: receipt);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan'),
        actions: [
          IconButton(
            tooltip: 'Accept current',
            icon: const Icon(Icons.check),
            onPressed: () async {
              final router = GoRouter.of(context);
              final r = await _ctrl.acceptCurrent();
              if (!mounted) return;
              if (r.isValid && r.isConfirmed) {
                router.goNamed('result', extra: r);
              }
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final cc = cameraController;
          final pct = _ctrl.progressPercent.clamp(0, 100);

          return Stack(
            fit: StackFit.expand,
            children: [
              if (cc != null && cc.value.isInitialized)
                CameraPreview(cc)
              else
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),

              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
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
      floatingActionButton: AnimatedSwitcher(
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
    );
  }
}
