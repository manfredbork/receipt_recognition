import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';
import 'package:receipt_recognition/src/utils/configuration/index.dart';
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

  /// Height of an entity’s TextLine.
  static double _heightL(TextLine l) => l.boundingBox.height;

  /// Center-Y of an entity’s TextLine.
  static double _cy(RecognizedEntity e) => _cyL(e.line);

  /// Center-X of an entity’s TextLine.
  static double _cx(RecognizedEntity e) => _cxL(e.line);

  /// Left X of an entity’s TextLine.
  static double _left(RecognizedEntity e) => _leftL(e.line);

  /// Right X of an entity’s TextLine.
  static double _right(RecognizedEntity e) => _rightL(e.line);

  /// Top Y of an entity’s TextLine.
  static double _top(RecognizedEntity e) => _topL(e.line);

  /// Bottom Y of an entity’s TextLine.
  static double _bottom(RecognizedEntity e) => _bottomL(e.line);

  /// Center-Y of a Rect.
  static double _cyR(Rect r) => r.center.dy;

  /// Absolute vertical distance between two TextLines’ centers.
  static double _dy(TextLine a, TextLine b) => _cyL(a) - _cyL(b);

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

  /// Converts a [RecognizedTotal] into a [RecognizedAmount] with shared value and line.
  static RecognizedAmount _toAmount(RecognizedTotal total) =>
      RecognizedAmount(value: total.value, line: total.line);

  /// Converts a [RecognizedAmount] into a [RecognizedTotal] with shared value and line.
  static RecognizedTotal _toTotal(RecognizedAmount amount) =>
      RecognizedTotal(value: amount.value, line: amount.line);

  /// ISO date (YYYY-MM-DD) directly before a time like "T08:50"; accepts unicode dashes.
  static final RegExp _dateIsoYMD = RegExp(
    r'(?<!\d)(\d{4}([-–—])\d{1,2}\2\d{1,2})(?=T\d{1,2}[:.]\d{2}(?::\d{2})?(?:[.,]\d+)?\b)',
  );

  /// Y-M-D with exactly 0 or 1 space around separators; allows time after or a non-alnum/end.
  static final RegExp _dateYearMonthDayNumeric = RegExp(
    r'(?<!\d)(\d{4} ?([./\-–—]) ?\d{1,2} ?\2 ?\d{1,2})(?:(?=[T\s]\d{1,2}[:.]\d{2})|(?![0-9A-Za-z]))',
  );

  /// D-M-Y with exactly 0 or 1 space around separators; allows time after or a non-alnum/end.
  static final RegExp _dateDayMonthYearNumeric = RegExp(
    r'(?<!\d)(\d{1,2} ?([./\-–—]) ?\d{1,2} ?\2 ?\d{2,4})(?:(?=\s+\d{1,2}[:.]\d{2})|(?![0-9A-Za-z]))',
  );

  /// Matches English dates like "1.September 25", "1. September 2025", or "1 September 2025".
  static final RegExp _dateDayMonthYearEn = RegExp(
    r'\b(\d{1,2}(?:\.\s*|\s+)(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|'
    r'Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|'
    r'Dec(?:ember)?)\.? ,?\s+\d{2,4})\b',
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
    r'Dez(?:ember)?)\.? ,?\s+\d{2,4})\b',
    caseSensitive: false,
  );

  /// Pattern to match monetary values (e.g., 1,99 or -5.00).
  static final RegExp _amount = RegExp(
    r'[-−–—]?\s*\d+\s*[.,‚،٫·]\s*\d{2}(?!\d)',
  );

  /// Matches quantity expressions like "3", "2x Item", "3 * Item", "2 kg × Another", and "2 Stk x".
  static final RegExp _quantity = RegExp(
    r'^\s*(\d+)(?:\s*(\S{1,3})?\s*[xX×*]\s*(.*))?\s*$',
  );

  /// Shorthand for the active options provided by [ReceiptRuntime].
  static ReceiptOptions get _options => ReceiptRuntime.options;

  /// Parses [text] with [options] and returns a structured [RecognizedReceipt].
  /// Performs line ordering, entity extraction, geometric filtering, and building.
  static RecognizedReceipt processText(
    RecognizedText text,
    ReceiptOptions options,
  ) {
    return ReceiptRuntime.runWithOptions(options, () {
      if (text.blocks.isEmpty) return RecognizedReceipt.empty();

      final lines = _convertText(text)..sort(_cmpCyThenCx);
      final parsed = _parseLines(lines);
      final entities = _filterEntities(parsed);

      return _buildReceipt(entities);
    });
  }

  /// Flattens text blocks to lines sorted by top Y (and left X).
  ///
  /// Returns a new list; does not mutate the input [text].
  static List<TextLine> _convertText(RecognizedText text) {
    return text.blocks.expand((block) => block.lines).toList()
      ..sort(_cmpTopThenLeft);
  }

  /// Extracts entities from sorted lines using geometry, patterns, and options.
  static List<RecognizedEntity> _parseLines(List<TextLine> lines) {
    final parsed = <RecognizedEntity>[];
    if (lines.isEmpty) return parsed;

    _applyPurchaseDate(lines, parsed);
    _applyBounds(lines, parsed);

    final bounds = _findBounds(parsed);
    if (bounds == null) return parsed;

    final fifth = (1 / 5) * (_rightL(bounds.line) - _leftL(bounds.line));
    final leftBound = _leftL(bounds.line) + fifth;
    final rightBound = _rightL(bounds.line) - fifth;

    for (final line in lines) {
      if (_tryIdentifyTotal(line, parsed, rightBound)) continue;
      if (_shouldStopIfTotalConfirmed(line, parsed)) break;
      if (_shouldStopIfStopWord(line)) break;
      if (_shouldIgnoreLine(line)) continue;
      if (_tryParseTotalLabel(line, parsed, leftBound)) continue;
      if (_tryParseStore(line, parsed)) continue;
      if (_tryParseAmount(line, parsed, rightBound)) continue;
      if (_tryParseUnit(line, parsed, rightBound)) continue;
      if (_tryParseUnknown(line, parsed, leftBound)) continue;
    }

    return parsed;
  }

  /// Returns true if the line matches ignore keywords.
  static bool _shouldIgnoreLine(TextLine line) =>
      _options.ignoreKeywords.hasMatch(line.text);

  /// Stops parsing once the running sum of detected amounts equals the confirmed total.
  ///
  /// Returns `true` if a [RecognizedTotal] is already known and the sum of
  /// collected [RecognizedAmount] values matches its formatted value
  /// (within formatting, not numeric tolerance). This acts as an early exit
  /// to avoid over-parsing below the total.
  static bool _shouldStopIfTotalConfirmed(
    TextLine line,
    List<RecognizedEntity> parsed,
  ) {
    final totalLabel = _findTotalLabel(parsed);
    if (totalLabel == null) return false;

    final total = _findTotal(parsed);
    if (total == null) return false;

    final amounts = parsed.whereType<RecognizedAmount>().toList();
    if (amounts.isEmpty) return false;

    final amountsTotal = amounts.fold<double>(0, (a, b) => a + b.value);
    final calculatedTotal = CalculatedTotal(value: amountsTotal);

    return total.formattedValue == calculatedTotal.formattedValue;
  }

  /// Returns `true` if the line matches a configured stop keyword.
  /// Used to terminate parsing once a footer or end-of-receipt marker is seen.
  static bool _shouldStopIfStopWord(TextLine line) =>
      _options.stopKeywords.hasMatch(line.text);

  /// Detects a total label on [line] via fuzzy match and appends it to [parsed]; returns true if added.
  static bool _tryParseTotalLabel(
    TextLine line,
    List<RecognizedEntity> parsed,
    double leftBound,
  ) {
    if (_leftL(line) > leftBound) return false;

    if (_options.totalLabels.mapping.isEmpty) return false;

    final label = _findTotalLabelLike(line.text);
    final canonical = _options.totalLabels.mapping[label] ?? label;
    if (canonical != null) {
      parsed.add(RecognizedTotalLabel(line: line, value: canonical));
      return true;
    }
    return false;
  }

  /// Returns true if [text] fuzzy-matches any configured total label above the adaptive threshold.
  static bool _isTotalLabelLike(String text) {
    return _findTotalLabelLike(text) != null;
  }

  /// Best-match total label key for [text] using normalized similarity + adaptive threshold, or null if none.
  static String? _findTotalLabelLike(String text) {
    String? bestLabel;
    int bestScore = 0;
    for (final label in _options.totalLabels.mapping.keys) {
      final normText = ReceiptNormalizer.normalizeKey(text).toLowerCase();
      if (normText.startsWith(label) && normText.length < label.length << 1) {
        return label;
      }

      final s = ratio(normText, label);
      if (s > bestScore && normText.length >= label.length) {
        bestScore = s;
        bestLabel = label;
      }
    }
    if (bestLabel == null) return null;
    final threshold = bestLabel.length > 5 ? 90 : 95;
    if (bestScore < threshold) return null;
    return bestLabel;
  }

  /// Detects store name via custom map; early-bails if we already saw a store or an amount.
  static bool _tryParseStore(TextLine line, List<RecognizedEntity> parsed) {
    final store = _findStore(parsed);
    if (store != null) return false;
    final amount = _findAmount(parsed);
    if (amount != null) return false;
    final customDetection = _options.storeNames;
    final text = ReceiptFormatter.trim(line.text);
    final customStore = customDetection.detect(text);
    if (customStore == null) return false;
    parsed.add(RecognizedStore(line: line, value: customStore));
    return true;
  }

  /// Attempts to identify and swap the closest amount entity near a total label as the receipt total.
  /// Returns `false` always; modifies [parsed] in place by converting detected total/amount pairs.
  static bool _tryIdentifyTotal(
    TextLine line,
    List<RecognizedEntity> parsed,
    double rightBound,
  ) {
    final totalLabel = _findTotalLabel(parsed);
    if (totalLabel == null) return false;
    final amounts = parsed.whereType<RecognizedAmount>().toList();
    final closestAmount = _findClosestTotalAmount(totalLabel, amounts);
    if (closestAmount != null) {
      replaceWhere<RecognizedEntity>(
        parsed,
        (e) => e is RecognizedTotal,
        (e) => _toAmount(e as RecognizedTotal),
      );
      replaceWhere<RecognizedEntity>(
        parsed,
        (e) => identical(e, closestAmount),
        (e) => _toTotal(e as RecognizedAmount),
      );
    }
    return false;
  }

  /// Recognizes right-side numeric lines as amounts and parses values.
  static bool _tryParseAmount(
    TextLine line,
    List<RecognizedEntity> parsed,
    double rightBound,
  ) {
    if (_rightL(line) <= rightBound) return false;
    final amount = _amount.stringMatch(line.text);
    if (amount == null) return false;
    final value = _convertToDouble(amount);
    if (value == null || value == 0) return false;
    parsed.add(RecognizedAmount(line: line, value: value.toDouble()));
    return true;
  }

  /// Recognizes left-side lines as unit quantity and/or price and parses values.
  static bool _tryParseUnit(
    TextLine line,
    List<RecognizedEntity> parsed,
    double rightBound,
  ) {
    if (_rightL(line) > rightBound) return false;
    final quantity = _quantity.stringMatch(line.text);
    final amount = _amount.stringMatch(line.text);

    int? unitQuantity;
    if (quantity != null) {
      unitQuantity = _convertToInteger(quantity);
    }

    double? unitPrice;
    if (amount != null) {
      unitPrice = _convertToDouble(amount);
    }

    if (unitQuantity == null && unitPrice == null) return false;

    if (unitQuantity != null) {
      parsed.add(RecognizedUnitQuantity(line: line, value: unitQuantity));
    }

    if (unitPrice != null) {
      parsed.add(RecognizedUnitPrice(line: line, value: unitPrice));
    }

    final qTokens = line.text.split(_quantity);
    final aTokens = line.text.split(_amount);
    final qLen = qTokens.join().length;
    final aLen = aTokens.join().length;
    final minLen = qLen < aLen ? qLen : aLen;

    String text = line.text;
    if (qTokens.length > 1 && aTokens.length > 1) {
      text =
          qTokens.first.length < aTokens.first.length
              ? qTokens.first
              : aTokens.first;
    } else if (qTokens.length > 1) {
      text = qTokens.first;
    } else if (aTokens.length > 1) {
      text = aTokens.first;
    }

    final minLenSatisfied1 = minLen / line.text.length >= 0.5;
    final minLenSatisfied2 = text.length / line.text.length >= 0.5;

    final looksLikeExtension = minLenSatisfied1 && minLenSatisfied2;
    if (looksLikeExtension) {
      final modified = ReceiptTextLine.fromLine(line).copyWith(text: text);
      _tryParseUnknown(modified, parsed, rightBound);
    }

    final looksLikeInsideProduct = minLenSatisfied1 && !minLenSatisfied2;
    if (looksLikeInsideProduct) {
      _tryParseUnknown(line, parsed, rightBound);
    }

    return true;
  }

  /// Classifies left-side text as unknown (potential product) lines.
  static bool _tryParseUnknown(
    TextLine line,
    List<RecognizedEntity> parsed,
    double leftBound,
  ) {
    if (_leftL(line) > leftBound) return false;
    final unknown = line.text;
    final numeric = _convertToDouble(unknown)?.toString() ?? '';
    if (numeric.length / unknown.length < 0.5) {
      parsed.add(RecognizedUnknown(line: line, value: unknown));
      return true;
    }
    return false;
  }

  /// Appends an aggregate (axis-aligned) receipt bounding box entity derived from all lines.
  static bool _applyBounds(
    List<TextLine> lines,
    List<RecognizedEntity> parsed,
  ) {
    final line = ReceiptTextLine().copyWith(
      boundingBox: _extractRectFromLines(lines),
    );
    parsed.add(RecognizedBounds(line: line, value: line.boundingBox));
    return true;
  }

  /// Extracts digits from a string and returns them as an integer, or null if no valid integer can be formed.
  static int? _convertToInteger(String input) {
    if (RegExp(r'\d[.,]\d').hasMatch(input)) return null;
    final norm = input.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(norm);
  }

  /// Converts a string to a double by normalizing minus signs and decimal separators.
  static double? _convertToDouble(String input) {
    final norm1 = input.replaceAll(RegExp('[-−–—]'), '-');
    final norm2 = norm1.replaceAll(RegExp('[.,‚،٫·]'), '.');
    final norm3 = norm2.replaceAll(RegExp('[^-0-9.]'), '');
    return double.tryParse(norm3);
  }

  /// Replaces elements in [list] that satisfy [test] by applying [replace] to them.
  /// Returns the count of elements that were replaced.
  static int replaceWhere<T>(
    List<T> list,
    bool Function(T element) test,
    T Function(T element) replace,
  ) {
    int count = 0;
    for (int i = 0; i < list.length; i++) {
      if (test(list[i])) {
        list[i] = replace(list[i]);
        count++;
      }
    }
    return count;
  }

  /// Computes the tight axis-aligned bounding [Rect] that encloses all [lines].
  /// Returns [Rect.zero] when the input is empty.
  static Rect _extractRectFromLines(List<TextLine> lines) {
    if (lines.isEmpty) return Rect.zero;
    double minX = _leftL(lines.first);
    double maxX = _rightL(lines.first);
    double minY = _topL(lines.first);
    double maxY = _bottomL(lines.first);
    for (int i = 1; i < lines.length; i++) {
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

  /// Finds the most prominent date: try ISO first, then YMD/DMY, then name-month; use all matches.
  static RecognizedPurchaseDate? _extractDateFromLines(List<TextLine> lines) {
    final patterns = [
      _dateIsoYMD,
      _dateYearMonthDayNumeric,
      _dateDayMonthYearNumeric,
      _dateMonthDayYearEn,
      _dateDayMonthYearEn,
      _dateDayMonthYearDe,
    ];

    for (final line in lines) {
      final t = line.text;
      for (final p in patterns) {
        for (final m in p.allMatches(t)) {
          if (m.groupCount < 1) continue;
          final s = m.group(1)!;
          DateTime? dt =
              identical(p, _dateIsoYMD) ||
                      identical(p, _dateYearMonthDayNumeric)
                  ? ReceiptFormatter.parseNumericYMD(s)
                  : identical(p, _dateDayMonthYearNumeric)
                  ? ReceiptFormatter.parseNumericDMY(s)
                  : identical(p, _dateMonthDayYearEn)
                  ? ReceiptFormatter.parseNameMDY(s)
                  : ReceiptFormatter.parseNameDMY(s);
          if (dt != null) {
            return RecognizedPurchaseDate(value: dt, line: line);
          }
        }
      }
    }
    return null;
  }

  /// Returns the first detected store entity if any.
  static RecognizedStore? _findStore(List<RecognizedEntity> entities) {
    return entities.whereType<RecognizedStore>().firstOrNull;
  }

  /// Returns the first detected purchase date entity if any.
  static RecognizedPurchaseDate? _findPurchaseDate(
    List<RecognizedEntity> entities,
  ) {
    return entities.whereType<RecognizedPurchaseDate>().firstOrNull;
  }

  /// Returns the first detected bounds entity if any.
  static RecognizedBounds? _findBounds(List<RecognizedEntity> entities) {
    return entities.whereType<RecognizedBounds>().firstOrNull;
  }

  /// Returns the last detected total label if any.
  static RecognizedTotalLabel? _findTotalLabel(
    List<RecognizedEntity> entities,
  ) {
    return entities.whereType<RecognizedTotalLabel>().lastOrNull;
  }

  /// Returns the last detected total if any.
  static RecognizedTotal? _findTotal(List<RecognizedEntity> entities) {
    return entities.whereType<RecognizedTotal>().lastOrNull;
  }

  /// Returns the last detected amount if any.
  static RecognizedAmount? _findAmount(List<RecognizedEntity> entities) {
    return entities.whereType<RecognizedAmount>().lastOrNull;
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
    receipt.bounds = bounds;
  }

  /// Applies the parsed store to the receipt.
  static void _processStore(RecognizedStore? store, RecognizedReceipt receipt) {
    receipt.store = store;
  }

  /// Pairs amounts with nearest left-side unknowns and units to create positions.
  static void _processAmounts(
    List<RecognizedEntity> entities,
    List<RecognizedUnknown> yUnknowns,
    List<RecognizedUnitPrice> yUnitPrices,
    List<RecognizedUnitQuantity> yUnitQuantities,
    RecognizedReceipt receipt,
  ) {
    final amounts = entities.whereType<RecognizedAmount>().toList();
    for (final amount in amounts) {
      if (!_createPositionForAmount(amount, yUnknowns, receipt)) {
        _createPositionForAmount(amount, yUnknowns, receipt, strict: false);
      }
    }
    _assignUnitToPositions(yUnitPrices, yUnitQuantities, receipt);
  }

  /// Pairs unit price and quantity for a position.
  static RecognizedUnit? _processUnit(
    RecognizedProduct product,
    List<RecognizedProduct> products,
    List<RecognizedUnitPrice> yUnitPrices,
    List<RecognizedUnitQuantity> yUnitQuantities,
  ) {
    if (product.position == null) return null;

    final yUnitPrice = _findClosestEntity(
      product,
      yUnitPrices,
      lineBelow: true,
      crossCheckEntities: products,
    );

    final yUnitQuantity = _findClosestEntity(
      product,
      yUnitQuantities,
      lineBelow: true,
      crossCheckEntities: products,
    );

    final tolerance = _options.tuning.optimizerTotalTolerance;
    final defaultLine = product.line;
    final defaultPrice = product.position!.price.value;
    final defaultQuantity = 1;

    final sign = (yUnitPrice?.value ?? 0) > 0 && defaultPrice < 0 ? -1.0 : 1.0;
    final unitPrice = sign * (yUnitPrice?.value ?? defaultPrice);
    final unitQuantity = yUnitQuantity?.value ?? defaultQuantity;

    if (yUnitPrice != null) yUnitPrices.remove(yUnitPrice);
    if (yUnitQuantity != null) yUnitQuantities.remove(yUnitQuantity);

    if (unitPrice != defaultPrice && unitQuantity != defaultQuantity) {
      final test = _isClose(unitPrice * unitQuantity, defaultPrice, tolerance);
      if (test) {
        return RecognizedUnit.fromNumbers(unitQuantity, unitPrice, defaultLine);
      }
    }

    if (unitPrice != defaultPrice) {
      final quantity = (defaultPrice / unitPrice).round();
      if (quantity > 0) {
        final test = _isClose(quantity * unitPrice, defaultPrice, tolerance);
        if (test) {
          return RecognizedUnit.fromNumbers(quantity, unitPrice, defaultLine);
        }
      }
    }

    if (unitQuantity != defaultQuantity) {
      final price = (defaultPrice / unitQuantity * 100).round() / 100;
      if (price != 0) {
        final test = _isClose(unitQuantity * price, defaultPrice, tolerance);
        if (test) {
          final unitPriceFromTotal = defaultPrice / unitQuantity;
          return RecognizedUnit.fromNumbers(
            unitQuantity,
            unitPriceFromTotal,
            defaultLine,
          );
        }
      }
    }

    return RecognizedUnit.fromNumbers(
      defaultQuantity,
      defaultPrice,
      defaultLine,
    );
  }

  /// Returns true if two numbers differ by less than the given tolerance.
  static bool _isClose(double a, double b, double tolerance) =>
      (a - b).abs() < tolerance;

  /// Assigns each unit to the closest position.
  static void _assignUnitToPositions(
    List<RecognizedUnitPrice> yUnitPrices,
    List<RecognizedUnitQuantity> yUnitQuantities,
    RecognizedReceipt receipt,
  ) {
    final positions = receipt.positions;
    final products = positions.map((p) => p.product).toList();
    for (final position in positions) {
      final unit = _processUnit(
        position.product,
        products,
        yUnitPrices,
        yUnitQuantities,
      );
      if (unit != null) {
        position.unit = unit;
      }
    }
  }

  /// Returns true if a position for an amount and unknown is created.
  static bool _createPositionForAmount(
    RecognizedAmount amount,
    List<RecognizedUnknown> yUnknowns,
    RecognizedReceipt receipt, {
    strict = true,
  }) {
    _sortByDistance(amount.line.boundingBox, yUnknowns);
    for (final yUnknown in yUnknowns) {
      if (_isMatchingUnknown(amount, yUnknown, strict: strict) &&
          identical(
            _findClosestEntity(amount, yUnknowns, lineAbove: !strict),
            yUnknown,
          )) {
        final position = _createPosition(yUnknown, amount, receipt.timestamp);
        receipt.positions.add(position);
        yUnknowns.removeWhere((e) => identical(e, yUnknown));
        return true;
      }
    }
    return false;
  }

  /// Returns true if [unknown] is left of [amount] and vertically aligned.
  static bool _isMatchingUnknown(
    RecognizedAmount amount,
    RecognizedUnknown unknown, {
    strict = true,
  }) {
    final unknownText = ReceiptFormatter.trim(unknown.value);
    final isLikelyLabel = _isTotalLabelLike(unknownText);
    if (isLikelyLabel) return false;

    final isLeftOfAmount = _right(unknown) <= _left(amount);
    final alignedVertically =
        _dy(amount.line, unknown.line).abs() <= _heightL(amount.line);

    return isLeftOfAmount && (alignedVertically || !strict);
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
      options: _options,
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

  /// Finds the closest entity to another entity using a geometric score.
  static RecognizedEntity? _findClosestEntity(
    RecognizedEntity entity,
    List<RecognizedEntity> entities, {
    lineAbove = false,
    lineBelow = false,
    List<RecognizedEntity> crossCheckEntities = const [],
  }) {
    RecognizedEntity? best;
    double bestScore = double.infinity;
    final line = entity.line;
    for (final e in entities) {
      final s = _distanceScore(
        line,
        e.line,
        lineAbove: lineAbove,
        lineBelow: lineBelow,
      );
      if (s < bestScore) {
        bestScore = s;
        best = e;
      }
    }
    if (best == null || bestScore == double.infinity) return null;
    if (crossCheckEntities.isNotEmpty) {
      final bothDirection = lineAbove && lineBelow;
      final crossLineAbove = bothDirection ? true : !lineAbove;
      final crossLineBelow = bothDirection ? true : !lineBelow;
      final crossCheckEntity = _findClosestEntity(
        best,
        crossCheckEntities,
        lineAbove: crossLineAbove,
        lineBelow: crossLineBelow,
      );
      if (!identical(entity, crossCheckEntity)) return null;
    }
    return best;
  }

  /// Finds the closest amount to a total label using a geometric score (single pass).
  static RecognizedAmount? _findClosestTotalAmount(
    RecognizedTotalLabel totalLabel,
    List<RecognizedAmount> amounts,
  ) {
    final entity = _findClosestEntity(totalLabel, amounts, lineBelow: true);
    return entity != null ? entity as RecognizedAmount : null;
  }

  /// Returns absolute ΔY if within vertical tolerance, otherwise `double.infinity` (lower is better).
  static double _distanceScore(
    TextLine sourceLine,
    TextLine targetLine, {
    bool lineAbove = false,
    bool lineBelow = false,
  }) {
    if (identical(sourceLine, targetLine)) return double.infinity;

    final tol = max(_heightL(sourceLine), _heightL(targetLine));
    final srcTop = _topL(sourceLine) - (lineAbove ? tol * pi : 0);
    final srcBottom = _bottomL(sourceLine) + (lineBelow ? tol * pi : 0);

    final targetCy = _cyL(targetLine);
    final isSameLine = targetCy >= srcTop && targetCy <= srcBottom;

    return isSameLine ? _dy(sourceLine, targetLine).abs() : double.infinity;
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

  /// Removes entities that are not required anymore.
  static List<RecognizedEntity> _filterEntities(
    List<RecognizedEntity> entities,
  ) {
    RecognizedUnknown? leftUnknown;
    double leftmostX = double.maxFinite;
    RecognizedAmount? rightAmount;
    double rightmostX = 0;
    RecognizedAmount? firstAmount;

    for (final e in entities) {
      if (e is RecognizedUnknown) {
        final lx = _left(e);
        if (lx < leftmostX) {
          leftmostX = lx;
          leftUnknown = e;
        }
      } else if (e is RecognizedAmount) {
        firstAmount ??= e;
        final rx = _right(e);
        if (rx > rightmostX) {
          rightmostX = rx;
          rightAmount = e;
        }
      }
    }
    if (leftUnknown == null || rightAmount == null) return entities;

    final totalLabel = _findTotalLabel(entities);
    final total = _findTotal(entities);

    final filtered = <RecognizedEntity>[];
    for (final entity in entities) {
      if (entity is RecognizedStore) {
        if (firstAmount != null && _cy(entity) < _top(firstAmount)) {
          filtered.add(entity);
        }
        continue;
      } else if (entity is RecognizedBounds ||
          entity is RecognizedPurchaseDate ||
          entity is RecognizedUnitPrice ||
          entity is RecognizedUnitQuantity) {
        filtered.add(entity);
        continue;
      } else if (entity is RecognizedTotalLabel) {
        if (identical(entity, totalLabel)) {
          filtered.add(entity);
        } else {
          filtered.add(
            RecognizedUnknown(value: entity.value, line: entity.line),
          );
        }
        continue;
      } else if (entity is RecognizedTotal) {
        if (identical(entity, total)) {
          filtered.add(entity);
        } else {
          filtered.add(
            RecognizedAmount(value: entity.value, line: entity.line),
          );
        }
        continue;
      }

      final horizontallyBetween =
          _left(entity) > _right(leftUnknown) &&
          _right(entity) < _left(rightAmount);

      final dyU = (_cy(entity) - _cy(leftUnknown)).abs();
      final dyA = (_cy(entity) - _cy(rightAmount)).abs();
      final verticallyAligned =
          dyU < _heightL(leftUnknown.line) || dyA < _heightL(rightAmount.line);

      final betweenUnknownAndAmount = horizontallyBetween && verticallyAligned;

      final belowTotalLabelAndTotal =
          totalLabel != null &&
          total != null &&
          _cy(entity) > _bottom(totalLabel) &&
          _cy(entity) > _bottom(total);

      if (!betweenUnknownAndAmount && !belowTotalLabelAndTotal) {
        filtered.add(entity);
      }
    }
    return filtered;
  }

  /// Builds a complete receipt from entities and post-filters.
  static RecognizedReceipt _buildReceipt(List<RecognizedEntity> entities) {
    final yUnknowns = entities.whereType<RecognizedUnknown>().toList();
    final yUnitPrices = entities.whereType<RecognizedUnitPrice>().toList();
    final yUnitQuantities =
        entities.whereType<RecognizedUnitQuantity>().toList();
    final receipt = RecognizedReceipt.empty();
    final store = _findStore(entities);
    final totalLabel = _findTotalLabel(entities);
    final total = _findTotal(entities);
    final purchaseDate = _findPurchaseDate(entities);
    final bounds = _findBounds(entities);

    _processStore(store, receipt);
    _processTotalLabel(totalLabel, receipt);
    _processTotal(total, receipt);
    _processPurchaseDate(purchaseDate, receipt);
    _processBounds(bounds, receipt);
    _processAmounts(entities, yUnknowns, yUnitPrices, yUnitQuantities, receipt);

    return receipt.copyWith(entities: entities);
  }
}
