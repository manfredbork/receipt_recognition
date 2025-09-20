import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Parses raw OCR text into structured receipt data.
///
/// Uses pattern matching and spatial analysis to identify receipt components
/// like company names, prices, products, and the total sum.
final class ReceiptParser {
  /// Processes raw OCR text into a structured receipt.
  ///
  /// This is the main entry point for receipt parsing.
  static RecognizedReceipt processText(RecognizedText text) {
    final lines = _convertText(text);
    final parsedEntities = _parseLines(lines);
    final filteredEntities = _filterIntermediaryEntities(parsedEntities);
    return _buildReceipt(filteredEntities);
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

      if (_tryParseAmount(line, parsed, receiptHalfWidth)) {
        detectedAmount = parsed.last as RecognizedAmount;
        continue;
      }

      if (_tryParseUnknown(line, parsed, receiptHalfWidth)) {
        continue;
      }
    }

    return parsed.toList();
  }

  static bool _shouldSkipLine(
    TextLine line,
    RecognizedSumLabel? detectedSumLabel,
  ) {
    return detectedSumLabel != null &&
        line.boundingBox.top > detectedSumLabel.line.boundingBox.bottom;
  }

  static bool _tryParseCompany(
    TextLine line,
    List<RecognizedEntity> parsed,
    RecognizedCompany? detectedCompany,
    RecognizedAmount? detectedAmount,
  ) {
    if (detectedCompany == null && detectedAmount == null) {
      final company = ReceiptPatterns.company.stringMatch(line.text);
      if (company != null) {
        parsed.add(RecognizedCompany(line: line, value: company));
        return true;
      }
    }
    return false;
  }

  static bool _tryParseSumLabel(TextLine line, List<RecognizedEntity> parsed) {
    final text = ReceiptFormatter.trim(line.text);

    final match = ReceiptPatterns.sumLabel.firstMatch(text);
    if (match != null) {
      final matchedValue = ReceiptFormatter.trim(match.group(0)!);
      parsed.add(RecognizedSumLabel(line: line, value: matchedValue));
      return true;
    }

    for (final label in _knownSumLabels()) {
      final threshold = _adaptiveThreshold(label);
      if (ratio(text, label) >= threshold) {
        parsed.add(RecognizedSumLabel(line: line, value: label));
        return true;
      }
    }

    return false;
  }

  static bool _shouldStopParsing(TextLine line) {
    return ReceiptPatterns.stopKeywords.hasMatch(line.text);
  }

  static bool _shouldIgnoreLine(TextLine line) {
    return ReceiptPatterns.ignoreKeywords.hasMatch(line.text);
  }

  static bool _tryParseAmount(
    TextLine line,
    List<RecognizedEntity> parsed,
    double receiptHalfWidth,
  ) {
    final amount = ReceiptPatterns.amount.stringMatch(line.text);
    if (amount != null && line.boundingBox.left > receiptHalfWidth) {
      final locale = _detectsLocale(amount);
      final trimmedAmount = ReceiptFormatter.trim(amount);
      final value = NumberFormat.decimalPattern(locale).parse(trimmedAmount);
      parsed.add(RecognizedAmount(line: line, value: value));
      return true;
    }
    return false;
  }

  static bool _tryParseUnknown(
    TextLine line,
    List<RecognizedEntity> parsed,
    double receiptHalfWidth,
  ) {
    if (_isLikelyMetadataLine(line)) return false;

    final unknown = ReceiptPatterns.unknown.stringMatch(line.text);
    if (unknown != null && line.boundingBox.left < receiptHalfWidth) {
      parsed.add(RecognizedUnknown(line: line, value: line.text));
      return true;
    }

    return false;
  }

  static RecognizedReceipt _buildReceipt(List<RecognizedEntity> entities) {
    final yUnknowns = entities.whereType<RecognizedUnknown>().toList();
    final receipt = RecognizedReceipt.empty();
    final List<RecognizedUnknown> forbidden = [];
    final company = _findCompany(entities);
    final sumLabel = _findSumLabel(entities);

    _setReceiptSum(entities, sumLabel, receipt);
    _processAmounts(entities, yUnknowns, receipt, forbidden);
    _processCompany(company, receipt);
    _filterSuspiciousProducts(receipt);
    _trimToMatchSum(receipt);

    return receipt.copyWith(entities: entities, sumLabel: sumLabel);
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

  static void _processCompany(
    RecognizedCompany? company,
    RecognizedReceipt receipt,
  ) {
    receipt.company = company;
  }

  static void _processAmounts(
    List<RecognizedEntity> entities,
    List<RecognizedUnknown> yUnknowns,
    RecognizedReceipt receipt,
    List<RecognizedUnknown> forbidden,
  ) {
    for (final entity in entities) {
      if (entity is RecognizedAmount) {
        if (receipt.sum?.line == entity.line) continue;
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
    if (entity == receipt.sum) return;

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
    final unknownText = ReceiptFormatter.trim(unknown.value);
    final unknownBox = unknown.line.boundingBox;

    final yT = (amountBounds.top - unknownBox.top).abs();
    final yB = (amountBounds.bottom - unknownBox.bottom).abs();
    final yCompare = min(yT, yB);

    final isLeftOfAmount = unknownBox.left < amountBounds.left;
    final isLikelyLabel = ReceiptPatterns.sumLabel.hasMatch(unknownText);

    return !forbidden.contains(unknown) &&
        yCompare <= ReceiptConstants.boundingBoxBuffer &&
        isLeftOfAmount &&
        !isLikelyLabel;
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

    final closestAmount = yAmounts.first;

    if (_isNearbyAmount(ySumLabel, closestAmount)) {
      receipt.sum = RecognizedSum(
        value: closestAmount.value,
        line: closestAmount.line,
      );
    }
  }

  static bool _isLikelyMetadataLine(TextLine line) {
    final text = line.text;

    return ReceiptPatterns.likelyNotProduct.hasMatch(text) ||
        ReceiptPatterns.quantityMetadata.hasMatch(text) ||
        ReceiptPatterns.unitPrice.hasMatch(text) ||
        ReceiptPatterns.standaloneInteger.hasMatch(text) ||
        ReceiptPatterns.standalonePrice.hasMatch(text) ||
        ReceiptPatterns.misleadingPriceLikeLeft.hasMatch(text);
  }

  static List<String> _knownSumLabels() {
    final source = ReceiptPatterns.sumLabel.pattern;
    final match = RegExp(r'\((.*?)\)').firstMatch(source);
    if (match == null) return [];

    return match.group(1)!.split('|').map((s) => s.trim()).toList();
  }

  static int _adaptiveThreshold(String label) {
    final length = label.length;

    if (length <= 3) return 95;
    if (length <= 6) return 90;
    if (length <= 12) return 85;
    return 80;
  }

  static bool _isNearbyAmount(Rect sumLabelBounds, RecognizedAmount amount) {
    final amountBox = amount.line.boundingBox;

    final yT = (sumLabelBounds.top - amountBox.top).abs();
    final yB = (sumLabelBounds.bottom - amountBox.bottom).abs();
    final yCenter = (sumLabelBounds.top + sumLabelBounds.bottom) / 2;

    final amountCenter = (amountBox.top + amountBox.bottom) / 2;
    final isAboveOrAligned =
        amountCenter <= yCenter + ReceiptConstants.boundingBoxBuffer / 2;

    final yCompare = min(yT, yB);
    return isAboveOrAligned && yCompare <= ReceiptConstants.boundingBoxBuffer;
  }

  static String? _detectsLocale(String text) {
    if (text.contains('.')) return 'en_US';
    if (text.contains(',')) return 'de_DE';
    return Intl.defaultLocale;
  }

  static void _sortByDistance(Rect amountBox, List<RecognizedEntity> entities) {
    entities.sort((a, b) {
      int verticalCompare(Rect aBox, Rect bBox) {
        final aT = (amountBox.top - aBox.top).abs();
        final bT = (amountBox.top - bBox.top).abs();
        final aB = (amountBox.bottom - aBox.bottom).abs();
        final bB = (amountBox.bottom - bBox.bottom).abs();
        return min(aT, aB).compareTo(min(bT, bB));
      }

      final result = verticalCompare(a.line.boundingBox, b.line.boundingBox);
      return result != 0
          ? result
          : a.line.boundingBox.left.compareTo(b.line.boundingBox.left);
    });
  }

  static List<RecognizedEntity> _filterIntermediaryEntities(
    List<RecognizedEntity> entities,
  ) {
    final filtered = <RecognizedEntity>[];
    const verticalTolerance = ReceiptConstants.boundingBoxBuffer;

    final leftUnknown = minBy(
      entities.whereType<RecognizedUnknown>(),
      (e) => e.line.boundingBox.left,
    );

    final rightAmount = maxBy(
      entities.whereType<RecognizedAmount>(),
      (e) => e.line.boundingBox.right,
    );

    if (leftUnknown == null || rightAmount == null) return entities;

    final sumLabel = entities.whereType<RecognizedSumLabel>().firstOrNull;

    RecognizedAmount? sum;
    for (final a in entities.whereType<RecognizedAmount>()) {
      if (sumLabel != null && _isNearbyAmount(sumLabel.line.boundingBox, a)) {
        sum = a;
        break;
      }
    }

    for (final entity in entities) {
      final type = entity.runtimeType;

      if (type == RecognizedCompany) {
        filtered.add(entity);
        continue;
      }

      final betweenUnknownAndAmount =
          _isBetweenHorizontallyAndAlignedVertically(
            entity,
            leftUnknown,
            rightAmount,
            verticalTolerance,
          );

      final betweenSumLabelAndSum =
          sumLabel != null &&
          sum != null &&
          entity.line.boundingBox.top > sumLabel.line.boundingBox.bottom &&
          entity.line.boundingBox.bottom < sum.line.boundingBox.top;

      if (!betweenUnknownAndAmount && !betweenSumLabelAndSum) {
        filtered.add(entity);
      }
    }

    return filtered;
  }

  static bool _isBetweenHorizontallyAndAlignedVertically(
    RecognizedEntity entity,
    RecognizedUnknown leftUnknown,
    RecognizedAmount rightAmount,
    int verticalTolerance,
  ) {
    final box = entity.line.boundingBox;

    final horizontallyBetween =
        box.left > leftUnknown.line.boundingBox.right &&
        box.right < rightAmount.line.boundingBox.left;

    final topDeltaUnknown = (box.top - leftUnknown.line.boundingBox.top).abs();
    final bottomDeltaUnknown =
        (box.bottom - leftUnknown.line.boundingBox.bottom).abs();

    final topDeltaAmount = (box.top - rightAmount.line.boundingBox.top).abs();
    final bottomDeltaAmount =
        (box.bottom - rightAmount.line.boundingBox.bottom).abs();

    final verticallyAligned =
        topDeltaUnknown < verticalTolerance ||
        bottomDeltaUnknown < verticalTolerance ||
        topDeltaAmount < verticalTolerance ||
        bottomDeltaAmount < verticalTolerance;

    return horizontallyBetween && verticallyAligned;
  }

  static void _trimToMatchSum(RecognizedReceipt receipt) {
    final target = receipt.sum?.value;
    if (target == null || receipt.positions.length <= 1) return;

    receipt.positions.removeWhere(
      (pos) =>
          receipt.sum != null &&
          (pos.price.value - receipt.sum!.value).abs() < 0.01 &&
          ReceiptPatterns.sumLabel.hasMatch(pos.product.value),
    );

    final positions = [...receipt.positions]
      ..sort((a, b) => a.confidence.compareTo(b.confidence));
    num currentSum = receipt.calculatedSum.value;

    for (final pos in positions) {
      if (currentSum <= target) break;

      final newSum = currentSum - pos.price.value;
      final improvement = (currentSum - target).abs() - (newSum - target).abs();

      if (improvement > 0) {
        receipt.positions.remove(pos);
        pos.group?.members.remove(pos);

        if ((pos.group?.members.isEmpty ?? false)) {
          receipt.positions.removeWhere((p) => p.group == pos.group);
        }

        currentSum = newSum;
      }
    }
  }

  static void _filterSuspiciousProducts(RecognizedReceipt receipt) {
    final toRemove = <RecognizedPosition>[];

    for (final pos in receipt.positions) {
      final productText = ReceiptFormatter.trim(pos.product.value);

      final isSuspicious = ReceiptPatterns.suspiciousProductName.hasMatch(
        productText,
      );

      if (isSuspicious) {
        toRemove.add(pos);
      }
    }

    for (final pos in toRemove) {
      receipt.positions.remove(pos);
      pos.group?.members.remove(pos);

      if ((pos.group?.members.isEmpty ?? false)) {
        receipt.positions.removeWhere((p) => p.group == pos.group);
      }
    }
  }
}
