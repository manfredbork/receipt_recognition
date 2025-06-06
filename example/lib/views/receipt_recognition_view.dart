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
  /// Creates a new instance of [ReceiptRecognitionView].
  const ReceiptRecognitionView({super.key});

  @override
  State<ReceiptRecognitionView> createState() => _ReceiptRecognitionViewState();
}

class _ReceiptRecognitionViewState extends State<ReceiptRecognitionView>
    with CameraHandlerMixin {
  /// Audio player for playing a scan confirmation sound.
  final _audioPlayer = AudioPlayer();

  /// Instance of the receipt recognizer used to process frames.
  ReceiptRecognizer? _receiptRecognizer;

  /// The recognized receipt, if one was successfully scanned.
  RecognizedReceipt? _receipt;

  /// Current progress and intermediate data from the scanning process.
  ScanProgress? _scanProgress;

  /// Error message shown if the scan fails.
  String? _errorMessage;

  /// Tracks the maximum percentage of scan progress reached.
  int _maxProgress = 0;

  /// Whether the app is currently allowed to process frames.
  bool _canProcess = false;

  /// Whether the camera feed is initialized and ready for processing.
  bool _isReady = false;

  /// Whether the app is currently processing a frame.
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

  @override
  Widget build(BuildContext context) {
    return _liveFeed();
  }

  /// Whether the system is ready and allowed to process the next frame.
  bool get isReadyToProcess =>
      _receiptRecognizer != null && _canProcess && _isReady && !_isBusy;

  /// Whether the camera preview is initialized and not disposed.
  bool get isCameraPreviewReady =>
      cameraController?.value.isInitialized == true && !isControllerDisposed;

  /// Whether the scan is still in progress (i.e., not yet 100% complete).
  bool get isScanInProgress => (_scanProgress?.estimatedPercentage ?? 0) < 100;

  @override
  void dispose() {
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

  void _onScanUpdate(ScanProgress progress) {
    setState(() {
      _scanProgress = progress;
      final current = progress.estimatedPercentage ?? 0;
      if (current > _maxProgress) {
        _maxProgress = current;
      }
    });
    if (!isScanInProgress) {
      _playScanSound();
    }
  }

  void _onScanTimeout() {
    if (_receipt != null) return;

    _canProcess = false;
    _receipt = null;
    _maxProgress = 0;
    stopLiveFeed();
    HapticFeedback.lightImpact();

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
    _receipt = receipt;
    _canProcess = false;
    _maxProgress = 0;
    _errorMessage = null;

    stopLiveFeed();

    if (mounted) {
      HapticFeedback.lightImpact();
      setState(() {});
    }
  }

  void _playScanSound() {
    _audioPlayer.play(AssetSource('sounds/checkout_beep.mp3'));
  }

  void _handleProcessingError(Object error, StackTrace stackTrace) {
    debugPrint('Image processing error: $error\n$stackTrace');
  }

  Future<void> _startLiveFeed() async {
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
                  if (_scanProgress?.positions.isNotEmpty == true)
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
            else if (_receipt == null && _errorMessage == null)
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
