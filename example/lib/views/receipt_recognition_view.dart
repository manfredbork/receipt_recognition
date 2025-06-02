import 'dart:io';

import 'package:camera/camera.dart';
import 'package:example/views/receipt_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// A Flutter widget that opens the camera, scans supermarket receipts,
/// and overlays the parsed receipt items.
///
/// It integrates with the [ReceiptRecognizer] and handles platform-specific
/// image stream conversion for ML Kit OCR.
class ReceiptRecognitionView extends StatefulWidget {
  const ReceiptRecognitionView({super.key});

  @override
  State<ReceiptRecognitionView> createState() => _ReceiptRecognitionViewState();
}

class _ReceiptRecognitionViewState extends State<ReceiptRecognitionView> {
  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  ReceiptRecognizer? _receiptRecognizer;
  RecognizedReceipt? _receipt;
  CameraDescription? _cameraBack;
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _canProcess = false;
  bool _isReady = false;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _initializeReceiptRecognizer();
    _initializeCamera();
  }

  /// Initializes the camera and starts the live feed.
  void _initializeCamera() async {
    _cameras = await availableCameras();
    for (var cam in _cameras) {
      if (cam.lensDirection == CameraLensDirection.back) {
        _cameraBack = cam;
        await _startLiveFeed();
        return;
      }
    }
  }

  /// Instantiates the [ReceiptRecognizer] with timeout handling.
  void _initializeReceiptRecognizer() {
    _receiptRecognizer = ReceiptRecognizer(onScanTimeout: _onScanTimeout);
  }

  /// Called if scanning times out without producing a valid receipt.
  void _onScanTimeout() {
    _canProcess = false;
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
    if (_cannotProcess()) {
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

  bool _cannotProcess() {
    return _receiptRecognizer == null || !_canProcess || !_isReady || _isBusy;
  }

  bool _isValidReceipt(RecognizedReceipt? receipt) {
    return receipt != null && receipt.positions.isNotEmpty;
  }

  void _handleSuccessfulScan(RecognizedReceipt receipt) {
    _receipt = receipt;
    _canProcess = false;
    if (mounted) {
      _showSuccessNotification();
    }
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

  @override
  Widget build(BuildContext context) {
    return _liveFeed();
  }

  /// Shows the live camera feed with overlaid receipt results, if any.
  Widget _liveFeed() {
    if (_cameraBack == null ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      body: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CameraPreview(_cameraController!),
            _receipt == null || _canProcess
                ? Container()
                : ReceiptWidget(receipt: _receipt!),
          ],
        ),
      ),
      floatingActionButton:
          !_isReady || _canProcess
              ? null
              : FloatingActionButton.extended(
                onPressed: () {
                  setState(() {
                    _receipt = null;
                    _canProcess = true;
                  });
                },
                label: const Text('Scan receipt'),
                icon: const Icon(Icons.document_scanner_outlined),
              ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  @override
  void dispose() {
    _canProcess = false;
    _isReady = false;
    _isBusy = false;
    _receiptRecognizer?.close();
    _stopLiveFeed();
    super.dispose();
  }

  /// Starts camera stream and feeds image frames to the OCR engine.
  Future<void> _startLiveFeed() async {
    _cameraController = CameraController(
      _cameraBack!,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid
              ? ImageFormatGroup.nv21
              : ImageFormatGroup.bgra8888,
    );

    await _cameraController?.initialize();
    if (!mounted) return;
    await _cameraController?.lockCaptureOrientation(
      DeviceOrientation.portraitUp,
    );

    _cameraController?.startImageStream(_processCameraImage).then((_) {
      _isReady = true;
      if (mounted) setState(() {});
    });
  }

  /// Stops the camera and releases camera controller resources.
  Future<void> _stopLiveFeed() async {
    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();
    _cameraController = null;
  }

  /// Converts raw [CameraImage] into [InputImage] and processes it.
  void _processCameraImage(CameraImage image) {
    if (!_canProcess || _isBusy) return;

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage != null) {
      _processImage(inputImage);
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_cameraController == null || image.planes.isEmpty) return null;

    final rotation = _getInputImageRotation(image);
    if (rotation == null) return null;

    final format = _getInputImageFormat(image);
    if (format == null) return null;

    final bytes = _combineImagePlanes(image);

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _getInputImageRotation(CameraImage image) {
    final sensorOrientation = _cameraBack?.sensorOrientation ?? 0;

    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[_cameraController!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      return InputImageRotationValue.fromRawValue(
        (sensorOrientation - rotationCompensation + 360) % 360,
      );
    }

    return null;
  }

  InputImageFormat? _getInputImageFormat(CameraImage image) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    if ((Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    return format;
  }

  Uint8List _combineImagePlanes(CameraImage image) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }
}
