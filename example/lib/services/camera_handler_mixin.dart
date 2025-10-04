import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// A mixin to manage camera setup, lifecycle, and streaming for MLKit-based apps.
///
/// Provides methods for initializing the back-facing camera, starting/stopping
/// a live feed, and converting camera frames into MLKit-compatible [InputImage]s.
mixin CameraHandlerMixin<T extends StatefulWidget> on State<T> {
  /// The back-facing camera, if available.
  CameraDescription? cameraBack;

  /// The active camera controller used for managing the live feed.
  CameraController? cameraController;

  /// Whether the camera is currently streaming image frames.
  bool isStreaming = false;

  /// Mapping from [DeviceOrientation] to degree-based orientation values.
  final orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Indicates if the camera controller has been disposed.
  bool isControllerDisposed = false;

  // --- New: single image-stream listener + guard ---
  bool _streamActive = false;
  void Function(CameraImage)? _imageListener;

  /// Initializes the back-facing camera from a list of available cameras.
  Future<void> initCamera(List<CameraDescription> cameras) async {
    for (var cam in cameras) {
      if (cam.lensDirection == CameraLensDirection.back) {
        cameraBack = cam;
        if (mounted) setState(() {});
        return;
      }
    }
  }

  /// Starts the live image stream and processes each frame using [processImage].
  ///
  /// Converts [CameraImage] frames into [InputImage]s for use with MLKit.
  Future<void> startLiveFeed(Function(InputImage) processImage) async {
    if (cameraController != null && cameraController!.value.isStreamingImages) {
      try {
        await cameraController!.stopImageStream();
      } catch (_) {}
      _imageListener = null;
      _streamActive = false;
      isStreaming = false;
    }

    if (cameraController == null || isControllerDisposed) {
      if (cameraBack == null) return;

      cameraController = CameraController(
        cameraBack!,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup:
            Platform.isAndroid
                ? ImageFormatGroup.nv21
                : ImageFormatGroup.bgra8888,
      );

      await cameraController!.initialize();
      isControllerDisposed = false;
      if (!mounted) return;

      await cameraController!.lockCaptureOrientation(
        DeviceOrientation.portraitUp,
      );
    }

    _streamActive = true;
    isStreaming = true;

    _imageListener = (CameraImage image) {
      if (!_streamActive) return;
      final input = convertToInputImage(image);
      if (input != null) {
        try {
          processImage(input);
        } catch (e) {
          debugPrint('processImage error: $e');
        }
      }
    };

    await cameraController!.startImageStream((img) {
      final l = _imageListener;
      if (l != null) l(img);
    });
  }

  /// Stops the live image stream and disposes of the camera controller.
  Future<void> stopLiveFeed() async {
    if (cameraController == null) return;

    final controller = cameraController!;
    _streamActive = false;
    isStreaming = false;
    _imageListener = null;

    setState(() {
      cameraController = null;
      isControllerDisposed = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (e) {
        debugPrint('stopImageStream error: $e');
      }

      try {
        await controller.dispose();
      } catch (e) {
        debugPrint('dispose error: $e');
      }
    });
  }

  /// Converts a [CameraImage] into an [InputImage] for MLKit processing.
  InputImage? convertToInputImage(CameraImage image) {
    if (image.planes.isEmpty) return null;

    final rotation = _getInputImageRotation();
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

  InputImageRotation? _getInputImageRotation() {
    if (cameraBack == null) return null;
    final sensorOrientation = cameraBack!.sensorOrientation;

    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      if (cameraController == null) return null;
      final rotationCompensation =
          orientations[cameraController!.value.deviceOrientation];
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
