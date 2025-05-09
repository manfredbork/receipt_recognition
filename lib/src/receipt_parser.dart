import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

import 'receipt_models.dart';

class ReceiptParser {
  static const patternStop = r'(Geg.|Rückgeld|Steuer|Brutto)';
  static const patternIgnore =
      r'(E-Bon|Handeingabe|Stk|EUR)|(([0-9])+\s?([.,])\s?([0-9]){3})';
  static const patternCompany =
      r'(Lidl|Aldi|Rewe|Edeka|Penny|Kaufland|Netto|Akzenta)';
  static const patternSumLabel = r'(Zu zahlen|Summe|Total|Sum)';
  static const patternUnknown = r'([^0-9]){6,}';
  static const patternAmount = r'-?\s?([0-9])+\s?([.,])\s?([0-9]){2}';

  static RecognizedReceipt? processText(RecognizedText text) {
    final converted = _convertText(text);
    final parsed = _parseLines(converted);
    final shrunken = _shrinkEntities(parsed);
    final receipt = _buildReceipt(shrunken);

    return receipt;
  }

  static List<TextLine> _convertText(RecognizedText text) {
    final List<TextLine> lines = [];

    for (final block in text.blocks) {
      lines.addAll(block.lines.map((line) => line));
    }

    return lines
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
  }

  static List<RecognizedEntity> _parseLines(List<TextLine> lines) {
    final List<RecognizedEntity> parsed = [];

    bool detectedCompany = false;
    bool detectedSumLabel = false;

    for (final line in lines) {
      if (RegExp(patternStop, caseSensitive: false).hasMatch(line.text)) {
        break;
      }

      if (RegExp(patternIgnore, caseSensitive: false).hasMatch(line.text)) {
        continue;
      }

      final company = RegExp(
        patternCompany,
        caseSensitive: false,
      ).stringMatch(line.text);

      if (company != null) {
        if (!detectedCompany) {
          parsed.add(RecognizedCompany(line: line, value: company));
          detectedCompany = true;
        }

        continue;
      }

      final sumLabel = RegExp(
        patternSumLabel,
        caseSensitive: false,
      ).stringMatch(line.text);

      if (sumLabel != null) {
        if (!detectedSumLabel) {
          parsed.add(RecognizedSumLabel(line: line, value: sumLabel));
          detectedSumLabel = true;
        }

        continue;
      }

      final unknown = RegExp(patternUnknown).stringMatch(line.text);

      if (unknown != null) {
        parsed.add(RecognizedUnknown(line: line, value: line.text));

        continue;
      }

      final amount = RegExp(patternAmount).stringMatch(line.text);

      if (amount != null) {
        final locale = _detectsLocale(amount);
        final value = NumberFormat.decimalPattern(locale).parse(amount);

        parsed.add(RecognizedAmount(line: line, value: value));
      }
    }

    return parsed;
  }

  static String? _detectsLocale(String text) {
    if (text.contains('.')) {
      return 'en_US';
    } else if (text.contains(',')) {
      return 'eu';
    }

    return Intl.defaultLocale;
  }

  static List<RecognizedEntity> _shrinkEntities(
    List<RecognizedEntity> entities,
  ) {
    final List<RecognizedEntity> shrunken = List<RecognizedEntity>.from(
      entities,
    );

    final beforeAmounts = shrunken.whereType<RecognizedAmount>();

    final yAmounts = List<RecognizedAmount>.from(beforeAmounts)..sort(
      (a, b) => (a.line.boundingBox.top).compareTo((b.line.boundingBox.top)),
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

    final afterAmounts = shrunken.whereType<RecognizedAmount>();

    final xAmounts = List<RecognizedAmount>.from(afterAmounts)..sort(
      (a, b) => (a.line.boundingBox.left).compareTo((b.line.boundingBox.left)),
    );

    if (xAmounts.isNotEmpty) {
      shrunken.removeWhere((e) => _isSmallerThanLeftBound(e, xAmounts.last));
    }

    return shrunken;
  }

  static RecognizedSum? _findSum(
    List<RecognizedEntity> entities,
    RecognizedSumLabel sumLabel,
  ) {
    final ySumLabel = sumLabel.line.boundingBox.top;
    final yAmounts = List<RecognizedAmount>.from(
      entities.whereType<RecognizedAmount>(),
    )..sort(
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
    final aBox = a.line.boundingBox;
    final bBox = b.line.boundingBox;

    return a is RecognizedAmount && aBox.right < bBox.left;
  }

  static bool _isSmallerThanTopBound(RecognizedEntity a, RecognizedEntity b) {
    final aBox = a.line.boundingBox;
    final bBox = b.line.boundingBox;

    return a is! RecognizedCompany && aBox.bottom < bBox.top;
  }

  static bool _isGreaterThanBottomBound(
    RecognizedEntity a,
    RecognizedEntity b,
  ) {
    final aBox = a.line.boundingBox;
    final bBox = b.line.boundingBox;

    return aBox.top > bBox.bottom;
  }

  static RecognizedReceipt? _buildReceipt(List<RecognizedEntity> entities) {
    final yUnknowns = List<RecognizedUnknown>.from(
      entities.whereType<RecognizedUnknown>(),
    );

    RecognizedSumLabel? sumLabel;
    RecognizedSum? sum;
    RecognizedCompany? company;

    final RecognizedReceipt receipt = RecognizedReceipt.empty();
    final List<RecognizedUnknown> forbidden = [];

    for (final entity in entities) {
      if (entity is RecognizedSumLabel) {
        sumLabel = entity;
      } else if (entity is RecognizedSum) {
        sum = entity;
      } else if (entity is RecognizedCompany) {
        company = entity;
      } else if (entity is RecognizedAmount) {
        final yAmount = entity.line.boundingBox.top;

        yUnknowns.sort(
          (a, b) => (yAmount - a.line.boundingBox.top).abs().compareTo(
            (yAmount - b.line.boundingBox.top).abs(),
          ),
        );

        for (final yUnknown in yUnknowns) {
          if (!forbidden.contains(yUnknown)) {
            receipt.positions.add(
              RecognizedPosition(
                product: RecognizedProduct(
                  value: yUnknown.value,
                  line: yUnknown.line,
                ),
                price: RecognizedPrice(line: entity.line, value: entity.value),
                timestamp: receipt.timestamp,
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
