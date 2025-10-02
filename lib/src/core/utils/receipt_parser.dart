import 'dart:math' as math;
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

final class ReceiptParser {
  static RecognizedReceipt _lastReceipt = RecognizedReceipt.empty();

  static RecognizedReceipt processText(
    RecognizedText text,
    ReceiptOptions options,
  ) {
    final lines = _convertText(text);

    final angleDeg = ReceiptSkewEstimator.estimateDegrees(_lastReceipt);
    final rot = ReceiptRotator(angleDeg);

    lines.sort((a, b) => rot.yCenter(a).compareTo(rot.yCenter(b)));

    final parsed = _parseLines(lines, options, rot);
    final prunedU = _filterUnknownLeftAlignmentOutliers(parsed, rot);
    final prunedA = _filterAmountXOutliers(prunedU, rot);
    final filtered = _filterIntermediaryEntities(prunedA, rot);

    _lastReceipt = _buildReceipt(filtered, rot, options);
    return _lastReceipt;
  }

  static List<TextLine> _convertText(RecognizedText text) {
    return text.blocks.expand((block) => block.lines).toList()
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
  }

  static List<RecognizedEntity> _parseLines(
    List<TextLine> lines,
    ReceiptOptions options,
    ReceiptRotator rot,
  ) {
    if (lines.isEmpty) return [];

    final parsed = <RecognizedEntity>[];

    final minX = lines.map((l) => rot.xAtCenterLeft(l)).reduce(math.min);
    final maxX = lines.map((l) => rot.xAtCenterRight(l)).reduce(math.max);
    final receiptHalfX = (minX + maxX) / 2;

    final Rect overallDeskewed = lines
        .map(rot.deskewLineBox)
        .reduce((a, b) => a.expandToInclude(b));
    final angleDeg = rot.angleDeg;

    _applyBoundingBox(_createTextLine(overallDeskewed, angleDeg), parsed, rot);

    RecognizedCompany? detectedCompany;
    RecognizedSumLabel? detectedSumLabel;
    RecognizedAmount? detectedAmount;

    for (final line in lines) {
      if (_tryParseCompany(
        line,
        parsed,
        detectedCompany,
        detectedAmount,
        options.storeNames,
      )) {
        detectedCompany = parsed.last as RecognizedCompany;
        continue;
      }

      if (_tryParseSumLabel(line, parsed, options.totalLabels)) {
        detectedSumLabel = parsed.last as RecognizedSumLabel;
        continue;
      }

      if (_tryParseAmount(line, parsed, receiptHalfX, rot)) {
        detectedAmount = parsed.last as RecognizedAmount;
        continue;
      }

      if (_shouldSkipLine(line, detectedSumLabel, rot)) continue;
      if (_shouldIgnoreLine(line, options)) continue;
      if (_shouldStopParsing(line, options)) break;
      if (_shouldExitWhenCorrectSum(parsed, detectedSumLabel, rot)) break;
      if (_tryParseUnknown(line, parsed, receiptHalfX, rot)) continue;
    }

    return parsed.toList();
  }

  static bool _shouldExitWhenCorrectSum(
    List<RecognizedEntity> entities,
    RecognizedSumLabel? sumLabel,
    ReceiptRotator rot,
  ) {
    final sum = _findSum(entities, sumLabel, rot);
    if (sum == null) return false;
    final amounts = entities.whereType<RecognizedAmount>().toList();
    if (amounts.isEmpty) return false;
    final calculatedSum = CalculatedSum(
      value: amounts.fold(-sum.value, (a, b) => a + b.value),
    );
    return sum.formattedValue == calculatedSum.formattedValue;
  }

  static bool _shouldSkipLine(
    TextLine line,
    RecognizedSumLabel? detectedSumLabel,
    ReceiptRotator rot,
  ) {
    if (detectedSumLabel == null) return false;
    final tol = ReceiptConstants.boundingBoxBuffer.toDouble();
    return rot.yCenter(line) > rot.yCenter(detectedSumLabel.line) + tol;
  }

  static bool _applyBoundingBox(
    TextLine line,
    List<RecognizedEntity> parsed,
    ReceiptRotator rot,
  ) {
    if (line.boundingBox == Rect.zero) return false;
    // keep deskewed AABB in the entity
    final deskewedBoundingBox = rot.deskewRect(line.boundingBox);
    parsed.add(RecognizedBoundingBox(line: line, value: deskewedBoundingBox));
    return true;
  }

  static bool _tryParseCompany(
    TextLine line,
    List<RecognizedEntity> parsed,
    RecognizedCompany? detectedCompany,
    RecognizedAmount? detectedAmount,
    DetectionMap customDetection,
  ) {
    if (detectedCompany == null && detectedAmount == null) {
      final text = ReceiptFormatter.trim(line.text);

      final customCompany = customDetection.detect(text);
      if (customCompany != null) {
        parsed.add(RecognizedCompany(line: line, value: customCompany));
        return true;
      }

      final company = ReceiptPatterns.companyNames.stringMatch(text);
      if (company != null) {
        parsed.add(RecognizedCompany(line: line, value: company));
        return true;
      }
    }
    return false;
  }

  static bool _tryParseSumLabel(
    TextLine line,
    List<RecognizedEntity> parsed,
    DetectionMap customSumLabelDetection,
  ) {
    final text = ReceiptFormatter.trim(line.text);

    final customSumLabel = customSumLabelDetection.detect(text);
    if (customSumLabel != null) {
      parsed.add(RecognizedSumLabel(line: line, value: customSumLabel));
      return true;
    }

    for (final label in _knownSumLabels(customSumLabelDetection.pattern)) {
      final threshold = _adaptiveThreshold(label);
      if (ratio(text, label) >= threshold) {
        parsed.add(RecognizedSumLabel(line: line, value: label));
        return true;
      }
    }

    final match = ReceiptPatterns.sumLabels.firstMatch(text);
    if (match != null) {
      final matchedValue = ReceiptFormatter.trim(match.group(0)!);
      parsed.add(RecognizedSumLabel(line: line, value: matchedValue));
      return true;
    }

    for (final label in _knownSumLabels(ReceiptPatterns.sumLabels.pattern)) {
      final threshold = _adaptiveThreshold(label);
      if (ratio(text, label) >= threshold) {
        parsed.add(RecognizedSumLabel(line: line, value: label));
        return true;
      }
    }
    return false;
  }

  static bool _shouldIgnoreLine(TextLine line, ReceiptOptions options) {
    return options.ignoreKeywords.hasMatch(line.text) ||
        ReceiptPatterns.ignoreKeywords.hasMatch(line.text);
  }

  static bool _shouldStopParsing(TextLine line, ReceiptOptions options) {
    return options.stopKeywords.hasMatch(line.text) ||
        ReceiptPatterns.stopKeywords.hasMatch(line.text);
  }

  static bool _tryParseAmount(
    TextLine line,
    List<RecognizedEntity> parsed,
    double receiptHalfX,
    ReceiptRotator rot,
  ) {
    final amount = ReceiptPatterns.amount.stringMatch(line.text);
    if (amount != null) {
      final tol = ReceiptConstants.boundingBoxBuffer.toDouble();
      if (rot.xCenter(line) > receiptHalfX - tol) {
        final trimmedAmount = ReceiptFormatter.trim(amount)
            .replaceAll(RegExp(r'[-−–—]'), '-')
            .replaceAll(RegExp(r'[.,‚،٫·]'), '.')
            .replaceAll(RegExp(r'[^\d.-]'), '');
        final value = double.parse(trimmedAmount);
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
    ReceiptRotator rot,
  ) {
    final unknown = ReceiptPatterns.unknown.stringMatch(line.text);
    if (unknown != null && rot.xCenter(line) < receiptHalfX) {
      parsed.add(RecognizedUnknown(line: line, value: line.text));
      return true;
    }
    return false;
  }

  static RecognizedReceipt _buildReceipt(
    List<RecognizedEntity> entities,
    ReceiptRotator rot,
    ReceiptOptions options,
  ) {
    final yUnknowns = entities.whereType<RecognizedUnknown>().toList();
    final receipt = RecognizedReceipt.empty();
    final List<RecognizedUnknown> forbidden = [];
    final company = _findCompany(entities);
    final sumLabel = _findSumLabel(entities);
    final boundingBox = _findBoundingBox(entities);

    _setSum(entities, sumLabel, receipt, rot);
    _processAmounts(
      entities,
      yUnknowns,
      receipt,
      forbidden,
      rot,
      options,
    ); // <-- pass
    _processCompany(company, receipt);
    _processBoundingBox(boundingBox, receipt);
    _filterSuspiciousProducts(receipt);
    _trimToMatchSum(receipt);

    return receipt.copyWith(entities: entities, sumLabel: sumLabel);
  }

  static RecognizedCompany? _findCompany(List<RecognizedEntity> entities) {
    for (final entity in entities) {
      if (entity is RecognizedCompany) return entity;
    }
    return null;
  }

  static RecognizedSumLabel? _findSumLabel(List<RecognizedEntity> entities) {
    for (final entity in entities) {
      if (entity is RecognizedSumLabel) return entity;
    }
    return null;
  }

  static RecognizedBoundingBox? _findBoundingBox(
    List<RecognizedEntity> entities,
  ) {
    for (final entity in entities) {
      if (entity is RecognizedBoundingBox) return entity;
    }
    return null;
  }

  static void _processBoundingBox(
    RecognizedBoundingBox? boundingBox,
    RecognizedReceipt receipt,
  ) {
    receipt.boundingBox = boundingBox;
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
    ReceiptRotator rot,
    ReceiptOptions options, // <-- added
  ) {
    for (final entity in entities) {
      if (entity is RecognizedAmount) {
        if (receipt.sum?.line == entity.line) continue;
        _createPositionForAmount(
          entity,
          yUnknowns,
          receipt,
          forbidden,
          rot,
          options,
        ); // <-- pass
      }
    }
  }

  static void _createPositionForAmount(
    RecognizedAmount entity,
    List<RecognizedUnknown> yUnknowns,
    RecognizedReceipt receipt,
    List<RecognizedUnknown> forbidden,
    ReceiptRotator rot,
    ReceiptOptions options, // <-- added
  ) {
    if (entity == receipt.sum) return;

    _sortByDistance(entity.line.boundingBox, yUnknowns, rot);

    for (final yUnknown in yUnknowns) {
      if (_isMatchingUnknown(entity, yUnknown, forbidden, rot)) {
        final position = _createPosition(
          yUnknown,
          entity,
          receipt.timestamp,
          options,
        ); // <-- pass
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
    ReceiptRotator rot,
  ) {
    final unknownText = ReceiptFormatter.trim(unknown.value);
    final isLikelyLabel = ReceiptPatterns.sumLabels.hasMatch(unknownText);
    if (forbidden.contains(unknown) || isLikelyLabel) return false;

    final amountBox = amount.line.boundingBox;
    final unknownBox = unknown.line.boundingBox;

    final isLeftOfAmount = rot.maxXOf(unknownBox) <= rot.minXOf(amountBox);

    final dy = (rot.yCenter(amount.line) - rot.yCenter(unknown.line)).abs();
    final alignedVertically = dy <= ReceiptConstants.boundingBoxBuffer;

    return isLeftOfAmount && alignedVertically;
  }

  static TextLine _createTextLine(Rect boundingBox, double angleDeg) {
    return TextLine(
      text: '',
      elements: [],
      boundingBox: boundingBox,
      recognizedLanguages: const [],
      cornerPoints: const [],
      confidence: null,
      angle: angleDeg,
    );
  }

  static RecognizedPosition _createPosition(
    RecognizedUnknown unknown,
    RecognizedAmount amount,
    DateTime timestamp,
    ReceiptOptions options, // <-- added
  ) {
    final product = RecognizedProduct(
      value: unknown.value,
      line: unknown.line,
      options: options, // <-- inject here
    );
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

  static RecognizedSum? _findSum(
    List<RecognizedEntity> entities,
    RecognizedSumLabel? sumLabel,
    ReceiptRotator rot,
  ) {
    if (sumLabel == null) return null;

    final amounts = entities.whereType<RecognizedAmount>().toList();
    if (amounts.isEmpty) return null;

    final tol = ReceiptConstants.boundingBoxBuffer.toDouble();

    final sameRow =
        amounts
            .where(
              (a) =>
                  (rot.yCenter(a.line) - rot.yCenter(sumLabel.line)).abs() <=
                      tol &&
                  rot.xCenter(a.line) >=
                      rot.maxXOf(sumLabel.line.boundingBox) - tol,
            )
            .toList();

    RecognizedAmount pick;
    if (sameRow.isNotEmpty) {
      sameRow.sort(
        (a, b) => rot.xCenter(b.line).compareTo(rot.xCenter(a.line)),
      );
      pick = sameRow.first;
    } else {
      final closest = _findClosestSumAmount(sumLabel, amounts, rot);
      if (closest == null) return null;
      pick = closest;
    }

    return RecognizedSum(value: pick.value, line: pick.line);
  }

  static void _setSum(
    List<RecognizedEntity> entities,
    RecognizedSumLabel? sumLabel,
    RecognizedReceipt receipt,
    ReceiptRotator rot,
  ) {
    RecognizedSum? sum = _findSum(entities, sumLabel, rot);
    if (sum == null) return;
    receipt.sum = sum;
  }

  static List<String> _knownSumLabels(String source) {
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
    ReceiptRotator rot,
  ) {
    final dy = (rot.yCenter(sumLabel) - rot.yCenter(amount)).abs();

    final labelRightX = rot.maxXOf(sumLabel.boundingBox);
    final amtX = rot.xCenter(amount);
    final dx = amtX - labelRightX;

    final dxPenalty = dx >= 0 ? dx : (dx.abs() * 3);
    return dy + (dxPenalty * 0.3);
  }

  static void _sortByDistance(
    Rect amountBox,
    List<RecognizedEntity> entities,
    ReceiptRotator rot,
  ) {
    final amountYCtr = rot.yOfCenter(amountBox);

    entities.sort((a, b) {
      final dyA = (rot.yCenter(a.line) - amountYCtr).abs();
      final dyB = (rot.yCenter(b.line) - amountYCtr).abs();
      final vc = dyA.compareTo(dyB);
      return vc != 0 ? vc : rot.xCenter(a.line).compareTo(rot.xCenter(b.line));
    });
  }

  static RecognizedAmount? _findClosestSumAmount(
    RecognizedSumLabel sumLabel,
    List<RecognizedAmount> amounts,
    ReceiptRotator rot,
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
    ReceiptRotator rot,
  ) {
    final filtered = <RecognizedEntity>[];
    const verticalTolerance = ReceiptConstants.boundingBoxBuffer;

    final leftUnknown = minBy(
      entities.whereType<RecognizedUnknown>(),
      (e) => rot.minXOf(e.line.boundingBox),
    );
    final rightAmount = maxBy(
      entities.whereType<RecognizedAmount>(),
      (e) => rot.maxXOf(e.line.boundingBox),
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
          rot.yCenter(entity.line) > rot.yCenter(sumLabel.line) &&
          rot.yCenter(entity.line) < rot.yCenter(protectedSumAmount.line);

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
    ReceiptRotator rot,
  ) {
    final box = entity.line.boundingBox;

    final horizontallyBetween =
        rot.minXOf(box) > rot.maxXOf(leftUnknown.line.boundingBox) &&
        rot.maxXOf(box) < rot.minXOf(rightAmount.line.boundingBox);

    final dyU =
        (rot.yCenter(entity.line) - rot.yCenter(leftUnknown.line)).abs();
    final dyA =
        (rot.yCenter(entity.line) - rot.yCenter(rightAmount.line)).abs();
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
          ReceiptPatterns.sumLabels.hasMatch(pos.product.value),
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
      if (isSuspicious) toRemove.add(pos);
    }

    for (final pos in toRemove) {
      receipt.positions.remove(pos);
      pos.group?.members.remove(pos);

      if ((pos.group?.members.isEmpty ?? false)) {
        receipt.positions.removeWhere((p) => p.group == pos.group);
      }
    }
  }

  // --- Outlier filters in deskewed X-space ---

  static List<RecognizedEntity> _filterOneSidedXOutliers(
    List<RecognizedEntity> entities,
    ReceiptRotator rot, {
    required bool Function(RecognizedEntity e) isTarget,
    required double Function(RecognizedEntity e, ReceiptRotator rot) xMetric,
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
    ReceiptRotator rot,
  ) {
    return _filterOneSidedXOutliers(
      entities,
      rot,
      isTarget: (e) => e is RecognizedUnknown,
      xMetric: (e, r) => r.minXOf(e.line.boundingBox),
      dropRightTail: true,
    );
  }

  static List<RecognizedEntity> _filterAmountXOutliers(
    List<RecognizedEntity> entities,
    ReceiptRotator rot,
  ) {
    return _filterOneSidedXOutliers(
      entities,
      rot,
      isTarget: (e) => e is RecognizedAmount,
      xMetric: (e, r) => r.xCenter(e.line),
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
