import 'dart:math' as math;
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
  static RecognizedReceipt processText(
    RecognizedText text,
    Map<String, Map<String, String>> options,
  ) {
    final lines = _convertText(text);

    final angleDeg = ReceiptSkewEstimatorFromLines.estimateDegreesFromLines(
      lines,
    );
    if (angleDeg.abs() < 0.5) {
      // No projection; use raw y (faster, avoids needless trig noise)
      double yOf(TextLine line) => line.boundingBox.center.dy.toDouble();
      lines.sort((a, b) => yOf(a).compareTo(yOf(b)));
      final parsed = _parseLines(lines, options, yOf);
      final filtered = _filterIntermediaryEntities(parsed, yOf);
      return _buildReceipt(filtered, yOf);
    } else {
      final angleRad = angleDeg * math.pi / 180.0;
      final cosA = math.cos(-angleRad), sinA = math.sin(-angleRad);
      double yOf(TextLine line) {
        final c = line.boundingBox.center;
        return c.dx * sinA + c.dy * cosA;
      }

      lines.sort((a, b) => yOf(a).compareTo(yOf(b)));
      final parsed = _parseLines(lines, options, yOf);
      final filtered = _filterIntermediaryEntities(parsed, yOf);
      return _buildReceipt(filtered, yOf);
    }
  }

  static List<TextLine> _convertText(RecognizedText text) {
    return text.blocks.expand((block) => block.lines).toList()
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
  }

  static Map<String, dynamic> _buildCustomCompanyDetection(
    Map<String, Map<String, String>> options,
  ) {
    String regexp = '';
    Map<String, String> mapping = {};
    if (options.containsKey('stores')) {
      final stores = options['stores'] ?? {};
      for (final key in stores.keys) {
        regexp += (regexp.isEmpty ? key : '|$key');
        mapping[key.toLowerCase()] = stores[key]!;
      }
    }
    return {
      'regexp': RegExp('($regexp)', caseSensitive: false),
      'mapping': mapping,
    };
  }

  static List<RecognizedEntity> _parseLines(
    List<TextLine> lines,
    Map<String, Map<String, String>> options,
    double Function(TextLine) yOf,
  ) {
    final parsed = <RecognizedEntity>[];
    final bounds = RecognizedBounds.fromLines(lines);
    final receiptHalfWidth = (bounds.minLeft + bounds.maxRight) / 2;
    final customCompanyDetection = _buildCustomCompanyDetection(options);

    RecognizedCompany? detectedCompany;
    RecognizedSumLabel? detectedSumLabel;
    RecognizedAmount? detectedAmount;

    for (final line in lines) {
      if (_shouldSkipLine(line, detectedSumLabel, yOf)) {
        continue;
      }

      if (_tryParseCompany(
        line,
        parsed,
        detectedCompany,
        detectedAmount,
        customCompanyDetection,
      )) {
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

      if (_tryParseAmount(line, parsed, receiptHalfWidth, yOf)) {
        detectedAmount = parsed.last as RecognizedAmount;
        continue;
      }

      if (_tryParseUnknown(line, parsed, receiptHalfWidth, yOf)) {
        continue;
      }
    }

    return parsed.toList();
  }

  static bool _shouldSkipLine(
    TextLine line,
    RecognizedSumLabel? detectedSumLabel,
    double Function(TextLine) yOf,
  ) {
    return detectedSumLabel != null && yOf(line) > yOf(detectedSumLabel.line);
  }

  static bool _tryParseCompany(
    TextLine line,
    List<RecognizedEntity> parsed,
    RecognizedCompany? detectedCompany,
    RecognizedAmount? detectedAmount,
    Map<String, dynamic> customCompanyDetection,
  ) {
    if (detectedCompany == null && detectedAmount == null) {
      final customCompanyRegExp = customCompanyDetection['regexp'];
      if (customCompanyRegExp is RegExp) {
        final customCompany = customCompanyRegExp.stringMatch(line.text);
        if (customCompany != null) {
          if (customCompanyDetection['mapping'] is Map<String, String>) {
            final key = customCompany.toLowerCase();
            final value = customCompanyDetection['mapping'][key];
            if (value != null) {
              parsed.add(RecognizedCompany(line: line, value: value));
              return true;
            }
          }
        }
      }
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
    double Function(TextLine) yOf,
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
    double Function(TextLine) yOf,
  ) {
    if (_isLikelyMetadataLine(line)) return false;
    final unknown = ReceiptPatterns.unknown.stringMatch(line.text);
    if (unknown != null && line.boundingBox.left < receiptHalfWidth) {
      parsed.add(RecognizedUnknown(line: line, value: line.text));
      return true;
    }
    return false;
  }

  static RecognizedReceipt _buildReceipt(
    List<RecognizedEntity> entities,
    double Function(TextLine) yOf,
  ) {
    final yUnknowns = entities.whereType<RecognizedUnknown>().toList();
    final receipt = RecognizedReceipt.empty();
    final List<RecognizedUnknown> forbidden = [];
    final company = _findCompany(entities);
    final sumLabel = _findSumLabel(entities);

    _setReceiptSum(entities, sumLabel, receipt, yOf);
    _processAmounts(entities, yUnknowns, receipt, forbidden, yOf);
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
    double Function(TextLine) yOf,
  ) {
    for (final entity in entities) {
      if (entity is RecognizedAmount) {
        if (receipt.sum?.line == entity.line) continue;
        _createPositionForAmount(entity, yUnknowns, receipt, forbidden, yOf);
      }
    }
  }

  static void _createPositionForAmount(
    RecognizedAmount entity,
    List<RecognizedUnknown> yUnknowns,
    RecognizedReceipt receipt,
    List<RecognizedUnknown> forbidden,
    double Function(TextLine) yOf,
  ) {
    if (entity == receipt.sum) return;

    // Sort unknowns by vertical proximity to amount
    _sortByDistance(entity.line.boundingBox, yUnknowns, yOf);

    for (final yUnknown in yUnknowns) {
      if (_isMatchingUnknown(entity, yUnknown, forbidden, yOf)) {
        final position = _createPosition(yUnknown, entity, receipt.timestamp);
        receipt.positions.add(position);
        forbidden.add(yUnknown);
        break;
      }
    }
  }

  static bool _isMatchingUnknown(
    RecognizedAmount amount,
    RecognizedUnknown unknown,
    List<RecognizedUnknown> forbidden,
    double Function(TextLine) yOf,
  ) {
    final unknownText = ReceiptFormatter.trim(unknown.value);
    final isLikelyLabel = ReceiptPatterns.sumLabel.hasMatch(unknownText);
    if (forbidden.contains(unknown) || isLikelyLabel) return false;

    final amountBox = amount.line.boundingBox;
    final unknownBox = unknown.line.boundingBox;

    final isLeftOfAmount = unknownBox.left < amountBox.left;

    // Use projected center Y difference with your existing tolerance
    final dy = (yOf(amount.line) - yOf(unknown.line)).abs();
    final alignedVertically = dy <= ReceiptConstants.boundingBoxBuffer;

    return isLeftOfAmount && alignedVertically;
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
    double Function(TextLine) yOf,
  ) {
    if (sumLabel == null) return;
    final yAmounts = entities.whereType<RecognizedAmount>().toList();
    if (yAmounts.isEmpty) return;

    // Sort by vertical distance to the label
    yAmounts.sort((a, b) {
      final da = (yOf(a.line) - yOf(sumLabel.line)).abs();
      final db = (yOf(b.line) - yOf(sumLabel.line)).abs();
      return da.compareTo(db);
    });

    final closest = yAmounts.first;
    if (_isNearbyAmount(sumLabel.line.boundingBox, closest, yOf)) {
      receipt.sum = RecognizedSum(value: closest.value, line: closest.line);
    }
  }

  static bool _isLikelyMetadataLine(TextLine line) {
    final text = line.text;

    return ReceiptPatterns.unitPrice.hasMatch(text) ||
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

  static bool _isNearbyAmount(
    Rect sumLabelBounds,
    RecognizedAmount amount,
    double Function(TextLine) yOf,
  ) {
    // Compare projected centers only (simpler and robust)
    final dy =
        (yOf(amount.line) - ((sumLabelBounds.top + sumLabelBounds.bottom) / 2))
            .abs();
    // NOTE: yOf expects a TextLine, so compute label center Y directly without projection:
    // To project the label center too, use a small helper to build a faux TextLine-like center.
    // Simpler: approximate by projecting the sum label line via yOf(sumLabel line).

    // Better version (if you have the line): yOf(sumLabel.line)
    // Here we assume you've passed the label's line into yOf when sorting above.

    // Threshold: keep your existing tolerance
    return dy <= ReceiptConstants.boundingBoxBuffer;
  }

  static String? _detectsLocale(String text) {
    if (text.contains('.')) return 'en_US';
    if (text.contains(',')) return 'de_DE';
    return Intl.defaultLocale;
  }

  static void _sortByDistance(
    Rect amountBox,
    List<RecognizedEntity> entities,
    double Function(TextLine) yOf,
  ) {
    entities.sort((a, b) {
      final dyA = (yOf(a.line) - (amountBox.top + amountBox.bottom) / 2).abs();
      final dyB = (yOf(b.line) - (amountBox.top + amountBox.bottom) / 2).abs();
      final vc = dyA.compareTo(dyB);
      return vc != 0
          ? vc
          : a.line.boundingBox.left.compareTo(b.line.boundingBox.left);
    });
  }

  static List<RecognizedEntity> _filterIntermediaryEntities(
    List<RecognizedEntity> entities,
    double Function(TextLine) yOf,
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
      if (sumLabel != null &&
          _isNearbyAmount(sumLabel.line.boundingBox, a, yOf)) {
        sum = a;
        break;
      }
    }

    for (final entity in entities) {
      if (entity is RecognizedCompany) {
        filtered.add(entity);
        continue;
      }

      final betweenUnknownAndAmount =
          _isBetweenHorizontallyAndAlignedVertically(
            entity,
            leftUnknown,
            rightAmount,
            verticalTolerance,
            yOf,
          );

      final betweenSumLabelAndSum =
          sumLabel != null &&
          sum != null &&
          yOf(entity.line) > yOf(sumLabel.line) &&
          yOf(entity.line) < yOf(sum.line);

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
    double Function(TextLine) yOf,
  ) {
    final box = entity.line.boundingBox;
    final horizontallyBetween =
        box.left > leftUnknown.line.boundingBox.right &&
        box.right < rightAmount.line.boundingBox.left;

    final dyU = (yOf(entity.line) - yOf(leftUnknown.line)).abs();
    final dyA = (yOf(entity.line) - yOf(rightAmount.line)).abs();
    final verticallyAligned =
        dyU < verticalTolerance || dyA < verticalTolerance;

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
