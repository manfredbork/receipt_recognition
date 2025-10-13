import 'dart:math' as math;
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/parser/index.dart';
import 'package:receipt_recognition/src/utils/geometry/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';
import 'package:receipt_recognition/src/utils/ocr/index.dart';

/// Parses OCR output into a structured receipt by deskewing, extracting entities,
/// filtering spatial outliers, and assembling positions, sum, store, and bounds.
final class ReceiptParser {
  static RecognizedReceipt _lastReceipt = RecognizedReceipt.empty();

  /// Parses [text] with [options] and returns a structured [RecognizedReceipt].
  /// Performs deskewing, line ordering, entity extraction, filtering, and building.
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

  /// Flattens text blocks to lines sorted by top Y.
  static List<TextLine> _convertText(RecognizedText text) {
    return text.blocks.expand((block) => block.lines).toList()
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
  }

  /// Extracts entities from sorted lines using geometry, patterns, and options.
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
    final angleDeg = rot.angleDeg;
    final Rect deskewedLines = lines
        .map(rot.deskewLineBox)
        .reduce((a, b) => a.expandToInclude(b));
    final TextLine deskewedText = _createTextLine(deskewedLines, angleDeg);

    RecognizedStore? detectedStore;
    RecognizedSumLabel? detectedSumLabel;
    RecognizedAmount? detectedAmount;

    _applyPurchaseDate(lines, parsed);
    _applyBoundingBox(deskewedText, parsed, rot);

    for (final line in lines) {
      if (_shouldExitIfValidSum(parsed, detectedSumLabel, rot)) break;
      if (_shouldStopParsing(line, options)) break;
      if (_shouldIgnoreLine(line, options)) continue;
      if (_shouldSkipLine(line, detectedSumLabel, rot)) continue;

      if (_tryParseStore(
        line,
        parsed,
        detectedStore,
        detectedAmount,
        options.storeNames,
      )) {
        detectedStore = parsed.last as RecognizedStore;
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

      if (_tryParseUnknown(line, parsed, receiptHalfX, rot)) continue;
    }

    return parsed.toList();
  }

  /// Stops early when a found sum equals the accumulated amounts.
  static bool _shouldExitIfValidSum(
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

  /// Skips lines that are clearly below the detected sum label.
  static bool _shouldSkipLine(
    TextLine line,
    RecognizedSumLabel? detectedSumLabel,
    ReceiptRotator rot,
  ) {
    if (detectedSumLabel == null) return false;
    final tol = ReceiptConstants.boundingBoxBuffer.toDouble();
    return rot.yCenter(line) > rot.yCenter(detectedSumLabel.line) + tol;
  }

  /// Appends a deskewed receipt bounding box entity if valid.
  static bool _applyBoundingBox(
    TextLine line,
    List<RecognizedEntity> parsed,
    ReceiptRotator rot,
  ) {
    if (line.boundingBox == Rect.zero) return false;
    final deskewedBoundingBox = rot.deskewRect(line.boundingBox);
    parsed.add(RecognizedBoundingBox(line: line, value: deskewedBoundingBox));
    return true;
  }

  /// Detects store name via custom map or fallback pattern.
  static bool _tryParseStore(
    TextLine line,
    List<RecognizedEntity> parsed,
    RecognizedStore? detectedStore,
    RecognizedAmount? detectedAmount,
    DetectionMap customDetection,
  ) {
    if (detectedStore == null && detectedAmount == null) {
      final text = ReceiptFormatter.trim(line.text);

      final customStore = customDetection.detect(text);
      if (customStore != null) {
        parsed.add(RecognizedStore(line: line, value: customStore));
        return true;
      }
    }
    return false;
  }

  /// Recognizes sum labels using custom detection, fuzziness, and patterns.
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
    return false;
  }

  /// Returns true if the line matches ignore keywords.
  static bool _shouldIgnoreLine(TextLine line, ReceiptOptions options) {
    return options.ignoreKeywords.hasMatch(line.text);
  }

  /// Returns true if the line matches stop keywords.
  static bool _shouldStopParsing(TextLine line, ReceiptOptions options) {
    return options.stopKeywords.hasMatch(line.text);
  }

  /// Recognizes right-side numeric lines as amounts and parses values.
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
        final trimmedAmount = ReceiptFormatter.normalizeAmount(amount);
        final value = double.parse(trimmedAmount);
        parsed.add(RecognizedAmount(line: line, value: value));
        return true;
      }
    }
    return false;
  }

  /// Classifies left-side text as unknown (potential product) lines.
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

  /// Extracts and adds purchase date to the parsed entities if found in the text lines.
  static bool _applyPurchaseDate(
    List<TextLine> lines,
    List<RecognizedEntity> parsed,
  ) {
    RecognizedPurchaseDate? purchaseDate = _extractDateFromLines(lines);
    if (purchaseDate != null) {
      parsed.add(purchaseDate);
      return true;
    }
    return false;
  }

  /// Extracts the first date found in the given text lines.
  static RecognizedPurchaseDate? _extractDateFromLines(List<TextLine> lines) {
    final datePatterns = [
      ReceiptPatterns.dateDayMonthYearNumeric,
      ReceiptPatterns.dateYearMonthDayNumeric,
      ReceiptPatterns.dateDayMonthYearEn,
      ReceiptPatterns.dateMonthDayYearEn,
      ReceiptPatterns.dateDayMonthYearDe,
    ];
    for (final line in lines) {
      for (final p in datePatterns) {
        final m = p.firstMatch(line.text);
        if (m != null && m.groupCount >= 1) {
          return RecognizedPurchaseDate(value: m.group(1)!, line: line);
        }
      }
    }
    return null;
  }

  /// Returns the first detected store entity if any.
  static RecognizedStore? _findStore(List<RecognizedEntity> entities) {
    for (final entity in entities) {
      if (entity is RecognizedStore) return entity;
    }
    return null;
  }

  /// Returns the first detected sum label if any.
  static RecognizedSumLabel? _findSumLabel(List<RecognizedEntity> entities) {
    for (final entity in entities) {
      if (entity is RecognizedSumLabel) return entity;
    }
    return null;
  }

  /// Returns the first detected purchase date entity if any.
  static RecognizedPurchaseDate? _findPurchaseDate(
    List<RecognizedEntity> entities,
  ) {
    for (final entity in entities) {
      if (entity is RecognizedPurchaseDate) return entity;
    }
    return null;
  }

  /// Returns the first detected bounding box entity if any.
  static RecognizedBoundingBox? _findBoundingBox(
    List<RecognizedEntity> entities,
  ) {
    for (final entity in entities) {
      if (entity is RecognizedBoundingBox) return entity;
    }
    return null;
  }

  /// Applies the parsed sum label to the receipt.
  static void _processSumLabel(
    RecognizedSumLabel? sumLabel,
    RecognizedReceipt receipt,
  ) {
    receipt.sumLabel = sumLabel ?? _lastReceipt.sumLabel;
  }

  /// Applies the parsed sum to the receipt.
  static void _processSum(RecognizedSum? sum, RecognizedReceipt receipt) {
    receipt.sum = sum ?? _lastReceipt.sum;
  }

  /// Applies the parsed purchase date to the receipt.
  static void _processPurchaseDate(
    RecognizedPurchaseDate? purchaseDate,
    RecognizedReceipt receipt,
  ) {
    receipt.purchaseDate = purchaseDate ?? _lastReceipt.purchaseDate;
  }

  /// Applies the parsed bounding box to the receipt.
  static void _processBoundingBox(
    RecognizedBoundingBox? boundingBox,
    RecognizedReceipt receipt,
  ) {
    receipt.boundingBox = boundingBox ?? _lastReceipt.boundingBox;
  }

  /// Applies the parsed store to the receipt.
  static void _processStore(RecognizedStore? store, RecognizedReceipt receipt) {
    receipt.store = store ?? _lastReceipt.store;
  }

  /// Pairs amounts with nearest left-side unknowns to create positions.
  static void _processAmounts(
    List<RecognizedEntity> entities,
    List<RecognizedUnknown> yUnknowns,
    RecognizedReceipt receipt,
    List<RecognizedUnknown> forbidden,
    ReceiptRotator rot,
    ReceiptOptions options,
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
        );
      }
    }
  }

  /// Creates a position for an amount by pairing a compatible unknown line.
  static void _createPositionForAmount(
    RecognizedAmount entity,
    List<RecognizedUnknown> yUnknowns,
    RecognizedReceipt receipt,
    List<RecognizedUnknown> forbidden,
    ReceiptRotator rot,
    ReceiptOptions options,
  ) {
    if (entity == receipt.sum) return;

    _sortByDistance(entity.line.boundingBox, yUnknowns, rot);

    for (final yUnknown in yUnknowns) {
      if (_isMatchingUnknown(entity, yUnknown, forbidden, rot, options)) {
        final position = _createPosition(
          yUnknown,
          entity,
          receipt.timestamp,
          options,
        );
        receipt.positions.add(position);
        forbidden.add(yUnknown);
        break;
      }
    }
  }

  /// Returns true if [unknown] is left of [amount] and vertically aligned.
  static bool _isMatchingUnknown(
    RecognizedAmount amount,
    RecognizedUnknown unknown,
    List<RecognizedUnknown> forbidden,
    ReceiptRotator rot,
    ReceiptOptions options,
  ) {
    final unknownText = ReceiptFormatter.trim(unknown.value);
    final isLikelyLabel = options.totalLabels.hasMatch(unknownText);
    if (forbidden.contains(unknown) || isLikelyLabel) return false;

    final amountBox = amount.line.boundingBox;
    final unknownBox = unknown.line.boundingBox;

    final isLeftOfAmount = rot.maxXOf(unknownBox) <= rot.minXOf(amountBox);

    final dy = (rot.yCenter(amount.line) - rot.yCenter(unknown.line)).abs();
    final alignedVertically = dy <= ReceiptConstants.boundingBoxBuffer;

    return isLeftOfAmount && alignedVertically;
  }

  /// Creates a minimal TextLine shell for synthetic entities.
  static TextLine _createTextLine(Rect deskewed, double angleDeg) {
    return ReceiptTextLine.fromRect(deskewed, angle: angleDeg);
  }

  /// Constructs a position from matched product text and amount.
  static RecognizedPosition _createPosition(
    RecognizedUnknown unknown,
    RecognizedAmount amount,
    DateTime timestamp,
    ReceiptOptions options,
  ) {
    final product = RecognizedProduct(
      value: unknown.value,
      line: unknown.line,
      options: options,
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

  /// Derives the sum amount from label alignment or nearest scoring.
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

  /// Extracts known labels from a regex alternation source.
  static List<String> _knownSumLabels(String source) {
    final match = RegExp(r'\((.*?)\)').firstMatch(source);
    if (match == null) return [];
    return match.group(1)!.split('|').map((s) => s.trim()).toList();
  }

  /// Returns a fuzzy threshold based on label length.
  static int _adaptiveThreshold(String label) {
    final length = label.length;
    if (length <= 3) return 95;
    if (length <= 6) return 90;
    if (length <= 12) return 85;
    return 80;
  }

  /// Scores proximity between a sum label and an amount with skew awareness.
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

  /// Sorts entities by vertical distance to an amount, then by X.
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

  /// Finds the closest amount to a sum label using a geometric score.
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

  /// Removes entities that sit between left products and right amounts.
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
      if (entity is RecognizedStore) {
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

  /// Checks if [entity] lies between [leftUnknown] and [rightAmount] and is vertically aligned.
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

  /// Prunes low-confidence positions to bring the total closer to the target sum.
  static void _trimToMatchSum(
    RecognizedReceipt receipt,
    ReceiptOptions options,
  ) {
    final target = receipt.sum?.value;
    if (target == null || receipt.positions.length <= 1) return;

    receipt.positions.removeWhere(
      (pos) =>
          receipt.sum != null &&
          (pos.price.value - receipt.sum!.value).abs() <
              ReceiptConstants.sumTolerance &&
          options.totalLabels.hasMatch(pos.product.value),
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

  /// Removes obviously suspicious product-name positions.
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

  /// One-sided MAD filter in X-space for target entities.
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

  /// Filters left-alignment outliers among unknown product lines.
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

  /// Filters X-center outliers among amount lines.
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

  /// Returns the median of a list of doubles.
  static double _median(List<double> xs) {
    if (xs.isEmpty) return double.nan;
    final a = [...xs]..sort();
    final n = a.length;
    final mid = n >> 1;
    return (n & 1) == 1 ? a[mid] : (a[mid - 1] + a[mid]) / 2.0;
  }

  /// Returns the median absolute deviation about [med].
  static double _mad(List<double> xs, double med) {
    final dev = xs.map((x) => (x - med).abs()).toList()..sort();
    return _median(dev);
  }

  /// Builds a complete receipt from entities and post-filters.
  static RecognizedReceipt _buildReceipt(
    List<RecognizedEntity> entities,
    ReceiptRotator rot,
    ReceiptOptions options,
  ) {
    final yUnknowns = entities.whereType<RecognizedUnknown>().toList();
    final receipt = RecognizedReceipt.empty();
    final List<RecognizedUnknown> forbidden = [];
    final store = _findStore(entities);
    final sumLabel = _findSumLabel(entities);
    final sum = _findSum(entities, sumLabel, rot);
    final purchaseDate = _findPurchaseDate(entities);
    final boundingBox = _findBoundingBox(entities);

    _processAmounts(entities, yUnknowns, receipt, forbidden, rot, options);
    _processStore(store, receipt);
    _processSumLabel(sumLabel, receipt);
    _processSum(sum, receipt);
    _processPurchaseDate(purchaseDate, receipt);
    _processBoundingBox(boundingBox, receipt);
    _filterSuspiciousProducts(receipt);
    _trimToMatchSum(receipt, options);

    return receipt.copyWith(entities: entities);
  }
}
