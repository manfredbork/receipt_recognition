import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';
import 'package:receipt_recognition/src/utils/configuration/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';

/// Parses OCR output into a structured receipt by extracting entities, ordering by
/// vertical position, filtering outliers, and assembling positions, total, store, and bounds.
///
/// Use [ReceiptTextProcessor.processText] to run this off the UI thread.
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

  /// Center-X of a Rect.
  static double _cxR(Rect r) => r.center.dx;

  /// Absolute vertical distance between two TextLines’ centers.
  static double _dy(TextLine a, TextLine b) => _cyL(a) - _cyL(b);

  static double _cxMedian(List<RecognizedEntity> parsed) {
    final bounds = parsed.whereType<RecognizedBounds>();
    return bounds.isNotEmpty ? _cxR(bounds.last.boundingBox) * 1.5 : 0;
  }

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

  /// Pattern to match strings likely to be product descriptions.
  static final RegExp _unknown = RegExp(r'[\D\S]{4,}');

  /// Pattern to filter out suspicious or metadata-like product names.
  static final RegExp _suspiciousProductName = RegExp(
    r'\bx\s?\d+|^\s*[\[(]?\s*\d{1,3}[.,]\d{3}\b',
    caseSensitive: false,
  );

  /// Shorthand for the active options provided by [ReceiptRuntime].
  static ReceiptOptions get _opts => ReceiptRuntime.options;

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
      final prunedUnknowns = _filterUnknownOutliers(parsed);
      final prunedAmounts = _filterAmountOutliers(prunedUnknowns);
      final prunedIntermediary = _filterIntermediaryEntities(prunedAmounts);
      final prunedBelow = _filterBelowTotalAndLabel(prunedIntermediary);

      return _buildReceipt(prunedBelow);
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
    if (lines.isEmpty) return <RecognizedEntity>[];

    final parsed = <RecognizedEntity>[];

    _applyPurchaseDate(lines, parsed);
    _applyBounds(lines, parsed);

    final median = _cxMedian(parsed);

    for (final line in lines) {
      if (_shouldStopIfTotalConfirmed(line, parsed)) break;
      if (_shouldStopIfStopWord(line)) break;
      if (_shouldIgnoreLine(line)) continue;
      if (_tryParseStore(line, parsed)) continue;
      if (_tryParseTotalLabel(line, parsed)) continue;
      if (_tryParseTotal(line, parsed, median)) continue;
      if (_tryParseAmount(line, parsed, median)) continue;
      if (_tryParseUnit(line, parsed, median)) continue;
      if (_tryParseUnknown(line, parsed, median)) continue;
    }

    return parsed;
  }

  /// Returns true if the line matches ignore keywords.
  static bool _shouldIgnoreLine(TextLine line) =>
      _opts.ignoreKeywords.hasMatch(line.text);

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
    final total = _findTotal(parsed);
    if (total == null) return false;

    final amounts = parsed.whereType<RecognizedAmount>().toList();
    if (amounts.isEmpty) return false;

    final sum = amounts.fold<double>(0, (a, b) => a + b.value);
    final formattedSum = CalculatedTotal(value: sum).formattedValue;
    final stop = total.formattedValue == formattedSum;
    return stop;
  }

  /// Returns `true` if the line matches a configured stop keyword.
  /// Used to terminate parsing once a footer or end-of-receipt marker is seen.
  static bool _shouldStopIfStopWord(TextLine line) =>
      _opts.stopKeywords.hasMatch(line.text);

  /// Detects a total label on [line] via fuzzy match and appends it to [parsed]; returns true if added.
  static bool _tryParseTotalLabel(
    TextLine line,
    List<RecognizedEntity> parsed,
  ) {
    if (_opts.totalLabels.mapping.isEmpty) return false;

    final totalLabel = _findTotalLabel(parsed);
    final total = _findTotalLabel(parsed);
    final label = _findTotalLabelLike(line.text);
    final canonical = _opts.totalLabels.mapping[label] ?? label;
    if (canonical != null) {
      if (totalLabel != null && total != null) {
        parsed.removeWhere(
          (e) => identical(e, totalLabel) || identical(e, total),
        );
      }
      parsed.add(RecognizedTotalLabel(line: line, value: canonical));
    }
    return canonical != null;
  }

  /// Returns true if [text] fuzzy-matches any configured total label above the adaptive threshold.
  static bool _isTotalLabelLike(String text) {
    return _findTotalLabelLike(text) != null;
  }

  /// Best-match total label key for [text] using normalized similarity + adaptive threshold, or null if none.
  static String? _findTotalLabelLike(String text) {
    int thr(String label) => _adaptiveThreshold(label);
    String? bestLabel;
    int bestScore = 0;
    for (final label in _opts.totalLabels.mapping.keys) {
      final s = ReceiptNormalizer.similarity(text.toLowerCase(), label);
      if (s > bestScore && text.length >= label.length) {
        bestScore = s;
        bestLabel = label;
      }
    }
    if (bestLabel == null || bestScore < thr(bestLabel)) return null;
    return bestLabel;
  }

  /// Finds the amount nearest to total label and marks it as [RecognizedTotal].
  /// Adds it to [parsed] and returns `true` if successful.
  static bool _tryParseTotal(
    TextLine line,
    List<RecognizedEntity> parsed,
    double median,
  ) {
    final totalLabel = _findTotalLabel(parsed);
    if (totalLabel == null) return false;
    final total = _findTotal(parsed);
    if (_tryParseAmount(line, parsed, median)) {
      final amounts = parsed.whereType<RecognizedAmount>().toList();
      final closestAmount = _findClosestTotalAmount(totalLabel, amounts);
      if (closestAmount == null) {
        parsed.removeLast();
        return false;
      } else {
        final i = parsed.indexWhere((e) => identical(e, total));
        if (i >= 0) {
          parsed[i] = _toAmount(parsed[i] as RecognizedTotal);
        }
        parsed.removeWhere(
          (e) => e is RecognizedAmount && identical(e, closestAmount),
        );
        parsed.add(_toTotal(closestAmount));
        return true;
      }
    }
    return false;
  }

  /// Detects store name via custom map; early-bails if we already saw a store or an amount.
  static bool _tryParseStore(TextLine line, List<RecognizedEntity> parsed) {
    final store = _findStore(parsed);
    if (store != null) return false;
    final amount = _findAmount(parsed);
    if (amount != null) return false;
    final customDetection = _opts.storeNames;
    final text = ReceiptFormatter.trim(line.text);
    final customStore = customDetection.detect(text);
    if (customStore == null) return false;
    parsed.add(RecognizedStore(line: line, value: customStore));
    return true;
  }

  /// Recognizes right-side numeric lines as amounts and parses values.
  static bool _tryParseAmount(
    TextLine line,
    List<RecognizedEntity> parsed,
    double median,
  ) {
    if (_cxL(line) <= median) return false;
    final amount = _amount.stringMatch(line.text);
    if (amount == null) return false;
    final value = double.tryParse(ReceiptFormatter.normalizeAmount(amount));
    if (value == null) return false;
    parsed.add(RecognizedAmount(line: line, value: value));
    return true;
  }

  /// Recognizes left-side and centered numeric lines as unit price and parses values.
  static bool _tryParseUnit(
    TextLine line,
    List<RecognizedEntity> parsed,
    double median,
  ) {
    if (_cxL(line) > median) return false;
    final amount = _amount.stringMatch(line.text);
    if (amount == null) return false;
    final value = double.tryParse(ReceiptFormatter.normalizeAmount(amount));
    if (value == null) return false;
    parsed.add(RecognizedUnitPrice(line: line, value: value));
    _tryParseUnknown(line, parsed, median);
    return true;
  }

  /// Classifies left-side text as unknown (potential product) lines.
  static bool _tryParseUnknown(
    TextLine line,
    List<RecognizedEntity> parsed,
    double median,
  ) {
    if (_cxL(line) > median) return false;
    final unknown = _unknown.stringMatch(
      ReceiptNormalizer.shouldNormalizeTail(line.text)
          ? ReceiptNormalizer.normalizeTail(line.text)
          : line.text,
    );
    if (unknown == null) return false;
    final leadingDigits = ReceiptFormatter.leadingDigits(unknown);
    final lettersOnly = ReceiptFormatter.lettersOnly(unknown);
    if (leadingDigits.isEmpty && lettersOnly.length >= 4) {
      parsed.add(RecognizedUnknown(line: line, value: unknown));
    }
    return true;
  }

  /// Appends an aggregate (axis-aligned) receipt bounding box entity derived from all lines.
  static bool _applyBounds(
    List<TextLine> lines,
    List<RecognizedEntity> parsed,
  ) {
    final line = ReceiptTextLine.fromRect(_extractRectFromLines(lines));
    parsed.add(RecognizedBounds(line: line, value: line.boundingBox));
    return true;
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
    RecognizedReceipt receipt,
  ) {
    final unprocessedAmounts = <RecognizedAmount>[];
    final amounts = entities.whereType<RecognizedAmount>().toList();
    for (final amount in amounts) {
      if (identical(receipt.total?.line, amount.line)) break;
      if (!_createPositionForAmount(amount, yUnknowns, yUnitPrices, receipt)) {
        unprocessedAmounts.add(amount);
      }
    }
    if (unprocessedAmounts.isNotEmpty && yUnknowns.isNotEmpty) {
      for (final amount in unprocessedAmounts) {
        _createPositionForAmount(
          amount,
          yUnknowns,
          yUnitPrices,
          receipt,
          strict: false,
        );
      }
    }
    _assignUnitToPositions(yUnitPrices, receipt);
  }

  /// Removes obviously suspicious product-name positions.
  static void _processSuspicious(RecognizedReceipt receipt) {
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

  /// Assigns each unit to the closest position.
  static void _assignUnitToPositions(
    List<RecognizedUnitPrice> yUnitPrices,
    RecognizedReceipt receipt,
  ) {
    final positions = receipt.positions;
    final products = positions.map((p) => p.product).toList();
    for (final position in positions) {
      final yUnitPrice = _findClosestEntity(
        position.product,
        yUnitPrices,
        lineBelow: true,
        crossCheckEntities: products,
      );

      if (yUnitPrice != null) {
        final unitPrice = yUnitPrice as RecognizedUnitPrice;
        final isDeposit = position.price.value < 0 && unitPrice.value > 0;
        final unitSign = isDeposit ? -1 : 1;
        final centsUnitPrice = (unitPrice.value * 100).round();
        final centsPrice = (position.price.value * 100).round();

        if (centsPrice % centsUnitPrice == 0) {
          position.unit = RecognizedUnit.fromNumbers(
            (centsPrice ~/ centsUnitPrice) * unitSign,
            (unitPrice.value * unitSign),
            yUnitPrice.line,
          );
          yUnitPrices.removeWhere((e) => identical(e, yUnitPrice));
        } else {
          position.unit = RecognizedUnit.fromNumbers(
            1,
            position.price.value,
            yUnitPrice.line,
          );
        }

        if (isDeposit) {
          final oldGroup = position.group;

          final newPosition = position.copyWith(
            product: position.product.copyWith(
              value: position.product.line.text,
            ),
          );
          newPosition.group = oldGroup;
          newPosition.product.position = newPosition;
          newPosition.price.position = newPosition;

          final i = receipt.positions.indexOf(position);
          if (i >= 0) receipt.positions[i] = newPosition;

          final gi = oldGroup?.members.indexOf(position) ?? -1;
          if (gi >= 0) oldGroup!.members[gi] = newPosition;
        }
      } else {
        position.unit = RecognizedUnit.fromNumbers(
          1,
          position.price.value,
          position.price.line,
        );
      }
    }
  }

  /// Returns true if a position for an amount and unknown is created.
  static bool _createPositionForAmount(
    RecognizedAmount amount,
    List<RecognizedUnknown> yUnknowns,
    List<RecognizedUnitPrice> yUnitPrices,
    RecognizedReceipt receipt, {
    strict = true,
  }) {
    _sortByDistance(amount.line.boundingBox, yUnknowns);
    for (final yUnknown in yUnknowns) {
      if (_isMatchingUnknown(amount, yUnknown) &&
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
    final entity = _findClosestEntity(totalLabel, amounts);
    return entity != null ? entity as RecognizedAmount : null;
  }

  /// Computes an adaptive fuzzy threshold based on label length and
  /// the number of allowed edits. Short labels require near-exact matches,
  /// while longer labels tolerate more deviations.
  ///
  /// Formula:
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
      xMetric: (e) => _right(e),
      dropRightTail: false,
    );
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
    final ids = <String>[];
    final targets = <RecognizedEntity>[];

    for (final e in entities) {
      if (isTarget(e)) {
        xs.add(xMetric(e));
        ids.add(_dbgId(e));
        targets.add(e);
      }
    }

    if (xs.length < minSamples) return entities;

    final scratch = <double>[];
    final med = _medianInPlace(List<double>.from(xs, growable: true));

    if (xs.isEmpty || med.isNaN || med.isInfinite) return entities;

    final madRaw = _madWithScratch(xs, med, scratch);
    final madScaled = (madRaw == 0.0) ? 0.0 : (1.4826 * madRaw);
    final lowerBound = med - k * madScaled;
    final upperBound = med + k * madScaled;
    final out = <RecognizedEntity>[];
    final removed = <Map<String, Object?>>[];
    final kept = <Map<String, Object?>>[];

    for (final e in entities) {
      if (!isTarget(e)) {
        out.add(e);
        kept.add(_dbgEntity(e, xMetric));
        continue;
      }
      final x = xMetric(e);
      final tol = _heightL(e.line);
      final isOutlier =
          dropRightTail ? (x > upperBound + tol) : (x < lowerBound - tol);

      if (!isOutlier) {
        out.add(e);
        kept.add(_dbgEntity(e, xMetric));
      } else {
        removed.add(_dbgEntity(e, xMetric));
      }
    }

    return out;
  }

  /// Returns a short debug identifier with entity type and approximate position.
  static String _dbgId(RecognizedEntity e) {
    try {
      return '${e.runtimeType}@'
          '${_left(e).toStringAsFixed(1)},'
          '${_cy(e).toStringAsFixed(1)}';
    } catch (_) {
      return '${e.runtimeType}';
    }
  }

  /// Returns a compact debug map describing an entity’s geometry and text/value.
  static Map<String, Object?> _dbgEntity(
    RecognizedEntity e,
    double Function(RecognizedEntity) xMetric,
  ) {
    double? left, right, cx, cy;
    try {
      left = _left(e);
      right = _right(e);
      cx = _cx(e);
      cy = _cy(e);
    } catch (_) {}

    return {
      'id': _dbgId(e),
      'type': '${e.runtimeType}',
      'xMetric': xMetric(e),
      'left': left,
      'right': right,
      'cx': cx,
      'cy': cy,
      'text':
          (e is RecognizedUnknown)
              ? ReceiptFormatter.trim(e.value)
              : (e is RecognizedAmount)
              ? e.value
              : (e is RecognizedTotalLabel)
              ? e.value
              : (e is RecognizedStore)
              ? e.value
              : null,
    };
  }

  /// Returns the median of a list by sorting in place.
  static double _medianInPlace(List<double> a) {
    if (a.isEmpty) return double.nan;
    a.sort();
    final n = a.length;
    final mid = n >> 1;
    return (n & 1) == 1 ? a[mid] : (a[mid - 1] + a[mid]) / 2.0;
  }

  /// Returns the median absolute deviation (MAD) of [xs] using a reusable buffer.
  static double _madWithScratch(
    List<double> xs,
    double med,
    List<double> scratch,
  ) {
    if (scratch.length != xs.length) {
      scratch
        ..clear()
        ..addAll(List<double>.filled(xs.length, 0.0));
    }
    for (int i = 0; i < xs.length; i++) {
      scratch[i] = (xs[i] - med).abs();
    }
    return _medianInPlace(scratch);
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
        if (firstAmount != null && _cy(entity) < _cy(firstAmount)) {
          filtered.add(entity);
        }
        continue;
      } else if (entity is RecognizedBounds ||
          entity is RecognizedPurchaseDate ||
          entity is RecognizedUnitPrice ||
          entity is RecognizedTotalLabel ||
          entity is RecognizedTotal) {
        filtered.add(entity);
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

      final betweenTotalLabelAndTotal =
          totalLabel != null &&
          total != null &&
          _cy(entity) > _top(totalLabel) &&
          _cy(entity) < _bottom(total);

      if (!betweenUnknownAndAmount && !betweenTotalLabelAndTotal) {
        filtered.add(entity);
      }
    }
    return filtered;
  }

  /// Drop entities strictly below total/label (keep RecognizedPurchaseDate).
  static List<RecognizedEntity> _filterBelowTotalAndLabel(
    List<RecognizedEntity> entities,
  ) {
    final totalLabel = _findTotalLabel(entities);
    final total = _findTotal(entities);

    if (totalLabel == null || total == null) return entities;

    double maxBottom = max(_bottom(totalLabel), _bottom(total));

    final out = <RecognizedEntity>[];
    final removed = <String>[];

    for (final e in entities) {
      if (e is RecognizedPurchaseDate) {
        out.add(e);
        continue;
      }
      final tol = _heightL(e.line);
      final isBelow = _top(e) > maxBottom + tol;
      if (!isBelow) {
        out.add(e);
      } else {
        removed.add(_dbgId(e));
      }
    }

    return out;
  }

  /// Builds a complete receipt from entities and post-filters.
  static RecognizedReceipt _buildReceipt(List<RecognizedEntity> entities) {
    final yUnknowns = entities.whereType<RecognizedUnknown>().toList();
    final yUnitPrices = entities.whereType<RecognizedUnitPrice>().toList();
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
    _processAmounts(entities, yUnknowns, yUnitPrices, receipt);
    _processSuspicious(receipt);

    return receipt.copyWith(entities: entities);
  }
}
