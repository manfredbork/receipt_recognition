import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:receipt_recognition/receipt_recognition.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'receipt_recognizer_test.mocks.dart';

@GenerateMocks([TextRecognizer, InputImage])
void main() {
  group('ReceiptRecognizer', () {
    late ReceiptRecognizer recognizer;
    late MockTextRecognizer mockTextRecognizer;
    late MockInputImage mockInputImage;

    setUp(() {
      mockTextRecognizer = MockTextRecognizer();
      recognizer = ReceiptRecognizer(textRecognizer: mockTextRecognizer);
      mockInputImage = MockInputImage();
    });

    test(
      'processImage returns RecognizedReceipt with expected values',
      () async {
        final storeTextLine = TextLine(
          text: 'ALDI',
          recognizedLanguages: [],
          boundingBox: Rect.fromLTWH(0, 0, 1, 1),
          cornerPoints: [],
          elements: [],
          confidence: null,
          angle: null,
        );

        final milkTextLine = TextLine(
          text: 'Cocoa 3.5%',
          recognizedLanguages: [],
          boundingBox: Rect.fromLTWH(0, 2, 1, 1),
          cornerPoints: [],
          elements: [],
          confidence: null,
          angle: null,
        );

        final milkPriceTextLine = TextLine(
          text: '\$1.99',
          recognizedLanguages: [],
          boundingBox: Rect.fromLTWH(1, 2, 1, 1),
          cornerPoints: [],
          elements: [],
          confidence: null,
          angle: null,
        );

        final butterTextLine = TextLine(
          text: 'Butter',
          recognizedLanguages: [],
          boundingBox: Rect.fromLTWH(0, 1, 1, 1),
          cornerPoints: [],
          elements: [],
          confidence: null,
          angle: null,
        );

        final butterPriceTextLine = TextLine(
          text: '\$2.99',
          recognizedLanguages: [],
          boundingBox: Rect.fromLTWH(1, 1, 1, 1),
          cornerPoints: [],
          elements: [],
          confidence: null,
          angle: null,
        );

        final totalLabelTextLine = TextLine(
          text: 'Total',
          recognizedLanguages: [],
          boundingBox: Rect.fromLTWH(0, 3, 1, 1),
          cornerPoints: [],
          elements: [],
          confidence: null,
          angle: null,
        );

        final totalTextLine = TextLine(
          text: '\$4.98',
          recognizedLanguages: [],
          boundingBox: Rect.fromLTWH(1, 3, 1, 1),
          cornerPoints: [],
          elements: [],
          confidence: null,
          angle: null,
        );

        final textBlock = TextBlock(
          text: '',
          recognizedLanguages: [],
          boundingBox: Rect.fromLTWH(0, 0, 4, 4),
          cornerPoints: [],
          lines: [
            storeTextLine,
            milkTextLine,
            butterTextLine,
            totalLabelTextLine,
            milkPriceTextLine,
            butterPriceTextLine,
            totalTextLine,
          ],
        );

        final recognizedText = RecognizedText(text: '', blocks: [textBlock]);

        when(
          mockTextRecognizer.processImage(any),
        ).thenAnswer((_) async => recognizedText);

        final result = await recognizer.processImage(mockInputImage);

        expect(result?.positions.first.price.value, 2.99);
        expect(result?.positions.first.product.value, 'Butter');
        expect(result?.positions.last.price.value, 1.99);
        expect(result?.positions.last.product.value, 'Cocoa 3.5%');
        expect(result?.company?.value, 'ALDI');
        expect(result?.sum?.value, 4.98);
      },
    );

    test('processImage handles empty text gracefully', () async {
      final recognizedText = RecognizedText(text: '', blocks: []);

      when(
        mockTextRecognizer.processImage(any),
      ).thenAnswer((_) async => recognizedText);

      final result = await recognizer.processImage(mockInputImage);

      expect(result, null);
    });
  });
}
