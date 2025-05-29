import 'dart:math';
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

final class ReceiptParser {
  static final RegExp patternCompany = RegExp(
    r'(Aldi|Rewe|Edeka|Penny|Lidl|Kaufland|Netto|Akzenta)',
    caseSensitive: false,
  );

  static final RegExp patternSumLabel = RegExp(
    r'(Zu zahlen|Summe|Total)',
    caseSensitive: false,
  );

  static final RegExp patternStopKeywords = RegExp(
    r'(Geg.|Rückgeld)',
    caseSensitive: false,
  );

  static final RegExp patternIgnoreKeywords = RegExp(
    r'(E-Bon|Coupon|Eingabe|Posten|Stk|kg)',
    caseSensitive: false,
  );

  static final RegExp patternInvalidAmount = RegExp(r'\d+\s*[.,]\s*\d{3}');

  static final RegExp patternAmount = RegExp(r'-?\s*\d+\s*[.,]\s*\d{2}');

  static final RegExp patternUnknown = RegExp(r'\D{6,}');

  static const int boundingBoxBuffer = 50;

  static RecognizedReceipt? processText(RecognizedText text) {
    final lines = _convertText(text);
    final parsedEntities = _parseLines(lines);
    return _buildReceipt(parsedEntities);
  }

  static List<TextLine> _convertText(RecognizedText text) {
    return text.blocks.expand((block) => block.lines).toList()
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
  }

  static List<RecognizedEntity> _parseLines(List<TextLine> lines) {
    final parsed = <RecognizedEntity>[];
    final bounds = RecognizedBounds.fromLines(lines);
    final receiptHalfWidth = (bounds.minLeft + bounds.maxRight) / 2;

    RecognizedCompany? detectedCompany;
    RecognizedSumLabel? detectedSumLabel;

    for (final line in lines) {
      if (detectedSumLabel != null &&
          line.boundingBox.top > detectedSumLabel.line.boundingBox.bottom) {
        continue;
      }

      if (detectedCompany == null) {
        final company = patternCompany.stringMatch(line.text);
        if (company != null) {
          detectedCompany = RecognizedCompany(line: line, value: company);
          parsed.add(detectedCompany);
          continue;
        }
      }

      if (detectedSumLabel == null) {
        final sumLabel = patternSumLabel.stringMatch(line.text);
        if (sumLabel != null) {
          detectedSumLabel = RecognizedSumLabel(line: line, value: sumLabel);
          parsed.add(detectedSumLabel);
          continue;
        }
      }

      if (patternStopKeywords.hasMatch(line.text)) {
        break;
      }

      if (patternIgnoreKeywords.hasMatch(line.text)) {
        continue;
      }

      final amount = patternAmount.stringMatch(line.text);
      if (amount != null && line.boundingBox.left > receiptHalfWidth) {
        final locale = _detectsLocale(amount);
        final trimmedAmount = ReceiptFormatter.trim(amount);
        final value = NumberFormat.decimalPattern(locale).parse(trimmedAmount);
        parsed.add(RecognizedAmount(line: line, value: value));
      }

      final unknown = patternUnknown.stringMatch(line.text);
      if (unknown != null && line.boundingBox.left < receiptHalfWidth) {
        parsed.add(RecognizedUnknown(line: line, value: line.text));
        continue;
      }
    }

    return parsed.toList();
  }

  static String? _detectsLocale(String text) {
    if (text.contains('.')) return 'en_US';
    if (text.contains(',')) return 'eu';
    return Intl.defaultLocale;
  }

  static RecognizedReceipt? _buildReceipt(List<RecognizedEntity> entities) {
    final yUnknowns = entities.whereType<RecognizedUnknown>().toList();
    final receipt = RecognizedReceipt.empty();
    final List<RecognizedUnknown> forbidden = [];

    RecognizedSumLabel? sumLabel;
    RecognizedCompany? company;

    for (final entity in entities) {
      if (entity is RecognizedSumLabel) {
        sumLabel = entity;
      } else if (entity is RecognizedCompany) {
        company = entity;
      } else if (entity is RecognizedAmount) {
        final yAmount = entity.line.boundingBox;

        _sortByDistance(yAmount, yUnknowns);

        for (final yUnknown in yUnknowns) {
          final yT = (yAmount.top - yUnknown.line.boundingBox.top).abs();
          final yB = (yAmount.bottom - yUnknown.line.boundingBox.bottom).abs();
          final yCompare = min(yT, yB);
          if (!forbidden.contains(yUnknown) && yCompare <= boundingBoxBuffer) {
            final product = RecognizedProduct(
              value: yUnknown.value,
              line: yUnknown.line,
            );
            final price = RecognizedPrice(
              line: entity.line,
              value: entity.value,
            );
            final position = RecognizedPosition(
              product: product,
              price: price,
              timestamp: receipt.timestamp,
              operation: Operation.added,
            );
            receipt.positions.add(position);
            product.position = position;
            price.position = position;
            forbidden.add(yUnknown);
            break;
          }
        }
      }
    }

    final yAmounts = entities.whereType<RecognizedAmount>().toList();
    if (sumLabel != null) {
      final ySumLabel = sumLabel.line.boundingBox;

      _sortByDistance(ySumLabel, yAmounts);

      final yT = (ySumLabel.top - yAmounts.first.line.boundingBox.top).abs();
      final yB =
          (ySumLabel.bottom - yAmounts.first.line.boundingBox.bottom).abs();
      final yCompare = min(yT, yB);

      if (yCompare <= boundingBoxBuffer) {
        receipt.sum = RecognizedSum(
          value: yAmounts.first.value,
          line: yAmounts.first.line,
        );
      }
    }

    receipt.company = company;

    return receipt;
  }

  static void _sortByDistance(
    Rect boundingBox,
    List<RecognizedEntity> entities,
  ) {
    entities.sort((a, b) {
      final aT = (boundingBox.top - a.line.boundingBox.top).abs();
      final bT = (boundingBox.top - b.line.boundingBox.top).abs();
      final aB = (boundingBox.bottom - a.line.boundingBox.bottom).abs();
      final bB = (boundingBox.bottom - b.line.boundingBox.bottom).abs();
      final aCompare = min(aT, aB);
      final bCompare = min(bT, bB);
      return aCompare.compareTo(bCompare);
    });
  }
}
