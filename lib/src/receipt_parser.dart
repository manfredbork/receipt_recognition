import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

import 'receipt_models.dart';

/// A receipt parser that parses a receipt from [RecognizedText].
class ReceiptParser {
  /// RegExp patterns
  static const patternCompany =
      r'(Lidl|Aldi|Rewe|Edeka|Penny|Rossmann|Kaufland|Netto)';
  static const patternSumLabel = r'(Zu zahlen|Summe|Gesamtsumme|Total|Sum)';
  static const patternAmount = r'-?([0-9])+([.,])([0-9]){2}';

  /// Processes [RecognizedText]. Returns a [RecognizedReceipt].
  static RecognizedReceipt? processText(RecognizedText text) {
    final convertedLines = _convertText(text);
    final parsedEntities = _parseLines(convertedLines);
    final shrunkenEntities = _shrinkEntities(parsedEntities);

    return _buildReceipt(shrunkenEntities);
  }

  /// Converts [RecognizedText]. Returns a list of [TextLine].
  static List<TextLine> _convertText(RecognizedText text) {
    final List<TextLine> lines = [];

    for (final block in text.blocks) {
      lines.addAll(block.lines.map((line) => line));
    }

    return lines;
  }

  /// Parses a list of [TextLine]. Returns a list of [RecognizedEntity].
  static List<RecognizedEntity> _parseLines(List<TextLine> lines) {
    final List<RecognizedEntity> parsedEntities = [];

    bool detectedCompany = false;
    bool detectedSumLabel = false;

    for (final line in lines) {
      final company = RegExp(
        patternCompany,
        caseSensitive: false,
      ).stringMatch(line.text);

      if (company != null && !detectedCompany) {
        parsedEntities.add(RecognizedCompany(line: line, value: company));
        detectedCompany = true;

        continue;
      }

      final sumLabel = RegExp(
        patternSumLabel,
        caseSensitive: false,
      ).stringMatch(line.text);

      if (sumLabel != null && !detectedSumLabel) {
        parsedEntities.add(RecognizedSumLabel(line: line, value: sumLabel));
        detectedSumLabel = true;

        continue;
      }

      final amount = RegExp(patternAmount).stringMatch(line.text);

      if (amount != null) {
        final locale = _detectsLocale(amount);
        final value = NumberFormat.decimalPattern(locale).parse(amount);

        parsedEntities.add(RecognizedAmount(line: line, value: value));
      } else {
        parsedEntities.add(RecognizedUnknown(line: line, value: line.text));
      }
    }

    return parsedEntities;
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
    final List<RecognizedEntity> shrunkenEntities = List.from(entities);

    shrunkenEntities.removeWhere(
      (a) => entities.any((b) => _isInvalidAmount(a, b)),
    );
    shrunkenEntities.removeWhere(
      (a) => entities.any((b) => _isInvalidProduct(a, b)),
    );

    final sumLabels = shrunkenEntities.whereType<RecognizedSumLabel>();
    final amounts = shrunkenEntities.whereType<RecognizedAmount>();

    if (amounts.isEmpty) return [];

    final RecognizedSum? sum;

    if (sumLabels.isNotEmpty) {
      sum = _findSum(amounts.toList(), sumLabels.first);

      final indexSum = shrunkenEntities.lastIndexWhere(
        (e) => e.value == sum?.value,
      );

      shrunkenEntities.removeAt(indexSum);
      shrunkenEntities.insert(indexSum, sum);
    }

    return shrunkenEntities..sort(
      (a, b) => a.line.boundingBox.top.compareTo(b.line.boundingBox.top),
    );
  }

  /// Finds sum in amounts by label. Returns a [RecognizedSum].
  static RecognizedSum _findSum(
    List<RecognizedAmount> amounts,
    RecognizedSumLabel sumLabel,
  ) {
    final ySumLabel = sumLabel.line.boundingBox.top;
    final sortedAmounts = List.from(amounts)..sort(
      (a, b) => (a.line.boundingBox.top - ySumLabel).abs().compareTo(
        (b.line.boundingBox.top - ySumLabel).abs(),
      ),
    );
    final sum = sortedAmounts.first;

    return RecognizedSum(line: sum.line, value: sum.value);
  }

  /// Checks if [RecognizedEntity] is opposite. Returns a [bool].
  static bool _isOpposite(RecognizedEntity a, RecognizedEntity b) {
    final aBB = a.line.boundingBox;
    final bBB = b.line.boundingBox;

    return a != b && (aBB.bottom > bBB.top && aBB.top < bBB.bottom);
  }

  /// Checks if [RecognizedEntity] is invalid amount. Returns a [bool].
  static bool _isInvalidAmount(RecognizedEntity a, RecognizedEntity b) {
    final aBB = a.line.boundingBox;
    final bBB = b.line.boundingBox;
    final aA = a is RecognizedAmount;
    final aOb = _isOpposite(a, b);
    final aLb = a.line.boundingBox.right < b.line.boundingBox.left;

    return a != b && (aBB.overlaps(bBB) || (aA && aOb && aLb));
  }

  /// Checks if [RecognizedEntity] is invalid product. Returns a [bool].
  static bool _isInvalidProduct(RecognizedEntity a, RecognizedEntity b) {
    final aBB = a.line.boundingBox;
    final bBB = b.line.boundingBox;
    final aU = a is RecognizedUnknown;
    final aOb = _isOpposite(a, b);
    final aGb = a.line.boundingBox.right > b.line.boundingBox.left;

    return a != b && (aBB.overlaps(bBB) || (aU && aOb && aGb));
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
