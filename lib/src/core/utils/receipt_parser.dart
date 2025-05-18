import 'dart:math';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Parses OCR-detected [RecognizedText] into structured receipt data.
///
/// This parser detects store/company names, product lines, totals, and
/// prices using patterns, positions, and bounding box geometry.
final class ReceiptParser {
  /// Vertical buffer (in pixels) used to exclude lines below the detected
  /// sum or total line on a receipt.
  static const int boundingBoxBuffer = 20;

  /// Keywords that indicate the logical end of a receipt (e.g. taxes).
  static final RegExp patternStopKeywords = RegExp(
    r'(Geg.|Rückgeld|Steuer|Brutto)',
    caseSensitive: false,
  );

  /// Keywords or patterns to ignore during parsing.
  static final RegExp patternIgnoreKeywords = RegExp(
    r'(E-Bon|Coupon|Hand|Eingabe|Posten|Stk|EUR[^A-Za-z])',
    caseSensitive: false,
  );

  /// Detects long numbers that are likely IDs or totals (not prices).
  static final RegExp patternIgnoreNumbers = RegExp(
    r'\d{1,3}(?:\s?[.,]\s?\d{3})+',
  );

  /// Detects common German supermarket brands.
  static final RegExp patternCompany = RegExp(
    r'(Aldi|Rewe|Edeka|Penny|Kaufland|Netto|Akzenta)',
    caseSensitive: false,
  );

  /// Detects sum labels like "SUMME" or "TOTAL".
  static final RegExp patternSumLabel = RegExp(
    r'(Zu zahlen|Summe|Total)',
    caseSensitive: false,
  );

  /// Matches generic unknown text lines.
  static final RegExp patternUnknown = RegExp(r'[^\d]{6,}');

  /// Matches currency-style amounts (e.g. 1,99 or 2.50).
  static final RegExp patternAmount = RegExp(r'-?\s*\d+\s*[.,]\s*\d{2}');

  /// High-level method to convert OCR [RecognizedText] into a [RecognizedReceipt].
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

  /// Parses lines into [RecognizedEntity] types based on regex rules.
  static List<RecognizedEntity> _parseLines(List<TextLine> lines) {
    final parsed = <RecognizedEntity>[];
    bool detectedCompany = false;
    bool detectedSumLabel = false;

    for (final line in lines) {
      if (patternStopKeywords.hasMatch(line.text)) break;
      if (patternIgnoreKeywords.hasMatch(line.text) ||
          patternIgnoreNumbers.hasMatch(line.text))
        continue;

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
        final normalized = ReceiptFormatter.normalizeCommas(amount);
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

  /// Removes entities likely to be noise or outside receipt bounds.
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

    final sumLabels = shrunken.whereType<RecognizedSumLabel>().toList();
    if (sumLabels.isNotEmpty) {
      final sum = _findSum(shrunken, sumLabels.first);
      if (sum != null) {
        final sumBottom = sum.line.boundingBox.bottom;
        shrunken.removeWhere(
          (e) => e.line.boundingBox.top > sumBottom + boundingBoxBuffer,
        );
        final indexSum = shrunken.indexWhere((e) => e.value == sum.value);
        if (indexSum >= 0) {
          shrunken.removeAt(indexSum);
          shrunken.insert(indexSum, sum);
        } else {
          shrunken.add(sum);
        }
      } else {
        final labelBottom = sumLabels.first.line.boundingBox.bottom;
        shrunken.removeWhere(
          (e) => e.line.boundingBox.top > labelBottom + boundingBoxBuffer,
        );
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

  /// Tries to match a recognized sum label with its nearest amount.
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

  /// Builds the final [RecognizedReceipt] from the list of structured entities.
  ///
  /// Matches unknowns to amounts based on spatial proximity and constructs
  /// positions from those pairs.
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
                positionIndex: 0,
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
