import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

mixin CameraHandlerMixin<T extends StatefulWidget> on State<T> {
  CameraDescription? cameraBack;
  CameraController? cameraController;
  bool isStreaming = false;

  final orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  bool isControllerDisposed = false;

  Future<void> initCamera(List<CameraDescription> cameras) async {
    for (var cam in cameras) {
      if (cam.lensDirection == CameraLensDirection.back) {
        cameraBack = cam;
        if (mounted) setState(() {});
        return;
      }
    }
  }

  Future<void> startLiveFeed(Function(InputImage) processImage) async {
    if (cameraController != null || isStreaming || isControllerDisposed) return;
    isControllerDisposed = false;
    isStreaming = true;

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
    if (!mounted) return;

    await cameraController!.lockCaptureOrientation(
      DeviceOrientation.portraitUp,
    );

    cameraController!.startImageStream((image) {
      if (!isControllerDisposed) {
        final input = convertToInputImage(image);
        if (input != null) processImage(input);
      }
    });
  }

  Future<void> stopLiveFeed() async {
    if (!isStreaming) return;
    isStreaming = false;

    if (cameraController != null && !isControllerDisposed) {
      final controller = cameraController!;
      cameraController = null;
      isControllerDisposed = true;
      isStreaming = false;

      if (mounted) setState(() {});

      try {
        await controller.stopImageStream();
      } catch (e) {
        debugPrint('stopImageStream error: $e');
      }

      try {
        await controller.dispose();
      } catch (e) {
        debugPrint('dispose error: $e');
      }
    }
  }

  InputImage? convertToInputImage(CameraImage image) {
    if (cameraController == null || image.planes.isEmpty) return null;

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
    final sensorOrientation = cameraBack!.sensorOrientation;

    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
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
