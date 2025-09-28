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
  static RecognizedReceipt _lastReceipt = RecognizedReceipt.empty();

  /// Processes raw OCR text into a structured receipt.
  ///
  /// This is the main entry point for receipt parsing.
  static RecognizedReceipt processText(
    RecognizedText text,
    Map<String, Map<String, String>> options,
  ) {
    final lines = _convertText(text);

    final angleDeg = ReceiptSkewEstimator.estimateDegrees(_lastReceipt);
    final rot = _Rotator(angleDeg);

    lines.sort((a, b) => rot.yOf(a).compareTo(rot.yOf(b)));

    final parsed = _parseLines(lines, options, rot);
    final prunedU = _filterUnknownLeftAlignmentOutliers(parsed, rot);
    final prunedA = _filterAmountXOutliers(prunedU, rot);
    final filtered = _filterIntermediaryEntities(prunedA, rot);

    _lastReceipt = _buildReceipt(filtered, rot);

    return _lastReceipt;
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
    _Rotator rot,
  ) {
    final parsed = <RecognizedEntity>[];

    final minX = lines.map((l) => rot.xOf(l)).reduce(math.min);
    final maxX = lines.map((l) => rot.xOf(l)).reduce(math.max);
    final receiptHalfX = (minX + maxX) / 2;

    final customCompanyDetection = _buildCustomCompanyDetection(options);

    RecognizedCompany? detectedCompany;
    RecognizedSumLabel? detectedSumLabel;
    RecognizedAmount? detectedAmount;

    for (final line in lines) {
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

      if (_tryParseAmount(line, parsed, receiptHalfX, rot)) {
        detectedAmount = parsed.last as RecognizedAmount;
        continue;
      }

      if (_shouldSkipLine(line, detectedSumLabel, rot)) {
        continue;
      }

      if (_shouldStopParsing(line)) break;
      if (_shouldIgnoreLine(line)) continue;

      if (_tryParseUnknown(line, parsed, receiptHalfX, rot)) {
        continue;
      }
    }

    return parsed.toList();
  }

  static bool _shouldSkipLine(
    TextLine line,
    RecognizedSumLabel? detectedSumLabel,
    _Rotator rot,
  ) {
    if (detectedSumLabel == null) return false;
    final tol = ReceiptConstants.boundingBoxBuffer.toDouble();
    return rot.yOf(line) > rot.yOf(detectedSumLabel.line) + tol;
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
    double receiptHalfX,
    _Rotator rot,
  ) {
    final amount = ReceiptPatterns.amount.stringMatch(line.text);
    if (amount != null) {
      final tol = ReceiptConstants.boundingBoxBuffer.toDouble();
      if (rot.xOf(line) > receiptHalfX - tol) {
        final locale = _detectsLocale(amount);
        final trimmedAmount = ReceiptFormatter.trim(amount)
            .replaceAll('\u00A0', ' ') // hard spaces to normal
            .replaceAll(RegExp(r'[^\d,.\-]'), ''); // strip currency etc.
        final value = NumberFormat.decimalPattern(locale).parse(trimmedAmount);
        parsed.add(RecognizedAmount(line: line, value: value));
        return true;
      }
    }
    return false;
  }

  static bool _tryParseUnknown(
    TextLine line,
    List<RecognizedEntity> parsed,
    double receiptHalfX,
    _Rotator rot,
  ) {
    final unknown = ReceiptPatterns.unknown.stringMatch(line.text);
    if (unknown != null && rot.xOf(line) < receiptHalfX) {
      parsed.add(RecognizedUnknown(line: line, value: line.text));
      return true;
    }
    return false;
  }

  static RecognizedReceipt _buildReceipt(
    List<RecognizedEntity> entities,
    _Rotator rot,
  ) {
    final yUnknowns = entities.whereType<RecognizedUnknown>().toList();
    final receipt = RecognizedReceipt.empty();
    final List<RecognizedUnknown> forbidden = [];
    final company = _findCompany(entities);
    final sumLabel = _findSumLabel(entities);

    _setReceiptSum(entities, sumLabel, receipt, rot);
    _processAmounts(entities, yUnknowns, receipt, forbidden, rot);
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
    _Rotator rot,
  ) {
    for (final entity in entities) {
      if (entity is RecognizedAmount) {
        if (receipt.sum?.line == entity.line) continue;
        _createPositionForAmount(entity, yUnknowns, receipt, forbidden, rot);
      }
    }
  }

  static void _createPositionForAmount(
    RecognizedAmount entity,
    List<RecognizedUnknown> yUnknowns,
    RecognizedReceipt receipt,
    List<RecognizedUnknown> forbidden,
    _Rotator rot,
  ) {
    if (entity == receipt.sum) return;

    _sortByDistance(entity.line.boundingBox, yUnknowns, rot);

    for (final yUnknown in yUnknowns) {
      if (_isMatchingUnknown(entity, yUnknown, forbidden, rot)) {
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
    _Rotator rot,
  ) {
    final unknownText = ReceiptFormatter.trim(unknown.value);
    final isLikelyLabel = ReceiptPatterns.sumLabel.hasMatch(unknownText);
    if (forbidden.contains(unknown) || isLikelyLabel) return false;

    final amountBox = amount.line.boundingBox;
    final unknownBox = unknown.line.boundingBox;

    final isLeftOfAmount = rot.xRightOf(unknownBox) <= rot.xLeftOf(amountBox);

    final dy = (rot.yOf(amount.line) - rot.yOf(unknown.line)).abs();
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
    _Rotator rot,
  ) {
    if (sumLabel == null) return;

    final amounts = entities.whereType<RecognizedAmount>().toList();
    if (amounts.isEmpty) return;

    final tol = ReceiptConstants.boundingBoxBuffer.toDouble();

    final sameRow =
        amounts
            .where(
              (a) =>
                  (rot.yOf(a.line) - rot.yOf(sumLabel.line)).abs() <= tol &&
                  rot.xOf(a.line) >=
                      rot.xRightOf(sumLabel.line.boundingBox) - tol,
            )
            .toList();

    RecognizedAmount pick;
    if (sameRow.isNotEmpty) {
      sameRow.sort((a, b) => rot.xOf(b.line).compareTo(rot.xOf(a.line)));
      pick = sameRow.first;
    } else {
      final closest = _findClosestSumAmount(sumLabel, amounts, rot);
      if (closest == null) return;
      pick = closest;
    }

    receipt.sum = RecognizedSum(value: pick.value, line: pick.line);
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

  static double _distanceScoreRot(
    TextLine sumLabel,
    TextLine amount,
    _Rotator rot,
  ) {
    final dy = (rot.yOf(sumLabel) - rot.yOf(amount)).abs();

    final labelRightX = rot.xRightOf(sumLabel.boundingBox);
    final amtX = rot.xOf(amount);
    final dx = amtX - labelRightX;

    final dxPenalty = dx >= 0 ? dx : (dx.abs() * 3);

    return dy + (dxPenalty * 0.3);
  }

  static String? _detectsLocale(String text) {
    if (text.contains('.')) return 'en_US';
    if (text.contains(',')) return 'de_DE';
    return Intl.defaultLocale;
  }

  static void _sortByDistance(
    Rect amountBox,
    List<RecognizedEntity> entities,
    _Rotator rot,
  ) {
    final amountYCtr =
        rot.hasRotation
            ? (rot.yOfCenter(amountBox))
            : (amountBox.top + amountBox.bottom) / 2;

    entities.sort((a, b) {
      final dyA = (rot.yOf(a.line) - amountYCtr).abs();
      final dyB = (rot.yOf(b.line) - amountYCtr).abs();
      final vc = dyA.compareTo(dyB);
      return vc != 0 ? vc : rot.xOf(a.line).compareTo(rot.xOf(b.line));
    });
  }

  static RecognizedAmount? _findClosestSumAmount(
    RecognizedSumLabel sumLabel,
    List<RecognizedAmount> amounts,
    _Rotator rot,
  ) {
    if (amounts.isEmpty) return null;

    final scored =
        amounts
            .map(
              (a) => MapEntry(a, _distanceScoreRot(sumLabel.line, a.line, rot)),
            )
            .toList();

    scored.sort((a, b) => a.value.compareTo(b.value));
    return scored.first.key;
  }

  static List<RecognizedEntity> _filterIntermediaryEntities(
    List<RecognizedEntity> entities,
    _Rotator rot,
  ) {
    final filtered = <RecognizedEntity>[];
    const verticalTolerance = ReceiptConstants.boundingBoxBuffer;

    final leftUnknown = minBy(
      entities.whereType<RecognizedUnknown>(),
      (e) => rot.xLeftOf(e.line.boundingBox),
    );
    final rightAmount = maxBy(
      entities.whereType<RecognizedAmount>(),
      (e) => rot.xRightOf(e.line.boundingBox),
    );

    if (leftUnknown == null || rightAmount == null) return entities;

    final sumLabel = entities.whereType<RecognizedSumLabel>().firstOrNull;

    RecognizedAmount? protectedSumAmount;
    if (sumLabel != null) {
      final amounts = entities.whereType<RecognizedAmount>().toList();
      protectedSumAmount = _findClosestSumAmount(sumLabel, amounts, rot);
    }

    for (final entity in entities) {
      if (entity is RecognizedCompany) {
        filtered.add(entity);
        continue;
      }
      if (entity == protectedSumAmount) {
        filtered.add(entity);
        continue;
      }

      final betweenUnknownAndAmount =
          _isBetweenHorizontallyAndAlignedVertically(
            entity,
            leftUnknown,
            rightAmount,
            verticalTolerance,
            rot,
          );

      final betweenSumLabelAndSum =
          sumLabel != null &&
          protectedSumAmount != null &&
          rot.yOf(entity.line) > rot.yOf(sumLabel.line) &&
          rot.yOf(entity.line) < rot.yOf(protectedSumAmount.line);

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
    _Rotator rot,
  ) {
    final box = entity.line.boundingBox;

    final horizontallyBetween =
        rot.xLeftOf(box) > rot.xRightOf(leftUnknown.line.boundingBox) &&
        rot.xRightOf(box) < rot.xLeftOf(rightAmount.line.boundingBox);

    final dyU = (rot.yOf(entity.line) - rot.yOf(leftUnknown.line)).abs();
    final dyA = (rot.yOf(entity.line) - rot.yOf(rightAmount.line)).abs();
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
          (pos.price.value - receipt.sum!.value).abs() <
              ReceiptConstants.sumTolerance &&
          ReceiptPatterns.sumLabel.hasMatch(pos.product.value),
    );

    final positions = [...receipt.positions]
      ..sort((a, b) => a.confidence.compareTo(b.confidence));
    num currentSum = receipt.calculatedSum.value;

    for (final pos in positions) {
      if ((currentSum - target).abs() <= ReceiptConstants.sumTolerance) break;

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

  // Generic one-sided MAD outlier filter in rotated X-space.
  // - isTarget: which entities to consider (e.g., Unknowns or Amounts)
  // - xMetric:  how to measure alignment (e.g., xLeftOf(box) for Unknowns, xOf(line) for Amounts)
  // - dropRightTail: true => drop x > upperBound; false => drop x < lowerBound
  static List<RecognizedEntity> _filterOneSidedXOutliers(
    List<RecognizedEntity> entities,
    _Rotator rot, {
    required bool Function(RecognizedEntity e) isTarget,
    required double Function(RecognizedEntity e, _Rotator rot) xMetric,
    required bool dropRightTail,
    int minSamples = 3,
    double k = 5.0,
  }) {
    final targets = entities.where(isTarget).toList();
    if (targets.length < minSamples) return entities;

    final xs = targets.map((e) => xMetric(e, rot)).toList();

    final med = _median(xs);
    if (med.isNaN) return entities;

    final madRaw = _mad(xs, med);
    final madScaled = (madRaw == 0.0) ? 1.0 : (1.4826 * madRaw);
    final tol = ReceiptConstants.boundingBoxBuffer.toDouble();

    double lowerBound = med - k * madScaled - tol;
    double upperBound = med + k * madScaled + tol;

    final outlierLines = <TextLine>{};
    for (var i = 0; i < targets.length; i++) {
      final x = xs[i];
      final isOutlier = dropRightTail ? (x > upperBound) : (x < lowerBound);
      if (isOutlier) outlierLines.add(targets[i].line);
    }
    if (outlierLines.isEmpty) return entities;

    return entities
        .where((e) => !(isTarget(e) && outlierLines.contains(e.line)))
        .toList();
  }

  static List<RecognizedEntity> _filterUnknownLeftAlignmentOutliers(
    List<RecognizedEntity> entities,
    _Rotator rot,
  ) {
    return _filterOneSidedXOutliers(
      entities,
      rot,
      isTarget: (e) => e is RecognizedUnknown,
      xMetric: (e, r) => r.xLeftOf(e.line.boundingBox),
      dropRightTail: true,
    );
  }

  static List<RecognizedEntity> _filterAmountXOutliers(
    List<RecognizedEntity> entities,
    _Rotator rot,
  ) {
    return _filterOneSidedXOutliers(
      entities,
      rot,
      isTarget: (e) => e is RecognizedAmount,
      xMetric: (e, r) => r.xOf(e.line),
      dropRightTail: false,
    );
  }

  static double _median(List<double> xs) {
    if (xs.isEmpty) return double.nan;
    final a = [...xs]..sort();
    final n = a.length;
    final mid = n >> 1;
    return (n & 1) == 1 ? a[mid] : (a[mid - 1] + a[mid]) / 2.0;
  }

  static double _mad(List<double> xs, double med) {
    final dev = xs.map((x) => (x - med).abs()).toList()..sort();
    return _median(dev);
  }
}

class _Rotator {
  final double sinA;
  final double cosA;
  final bool hasRotation;

  _Rotator(double angleDeg)
    : hasRotation = angleDeg.abs() >= 0.5,
      sinA = math.sin(-angleDeg * math.pi / 180.0),
      cosA = math.cos(-angleDeg * math.pi / 180.0);

  double yOf(TextLine l) {
    final c = l.boundingBox.center;
    if (!hasRotation) return c.dy.toDouble();
    return c.dx * sinA + c.dy * cosA;
  }

  double xOf(TextLine l) {
    final c = l.boundingBox.center;
    if (!hasRotation) return c.dx.toDouble();
    return c.dx * cosA - c.dy * sinA;
  }

  double xLeftOf(Rect r) {
    if (!hasRotation) return r.left.toDouble();
    final pts = [
      Offset(r.left, r.top),
      Offset(r.right, r.top),
      Offset(r.left, r.bottom),
      Offset(r.right, r.bottom),
    ];
    return pts.map((p) => p.dx * cosA - p.dy * sinA).reduce(math.min);
  }

  double xRightOf(Rect r) {
    if (!hasRotation) return r.right.toDouble();
    final pts = [
      Offset(r.left, r.top),
      Offset(r.right, r.top),
      Offset(r.left, r.bottom),
      Offset(r.right, r.bottom),
    ];
    return pts.map((p) => p.dx * cosA - p.dy * sinA).reduce(math.max);
  }

  double yOfCenter(Rect r) {
    final c = r.center;
    if (!hasRotation) return c.dy.toDouble();
    return c.dx * sinA + c.dy * cosA;
  }
}
