import 'dart:math';

import 'package:flutter/foundation.dart';
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
  static const int boundingBoxBuffer = 40;

  /// Keywords that indicate the logical end of a receipt (e.g. taxes).
  static final RegExp patternStopKeywords = RegExp(
    r'(Geg.|Rückgeld)',
    caseSensitive: false,
  );

  /// Keywords or patterns to ignore during parsing.
  static final RegExp patternIgnoreKeywords = RegExp(
    r'(E-Bon|Coupon|Hand|Eingabe|Posten|Stk)',
    caseSensitive: false,
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
  static final RegExp patternUnknown = RegExp(r'\D{6,}');

  /// Matches currency-style amounts (e.g. 1,99 or 2.50).
  static final RegExp patternAmount = RegExp(r'-?\s*\d+\s*[.,]\s*\d{2}');

  /// High-level method to convert OCR [RecognizedText] into a [RecognizedReceipt].
  static RecognizedReceipt? processText(RecognizedText text) {
    final lines = _convertText(text);
    final parsedEntities = _parseLines(lines);
    if (kDebugMode) {
      for (final entity in parsedEntities) {
        print('$entity detected with value ${entity.value}');
      }
    }
    return _buildReceipt(parsedEntities);
  }

  static List<TextLine> _convertText(RecognizedText text) {
    return text.blocks.expand((block) => block.lines).toList()
      ..sort((a, b) => a.boundingBox.bottom.compareTo(b.boundingBox.bottom));
  }

  /// Parses lines into [RecognizedEntity] types based on regex rules.
  static List<RecognizedEntity> _parseLines(List<TextLine> lines) {
    final parsed = <RecognizedEntity>[];
    final bounds = RecognizedBounds.fromLines(lines);
    final receiptHalfWidth = (bounds.minLeft + bounds.maxRight) / 2;
    bool detectedCompany = false;
    bool detectedSumLabel = false;

    for (final line in lines) {
      if (patternStopKeywords.hasMatch(line.text)) {
        break;
      }

      if (patternIgnoreKeywords.hasMatch(line.text)) {
        continue;
      }

      final company = patternCompany.stringMatch(line.text);
      if (company != null && !detectedCompany) {
        parsed.add(RecognizedCompany(line: line, value: company));
        detectedCompany = true;
        continue;
      }

      final amount = patternAmount.stringMatch(line.text);
      if (amount != null && line.boundingBox.left > receiptHalfWidth) {
        final locale = _detectsLocale(amount);
        final normalized = ReceiptFormatter.normalizeCommas(amount);
        final value = NumberFormat.decimalPattern(locale).parse(normalized);
        parsed.add(RecognizedAmount(line: line, value: value));
      }

      if (detectedSumLabel) {
        break;
      }

      final sumLabel = patternSumLabel.stringMatch(line.text);
      if (sumLabel != null && !detectedSumLabel) {
        parsed.add(RecognizedSumLabel(line: line, value: sumLabel));
        detectedSumLabel = true;
        continue;
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
                scanIndex: 0,
              ),
            );
            forbidden.add(yUnknown);
            break;
          } else {
            sum = RecognizedSum(line: entity.line, value: entity.value);
          }
        }
      }
    }

    if (sum != null && receipt.calculatedSum.value >= sum.value) {
      receipt.sum = sum;
    }

    receipt.sumLabel = sumLabel;
    receipt.company = company;

    return receipt;
  }
}
