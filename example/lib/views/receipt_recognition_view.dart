import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:example/services/camera_handler_mixin.dart';
import 'package:example/widgets/position_overlay.dart';
import 'package:example/widgets/receipt_widget.dart';
import 'package:example/widgets/scan_info_screen.dart';
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
  ScanProgress? _scanProgress;
  int _maxProgress = 0;
  bool _canProcess = false;
  bool _isReady = false;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer.setSource(AssetSource('sounds/checkout_beep.mp3'));
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
    setState(() {
      _scanProgress = progress;
      final current = progress.estimatedPercentage ?? 0;
      if (current > _maxProgress) {
        _maxProgress = current;
      }
    });
  }

  void _onScanTimeout() {
    _canProcess = false;
    _receipt = null;
    _maxProgress = 0;
    stopLiveFeed();
    HapticFeedback.lightImpact();
    _showSnackBar('Scan failed', Colors.red);
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
    _maxProgress = 0;

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
    _showSnackBar('Scan succeed', Colors.green);
  }

  void _handleProcessingError(Object error, StackTrace stackTrace) {
    debugPrint('Image processing error: $error\n$stackTrace');
  }

  Future<void> _startLiveFeed() async {
    await startLiveFeed(_processImage);
    _isReady = true;
    if (mounted) setState(() {});
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
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
              Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(cameraController!),
                  if (_scanProgress?.addedPositions.isNotEmpty == true)
                    PositionOverlay(
                      positions: _scanProgress!.addedPositions,
                      imageSize: Size(
                        cameraController!.value.previewSize!.height,
                        cameraController!.value.previewSize!.width,
                      ),
                      screenSize: MediaQuery.of(context).size,
                      company: _scanProgress?.mergedReceipt?.company,
                      sum: _scanProgress?.mergedReceipt?.sum,
                    ),
                  if (_scanProgress != null && _maxProgress > 0)
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 64,
                            height: 64,
                            child: CircularProgressIndicator(
                              value: (_maxProgress / 100).clamp(0.0, 1.0),
                              strokeWidth: 6,
                              backgroundColor: Colors.white24,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.greenAccent,
                              ),
                            ),
                          ),
                          Text(
                            '$_maxProgress%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              )
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
                          setState(() => _receipt = null);
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
