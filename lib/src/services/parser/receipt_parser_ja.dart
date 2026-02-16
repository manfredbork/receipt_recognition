import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';
import 'package:receipt_recognition/src/utils/configuration/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';

/// Japanese receipt parser using a row-grouping strategy.
///
/// Groups [TextLine]s into rows by Y-coordinate proximity, then extracts
/// prices and product names from each row. This handles both separate and
/// combined product-name/price [TextLine]s that are common in Japanese receipts.
///
/// Falls back to the same [RecognizedReceipt] output format as
/// [ReceiptParser] so the optimizer and validation pipeline work unchanged.
final class ReceiptParserJa {
  /// Matches Japanese yen amounts: ¥198, ￥1,280, ¥702※, etc.
  /// Captures the numeric portion (digits, commas, spaces).
  static final RegExp _yenPrefix = RegExp(
    r'[¥￥]\s*([\d,\s]+)',
  );

  /// Matches amounts with trailing 円: 198円, 1,280円
  static final RegExp _yenSuffix = RegExp(
    r'(\d[\d,]*)\s*円',
  );

  /// Matches standalone discount lines: -100, −200, –300
  static final RegExp _discount = RegExp(
    r'^[-−–—]\s*([\d,]+)$',
  );

  /// Fallback: standalone price-like numbers without ¥/円.
  /// Handles OCR artifacts: leading *, +; trailing >, %, ), X, *.
  /// Requires 2+ digits to avoid matching quantity "1".
  static final RegExp _standalonePrice = RegExp(
    r'^[*+]?(\d[\d,]{1,5})[>%\)X※＞\*]*$',
  );

  /// Garbled ¥ prefix: OCR commonly reads ¥ as digit 4.
  /// "4702%" → ¥702※ (price = 702).
  /// Requires trailing artifacts to distinguish from legitimate prices.
  static final RegExp _yenGarbled = RegExp(
    r'^4(\d[\d,]{0,5})[%\)>※＞\*X]+$',
  );

  /// Matches tax rate indicator lines common on Japanese receipts:
  /// "(8% 軽)", "(10% 標)", "(8% 内税額)", etc.
  /// OCR often garbles these to "(8% REAR", "(8% BRI", "(10% ..." etc.
  static final RegExp _taxRate = RegExp(
    r'^\(?\d{1,2}%',
  );

  /// Active options from [ReceiptRuntime].
  static ReceiptOptions get _options => ReceiptRuntime.options;

  /// Parses [text] using the row-grouping strategy and returns a receipt.
  static RecognizedReceipt processText(
    RecognizedText text,
    ReceiptOptions options,
  ) {
    return ReceiptRuntime.runWithOptions(options, () {
      if (text.blocks.isEmpty) return RecognizedReceipt.empty();

      final allLines = text.blocks
          .expand((b) => b.lines)
          .toList();

      if (allLines.isEmpty) return RecognizedReceipt.empty();

      // Detect if the image is rotated 90° (text lines taller than wide).
      final rotated = _isRotated(allLines);

      // Sort: primary axis = receipt top→bottom, secondary = within-line.
      allLines.sort((a, b) {
        final ab = a.boundingBox;
        final bb = b.boundingBox;
        final (p1, s1, p2, s2) = rotated
            ? (ab.left, ab.top, bb.left, bb.top)
            : (ab.top, ab.left, bb.top, bb.left);
        return switch (p1.compareTo(p2)) {
          0 => s1.compareTo(s2),
          final c => c,
        };
      });

      final entities = <RecognizedEntity>[];

      // Extract date from all lines.
      final purchaseDate = _extractDate(allLines);
      if (purchaseDate != null) entities.add(purchaseDate);

      // Extract aggregate bounds.
      final bounds = _extractBounds(allLines);
      entities.add(bounds);

      // Group lines into rows (by X proximity if rotated, Y otherwise).
      final rows = _groupIntoRows(allLines, rotated: rotated);

      // Extract store name from early rows.
      final store = _extractStore(rows);
      if (store != null) entities.add(store);

      // Process rows into items and total.
      final timestamp = DateTime.now();
      final positions = <RecognizedPosition>[];
      RecognizedTotal? total;
      RecognizedTotalLabel? totalLabel;
      var foundAnyTotal = false;

      for (final row in rows) {
        final rowText = row.map((l) => l.text).join(' ');
        final normalizedRowText =
            ReceiptNormalizer.normalizeFullWidth(rowText);

        // Strip markers (※ etc.) before keyword checks, since these
        // appear as trailing markers on product lines but are also
        // registered as ignore keywords for standalone annotation lines.
        final cleanedRowText = normalizedRowText
            .replaceAll('※', '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        // Stop keywords → stop processing.
        if (_options.stopKeywords.hasMatch(cleanedRowText)) break;

        // Ignore keywords → skip this row (only if the cleaned text
        // still matches, avoiding false positives from embedded markers).
        if (cleanedRowText.isNotEmpty &&
            _options.ignoreKeywords.hasMatch(cleanedRowText)) {
          continue;
        }

        // Skip date line.
        if (purchaseDate != null &&
            row.any((l) => identical(l, purchaseDate.line))) {
          continue;
        }

        // Skip tax rate indicator lines: (8% ...), (10% ...).
        if (_taxRate.hasMatch(cleanedRowText)) continue;

        // Total label detection.
        if (_options.totalLabels.hasMatch(cleanedRowText)) {
          final label = _options.totalLabels.detect(cleanedRowText);
          if (label != null) {
            final labelLine = row.first;
            totalLabel = RecognizedTotalLabel(line: labelLine, value: label);
            entities.add(totalLabel);

            final price = _extractPrice(row);
            if (price != null) {
              total = RecognizedTotal(value: price, line: _priceLine(row));
              entities.add(total);
            }
            foundAnyTotal = true;
            continue;
          }
        }

        // Don't collect items after a total label.
        if (foundAnyTotal) continue;

        // Skip parenthesized label lines: (消費税), (お釣り), (SH), etc.
        // On Japanese receipts, product names never start with "(".
        // Total labels are already handled above.
        if (cleanedRowText.startsWith('(')) continue;

        // Check for discount line first (standalone negative like -100).
        final discountVal = _extractDiscount(row);
        if (discountVal != null) {
          final name = _extractProductName(row);
          final pos = _createPosition(
            name: name,
            row: row,
            price: -discountVal,
            timestamp: timestamp,
          );
          positions.add(pos);
          entities
            ..add(RecognizedAmount(value: -discountVal, line: pos.price.line))
            ..add(RecognizedUnknown(value: name, line: pos.product.line));
          continue;
        }

        // Try to extract a price from this row.
        final price = _extractPrice(row);
        if (price == null) continue;

        // Normal item line.
        final productName = _extractProductName(row);
        if (productName.isEmpty || !_isMeaningfulName(productName)) continue;

        final pos = _createPosition(
          name: productName,
          row: row,
          price: price,
          timestamp: timestamp,
        );
        positions.add(pos);
        entities
          ..add(RecognizedAmount(value: price, line: pos.price.line))
          ..add(RecognizedUnknown(value: productName, line: pos.product.line));
      }

      // Estimate total from item sum when label-based detection failed.
      if (total == null && positions.isNotEmpty) {
        total = _estimateTotal(positions, allLines);
        if (total != null) entities.add(total);
      }

      // Build the receipt.
      final receipt = RecognizedReceipt.empty()
        ..store = store
        ..totalLabel = totalLabel
        ..total = total
        ..purchaseDate = purchaseDate
        ..bounds = bounds
        ..positions.addAll(positions);

      return receipt.copyWith(entities: entities);
    });
  }

  // ─── Rotation Detection ──────────────────────────────────────

  /// Detects if the image is rotated ~90° based on text line aspect ratios.
  ///
  /// Returns true if most sampled lines are taller than wide, indicating
  /// the receipt text is oriented vertically in the image.
  static bool _isRotated(List<TextLine> lines) {
    if (lines.length < 3) return false;
    final sampleSize = lines.length.clamp(0, 10);
    var verticalCount = 0;
    for (var i = 0; i < sampleSize; i++) {
      final bb = lines[i].boundingBox;
      if (bb.height > bb.width * 1.5) verticalCount++;
    }
    return verticalCount > sampleSize / 2;
  }

  // ─── Row Grouping ─────────────────────────────────────────────

  /// Groups [TextLine]s into rows by coordinate proximity.
  ///
  /// For normal images, groups by Y (top) proximity and sorts left-to-right.
  /// For [rotated] images (90°), groups by X (left) proximity and sorts
  /// by Y within each row, since receipt lines run along the X axis.
  static List<List<TextLine>> _groupIntoRows(
    List<TextLine> lines, {
    bool rotated = false,
  }) {
    if (lines.isEmpty) return [];

    final rows = <List<TextLine>>[];
    var currentRow = <TextLine>[lines.first];
    var currentPos = rotated
        ? lines.first.boundingBox.left
        : lines.first.boundingBox.top;

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      final pos =
          rotated ? line.boundingBox.left : line.boundingBox.top;

      // Adaptive tolerance: use the larger of the current row's first
      // line height and the candidate line's height. This prevents
      // small header text from setting a global tolerance too small
      // for larger body text.
      final rowBb = currentRow.first.boundingBox;
      final lineBb = line.boundingBox;
      final rowSize = rotated ? rowBb.width : rowBb.height;
      final lineSize = rotated ? lineBb.width : lineBb.height;
      final maxSize = rowSize > lineSize ? rowSize : lineSize;
      final tolerance = maxSize * 0.6;

      if ((pos - currentPos).abs() <= tolerance) {
        currentRow.add(line);
      } else {
        rows.add(currentRow);
        currentRow = [line];
        currentPos = pos;
      }
    }
    rows.add(currentRow);

    // Sort within each row along the reading axis.
    for (final row in rows) {
      row.sort((a, b) => switch (rotated) {
        true => a.boundingBox.top.compareTo(b.boundingBox.top),
        false => a.boundingBox.left.compareTo(b.boundingBox.left),
      });
    }

    return rows;
  }

  // ─── Price Extraction ─────────────────────────────────────────

  /// Extracts a positive price from a row of [TextLine]s.
  ///
  /// Checks each line for ¥ prefix or 円 suffix patterns first.
  /// Falls back to standalone number patterns for cases where OCR
  /// fails to recognize the ¥ symbol.
  static double? _extractPrice(List<TextLine> row) {
    // First pass: look for explicit ¥/円 patterns.
    for (final line in row) {
      final normalized = ReceiptNormalizer.normalizeFullWidth(line.text)
          .replaceAll('※', '')
          .replaceAll(RegExp(r'[＞>X]'), '')
          .trim();

      // ¥ prefix pattern.
      final prefixMatch = _yenPrefix.firstMatch(normalized);
      if (prefixMatch != null) {
        final priceStr =
            prefixMatch.group(1)!.replaceAll(RegExp(r'[\s,]'), '');
        final price = double.tryParse(priceStr);
        if (price != null && price > 0) return price;
      }

      // 円 suffix pattern.
      final suffixMatch = _yenSuffix.firstMatch(normalized);
      if (suffixMatch != null) {
        final priceStr = suffixMatch.group(1)!.replaceAll(',', '');
        final price = double.tryParse(priceStr);
        if (price != null && price > 0) return price;
      }
    }

    // Second pass: garbled ¥ prefix (OCR reads ¥ as 4).
    // Uses original text (fullwidth-normalized only) to preserve trailing
    // artifacts like % and ) that distinguish garbled ¥ from real prices.
    for (final line in row) {
      final normalized =
          ReceiptNormalizer.normalizeFullWidth(line.text).trim();
      final garbMatch = _yenGarbled.firstMatch(normalized);
      if (garbMatch != null) {
        final priceStr = garbMatch.group(1)!.replaceAll(',', '');
        final price = double.tryParse(priceStr);
        if (price != null && price > 0) return price;
      }
    }

    // Third pass: fallback to standalone number patterns.
    // Only use the last line in the row (rightmost = price column).
    if (row.isNotEmpty) {
      final lastLine = row.last;
      final normalized =
          ReceiptNormalizer.normalizeFullWidth(lastLine.text).trim();
      final m = _standalonePrice.firstMatch(normalized);
      if (m != null) {
        final priceStr = m.group(1)!.replaceAll(',', '');
        final price = double.tryParse(priceStr);
        if (price != null && price >= 10) return price;
      }
    }
    return null;
  }

  /// Extracts a standalone discount value from a row.
  /// Returns the absolute value (caller negates it).
  static double? _extractDiscount(List<TextLine> row) {
    for (final line in row) {
      final text = ReceiptNormalizer.normalizeFullWidth(line.text).trim();
      final m = _discount.firstMatch(text);
      if (m != null) {
        return double.tryParse(m.group(1)!.replaceAll(',', ''));
      }
    }
    return null;
  }

  // ─── Product Name Extraction ──────────────────────────────────

  /// Extracts a product name from a row by excluding price-matching lines.
  static String _extractProductName(List<TextLine> row) {
    final names = <String>[];
    for (final line in row) {
      final text = ReceiptNormalizer.normalizeFullWidth(line.text).trim();

      // Skip lines that are purely a price pattern.
      if (_isPriceLine(text)) continue;

      // Skip standalone discount lines.
      if (_discount.hasMatch(text)) continue;

      // If the line embeds a price, remove the price portion.
      final cleaned = _removePriceFromText(text);
      if (cleaned.isNotEmpty) names.add(cleaned);
    }
    return names.join(' ').trim();
  }

  /// Common OCR artifacts adjacent to prices on Japanese receipts.
  /// ※ → %, ), X, >, * etc. when garbled by ML Kit.
  static final RegExp _priceArtifacts = RegExp(r'^[※＞>%\)\*X\s]*$');

  /// Returns true if the entire [text] is a price pattern.
  static bool _isPriceLine(String text) {
    final stripped = text
        .replaceAll('※', '')
        .replaceAll(RegExp(r'[＞>X]'), '')
        .trim();

    final prefixMatch = _yenPrefix.firstMatch(stripped);
    if (prefixMatch != null) {
      final remainder = stripped.replaceFirst(_yenPrefix, '').trim();
      return remainder.isEmpty || _priceArtifacts.hasMatch(remainder);
    }

    final suffixMatch = _yenSuffix.firstMatch(stripped);
    if (suffixMatch != null) {
      final remainder = stripped.replaceFirst(_yenSuffix, '').trim();
      return remainder.isEmpty || _priceArtifacts.hasMatch(remainder);
    }

    // Standalone number pattern (OCR missed ¥ symbol).
    if (_standalonePrice.hasMatch(stripped)) return true;

    return false;
  }

  /// Removes embedded price patterns from [text] and returns the remainder.
  static String _removePriceFromText(String text) {
    var result = text;
    // Remove ¥-prefixed amounts.
    result = result.replaceAll(_yenPrefix, '');
    // Remove 円-suffixed amounts.
    result = result.replaceAll(_yenSuffix, '');
    // Remove standalone price patterns.
    result = result.replaceAll(_standalonePrice, '');
    // Clean up price-adjacent artifacts and extra whitespace.
    result = result
        .replaceAll('※', '')
        .replaceAll(RegExp(r'[＞>%\)\*X]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return result;
  }

  // ─── Position Factory ─────────────────────────────────────────

  /// Creates a [RecognizedPosition] from [row] with mutually linked
  /// product/price entities.
  static RecognizedPosition _createPosition({
    required String name,
    required List<TextLine> row,
    required double price,
    required DateTime timestamp,
  }) {
    final product = RecognizedProduct(
      value: name,
      line: _productLine(row),
      options: _options,
    );
    final recognizedPrice = RecognizedPrice(
      line: _priceLine(row),
      value: price,
    );
    final position = RecognizedPosition(
      product: product,
      price: recognizedPrice,
      timestamp: timestamp,
      operation: Operation.none,
    );
    product.position = position;
    recognizedPrice.position = position;
    return position;
  }

  /// Returns true if [name] has enough meaningful characters to be a
  /// product name. CJK names are always accepted; ASCII-only names
  /// need 3+ non-punctuation chars to filter garbled OCR labels.
  static bool _isMeaningfulName(String name) {
    final meaningful = name.replaceAll(
      RegExp('[\\d\\s()|.,*`°#@\\-\'"\\\\]'),
      '',
    );
    final hasCjk = RegExp('[\u3000-\u9fff\uf900-\ufaff]')
        .hasMatch(meaningful);
    return hasCjk || meaningful.length >= 3;
  }

  // ─── Total Estimation ───────────────────────────────────────────

  /// Estimates total from item sum when label-based detection failed.
  /// Searches [allLines] for a ¥-prefixed or standalone price matching
  /// the sum of [positions], falls back to the last position's price line.
  static RecognizedTotal? _estimateTotal(
    List<RecognizedPosition> positions,
    List<TextLine> allLines,
  ) {
    final expected = positions.fold<double>(
      0,
      (sum, p) => sum + p.price.value,
    );
    if (expected <= 0) return null;

    final totalLine = _findLineByAmount(allLines, expected);
    return RecognizedTotal(
      value: expected,
      line: totalLine ?? positions.last.price.line,
    );
  }

  /// Finds a [TextLine] whose parsed amount equals [amount].
  /// Checks ¥-prefix first, then standalone price pattern.
  static TextLine? _findLineByAmount(
    List<TextLine> lines,
    double amount,
  ) {
    for (final line in lines) {
      final text =
          ReceiptNormalizer.normalizeFullWidth(line.text).trim();
      final m = _yenPrefix.firstMatch(text);
      if (m != null) {
        final v = double.tryParse(
          m.group(1)!.replaceAll(RegExp(r'[\s,]'), ''),
        );
        if (v == amount) return line;
      }
    }
    for (final line in lines) {
      final text =
          ReceiptNormalizer.normalizeFullWidth(line.text).trim();
      final m = _standalonePrice.firstMatch(text);
      if (m != null) {
        final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
        if (v == amount) return line;
      }
    }
    return null;
  }

  // ─── Line Helpers ─────────────────────────────────────────────

  /// Returns the first line in [row] that does NOT match a price pattern,
  /// or falls back to the first line.
  static TextLine _productLine(List<TextLine> row) {
    for (final line in row) {
      final text = ReceiptNormalizer.normalizeFullWidth(line.text).trim();
      if (!_isPriceLine(text) && !_discount.hasMatch(text)) return line;
    }
    return row.first;
  }

  /// Returns the first line in [row] that matches a price pattern,
  /// or falls back to the last line (rightmost = likely price column).
  static TextLine _priceLine(List<TextLine> row) {
    for (final line in row) {
      final text = ReceiptNormalizer.normalizeFullWidth(line.text).trim();
      if (_isPriceLine(text)) return line;
    }
    return row.last;
  }

  // ─── Store Detection ──────────────────────────────────────────

  /// Matches phone number patterns common in receipt headers.
  static final RegExp _phoneNumber = RegExp(
    r'\d{2,4}-\d{3,4}-\d{3,4}',
  );

  /// Attempts to detect a store name from the first few rows.
  /// Only checks rows before any price-containing row.
  /// Falls back to the first qualifying text row (3+ chars, not a phone
  /// number or pure digits) when dictionary matching fails.
  static RecognizedStore? _extractStore(List<List<TextLine>> rows) {
    for (final row in rows) {
      final rowText = row.map((l) => l.text).join(' ');
      final normalized = ReceiptNormalizer.normalizeFullWidth(rowText);

      // Stop looking once we encounter a price.
      if (_extractPrice(row) != null) break;

      final storeName = _options.storeNames.detect(normalized);
      if (storeName != null) {
        return RecognizedStore(line: row.first, value: storeName);
      }
    }

    // Fallback: first qualifying text row before any price row.
    for (final row in rows) {
      final rowText = row.map((l) => l.text).join(' ');
      final normalized =
          ReceiptNormalizer.normalizeFullWidth(rowText).trim();
      if (_extractPrice(row) != null) break;
      if (normalized.length < 3) continue;
      if (_phoneNumber.hasMatch(normalized)) continue;
      if (RegExp(r'^\d+$').hasMatch(normalized)) continue;
      return RecognizedStore(line: row.first, value: normalized);
    }
    return null;
  }

  // ─── Date Extraction ──────────────────────────────────────────

  /// Japanese era date: 令和7年1月15日
  static final RegExp _dateJapaneseEra = RegExp(
    r'((令和|平成|昭和|大正|明治)\s*\d{1,2}\s*年\s*\d{1,2}\s*月\s*\d{1,2}\s*日)',
  );

  /// Kanji date: 2025年1月15日
  static final RegExp _dateKanji = RegExp(
    r'(\d{4}\s*年\s*\d{1,2}\s*月\s*\d{1,2}\s*日)',
  );

  /// Numeric date: 2025/01/15 or 2025-01-15
  static final RegExp _dateNumeric = RegExp(
    r'(\d{4})\s*[/\-]\s*(\d{1,2})\s*[/\-]\s*(\d{1,2})',
  );

  /// Garbled date: "20264# 2A 8A(A)..." → 2026/2/8.
  /// OCR garbles 年/月/日 kanji into random characters, but digits survive.
  static final RegExp _dateGarbled = RegExp(
    r'(20\d{2})\d?\D{1,3}(\d{1,2})\D{1,3}(\d{1,2})\D',
  );

  /// Extracts a purchase date from all [lines].
  /// Tries Japanese era → Kanji → numeric patterns in priority order.
  static RecognizedPurchaseDate? _extractDate(List<TextLine> lines) {
    for (final line in lines) {
      final text = ReceiptNormalizer.normalizeFullWidth(line.text);

      // Japanese era date.
      final eraMatch = _dateJapaneseEra.firstMatch(text);
      if (eraMatch != null) {
        final dt = ReceiptFormatter.parseJapaneseEraDate(eraMatch.group(1)!);
        if (dt != null) {
          return RecognizedPurchaseDate(value: dt, line: line);
        }
      }

      // Kanji date.
      final kanjiMatch = _dateKanji.firstMatch(text);
      if (kanjiMatch != null) {
        final dt = ReceiptFormatter.parseKanjiDate(kanjiMatch.group(1)!);
        if (dt != null) {
          return RecognizedPurchaseDate(value: dt, line: line);
        }
      }

      // Numeric date.
      final numMatch = _dateNumeric.firstMatch(text);
      if (numMatch != null) {
        final y = int.tryParse(numMatch.group(1)!);
        final m = int.tryParse(numMatch.group(2)!);
        final d = int.tryParse(numMatch.group(3)!);
        if (y != null &&
            y > 2000 &&
            m != null &&
            m >= 1 &&
            m <= 12 &&
            d != null &&
            d >= 1 &&
            d <= 31) {
          return RecognizedPurchaseDate(
            value: DateTime.utc(y, m, d),
            line: line,
          );
        }
      }
    }

    // Fallback: garbled kanji date (年月日 → random chars, digits survive).
    for (final line in lines) {
      final text = ReceiptNormalizer.normalizeFullWidth(line.text);
      final garbMatch = _dateGarbled.firstMatch(text);
      if (garbMatch != null) {
        final y = int.tryParse(garbMatch.group(1)!);
        final m = int.tryParse(garbMatch.group(2)!);
        final d = int.tryParse(garbMatch.group(3)!);
        if (y != null &&
            y >= 2020 &&
            y <= 2030 &&
            m != null &&
            m >= 1 &&
            m <= 12 &&
            d != null &&
            d >= 1 &&
            d <= 31) {
          return RecognizedPurchaseDate(
            value: DateTime.utc(y, m, d),
            line: line,
          );
        }
      }
    }
    return null;
  }

  // ─── Bounds Extraction ────────────────────────────────────────

  /// Creates a [RecognizedBounds] entity from the aggregate bounding box.
  static RecognizedBounds _extractBounds(List<TextLine> lines) {
    var rect = Rect.zero;
    if (lines.isNotEmpty) {
      double minX = lines.first.boundingBox.left;
      double maxX = lines.first.boundingBox.right;
      double minY = lines.first.boundingBox.top;
      double maxY = lines.first.boundingBox.bottom;
      for (var i = 1; i < lines.length; i++) {
        final bb = lines[i].boundingBox;
        if (bb.left < minX) minX = bb.left;
        if (bb.right > maxX) maxX = bb.right;
        if (bb.top < minY) minY = bb.top;
        if (bb.bottom > maxY) maxY = bb.bottom;
      }
      rect = Rect.fromLTRB(minX, minY, maxX, maxY);
    }
    final line = ReceiptTextLine(boundingBox: rect, angle: 0);
    return RecognizedBounds(line: line, value: rect);
  }
}
