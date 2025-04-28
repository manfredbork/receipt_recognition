import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

import 'receipt_models.dart';

/// A receipt parser that parses a receipt from [RecognizedText].
class ReceiptParser {
  /// RegExp patterns
  static const patternCompany =
      r'(Lidl|Aldi|Rewe|Edeka|Penny|Rossmann|Kaufland|Netto|akzenta)';
  static const patternSumLabel = r'(Zu zahlen|Summe|Total|Sum)';
  static const patternAmount = r'-?([0-9])+\s?([.,])\s?([0-9]){2}';

  /// Processes [RecognizedText]. Returns a [RecognizedReceipt].
  static RecognizedReceipt? processText(RecognizedText text) {
    final converted = _convertText(text);
    final parsed = _parseLines(converted);
    final shrunken = _shrinkEntities(parsed);

    return _buildReceipt(shrunken);
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
        patternCompany,
        caseSensitive: false,
      ).stringMatch(line.text);

      if (company != null && !detectedCompany) {
        parsed.add(RecognizedCompany(line: line, value: company));
        detectedCompany = true;

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

      final amount = RegExp(patternAmount).stringMatch(line.text);

      if (amount != null) {
        final locale = _detectsLocale(amount);
        final value = NumberFormat.decimalPattern(locale).parse(amount);

        parsed.add(RecognizedAmount(line: line, value: value));
      } else {
        parsed.add(RecognizedUnknown(line: line, value: line.text));
      }
    }

    final sumLabels = parsed.whereType<RecognizedSumLabel>();

    if (sumLabels.isNotEmpty) {
      final sum = _findSum(parsed, sumLabels.first);
      final indexSum = parsed.indexWhere((e) => e.value == sum.value);

      parsed.removeAt(indexSum);
      parsed.insert(indexSum, sum);
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

    shrunken.removeWhere((a) => shrunken.every((b) => _isInvalid(a, b)));

    final amounts = shrunken.whereType<RecognizedAmount>();

    if (amounts.isEmpty) return [];

    final sums = shrunken.whereType<RecognizedSum>();

    if (sums.isNotEmpty) {
      shrunken.removeWhere((e) => _isGreaterThanBottomBound(e, sums.first));
      shrunken.removeWhere((e) => _isSmallerThanLeftBound(e, sums.first));
    } else {
      shrunken.removeWhere((e) => _isGreaterThanBottomBound(e, amounts.last));
      shrunken.removeWhere((e) => _isSmallerThanLeftBound(e, amounts.last));
    }

    shrunken.removeWhere((e) => _isSmallerThanTopBound(e, amounts.first));

    return shrunken;
  }

  /// Finds sum by sum label. Returns a [RecognizedSum].
  static RecognizedSum _findSum(
    List<RecognizedEntity> entities,
    RecognizedSumLabel sumLabel,
  ) {
    final amounts = entities.whereType<RecognizedAmount>();
    final ySumLabel = sumLabel.line.boundingBox.top;
    final sorted =
        amounts.toList()..sort(
          (a, b) => (a.line.boundingBox.top - ySumLabel).abs().compareTo(
            (b.line.boundingBox.top - ySumLabel).abs(),
          ),
        );
    final sum = sorted.first;

    return RecognizedSum(line: sum.line, value: sum.value);
  }

  /// Checks if [RecognizedEntity] is invalid. Returns a [bool].
  static bool _isInvalid(RecognizedEntity a, RecognizedEntity b) {
    return a is! RecognizedCompany && !_isOpposite(a, b);
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

    RecognizedSum? sum;
    RecognizedCompany? company;

    List<RecognizedPosition> positions = [];
    List<RecognizedUnknown> forbidden = [];

    for (final entity in entities) {
      if (entity is RecognizedSum) {
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
            positions.add(RecognizedPosition(product: yUnknown, price: entity));
            forbidden.add(yUnknown);
            break;
          }
        }
      }
    }

    return RecognizedReceipt(positions: positions, sum: sum, company: company);
  }
}
