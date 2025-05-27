import 'dart:math';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

final class ReceiptParser {
  static final RegExp patternCompany = RegExp(
    r'(Aldi|Rewe|Edeka|Penny|Lidl|Kaufland|Netto|Akzenta)',
    caseSensitive: false,
  );

  static final RegExp patternSumLabel = RegExp(
    r'(Zu zahlen|Summe|Total|Sum)',
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

  static const int boundingBoxBuffer = 100;

  static RecognizedReceipt? processText(RecognizedText text) {
    final lines = _convertText(text);
    final parsedEntities = _parseLines(lines);
    return _buildReceipt(parsedEntities);
  }

  static List<TextLine> _convertText(RecognizedText text) {
    return text.blocks.expand((block) => block.lines).toList()
      ..sort((a, b) => a.boundingBox.bottom.compareTo(b.boundingBox.bottom));
  }

  static List<RecognizedEntity> _parseLines(List<TextLine> lines) {
    final parsed = <RecognizedEntity>[];
    final bounds = RecognizedBounds.fromLines(lines);
    final receiptHalfWidth = (bounds.minLeft + bounds.maxRight) / 2;

    bool detectedCompany = false;

    for (final line in lines) {
      if (!detectedCompany) {
        final company = patternCompany.stringMatch(line.text);
        if (company != null) {
          parsed.add(RecognizedCompany(line: line, value: company));
          detectedCompany = true;
          continue;
        }
      }

      final sumLabel = patternSumLabel.stringMatch(line.text);
      if (sumLabel != null) {
        parsed.add(RecognizedSumLabel(line: line, value: sumLabel));
        break;
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

    return parsed..sort(
      (a, b) => a.line.boundingBox.top.compareTo(b.line.boundingBox.top),
    );
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

    RecognizedSum? sum;
    RecognizedCompany? company;

    for (final entity in entities) {
      if (entity is RecognizedSumLabel) {
        continue;
      } else if (entity is RecognizedCompany) {
        company = entity;
      } else if (entity is RecognizedAmount) {
        final yAmount = entity.line.boundingBox;

        yUnknowns.sort((a, b) {
          final aT = (yAmount.top - a.line.boundingBox.top).abs();
          final bT = (yAmount.top - b.line.boundingBox.top).abs();
          final aB = (yAmount.bottom - a.line.boundingBox.bottom).abs();
          final bB = (yAmount.bottom - b.line.boundingBox.bottom).abs();
          final aCompare = min(aT, aB);
          final bCompare = min(bT, bB);
          return aCompare.compareTo(bCompare);
        });

        for (final yUnknown in yUnknowns) {
          final yT = (yAmount.top - yUnknown.line.boundingBox.top).abs();
          final yB = (yAmount.bottom - yUnknown.line.boundingBox.bottom).abs();
          final yCompare = min(yT, yB);
          if (!forbidden.contains(yUnknown) && yCompare < boundingBoxBuffer) {
            receipt.positions.add(
              RecognizedPosition(
                product: RecognizedProduct(
                  value: yUnknown.value,
                  line: yUnknown.line,
                ),
                price: RecognizedPrice(line: entity.line, value: entity.value),
                timestamp: receipt.timestamp,
                operation: Operation.added,
              ),
            );
            forbidden.add(yUnknown);
            break;
          } else {
            sum = RecognizedSum(line: entity.line, value: entity.value);
            break;
          }
        }
      }
    }

    receipt.sum = sum;
    receipt.company = company;

    return receipt;
  }
}
