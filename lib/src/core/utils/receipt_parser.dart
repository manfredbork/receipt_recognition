import 'dart:math';
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Parses raw OCR text into structured receipt data.
///
/// Uses pattern matching and spatial analysis to identify receipt components
/// like company names, prices, products, and the total sum.
final class ReceiptParser {
  /// Pattern to match common supermarket/store names.
  static final RegExp patternCompany = RegExp(
    r'(Aldi|Rewe|Edeka|Penny|Lidl|Kaufland|Netto|Akzenta)',
    caseSensitive: false,
  );

  /// Pattern to match various ways a total sum might be labeled.
  static final RegExp patternSumLabel = RegExp(
    r'(Zu zahlen|Gesamt|Summe|Total)',
    caseSensitive: false,
  );

  /// Pattern for keywords that indicate we should stop parsing (end of receipt).
  static final RegExp patternStopKeywords = RegExp(
    r'(Geg.|Rückgeld)',
    caseSensitive: false,
  );

  /// Pattern for keywords to ignore as they don't represent product items.
  static final RegExp patternIgnoreKeywords = RegExp(
    r'(E-Bon|Coupon|Eingabe|Posten|Stk|kg)',
    caseSensitive: false,
  );

  /// Pattern for invalid amount formats (likely not price values).
  static final RegExp patternInvalidAmount = RegExp(r'\d+\s*[.,]\s*\d{3}');

  /// Pattern to recognize monetary amounts with optional sign.
  static final RegExp patternAmount = RegExp(r'-?\s*\d+\s*[.,]\s*\d{2}');

  /// Pattern to recognize text that might be product descriptions.
  static final RegExp patternUnknown = RegExp(r'\D{6,}');

  static const int boundingBoxBuffer = 50;

  /// Processes raw OCR text into a structured receipt.
  ///
  /// This is the main entry point for receipt parsing.
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
    RecognizedAmount? detectedAmount;

    for (final line in lines) {
      if (_shouldSkipLine(line, detectedSumLabel)) {
        continue;
      }

      if (_tryParseCompany(line, parsed, detectedCompany, detectedAmount)) {
        detectedCompany = parsed.last as RecognizedCompany;
        continue;
      }

      if (_tryParseSumLabel(line, parsed)) {
        detectedSumLabel = parsed.last as RecognizedSumLabel;
        continue;
      }

      if (_shouldStopParsing(line)) {
        break;
      }

      if (_shouldIgnoreLine(line)) {
        continue;
      }

      _tryParseAmount(line, parsed, receiptHalfWidth);
      _tryParseUnknown(line, parsed, receiptHalfWidth);
    }

    return parsed.toList();
  }

  static bool _shouldSkipLine(
    TextLine line,
    RecognizedSumLabel? detectedSumLabel,
  ) {
    return detectedSumLabel != null &&
        line.boundingBox.top > detectedSumLabel.line.boundingBox.top;
  }

  static bool _tryParseCompany(
    TextLine line,
    List<RecognizedEntity> parsed,
    RecognizedCompany? detectedCompany,
    RecognizedAmount? detectedAmount,
  ) {
    if (detectedCompany == null && detectedAmount == null) {
      final company = patternCompany.stringMatch(line.text);
      if (company != null) {
        parsed.add(RecognizedCompany(line: line, value: company));
        return true;
      }
    }
    return false;
  }

  static bool _tryParseSumLabel(TextLine line, List<RecognizedEntity> parsed) {
    final sumLabel = patternSumLabel.stringMatch(line.text);
    if (sumLabel != null) {
      parsed.add(RecognizedSumLabel(line: line, value: sumLabel));
      return true;
    }
    return false;
  }

  static bool _shouldStopParsing(TextLine line) {
    return patternStopKeywords.hasMatch(line.text);
  }

  static bool _shouldIgnoreLine(TextLine line) {
    return patternIgnoreKeywords.hasMatch(line.text);
  }

  static void _tryParseAmount(
    TextLine line,
    List<RecognizedEntity> parsed,
    double receiptHalfWidth,
  ) {
    final amount = patternAmount.stringMatch(line.text);
    if (amount != null && line.boundingBox.left > receiptHalfWidth) {
      final locale = _detectsLocale(amount);
      final trimmedAmount = ReceiptFormatter.trim(amount);
      final value = NumberFormat.decimalPattern(locale).parse(trimmedAmount);
      parsed.add(RecognizedAmount(line: line, value: value));
    }
  }

  static void _tryParseUnknown(
    TextLine line,
    List<RecognizedEntity> parsed,
    double receiptHalfWidth,
  ) {
    final unknown = patternUnknown.stringMatch(line.text);
    if (unknown != null && line.boundingBox.left < receiptHalfWidth) {
      parsed.add(RecognizedUnknown(line: line, value: line.text));
    }
  }

  static RecognizedReceipt? _buildReceipt(List<RecognizedEntity> entities) {
    final yUnknowns = entities.whereType<RecognizedUnknown>().toList();
    final receipt = RecognizedReceipt.empty();
    final List<RecognizedUnknown> forbidden = [];

    final company = _findCompany(entities);
    final sumLabel = _findSumLabel(entities);

    _processAmounts(entities, yUnknowns, receipt, forbidden);
    _setReceiptSum(entities, sumLabel, receipt);

    receipt.company = company;

    return receipt;
  }

  static RecognizedCompany? _findCompany(List<RecognizedEntity> entities) {
    for (final entity in entities) {
      if (entity is RecognizedCompany) {
        return entity;
      }
    }
    return null;
  }

  static RecognizedSumLabel? _findSumLabel(List<RecognizedEntity> entities) {
    for (final entity in entities) {
      if (entity is RecognizedSumLabel) {
        return entity;
      }
    }
    return null;
  }

  static void _processAmounts(
    List<RecognizedEntity> entities,
    List<RecognizedUnknown> yUnknowns,
    RecognizedReceipt receipt,
    List<RecognizedUnknown> forbidden,
  ) {
    for (final entity in entities) {
      if (entity is RecognizedAmount) {
        _createPositionForAmount(entity, yUnknowns, receipt, forbidden);
      }
    }
  }

  static void _createPositionForAmount(
    RecognizedAmount entity,
    List<RecognizedUnknown> yUnknowns,
    RecognizedReceipt receipt,
    List<RecognizedUnknown> forbidden,
  ) {
    final yAmount = entity.line.boundingBox;
    _sortByDistance(yAmount, yUnknowns);

    for (final yUnknown in yUnknowns) {
      if (_isMatchingUnknown(yAmount, yUnknown, forbidden)) {
        final position = _createPosition(yUnknown, entity, receipt.timestamp);
        receipt.positions.add(position);
        forbidden.add(yUnknown);
        break;
      }
    }
  }

  static bool _isMatchingUnknown(
    Rect amountBounds,
    RecognizedUnknown unknown,
    List<RecognizedUnknown> forbidden,
  ) {
    final yT = (amountBounds.top - unknown.line.boundingBox.top).abs();
    final yB = (amountBounds.bottom - unknown.line.boundingBox.bottom).abs();
    final yCompare = min(yT, yB);
    return !forbidden.contains(unknown) && yCompare <= boundingBoxBuffer;
  }

  static RecognizedPosition _createPosition(
    RecognizedUnknown unknown,
    RecognizedAmount amount,
    DateTime timestamp,
  ) {
    final product = RecognizedProduct(value: unknown.value, line: unknown.line);
    final price = RecognizedPrice(line: amount.line, value: amount.value);
    final position = RecognizedPosition(
      product: product,
      price: price,
      timestamp: timestamp,
      operation: Operation.none,
    );
    product.position = position;
    price.position = position;
    return position;
  }

  static void _setReceiptSum(
    List<RecognizedEntity> entities,
    RecognizedSumLabel? sumLabel,
    RecognizedReceipt receipt,
  ) {
    if (sumLabel == null) return;

    final yAmounts = entities.whereType<RecognizedAmount>().toList();
    if (yAmounts.isEmpty) return;

    final ySumLabel = sumLabel.line.boundingBox;
    _sortByDistance(ySumLabel, yAmounts);

    if (_isNearbyAmount(ySumLabel, yAmounts.first)) {
      receipt.sum = RecognizedSum(
        value: yAmounts.first.value,
        line: yAmounts.first.line,
      );
    }
  }

  static bool _isNearbyAmount(Rect sumLabelBounds, RecognizedAmount amount) {
    final yT = (sumLabelBounds.top - amount.line.boundingBox.top).abs();
    final yB = (sumLabelBounds.bottom - amount.line.boundingBox.bottom).abs();
    final yCompare = min(yT, yB);
    return yCompare <= boundingBoxBuffer;
  }

  static String? _detectsLocale(String text) {
    if (text.contains('.')) return 'en_US';
    if (text.contains(',')) return 'eu';
    return Intl.defaultLocale;
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
