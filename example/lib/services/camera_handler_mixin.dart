import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

mixin CameraHandlerMixin<T extends StatefulWidget> on State<T> {
  CameraDescription? cameraBack;
  CameraController? cameraController;

  final orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  bool isStreaming = false;
  bool isControllerDisposed = false;
  bool _streamActive = false;
  void Function(CameraImage)? _imageListener;

  Future<void> initCamera(List<CameraDescription> cameras) async {
    for (CameraDescription cam in cameras) {
      if (cam.lensDirection == CameraLensDirection.back) {
        cameraBack = cam;
        if (mounted) setState(() {});
        return;
      }
    }
  }

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
        } catch (_) {}
      }
    };

    await cameraController!.startImageStream((img) {
      final l = _imageListener;
      if (l != null) l(img);
    });
  }

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
      } catch (_) {}

      try {
        await controller.dispose();
      } catch (_) {}
    });
  }

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
