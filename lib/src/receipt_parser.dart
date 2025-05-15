import 'dart:math';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

import 'receipt_core.dart';

final class ReceiptParser {
  static final RegExp patternStopKeywords = RegExp(
    r'(Geg.|Rückgeld|Steuer|Brutto)',
    caseSensitive: false,
  );
  static final RegExp patternIgnoreKeywords = RegExp(
    r'(E-Bon|Coupon|Hand|Eingabe|Posten|Stk|EUR/kg)',
    caseSensitive: false,
  );
  static final RegExp patternIgnoreNumbers = RegExp(
    r'\d{1,3}(?:\s?[.,]\s?\d{3})+',
  );
  static final RegExp patternCompany = RegExp(
    r'(Aldi|Rewe|Edeka|Penny|Kaufland|Netto|Akzenta)',
    caseSensitive: false,
  );
  static final RegExp patternSumLabel = RegExp(
    r'(Zu zahlen|Summe|Total)',
    caseSensitive: false,
  );
  static final RegExp patternUnknown = RegExp(r'[^\d]{6,}');
  static final RegExp patternAmount = RegExp(r'-?\s*\d+\s*[.,]\s*\d{2}');

  static RecognizedReceipt? processText(RecognizedText text) {
    final lines = _convertText(text);
    final parsedEntities = _parseLines(lines);
    final shrunkEntities = _shrinkEntities(parsedEntities);
    return _buildReceipt(shrunkEntities);
  }

  static List<TextLine> _convertText(RecognizedText text) {
    return text.blocks.expand((block) => block.lines).toList()
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
  }

  static List<RecognizedEntity> _parseLines(List<TextLine> lines) {
    final parsed = <RecognizedEntity>[];

    bool detectedCompany = false;
    bool detectedSumLabel = false;

    for (final line in lines) {
      if (patternStopKeywords.hasMatch(line.text)) break;
      if (patternIgnoreKeywords.hasMatch(line.text) ||
          patternIgnoreNumbers.hasMatch(line.text)) {
        continue;
      }

      final company = patternCompany.stringMatch(line.text);
      if (company != null && !detectedCompany) {
        parsed.add(RecognizedCompany(line: line, value: company));
        detectedCompany = true;
        continue;
      }

      final sumLabel = patternSumLabel.stringMatch(line.text);
      if (sumLabel != null && !detectedSumLabel) {
        parsed.add(RecognizedSumLabel(line: line, value: sumLabel));
        detectedSumLabel = true;
        continue;
      }

      final unknown = patternUnknown.stringMatch(line.text);
      if (unknown != null) {
        parsed.add(RecognizedUnknown(line: line, value: line.text));
        continue;
      }

      final amount = patternAmount.stringMatch(line.text);
      if (amount != null) {
        final locale = _detectsLocale(amount);
        final normalized = Formatter.normalizeCommas(amount);
        final value = NumberFormat.decimalPattern(locale).parse(normalized);
        parsed.add(RecognizedAmount(line: line, value: value));
      }
    }

    return parsed;
  }

  static String? _detectsLocale(String text) {
    if (text.contains('.')) return 'en_US';
    if (text.contains(',')) return 'eu';
    return Intl.defaultLocale;
  }

  static List<RecognizedEntity> _shrinkEntities(
    List<RecognizedEntity> entities,
  ) {
    final shrunken = List<RecognizedEntity>.from(entities);
    final yAmounts =
        shrunken.whereType<RecognizedAmount>().toList()..sort(
          (a, b) => a.line.boundingBox.top.compareTo(b.line.boundingBox.top),
        );

    if (yAmounts.isNotEmpty) {
      shrunken.removeWhere((e) => _isSmallerThanTopBound(e, yAmounts.first));
      shrunken.removeWhere((e) => _isGreaterThanBottomBound(e, yAmounts.last));
    }

    final sumLabels = shrunken.whereType<RecognizedSumLabel>();
    if (sumLabels.isNotEmpty) {
      final sum = _findSum(shrunken, sumLabels.first);
      if (sum != null) {
        final indexSum = shrunken.indexWhere((e) => e.value == sum.value);
        if (indexSum >= 0) {
          shrunken.removeAt(indexSum);
          shrunken.insert(indexSum, sum);
          shrunken.removeWhere((e) => _isGreaterThanBottomBound(e, sum));
        }
      }
    }

    shrunken.removeWhere((a) => shrunken.every((b) => _isInvalid(a, b)));
    final xAmounts =
        shrunken.whereType<RecognizedAmount>().toList()..sort(
          (a, b) => a.line.boundingBox.left.compareTo(b.line.boundingBox.left),
        );

    if (xAmounts.isNotEmpty) {
      shrunken.removeWhere((e) => _isSmallerThanLeftBound(e, xAmounts.last));
    }

    return shrunken;
  }

  static bool _isInvalid(RecognizedEntity a, RecognizedEntity b) {
    return a is! RecognizedCompany &&
        a is! RecognizedSumLabel &&
        a is! RecognizedSum &&
        !_isOpposite(a, b);
  }

  static bool _isOpposite(RecognizedEntity a, RecognizedEntity b) {
    final aBox = a.line.boundingBox;
    final bBox = b.line.boundingBox;
    return !aBox.overlaps(bBox) &&
        (aBox.bottom > bBox.top && aBox.top < bBox.bottom);
  }

  static bool _isSmallerThanLeftBound(RecognizedEntity a, RecognizedEntity b) {
    return a is RecognizedAmount &&
        a.line.boundingBox.right < b.line.boundingBox.left;
  }

  static bool _isSmallerThanTopBound(RecognizedEntity a, RecognizedEntity b) {
    return a is! RecognizedCompany &&
        a.line.boundingBox.bottom < b.line.boundingBox.top;
  }

  static bool _isGreaterThanBottomBound(
    RecognizedEntity a,
    RecognizedEntity b,
  ) {
    return a.line.boundingBox.top > b.line.boundingBox.bottom;
  }

  static RecognizedSum? _findSum(
    List<RecognizedEntity> entities,
    RecognizedSumLabel sumLabel,
  ) {
    final ySumLabel = sumLabel.line.boundingBox.top;
    final yAmounts =
        entities.whereType<RecognizedAmount>().toList()..sort(
          (a, b) => (a.line.boundingBox.top - ySumLabel).abs().compareTo(
            (b.line.boundingBox.top - ySumLabel).abs(),
          ),
        );

    if (yAmounts.isNotEmpty) {
      final yAmount = yAmounts.first.line.boundingBox.top;
      final hSumLabel = (ySumLabel - sumLabel.line.boundingBox.bottom).abs();
      if ((yAmount - ySumLabel).abs() < hSumLabel) {
        return RecognizedSum(
          line: yAmounts.first.line,
          value: yAmounts.first.value,
        );
      }
    }
    return null;
  }

  static RecognizedReceipt? _buildReceipt(List<RecognizedEntity> entities) {
    final yUnknowns = entities.whereType<RecognizedUnknown>().toList();
    final receipt = RecognizedReceipt.empty();
    final List<RecognizedUnknown> forbidden = [];

    RecognizedSumLabel? sumLabel;
    RecognizedSum? sum;
    RecognizedCompany? company;

    for (final entity in entities) {
      if (entity is RecognizedSumLabel) {
        sumLabel = entity;
      } else if (entity is RecognizedSum) {
        sum = entity;
      } else if (entity is RecognizedCompany) {
        company = entity;
      } else if (entity is RecognizedAmount) {
        final yAmount = entity.line.boundingBox;

        yUnknowns.sort(
          (a, b) => (yAmount.top - a.line.boundingBox.top).abs().compareTo(
            (yAmount.top - b.line.boundingBox.top).abs(),
          ),
        );

        for (final yUnknown in yUnknowns) {
          if (!forbidden.contains(yUnknown) &&
              (yAmount.top - yUnknown.line.boundingBox.top).abs() <
                  yAmount.height * pi) {
            receipt.positions.add(
              RecognizedPosition(
                product: RecognizedProduct(
                  value: yUnknown.value,
                  line: yUnknown.line,
                ),
                price: RecognizedPrice(line: entity.line, value: entity.value),
                timestamp: receipt.timestamp,
                group: PositionGroup.empty(),
                operation: Operation.added,
              ),
            );
            forbidden.add(yUnknown);
            break;
          }
        }
      }
    }

    receipt.sumLabel = sumLabel;
    receipt.sum = sum;
    receipt.company = company;
    return receipt;
  }
}
