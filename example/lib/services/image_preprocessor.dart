import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

class ImagePreprocessor {
  /// Preprocesses an image for better OCR recognition
  ///
  /// Pipeline:
  /// 1. Resize to max 1280px width
  /// 2. Convert to grayscale
  /// 3. Apply Gaussian blur (noise reduction)
  /// 4. Enhance contrast with CLAHE
  static Future<Uint8List> preprocessForOCR(Uint8List imageBytes) async {
    try {
      // Decode image
      cv.Mat image = cv.imdecode(imageBytes, cv.IMREAD_COLOR);

      // Step 1: Resize to max 1080px width while maintaining aspect ratio
      image = _resizeImage(image, maxWidth: 1280);

      // Step 2: Convert to grayscale
      cv.Mat grayImage = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
      image.dispose(); // Clean up original

      // Step 3: Apply light Gaussian blur to reduce noise
      cv.Mat blurredImage = cv.gaussianBlur(grayImage, (3, 3), 0.8);
      grayImage.dispose();

      // Step 4: Enhance contrast with CLAHE
      cv.CLAHE clahe = cv.createCLAHE(clipLimit: 3.0, tileGridSize: (8, 8));
      cv.Mat contrastImage = clahe.apply(blurredImage);
      blurredImage.dispose();
      clahe.dispose();

      // Encode back to bytes - imencode returns (bool success, Uint8List data)
      final (success, encodedData) = cv.imencode('.jpg', contrastImage);
      contrastImage.dispose();

      if (success) {
        return encodedData;
      } else {
        // Fallback to original if encoding fails
        return imageBytes;
      }
    } catch (e) {
      // Fallback to original if any error occurs
      return imageBytes;
    }
  }

  /// Resizes image to specified max width while maintaining aspect ratio
  static cv.Mat _resizeImage(cv.Mat image, {required int maxWidth}) {
    final currentWidth = image.cols;
    final currentHeight = image.rows;

    // Don't upscale, only downscale if needed
    if (currentWidth <= maxWidth) {
      return image;
    }

    // Calculate new dimensions maintaining aspect ratio
    final scale = maxWidth / currentWidth;
    final newHeight = (currentHeight * scale).round();

    cv.Mat resizedImage = cv.resize(
      image,
      (maxWidth, newHeight),
      interpolation: cv.INTER_LANCZOS4, // High-quality interpolation
    );

    image.dispose(); // Clean up original
    return resizedImage;
  }
}
