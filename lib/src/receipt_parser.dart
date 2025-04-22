import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

import 'receipt_models.dart';

/// A receipt parser that parses a receipt from [RecognizedText].
class ReceiptParser {
  /// Constructor to create an instance of [ReceiptRecognizer].
  ReceiptParser();

  /// Processes [RecognizedText]. Returns a list of [RecognizedEntity].
  List<RecognizedEntity> processText(RecognizedText text) {
    final convertedLines = _convertText(text);
    final parsedEntities = _parseLines(convertedLines);
    final optimizedEntities = _optimizeEntities(parsedEntities);
    return optimizedEntities;
  }

  /// Builds receipt from list of [RecognizedEntity]. Returns a [RecognizedReceipt].
  RecognizedReceipt? buildReceipt(List<RecognizedEntity> entities) {
    final yUnknowns = [...entities.whereType<RecognizedUnknown>()];
    if (yUnknowns.isEmpty) return null;
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

  static const _empty = '';
  static const _period = '.';
  static const _comma = ',';
  static const _localeEU = 'eu';
  static const _localeUS = 'en_US';
  static const _checkIfSumLabel = r'^(Zu zahlen|Summe|Gesamtsumme|Total|Sum)$';
  static const _checkIfCompany = r'^(Lidl|Aldi|Rewe|Edeka|Penny|Netto)$';
  static const _checkIfUnknown = r'^[^0-9].*$';
  static const _checkIfAmount = r'^.*-?([0-9])+\s?([.,])\s?([0-9]){2}.*$';
  static const _replaceIfAmount = r'[^-0-9,.]';

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
    for (final line in lines) {
      if (_isAmount(line.text)) {
        final locale = _getLocale(line.text);
        final text = _getReplacedText(line.text);
        try {
          parsedEntities.add(
            RecognizedAmount(
              line: line,
              value: NumberFormat.decimalPattern(locale).parse(text),
            ),
          );
        } on FormatException {
          parsedEntities.add(RecognizedUnknown(line: line, value: line.text));
        }
      } else if (_isUnknown(line.text)) {
        parsedEntities.add(RecognizedUnknown(line: line, value: line.text));
      }
    }
    return parsedEntities;
  }

  /// Finds amounts. Returns a list of [RecognizedAmount].
  static List<RecognizedAmount> _findAmounts(List<RecognizedEntity> entities) {
    final amounts = entities.whereType<RecognizedAmount>();
    if (amounts.isEmpty) return [];
    return [...amounts];
  }

  /// Finds company. Returns a [RecognizedCompany].
  static RecognizedCompany? _findCompany(List<RecognizedEntity> entities) {
    final company = entities.where(
      (e) =>
          e is RecognizedUnknown &&
          RegExp(_checkIfCompany, caseSensitive: false).hasMatch(e.value),
    );
    if (company.isEmpty) return null;
    return RecognizedCompany(
      line: company.first.line,
      value: company.first.value,
    );
  }

  /// Finds sum. Returns a [RecognizedSum].
  static RecognizedSum? _findSum(List<RecognizedEntity> entities) {
    final sumLabel = entities.where(
      (e) =>
          e is RecognizedUnknown &&
          RegExp(_checkIfSumLabel, caseSensitive: false).hasMatch(e.value),
    );
    if (sumLabel.isEmpty) return null;
    final ySumLabel = sumLabel.first.line.boundingBox.top;
    final yAmounts = [...entities.whereType<RecognizedAmount>()];
    if (yAmounts.isEmpty) return null;
    yAmounts.sort(
      (a, b) => (ySumLabel - a.line.boundingBox.top).abs().compareTo(
        (ySumLabel - b.line.boundingBox.top).abs(),
      ),
    );
    return RecognizedSum(
      line: yAmounts.first.line,
      value: yAmounts.first.value,
    );
  }

  /// Optimizes to a list of [RecognizedEntity]. Returns a list of [RecognizedEntity].
  static List<RecognizedEntity> _optimizeEntities(
    List<RecognizedEntity> entities,
  ) {
    entities.sort(
      (a, b) => a.line.boundingBox.top.compareTo(b.line.boundingBox.top),
    );
    final company = _findCompany(entities);
    final sum = _findSum(entities);
    final amounts = _findAmounts(entities);
    if (amounts.isEmpty) return [];
    final min = amounts.first;
    final max = sum ?? amounts.last;
    final outer = entities.where(
      (e) => _isOuterLeft(e, entities) || _isOuterRight(e, entities),
    );
    if (outer.isEmpty) return [];
    final reduced = [...outer];
    reduced.removeWhere((e) => _isOutOfBounds(e, min, max));
    reduced.removeWhere((e) => _isInvalidCompany(e, min));
    reduced.removeWhere((e) => _isInvalidAmount(e, max));
    List<RecognizedEntity> merged = [];
    if (company != null) merged = merged + [company];
    merged = merged + reduced;
    if (sum != null) merged = merged + [sum];
    return merged;
  }

  /// Checks if entity is on the outer left side. Returns a [bool].
  static bool _isOuterLeft(
    RecognizedEntity entity,
    List<RecognizedEntity> entities,
  ) {
    return entities.every(
      (e) =>
          !_isOpposite(e, entity) ||
          (_isOpposite(e, entity) &&
              e.line.boundingBox.left > entity.line.boundingBox.left),
    );
  }

  /// Checks if entity is on the outer right side. Returns a [bool].
  static bool _isOuterRight(
    RecognizedEntity entity,
    List<RecognizedEntity> entities,
  ) {
    return entities.every(
      (e) =>
          !_isOpposite(e, entity) ||
          (_isOpposite(e, entity) &&
              e.line.boundingBox.right < entity.line.boundingBox.right),
    );
  }

  /// Checks if [RecognizedEntity] is opposite. Returns a [bool].
  static bool _isOpposite(RecognizedEntity a, RecognizedEntity b) {
    return !a.line.boundingBox.overlaps(b.line.boundingBox) &&
        a.line.boundingBox.bottom > b.line.boundingBox.top &&
        a.line.boundingBox.top < b.line.boundingBox.bottom;
  }

  /// Checks if [RecognizedEntity] is out of bounds. Returns a [bool].
  static bool _isOutOfBounds(
    RecognizedEntity entity,
    RecognizedEntity min,
    RecognizedEntity max,
  ) {
    return (entity is! RecognizedCompany) &&
        (entity.line.boundingBox.bottom < min.line.boundingBox.top ||
            entity.line.boundingBox.top >= max.line.boundingBox.top);
  }

  /// Checks if entity is an invalid [RecognizedCompany]. Returns a [bool].
  static bool _isInvalidCompany(RecognizedEntity entity, RecognizedEntity min) {
    return entity is RecognizedCompany &&
        entity.line.boundingBox.bottom >= min.line.boundingBox.top;
  }

  /// Checks if entity is an invalid [RecognizedAmount]. Returns a [bool].
  static bool _isInvalidAmount(RecognizedEntity entity, RecognizedEntity max) {
    return entity is RecognizedAmount &&
        entity.line.boundingBox.right < max.line.boundingBox.left;
  }

  /// Gets locale by separator. Returns a [String].
  static String _getLocale(String text) {
    if (text.contains(_period)) {
      return _localeUS;
    }
    return _localeEU;
  }

  /// Gets replaced text. Returns a [String].
  static String _getReplacedText(String text) {
    final locale = _getLocale(text);
    if (locale == _localeUS) {
      return text
          .replaceAll(RegExp(_replaceIfAmount), _empty)
          .replaceFirst(_comma, _period);
    }
    return text
        .replaceAll(RegExp(_replaceIfAmount), _empty)
        .replaceFirst(_period, _comma);
  }

  /// Checks if text is [RecognizedUnknown]. Returns [bool].
  static bool _isUnknown(String text) {
    return RegExp(_checkIfUnknown).hasMatch(text);
  }

  /// Checks if text is [RecognizedAmount]. Returns [bool].
  static bool _isAmount(String text) {
    return RegExp(_checkIfAmount).hasMatch(text);
  }
}
