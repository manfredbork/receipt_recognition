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

/// A screen that manages the full camera-based receipt recognition flow.
///
/// Displays a camera preview, handles scan progress, overlays bounding boxes,
/// and shows the result in a formatted receipt widget when scanning completes.
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
  RecognizedScanProgress? _scanProgress;

  String? _errorMessage;

  int _maxProgress = 0;

  bool _canProcess = false;
  bool _isReady = false;
  bool _isBusy = false;
  bool _didComplete = false;

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

  @override
  Widget build(BuildContext context) => _liveFeed();

  bool get isReadyToProcess =>
      _receiptRecognizer != null &&
      _canProcess &&
      _isReady &&
      !_isBusy &&
      !_didComplete;

  bool get isCameraPreviewReady =>
      cameraController?.value.isInitialized == true && !isControllerDisposed;

  bool get isScanInProgress => (_scanProgress?.estimatedPercentage ?? 0) < 100;

  @override
  void dispose() {
    _didComplete = true;
    _canProcess = false;
    _isReady = false;
    _isBusy = false;
    _receiptRecognizer?.close();
    stopLiveFeed();
    super.dispose();
  }

  void _initializeCamera() async {
    final cameras = await availableCameras();
    await initCamera(cameras);
    if (mounted) setState(() {});
  }

  void _onScanUpdate(RecognizedScanProgress progress) {
    if (_didComplete) return;
    setState(() {
      _scanProgress = progress;
      final current = progress.estimatedPercentage ?? 0;
      if (current > _maxProgress) _maxProgress = current;
    });
  }

  Future<void> _onScanTimeout() async {
    if (_receipt != null) return;

    _canProcess = false;
    _receipt = null;
    _maxProgress = 0;
    HapticFeedback.lightImpact();

    await stopLiveFeed(); // ensure camera actually stops

    setState(() {
      _errorMessage = 'Scan failed – try again';
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _errorMessage != null) {
        setState(() => _errorMessage = null);
      }
    });
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (!isReadyToProcess) return;
    _isBusy = true;

    final processedMlkitImage =
        (inputImage.bytes != null)
            ? InputImage.fromBytes(
              bytes: inputImage.bytes!,
              metadata: InputImageMetadata(
                size: inputImage.metadata!.size,
                rotation: inputImage.metadata!.rotation,
                format: inputImage.metadata!.format,
                bytesPerRow: inputImage.metadata!.bytesPerRow,
              ),
            )
            : inputImage;

    try {
      final receipt = await _receiptRecognizer?.processImage(
        processedMlkitImage,
      );

      if (!_canProcess || _didComplete) return;

      if (_isValidReceipt(receipt)) {
        await _handleSuccessfulScan(receipt!);
      }
    } catch (e, st) {
      _handleProcessingError(e, st);
    } finally {
      _isBusy = false;
      if (mounted) setState(() {});
    }
  }

  bool _isValidReceipt(RecognizedReceipt? receipt) {
    if (receipt == null) return false;

    if (receipt.isValid == true) return true;

    final hasPositions = receipt.positions.isNotEmpty;
    final hasSum = receipt.sum != null;

    final pct = _scanProgress?.estimatedPercentage ?? 0;
    final nearlyDone = pct >= 95;

    return hasPositions && (hasSum || nearlyDone);
  }

  Future<void> _handleSuccessfulScan(RecognizedReceipt receipt) async {
    if (_didComplete) return;
    _didComplete = true;

    _canProcess = false;
    _receipt = receipt;
    _maxProgress = 0;
    _errorMessage = null;

    _playScanSound();
    HapticFeedback.lightImpact();

    await stopLiveFeed();

    // Prep recognizer for the next scan session
    _receiptRecognizer?.init();

    if (mounted) setState(() {});
  }

  void _playScanSound() {
    _audioPlayer.play(AssetSource('sounds/checkout_beep.mp3'));
  }

  void _handleProcessingError(Object error, StackTrace stackTrace) {
    debugPrint('Image processing error: $error');
  }

  Future<void> _startLiveFeed() async {
    _didComplete = false;
    await startLiveFeed(_processImage);
    _isReady = true;
    if (mounted) setState(() {});
  }

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
                  if (_scanProgress?.positions.isNotEmpty == true &&
                      _receipt == null) // hide overlays after success
                    PositionOverlay(
                      positions:
                          isScanInProgress ? _scanProgress!.positions : [],
                      imageSize: Size(
                        cameraController!.value.previewSize!.height,
                        cameraController!.value.previewSize!.width,
                      ),
                      screenSize: MediaQuery.of(context).size,
                      company: _scanProgress?.mergedReceipt?.company,
                      sumLabel: _scanProgress?.mergedReceipt?.sumLabel,
                      sum: _scanProgress?.mergedReceipt?.sum,
                    ),
                  if (_scanProgress != null &&
                      _maxProgress > 0 &&
                      _receipt == null)
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
                              valueColor: const AlwaysStoppedAnimation<Color>(
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
            else if (_receipt == null && _errorMessage == null)
              ScanInfoScreen(
                onStartScan: () async {
                  setState(() {
                    _receipt = null;
                    _errorMessage = null;
                    _scanProgress = null; // reset progress
                    _maxProgress = 0; // reset UI
                    _didComplete = false; // reset completion latch
                    _canProcess = true;
                    _isReady = false;
                    isControllerDisposed = false;
                  });

                  _receiptRecognizer?.init(); // reset internal caches

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
                          setState(() {
                            _receipt = null;
                            _scanProgress = null;
                            _maxProgress = 0;
                            _didComplete = false;
                          });
                          _receiptRecognizer?.init();
                        },
                      )
                      : const SizedBox.shrink(),
            ),
            if (_receipt == null && _errorMessage != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withAlpha(224),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Scan failed. Please try again.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
