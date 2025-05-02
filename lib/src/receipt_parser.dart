import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

import 'receipt_models.dart';

/// A receipt parser that parses a receipt from [RecognizedText].
class ReceiptParser {
  /// RegExp patterns
  static const patternSumLabel = r'(Zu zahlen|Summe|Total|Sum)';
  static const patternUnknown = r'([^0-9\s]){4,}';
  static const patternAmount = r'-?\s?([0-9])+\s?([.,])\s?([0-9]){2}';

  /// RegExp patterns and aliases
  static const patternsCompany = {
    'ldl': 'Lidl',
    'aldi': 'ALDI',
    'rewe': 'REWE',
    'edeka': 'EDEKA',
    'penny': 'PENNY',
    'kaufland': 'Kaufland',
    'netto': 'Netto',
    'akzenta': 'akzenta',
  };

  /// Processes [RecognizedText]. Returns a [RecognizedReceipt].
  static RecognizedReceipt? processText(RecognizedText text) {
    final converted = _convertText(text);
    final parsed = _parseLines(converted);
    final shrunken = _shrinkEntities(parsed);
    final receipt = _buildReceipt(shrunken);

    return receipt;
  }

  /// Converts [RecognizedText]. Returns a list of [TextLine].
  static List<TextLine> _convertText(RecognizedText text) {
    final List<TextLine> lines = [];

    for (final block in text.blocks) {
      lines.addAll(block.lines.map((line) => line));
    }

    return lines
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
  }

  /// Parses a list of [TextLine]. Returns a list of [RecognizedEntity].
  static List<RecognizedEntity> _parseLines(List<TextLine> lines) {
    final List<RecognizedEntity> parsed = [];

    bool detectedCompany = false;
    bool detectedSumLabel = false;

    for (final line in lines) {
      final company = RegExp(
        '(${patternsCompany.keys.join('|')})',
        caseSensitive: false,
      ).stringMatch(line.text);

      if (company != null && !detectedCompany) {
        final pCompany = patternsCompany[company.toLowerCase()];

        if (pCompany != null) {
          parsed.add(RecognizedCompany(line: line, value: pCompany));
          detectedCompany = true;
        }

        continue;
      }

      final sumLabel = RegExp(
        patternSumLabel,
        caseSensitive: false,
      ).stringMatch(line.text);

      if (sumLabel != null && !detectedSumLabel) {
        parsed.add(RecognizedSumLabel(line: line, value: sumLabel));
        detectedSumLabel = true;

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

  /// Detects locale by separator. Returns a [String].
  static String? _detectsLocale(String text) {
    if (text.contains('.')) {
      return 'en_US';
    } else if (text.contains(',')) {
      return 'eu';
    }

    return Intl.defaultLocale;
  }

  /// Shrinks a list of [RecognizedEntity]. Returns a list of [RecognizedEntity].
  static List<RecognizedEntity> _shrinkEntities(
    List<RecognizedEntity> entities,
  ) {
    final List<RecognizedEntity> shrunken = List.from(entities);

    final beforeAmounts = shrunken.whereType<RecognizedAmount>();

    final yAmounts =
        beforeAmounts.toList()..sort(
          (a, b) =>
              (a.line.boundingBox.top).compareTo((b.line.boundingBox.top)),
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

    final xAmounts =
        afterAmounts.toList()..sort(
          (a, b) =>
              (a.line.boundingBox.left).compareTo((b.line.boundingBox.left)),
        );

    if (xAmounts.isNotEmpty) {
      shrunken.removeWhere((e) => _isSmallerThanLeftBound(e, xAmounts.last));
    }

    return shrunken;
  }

  /// Finds sum by sum label. Returns a [RecognizedSum].
  static RecognizedSum? _findSum(
    List<RecognizedEntity> entities,
    RecognizedSumLabel sumLabel,
  ) {
    final ySumLabel = sumLabel.line.boundingBox.top;
    final amounts = entities.whereType<RecognizedAmount>();
    final yAmounts =
        amounts.toList()..sort(
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

  /// Checks if [RecognizedEntity] is invalid. Returns a [bool].
  static bool _isInvalid(RecognizedEntity a, RecognizedEntity b) {
    return a is! RecognizedCompany &&
        a is! RecognizedSumLabel &&
        a is! RecognizedSum &&
        !_isOpposite(a, b);
  }

  /// Checks if [RecognizedEntity] is opposite. Returns a [bool].
  static bool _isOpposite(RecognizedEntity a, RecognizedEntity b) {
    final aBox = a.line.boundingBox;
    final bBox = b.line.boundingBox;

    return !aBox.overlaps(bBox) &&
        (aBox.bottom > bBox.top && aBox.top < bBox.bottom);
  }

  /// Checks if [RecognizedEntity] is smaller than left bound. Returns a [bool].
  static bool _isSmallerThanLeftBound(RecognizedEntity a, RecognizedEntity b) {
    final aBox = a.line.boundingBox;
    final bBox = b.line.boundingBox;

    return a is RecognizedAmount && aBox.right < bBox.left;
  }

  /// Checks if [RecognizedEntity] is smaller than top bound. Returns a [bool].
  static bool _isSmallerThanTopBound(RecognizedEntity a, RecognizedEntity b) {
    final aBox = a.line.boundingBox;
    final bBox = b.line.boundingBox;

    return a is! RecognizedCompany && aBox.bottom < bBox.top;
  }

  /// Checks if [RecognizedEntity] is greater than bottom bound. Returns a [bool].
  static bool _isGreaterThanBottomBound(
    RecognizedEntity a,
    RecognizedEntity b,
  ) {
    final aBox = a.line.boundingBox;
    final bBox = b.line.boundingBox;

    return aBox.top > bBox.bottom;
  }

  /// Builds receipt from list of [RecognizedEntity]. Returns a [RecognizedReceipt].
  static RecognizedReceipt? _buildReceipt(List<RecognizedEntity> entities) {
    final unknowns = entities.whereType<RecognizedUnknown>();

    if (unknowns.isEmpty) return null;

    final yUnknowns = unknowns.toList();

    RecognizedSumLabel? sumLabel;
    RecognizedSum? sum;
    RecognizedCompany? company;

    List<RecognizedPosition> positions = [];
    List<RecognizedUnknown> forbidden = [];

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
            positions.add(
              RecognizedPosition(
                product: RecognizedProduct(
                  value: yUnknown.value,
                  line: yUnknown.line,
                ),
                price: RecognizedPrice(line: entity.line, value: entity.value),
              ),
            );
            forbidden.add(yUnknown);
            break;
          }
        }
      }
    }

    if (sumLabel == null) sum = null;

    return RecognizedReceipt(positions: positions, sum: sum, company: company);
  }
}
