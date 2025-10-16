import 'dart:ui';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';
import 'package:receipt_recognition/src/utils/configuration/index.dart';
import 'package:receipt_recognition/src/utils/geometry/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';

/// Parses OCR output into a structured receipt by extracting entities, ordering by
/// vertical position, filtering outliers, and assembling positions, total, store, and bounds.
final class ReceiptParser {
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

  /// Matches numeric dates in the format "01.09.2025" or "1/9/25" with a consistent separator.
  static final RegExp _dateDayMonthYearNumeric = RegExp(
    r'\b(\d{1,2}([./-])\d{1,2}\2\d{2,4})\b',
  );

  /// Matches numeric dates in the format "2025-09-01" or "2025/9/1" with a consistent separator.
  static final RegExp _dateYearMonthDayNumeric = RegExp(
    r'\b(\d{4}([./-])\d{1,2}\2\d{1,2})\b',
  );

  /// Matches English dates like "1.September 25", "1. September 2025", or "1 September 2025".
  static final RegExp _dateDayMonthYearEn = RegExp(
    r'\b(\d{1,2}(?:\.\s*|\s+)(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|'
    r'Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|'
    r'Dec(?:ember)?)\.?,?\s+\d{2,4})\b',
    caseSensitive: false,
  );

  /// Matches U.S. English dates like "September 1, 2025", "Sep 1 25", or "Sep.1,2025".
  static final RegExp _dateMonthDayYearEn = RegExp(
    r'\b((Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|'
    r'Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|'
    r'Dec(?:ember)?)\.?\s*\d{1,2},?\s*\d{2,4})\b',
    caseSensitive: false,
  );

  /// Matches German dates like "1.September 25", "1. September 2025", or "1 September 2025".
  static final RegExp _dateDayMonthYearDe = RegExp(
    r'\b(\d{1,2}(?:\.\s*|\s+)(Jan(?:uar)?|Feb(?:ruar)?|Mär(?:z)?|Apr(?:il)?|Mai|Jun(?:i)?|'
    r'Jul(?:i)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Okt(?:ober)?|Nov(?:ember)?|'
    r'Dez(?:ember)?)\.?,?\s+\d{2,4})\b',
    caseSensitive: false,
  );

  /// Pattern to match monetary values (e.g., 1,99 or -5.00).
  static final RegExp _amount = RegExp(
    r'[-−–—]?\s*\d+\s*[.,‚،٫·]\s*\d{2}(?!\d)',
  );

  /// Pattern to match strings likely to be product descriptions.
  static final RegExp _unknown = RegExp(r'[\D\S]{4,}');

  /// Pattern to filter out suspicious or metadata-like product names.
  static final RegExp _suspiciousProductName = RegExp(
    r'\bx\s?\d+',
    caseSensitive: false,
  );

  /// Effective geometric tolerance as double from runtime.
  static double get _tol => ReceiptRuntime.tuning.verticalTolerance.toDouble();

  /// Shorthand for the active parser options provided by [ReceiptRuntime].
  static ReceiptOptions get _opts => ReceiptRuntime.options;

  /// Parses [text] with [options] and returns a structured [RecognizedReceipt].
  /// Performs line ordering, entity extraction, geometric filtering, and building.
  static RecognizedReceipt processText(
    RecognizedText text,
    ReceiptOptions options,
  ) {
    return ReceiptRuntime.runWithOptions(options, () {
      final lines = _convertText(text);
      lines.sort(_cmpCyThenCx);

      final parsed = _parseLines(lines);
      final prunedU = _filterUnknownOutliers(parsed);
      final prunedA = _filterAmountOutliers(prunedU);
      final filtered = _filterIntermediaryEntities(prunedA);

      return _buildReceipt(filtered);
    });
  }

  /// Flattens text blocks to lines sorted by top Y (and left X).
  static List<TextLine> _convertText(RecognizedText text) {
    return text.blocks.expand((block) => block.lines).toList()
      ..sort(_cmpTopThenLeft);
  }

  /// Extracts entities from sorted lines using geometry, patterns, and options.
  static List<RecognizedEntity> _parseLines(List<TextLine> lines) {
    if (lines.isEmpty) return <RecognizedEntity>[];

    final parsed = <RecognizedEntity>[];
    final rect = _extractRectFromLines(lines);
    final median = _cxR(rect);

    RecognizedStore? detectedStore;
    RecognizedTotalLabel? detectedTotalLabel;
    RecognizedAmount? detectedAmount;

    _applyPurchaseDate(lines, parsed);
    _applyBoundingBox(lines, parsed);

    for (final line in lines) {
      if (_shouldExitIfValidTotal(parsed, detectedTotalLabel)) break;
      if (_shouldStopParsing(line)) break;
      if (_shouldIgnoreLine(line)) continue;
      if (_shouldSkipLine(line, detectedTotalLabel)) continue;

      if (_tryParseStore(
        line,
        parsed,
        detectedStore,
        detectedAmount,
        _opts.storeNames,
      )) {
        detectedStore = parsed.last as RecognizedStore;
        continue;
      }

      final text = ReceiptFormatter.trim(line.text);
      final fuzzyTotal = _detectTotalLabelFuzzy(text);
      if (fuzzyTotal != null) {
        parsed.add(RecognizedTotalLabel(line: line, value: fuzzyTotal));
        detectedTotalLabel = parsed.last as RecognizedTotalLabel;
        continue;
      }

      if (detectedTotalLabel?.line == line) continue;

      if (_tryParseAmount(line, parsed, median)) {
        detectedAmount = parsed.last as RecognizedAmount;
        continue;
      }

      if (_tryParseUnknown(line, parsed, median)) continue;
    }

    return parsed;
  }

  /// Fuzzy score for detecting a label *inside* a longer line.
  /// Use the max of partialRatio and tokenSetRatio to handle substrings and word shuffles.
  static int _scoreFuzzy(String line, String label) {
    final p = partialRatio(line, label);
    final ts = tokenSetRatio(line, label);
    return p > ts ? p : ts;
  }

  /// Find best fuzzy match among configured total label *keys*.
  /// Returns the **canonical** value or null if under threshold.
  static String? _detectTotalLabelFuzzy(String lineText) {
    if (_opts.totalLabels.mapping.isEmpty) return null;

    int thr(String label) => _adaptiveThreshold(label);

    String? bestLabel;
    int bestScore = 0;

    for (final label in _opts.totalLabels.mapping.keys) {
      final s = _scoreFuzzy(lineText, label);
      if (s > bestScore) {
        bestScore = s;
        bestLabel = label;
      }
    }

    if (bestLabel == null) return null;
    if (bestScore < thr(bestLabel)) return null;

    final canonical =
        _opts.totalLabels.mapping[bestLabel.toLowerCase()] ?? bestLabel;

    return canonical;
  }

  /// Stops early when a found total equals the accumulated amounts.
  static bool _shouldExitIfValidTotal(
    List<RecognizedEntity> entities,
    RecognizedTotalLabel? totalLabel,
  ) {
    final total = _findTotal(entities, totalLabel);
    if (total == null) return false;
    final amounts = entities.whereType<RecognizedAmount>().toList();
    if (amounts.isEmpty) return false;
    final calculatedTotal = CalculatedTotal(
      value: amounts.fold(-total.value, (a, b) => a + b.value),
    );
    return total.formattedValue == calculatedTotal.formattedValue;
  }

  /// Skips lines that are clearly below the detected total label.
  static bool _shouldSkipLine(
    TextLine line,
    RecognizedTotalLabel? detectedTotalLabel,
  ) {
    if (detectedTotalLabel == null) return false;
    return _cyL(line) > _cyL(detectedTotalLabel.line) + _tol;
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
  static bool _shouldIgnoreLine(TextLine line) =>
      _opts.ignoreKeywords.hasMatch(line.text);

  /// Returns true if the line matches stop keywords.
  static bool _shouldStopParsing(TextLine line) =>
      _opts.stopKeywords.hasMatch(line.text);

  /// Recognizes right-side numeric lines as amounts and parses values.
  static bool _tryParseAmount(
    TextLine line,
    List<RecognizedEntity> parsed,
    double median,
  ) {
    final amount = _amount.stringMatch(line.text);
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
    final unknown = _unknown.stringMatch(line.text);
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
    parsed.add(RecognizedBounds(line: line, value: line.boundingBox));
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

  /// Extracts the first purchase date as a UTC `DateTime` placed directly in `value`,
  /// using the class-level `_date*` regex patterns (numeric and EN/DE month-name forms).
  static RecognizedPurchaseDate? _extractDateFromLines(List<TextLine> lines) {
    final patterns = [
      _dateYearMonthDayNumeric,
      _dateDayMonthYearNumeric,
      _dateDayMonthYearEn,
      _dateMonthDayYearEn,
      _dateDayMonthYearDe,
    ];

    for (final line in lines) {
      final text = line.text;
      for (final p in patterns) {
        final m = p.firstMatch(text);
        if (m == null || m.groupCount < 1) continue;
        final token = m.group(1)!;
        DateTime? dt;

        if (identical(p, _dateYearMonthDayNumeric)) {
          dt = ReceiptFormatter.parseNumericYMD(token);
        } else if (identical(p, _dateDayMonthYearNumeric)) {
          dt = ReceiptFormatter.parseNumericDMY(token);
        } else if (identical(p, _dateMonthDayYearEn)) {
          dt = ReceiptFormatter.parseNameMDY(token);
        } else {
          dt = ReceiptFormatter.parseNameDMY(token);
        }

        if (dt != null) {
          return RecognizedPurchaseDate(value: dt, line: line);
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

  /// Returns the first detected total label if any.
  static RecognizedTotalLabel? _findTotalLabel(
    List<RecognizedEntity> entities,
  ) {
    for (final entity in entities) {
      if (entity is RecognizedTotalLabel) return entity;
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

  /// Returns the first detected bounds entity if any.
  static RecognizedBounds? _findBounds(List<RecognizedEntity> entities) {
    for (final entity in entities) {
      if (entity is RecognizedBounds) return entity;
    }
    return null;
  }

  /// Applies the parsed total label to the receipt.
  static void _processTotalLabel(
    RecognizedTotalLabel? totalLabel,
    RecognizedReceipt receipt,
  ) {
    receipt.totalLabel = totalLabel;
  }

  /// Applies the parsed total to the receipt.
  static void _processTotal(RecognizedTotal? total, RecognizedReceipt receipt) {
    receipt.total = total;
  }

  /// Applies the parsed purchase date to the receipt.
  static void _processPurchaseDate(
    RecognizedPurchaseDate? purchaseDate,
    RecognizedReceipt receipt,
  ) {
    receipt.purchaseDate = purchaseDate;
  }

  /// Applies the parsed bounds to the receipt.
  static void _processBounds(
    RecognizedBounds? bounds,
    RecognizedReceipt receipt,
  ) {
    final skewAngle = ReceiptSkewEstimator.estimateDegrees(receipt);
    receipt.bounds = bounds?.copyWith(skewAngle: skewAngle);
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
  ) {
    for (final entity in entities) {
      if (entity is! RecognizedAmount) continue;
      if (receipt.total?.line == entity.line) continue;
      _createPositionForAmount(entity, yUnknowns, receipt, forbidden);
    }
  }

  /// Creates a position for an amount by pairing a compatible unknown line.
  static void _createPositionForAmount(
    RecognizedAmount entity,
    List<RecognizedUnknown> yUnknowns,
    RecognizedReceipt receipt,
    List<RecognizedUnknown> forbidden,
  ) {
    if (entity == receipt.total) return;
    _sortByDistance(entity.line.boundingBox, yUnknowns);

    for (final yUnknown in yUnknowns) {
      if (_isMatchingUnknown(entity, yUnknown, forbidden)) {
        final position = _createPosition(yUnknown, entity, receipt.timestamp);
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
  ) {
    final unknownText = ReceiptFormatter.trim(unknown.value);
    final isLikelyLabel = _opts.totalLabels.hasMatch(unknownText);
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
  ) {
    final product = RecognizedProduct(
      value: unknown.value,
      line: unknown.line,
      options: _opts,
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

  /// Derives the total amount from label alignment or nearest scoring.
  static RecognizedTotal? _findTotal(
    List<RecognizedEntity> entities,
    RecognizedTotalLabel? totalLabel,
  ) {
    if (totalLabel == null) return null;

    final amounts = entities.whereType<RecognizedAmount>().toList();
    if (amounts.isEmpty) return null;

    RecognizedAmount? rightmost;
    double rightmostX = -double.infinity;
    for (final a in amounts) {
      final dy = (_cyL(a.line) - _cyL(totalLabel.line)).abs();
      if (dy <= _tol && _cxL(a.line) >= _rightL(totalLabel.line) - _tol) {
        final x = _cxL(a.line);
        if (x > rightmostX) {
          rightmostX = x;
          rightmost = a;
        }
      }
    }

    final pick = rightmost ?? _findClosestTotalAmount(totalLabel, amounts);
    if (pick == null) return null;

    return RecognizedTotal(value: pick.value, line: pick.line);
  }

  /// Finds the closest amount to a total label using a geometric score (single pass).
  static RecognizedAmount? _findClosestTotalAmount(
    RecognizedTotalLabel totalLabel,
    List<RecognizedAmount> amounts,
  ) {
    RecognizedAmount? best;
    double bestScore = double.infinity;
    final labelLine = totalLabel.line;
    for (final a in amounts) {
      final s = _distanceScore(labelLine, a.line);
      if (s < bestScore) {
        bestScore = s;
        best = a;
      }
    }
    return best;
  }

  /// Computes an adaptive fuzzy threshold based on label length and an
  /// allowed number of edits. Short labels require near-exact matches,
  /// while longer labels tolerate more edits. The formula is
  /// `threshold(L, k) = round(100 × (1 − k / L)) − margin`,
  /// clamped between 75 and 98 to avoid extremes.
  static int _adaptiveThreshold(String label) {
    final L = label.length;
    if (L <= 0) return 100;
    if (L <= 3) return 98;

    int k;
    if (L <= 5) {
      k = 1;
    } else if (L <= 10) {
      k = 2;
    } else if (L <= 20) {
      k = 3;
    } else {
      k = 4;
    }

    const int margin = 2;
    final double base = 100.0 * (1.0 - (k / L));
    int thr = (base - margin).round();
    thr = thr.clamp(75, 98);
    return thr;
  }

  /// Scores proximity between a total label and an amount using vertical distance and rightward X offset.
  static double _distanceScore(TextLine totalLabel, TextLine amount) {
    final dy = _dy(totalLabel, amount);
    final dx = _cxL(amount) - _rightL(totalLabel);
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

    final totalLabel =
        entities.whereType<RecognizedTotalLabel>().isEmpty
            ? null
            : entities.whereType<RecognizedTotalLabel>().first;
    RecognizedAmount? protectedTotalAmount;
    if (totalLabel != null) {
      final amounts = entities.whereType<RecognizedAmount>().toList();
      protectedTotalAmount = _findClosestTotalAmount(totalLabel, amounts);
    }

    final filtered = <RecognizedEntity>[];
    for (final entity in entities) {
      if (entity is RecognizedStore ||
          entity is RecognizedBounds ||
          entity is RecognizedPurchaseDate ||
          identical(entity, protectedTotalAmount)) {
        filtered.add(entity);
        continue;
      }

      final horizontallyBetween =
          _left(entity) > _right(leftUnknown) &&
          _right(entity) < _left(rightAmount);

      final dyU = (_cy(entity) - _cy(leftUnknown)).abs();
      final dyA = (_cy(entity) - _cy(rightAmount)).abs();
      final verticallyAligned = dyU < _tol || dyA < _tol;

      final betweenUnknownAndAmount = horizontallyBetween && verticallyAligned;

      final betweenTotalLabelAndTotal =
          totalLabel != null &&
          protectedTotalAmount != null &&
          _cy(entity) > _cy(totalLabel) &&
          _cy(entity) < _cy(protectedTotalAmount);

      if (!betweenUnknownAndAmount && !betweenTotalLabelAndTotal) {
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
  static List<RecognizedEntity> _filterUnknownOutliers(
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
  static List<RecognizedEntity> _filterAmountOutliers(
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
  static RecognizedReceipt _buildReceipt(List<RecognizedEntity> entities) {
    final yUnknowns = entities.whereType<RecognizedUnknown>().toList();
    final receipt = RecognizedReceipt.empty();
    final forbidden = <RecognizedUnknown>[];
    final store = _findStore(entities);
    final totalLabel = _findTotalLabel(entities);
    final total = _findTotal(entities, totalLabel);
    final purchaseDate = _findPurchaseDate(entities);
    final bounds = _findBounds(entities);

    _processAmounts(entities, yUnknowns, receipt, forbidden);
    _processStore(store, receipt);
    _processTotalLabel(totalLabel, receipt);
    _processTotal(total, receipt);
    _processPurchaseDate(purchaseDate, receipt);
    _processBounds(bounds, receipt);
    _filterSuspiciousProducts(receipt);
    _trimToMatchTotal(receipt);

    return receipt.copyWith(entities: entities);
  }

  /// Removes obviously suspicious product-name positions.
  static void _filterSuspiciousProducts(RecognizedReceipt receipt) {
    final toRemove = <RecognizedPosition>[];
    for (final pos in receipt.positions) {
      final productText = ReceiptFormatter.trim(pos.product.value);
      if (_suspiciousProductName.hasMatch(productText)) {
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

  /// Prunes low-confidence positions to bring the total closer to the target total.
  static void _trimToMatchTotal(RecognizedReceipt receipt) {
    final target = receipt.total?.value;
    if (target == null || receipt.positions.length <= 1) return;

    final tol = _opts.tuning.totalTolerance;

    receipt.positions.removeWhere(
      (pos) =>
          receipt.total != null &&
          (pos.price.value - receipt.total!.value).abs() <= tol &&
          _opts.totalLabels.hasMatch(pos.product.value),
    );

    final positions = List<RecognizedPosition>.from(receipt.positions)
      ..sort((a, b) => a.confidence.compareTo(b.confidence));
    num currentTotal = receipt.calculatedTotal.value;

    for (final pos in positions) {
      if ((currentTotal - target).abs() <= tol) break;

      final newTotal = currentTotal - pos.price.value;
      final improvement =
          (currentTotal - target).abs() - (newTotal - target).abs();

      if (improvement > 0) {
        receipt.positions.remove(pos);
        pos.group?.members.remove(pos);

        if ((pos.group?.members.isEmpty ?? false)) {
          receipt.positions.removeWhere((p) => p.group == pos.group);
        }
        currentTotal = newTotal;
      }
    }
  }
}
