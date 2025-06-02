import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:example/views/camera_handler_mixin.dart';
import 'package:example/views/receipt_widget.dart';
import 'package:example/views/scan_info_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

class ReceiptRecognitionView extends StatefulWidget {
  const ReceiptRecognitionView({super.key});

  @override
  State<ReceiptRecognitionView> createState() => _ReceiptRecognitionViewState();
}

class _ReceiptRecognitionViewState extends State<ReceiptRecognitionView>
    with CameraHandlerMixin {
  final _audioPlayer = AudioPlayer();
  ReceiptRecognizer? _receiptRecognizer;
  RecognizedReceipt? _receipt;
  bool _canProcess = false;
  bool _isReady = false;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _receiptRecognizer = ReceiptRecognizer(
      onScanUpdate: _onScanUpdate,
      onScanTimeout: _onScanTimeout,
    );
    _initializeCamera();
  }

  void _initializeCamera() async {
    final cameras = await availableCameras();
    await initCamera(cameras);
    if (mounted) setState(() {});
  }

  void _onScanUpdate(ScanProgress progress) {
    // TODO
  }

  void _onScanTimeout() {
    _canProcess = false;
    stopLiveFeed(); // Stop camera here
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scan failed', textAlign: TextAlign.center),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (!isReadyToProcess) {
      return;
    }
    _isBusy = true;
    try {
      final receipt = await _receiptRecognizer?.processImage(inputImage);
      if (_isValidReceipt(receipt)) {
        _handleSuccessfulScan(receipt!);
      }
    } catch (e, st) {
      _handleProcessingError(e, st);
    } finally {
      _isBusy = false;
      if (mounted) setState(() {});
    }
  }

  bool _isValidReceipt(RecognizedReceipt? receipt) {
    return receipt != null && receipt.positions.isNotEmpty;
  }

  void _handleSuccessfulScan(RecognizedReceipt receipt) {
    _playScanSound();

    _receipt = receipt;
    _canProcess = false;

    stopLiveFeed();

    if (mounted) {
      _showSuccessNotification();
      setState(() {});
    }
  }

  void _playScanSound() {
    _audioPlayer.play(AssetSource('sounds/checkout_beep.mp3'));
  }

  void _showSuccessNotification() {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scan succeed', textAlign: TextAlign.center),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _handleProcessingError(Object error, StackTrace stackTrace) {
    debugPrint('Image processing error: $error\n$stackTrace');
  }

  Future<void> _startLiveFeed() async {
    await startLiveFeed(_processImage);
    _isReady = true;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _liveFeed();
  }

  bool get isReadyToProcess =>
      _receiptRecognizer != null && _canProcess && _isReady && !_isBusy;

  bool get isCameraPreviewReady =>
      cameraController?.value.isInitialized == true && !isControllerDisposed;

  Widget _liveFeed() {
    return Scaffold(
      body: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (isCameraPreviewReady)
              CameraPreview(cameraController!)
            else if (!isControllerDisposed && cameraBack == null)
              const Center(child: CircularProgressIndicator())
            else if (_receipt == null)
              ScanInfoScreen(
                onStartScan: () async {
                  setState(() {
                    _receipt = null;
                    _canProcess = true;
                    _isReady = false;
                    isControllerDisposed = false;
                  });
                  await _startLiveFeed();
                },
              ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child:
                  (_receipt != null && !_canProcess)
                      ? ReceiptWidget(
                        key: ValueKey(_receipt),
                        receipt: _receipt!,
                        onClose: () {
                          Future.delayed(const Duration(milliseconds: 500), () {
                            if (mounted) {
                              setState(() => _receipt = null);
                            }
                          });
                        },
                      )
                      : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _canProcess = false;
    _isReady = false;
    _isBusy = false;
    _receiptRecognizer?.close();
    stopLiveFeed();
    super.dispose();
  }
}
