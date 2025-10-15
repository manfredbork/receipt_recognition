import 'dart:ui';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/parser/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';
import 'package:receipt_recognition/src/utils/ocr/index.dart';

/// Parses OCR output into a structured receipt by extracting entities,
/// ordering by vertical position, filtering outliers, and assembling positions, sum, store, and bounds.
final class ReceiptParser {
  /// Common tolerance as double.
  static double get _tol => ReceiptConstants.boundingBoxBuffer.toDouble();

  /// Center-Y of a TextLine.
  static double _cyL(TextLine l) => l.boundingBox.center.dy;

  /// Center-X of a TextLine.
  static double _cxL(TextLine l) => l.boundingBox.center.dx;

  /// Left X of a TextLine.
  static double _leftL(TextLine l) => l.boundingBox.left;

  /// Right X of a TextLine.
  static double _rightL(TextLine l) => l.boundingBox.right;

  /// Top Y of a TextLine.
  static double _topL(TextLine l) => l.boundingBox.top;

  /// Bottom Y of a TextLine.
  static double _bottomL(TextLine l) => l.boundingBox.bottom;

  /// Center-Y of an entity’s TextLine.
  static double _cy(RecognizedEntity e) => _cyL(e.line);

  /// Center-X of an entity’s TextLine.
  static double _cx(RecognizedEntity e) => _cxL(e.line);

  /// Left X of an entity’s TextLine.
  static double _left(RecognizedEntity e) => _leftL(e.line);

  /// Right X of an entity’s TextLine.
  static double _right(RecognizedEntity e) => _rightL(e.line);

  /// Center-Y of a Rect.
  static double _cyR(Rect r) => r.center.dy;

  /// Center-X of a Rect.
  static double _cxR(Rect r) => r.center.dx;

  /// Absolute vertical distance between two TextLines’ centers.
  static double _dy(TextLine a, TextLine b) => (_cyL(a) - _cyL(b)).abs();

  /// Comparator by center-Y, then center-X (ascending).
  static int _cmpCyThenCx(TextLine a, TextLine b) {
    final c = _cyL(a).compareTo(_cyL(b));
    return c != 0 ? c : _cxL(a).compareTo(_cxL(b));
  }

  /// Comparator by top Y, then left X (ascending).
  static int _cmpTopThenLeft(TextLine a, TextLine b) {
    final c = _topL(a).compareTo(_topL(b));
    return c != 0 ? c : _leftL(a).compareTo(_leftL(b));
  }

  /// Parses [text] with [options] and returns a structured [RecognizedReceipt].
  /// Performs line ordering, entity extraction, geometric filtering, and building.
  static RecognizedReceipt processText(
    RecognizedText text,
    ReceiptOptions options,
  ) {
    final lines = _convertText(text);
    lines.sort(_cmpCyThenCx);

    final parsed = _parseLines(lines, options);
    final prunedU = _filterUnknownLeftAlignmentOutliers(parsed);
    final prunedA = _filterAmountXOutliers(prunedU);
    final filtered = _filterIntermediaryEntities(prunedA);

    return _buildReceipt(filtered, options);
  }

  /// Flattens text blocks to lines sorted by top Y (and left X).
  static List<TextLine> _convertText(RecognizedText text) {
    return text.blocks.expand((block) => block.lines).toList()
      ..sort(_cmpTopThenLeft);
  }

  /// Extracts entities from sorted lines using geometry, patterns, and options.
  static List<RecognizedEntity> _parseLines(
    List<TextLine> lines,
    ReceiptOptions options,
  ) {
    if (lines.isEmpty) return <RecognizedEntity>[];

    final parsed = <RecognizedEntity>[];
    final rect = _extractRectFromLines(lines);
    final median = _cxR(rect);

    RecognizedStore? detectedStore;
    RecognizedSumLabel? detectedSumLabel;
    RecognizedAmount? detectedAmount;

    _applyPurchaseDate(lines, parsed);
    _applyBoundingBox(lines, parsed);

    final thresholdCache = <String, int>{};
    int thr(String label) =>
        thresholdCache[label] ??= _adaptiveThreshold(label);

    for (final line in lines) {
      if (_shouldExitIfValidSum(parsed, detectedSumLabel)) break;
      if (_shouldStopParsing(line, options)) break;
      if (_shouldIgnoreLine(line, options)) continue;
      if (_shouldSkipLine(line, detectedSumLabel)) continue;

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

      final text = ReceiptFormatter.trim(line.text);
      final customSumLabel = options.totalLabels.detect(text);
      if (customSumLabel != null) {
        parsed.add(RecognizedSumLabel(line: line, value: customSumLabel));
        detectedSumLabel = parsed.last as RecognizedSumLabel;
        continue;
      }
      for (final label in options.totalLabels.mapping.keys) {
        if (ratio(text, label) >= thr(label)) {
          parsed.add(RecognizedSumLabel(line: line, value: label));
          detectedSumLabel = parsed.last as RecognizedSumLabel;
          break;
        }
      }
      if (detectedSumLabel?.line == line) continue;

      if (_tryParseAmount(line, parsed, median)) {
        detectedAmount = parsed.last as RecognizedAmount;
        continue;
      }

      if (_tryParseUnknown(line, parsed, median)) continue;
    }

    return parsed;
  }

  /// Stops early when a found sum equals the accumulated amounts.
  static bool _shouldExitIfValidSum(
    List<RecognizedEntity> entities,
    RecognizedSumLabel? sumLabel,
  ) {
    final sum = _findSum(entities, sumLabel);
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
  ) {
    if (detectedSumLabel == null) return false;
    return _cyL(line) > _cyL(detectedSumLabel.line) + _tol;
  }

  /// Detects store name via custom map; early-bails if we already saw a store or an amount.
  static bool _tryParseStore(
    TextLine line,
    List<RecognizedEntity> parsed,
    RecognizedStore? detectedStore,
    RecognizedAmount? detectedAmount,
    DetectionMap customDetection,
  ) {
    if (detectedStore != null || detectedAmount != null) return false;
    final text = ReceiptFormatter.trim(line.text);
    final customStore = customDetection.detect(text);
    if (customStore == null) return false;
    parsed.add(RecognizedStore(line: line, value: customStore));
    return true;
  }

  /// Returns true if the line matches ignore keywords.
  static bool _shouldIgnoreLine(TextLine line, ReceiptOptions options) =>
      options.ignoreKeywords.hasMatch(line.text);

  /// Returns true if the line matches stop keywords.
  static bool _shouldStopParsing(TextLine line, ReceiptOptions options) =>
      options.stopKeywords.hasMatch(line.text);

  /// Recognizes right-side numeric lines as amounts and parses values.
  static bool _tryParseAmount(
    TextLine line,
    List<RecognizedEntity> parsed,
    double median,
  ) {
    final amount = ReceiptPatterns.amount.stringMatch(line.text);
    if (amount == null) return false;
    if (_cxL(line) <= median - _tol) return false;
    final value = double.parse(ReceiptFormatter.normalizeAmount(amount));
    parsed.add(RecognizedAmount(line: line, value: value));
    return true;
  }

  /// Classifies left-side text as unknown (potential product) lines.
  static bool _tryParseUnknown(
    TextLine line,
    List<RecognizedEntity> parsed,
    double median,
  ) {
    final unknown = ReceiptPatterns.unknown.stringMatch(line.text);
    if (unknown == null || _cxL(line) >= median) return false;
    parsed.add(RecognizedUnknown(line: line, value: line.text));
    return true;
  }

  /// Appends an aggregate (axis-aligned) receipt bounding box entity derived from all lines.
  static bool _applyBoundingBox(
    List<TextLine> lines,
    List<RecognizedEntity> parsed,
  ) {
    if (lines.isEmpty) return false;
    final line = ReceiptTextLine.fromRect(_extractRectFromLines(lines));
    parsed.add(RecognizedBoundingBox(line: line, value: line.boundingBox));
    return true;
  }

  static Rect _extractRectFromLines(List<TextLine> lines) {
    if (lines.isEmpty) return Rect.zero;
    double minX = _leftL(lines.first);
    double maxX = _rightL(lines.first);
    double minY = _topL(lines.first);
    double maxY = _bottomL(lines.first);
    for (var i = 1; i < lines.length; i++) {
      final l = lines[i];
      final left = _leftL(l),
          right = _rightL(l),
          top = _topL(l),
          bottom = _bottomL(l);
      if (left < minX) minX = left;
      if (right > maxX) maxX = right;
      if (top < minY) minY = top;
      if (bottom > maxY) maxY = bottom;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Extracts and adds purchase date to the parsed entities if found in the text lines.
  static bool _applyPurchaseDate(
    List<TextLine> lines,
    List<RecognizedEntity> parsed,
  ) {
    final purchaseDate = _extractDateFromLines(lines);
    if (purchaseDate == null) return false;
    parsed.add(purchaseDate);
    return true;
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
    receipt.sumLabel = sumLabel;
  }

  /// Applies the parsed sum to the receipt.
  static void _processSum(RecognizedSum? sum, RecognizedReceipt receipt) {
    receipt.sum = sum;
  }

  /// Applies the parsed purchase date to the receipt.
  static void _processPurchaseDate(
    RecognizedPurchaseDate? purchaseDate,
    RecognizedReceipt receipt,
  ) {
    receipt.purchaseDate = purchaseDate;
  }

  /// Applies the parsed bounding box to the receipt.
  static void _processBoundingBox(
    RecognizedBoundingBox? boundingBox,
    RecognizedReceipt receipt,
  ) {
    receipt.boundingBox = boundingBox;
  }

  /// Applies the parsed store to the receipt.
  static void _processStore(RecognizedStore? store, RecognizedReceipt receipt) {
    receipt.store = store;
  }

  /// Pairs amounts with nearest left-side unknowns to create positions.
  static void _processAmounts(
    List<RecognizedEntity> entities,
    List<RecognizedUnknown> yUnknowns,
    RecognizedReceipt receipt,
    List<RecognizedUnknown> forbidden,
    ReceiptOptions options,
  ) {
    for (final entity in entities) {
      if (entity is! RecognizedAmount) continue;
      if (receipt.sum?.line == entity.line) continue;
      _createPositionForAmount(entity, yUnknowns, receipt, forbidden, options);
    }
  }

  /// Creates a position for an amount by pairing a compatible unknown line.
  static void _createPositionForAmount(
    RecognizedAmount entity,
    List<RecognizedUnknown> yUnknowns,
    RecognizedReceipt receipt,
    List<RecognizedUnknown> forbidden,
    ReceiptOptions options,
  ) {
    if (entity == receipt.sum) return;
    _sortByDistance(entity.line.boundingBox, yUnknowns);

    for (final yUnknown in yUnknowns) {
      if (_isMatchingUnknown(entity, yUnknown, forbidden, options)) {
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
    ReceiptOptions options,
  ) {
    final unknownText = ReceiptFormatter.trim(unknown.value);
    final isLikelyLabel = options.totalLabels.hasMatch(unknownText);
    if (forbidden.contains(unknown) || isLikelyLabel) return false;

    final isLeftOfAmount = _right(unknown) <= _left(amount);
    final alignedVertically = _dy(amount.line, unknown.line) <= _tol;

    return isLeftOfAmount && alignedVertically;
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
  ) {
    if (sumLabel == null) return null;

    final amounts = entities.whereType<RecognizedAmount>().toList();
    if (amounts.isEmpty) return null;

    RecognizedAmount? rightmost;
    double rightmostX = -double.infinity;
    for (final a in amounts) {
      final dy = (_cyL(a.line) - _cyL(sumLabel.line)).abs();
      if (dy <= _tol && _cxL(a.line) >= _rightL(sumLabel.line) - _tol) {
        final x = _cxL(a.line);
        if (x > rightmostX) {
          rightmostX = x;
          rightmost = a;
        }
      }
    }

    final pick = rightmost ?? _findClosestSumAmount(sumLabel, amounts);
    if (pick == null) return null;

    return RecognizedSum(value: pick.value, line: pick.line);
  }

  /// Finds the closest amount to a sum label using a geometric score (single pass).
  static RecognizedAmount? _findClosestSumAmount(
    RecognizedSumLabel sumLabel,
    List<RecognizedAmount> amounts,
  ) {
    RecognizedAmount? best;
    double bestScore = double.infinity;
    final labelLine = sumLabel.line;
    for (final a in amounts) {
      final s = _distanceScore(labelLine, a.line);
      if (s < bestScore) {
        bestScore = s;
        best = a;
      }
    }
    return best;
  }

  /// Returns a fuzzy threshold based on label length.
  static int _adaptiveThreshold(String label) {
    final length = label.length;
    if (length <= 3) return 95;
    if (length <= 6) return 90;
    if (length <= 12) return 85;
    return 80;
  }

  /// Scores proximity between a sum label and an amount using vertical distance and rightward X offset.
  static double _distanceScore(TextLine sumLabel, TextLine amount) {
    final dy = _dy(sumLabel, amount);
    final dx = _cxL(amount) - _rightL(sumLabel);
    final dxPenalty = dx >= 0 ? dx : (dx.abs() * 3);
    return dy + (dxPenalty * 0.3);
  }

  /// Sorts entities by vertical distance to an amount, then by X.
  static void _sortByDistance(Rect amountBox, List<RecognizedEntity> entities) {
    final amountYCtr = _cyR(amountBox);

    entities.sort((a, b) {
      final dyA = (_cy(a) - amountYCtr).abs();
      final dyB = (_cy(b) - amountYCtr).abs();
      final vc = dyA.compareTo(dyB);
      return vc != 0 ? vc : _cx(a).compareTo(_cx(b));
    });
  }

  /// Removes entities that sit between left products and right amounts.
  static List<RecognizedEntity> _filterIntermediaryEntities(
    List<RecognizedEntity> entities,
  ) {
    RecognizedUnknown? leftUnknown;
    double leftmostX = double.infinity;
    RecognizedAmount? rightAmount;
    double rightmostX = -double.infinity;

    for (final e in entities) {
      if (e is RecognizedUnknown) {
        final lx = _left(e);
        if (lx < leftmostX) {
          leftmostX = lx;
          leftUnknown = e;
        }
      } else if (e is RecognizedAmount) {
        final rx = _right(e);
        if (rx > rightmostX) {
          rightmostX = rx;
          rightAmount = e;
        }
      }
    }
    if (leftUnknown == null || rightAmount == null) return entities;

    final sumLabel =
        entities.whereType<RecognizedSumLabel>().isEmpty
            ? null
            : entities.whereType<RecognizedSumLabel>().first;
    RecognizedAmount? protectedSumAmount;
    if (sumLabel != null) {
      final amounts = entities.whereType<RecognizedAmount>().toList();
      protectedSumAmount = _findClosestSumAmount(sumLabel, amounts);
    }

    final filtered = <RecognizedEntity>[];
    for (final entity in entities) {
      if (entity is RecognizedStore ||
          entity is RecognizedBoundingBox ||
          entity is RecognizedPurchaseDate ||
          identical(entity, protectedSumAmount)) {
        filtered.add(entity);
        continue;
      }

      final horizontallyBetween =
          _left(entity) > _right(leftUnknown) &&
          _right(entity) < _left(rightAmount);

      final dyU = (_cy(entity) - _cy(leftUnknown)).abs();
      final dyA = (_cy(entity) - _cy(rightAmount)).abs();
      final verticallyAligned =
          dyU < ReceiptConstants.boundingBoxBuffer ||
          dyA < ReceiptConstants.boundingBoxBuffer;

      final betweenUnknownAndAmount = horizontallyBetween && verticallyAligned;

      final betweenSumLabelAndSum =
          sumLabel != null &&
          protectedSumAmount != null &&
          _cy(entity) > _cy(sumLabel) &&
          _cy(entity) < _cy(protectedSumAmount);

      if (!betweenUnknownAndAmount && !betweenSumLabelAndSum) {
        filtered.add(entity);
      }
    }
    return filtered;
  }

  /// One-sided MAD filter in X-space for target entities (single pass filter without sets).
  static List<RecognizedEntity> _filterOneSidedXOutliers(
    List<RecognizedEntity> entities, {
    required bool Function(RecognizedEntity e) isTarget,
    required double Function(RecognizedEntity e) xMetric,
    required bool dropRightTail,
    int minSamples = 3,
    double k = 5.0,
  }) {
    final xs = <double>[];
    for (final e in entities) {
      if (isTarget(e)) xs.add(xMetric(e));
    }
    if (xs.length < minSamples) return entities;

    final scratch = <double>[];

    final med = _medianInPlace(List<double>.from(xs, growable: true));
    if (med.isNaN) return entities;

    final madRaw = _madWithScratch(xs, med, scratch);
    final madScaled = (madRaw == 0.0) ? 1.0 : (1.4826 * madRaw);

    final lowerBound = med - k * madScaled - _tol;
    final upperBound = med + k * madScaled + _tol;

    final out = <RecognizedEntity>[];
    for (final e in entities) {
      if (!isTarget(e)) {
        out.add(e);
        continue;
      }
      final x = xMetric(e);
      final isOutlier = dropRightTail ? (x > upperBound) : (x < lowerBound);
      if (!isOutlier) out.add(e);
    }
    return out;
  }

  /// Filters left-alignment outliers among unknown product lines.
  static List<RecognizedEntity> _filterUnknownLeftAlignmentOutliers(
    List<RecognizedEntity> entities,
  ) {
    return _filterOneSidedXOutliers(
      entities,
      isTarget: (e) => e is RecognizedUnknown,
      xMetric: (e) => _left(e),
      dropRightTail: true,
    );
  }

  /// Filters X-center outliers among amount lines.
  static List<RecognizedEntity> _filterAmountXOutliers(
    List<RecognizedEntity> entities,
  ) {
    return _filterOneSidedXOutliers(
      entities,
      isTarget: (e) => e is RecognizedAmount,
      xMetric: (e) => _cx(e),
      dropRightTail: false,
    );
  }

  /// Returns the median of a list by sorting in place.
  static double _medianInPlace(List<double> a) {
    if (a.isEmpty) return double.nan;
    a.sort();
    final n = a.length;
    final mid = n >> 1;
    return (n & 1) == 1 ? a[mid] : (a[mid - 1] + a[mid]) / 2.0;
  }

  /// Returns the median absolute deviation using a reusable scratch buffer.
  static double _madWithScratch(
    List<double> xs,
    double med,
    List<double> scratch,
  ) {
    scratch
      ..clear()
      ..length = xs.length;
    for (var i = 0; i < xs.length; i++) {
      scratch[i] = (xs[i] - med).abs();
    }
    return _medianInPlace(scratch);
  }

  /// Builds a complete receipt from entities and post-filters.
  static RecognizedReceipt _buildReceipt(
    List<RecognizedEntity> entities,
    ReceiptOptions options,
  ) {
    final yUnknowns = entities.whereType<RecognizedUnknown>().toList();
    final receipt = RecognizedReceipt.empty();
    final forbidden = <RecognizedUnknown>[];
    final store = _findStore(entities);
    final sumLabel = _findSumLabel(entities);
    final sum = _findSum(entities, sumLabel);
    final purchaseDate = _findPurchaseDate(entities);
    final boundingBox = _findBoundingBox(entities);

    _processAmounts(entities, yUnknowns, receipt, forbidden, options);
    _processStore(store, receipt);
    _processSumLabel(sumLabel, receipt);
    _processSum(sum, receipt);
    _processPurchaseDate(purchaseDate, receipt);
    _processBoundingBox(boundingBox, receipt);
    _filterSuspiciousProducts(receipt);
    _trimToMatchSum(receipt, options);

    return receipt.copyWith(entities: entities);
  }

  /// Removes obviously suspicious product-name positions.
  static void _filterSuspiciousProducts(RecognizedReceipt receipt) {
    final toRemove = <RecognizedPosition>[];
    for (final pos in receipt.positions) {
      final productText = ReceiptFormatter.trim(pos.product.value);
      if (ReceiptPatterns.suspiciousProductName.hasMatch(productText)) {
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

    final positions = List<RecognizedPosition>.from(receipt.positions)
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
}
