import 'package:intl/intl.dart';

/// Utility for locale-aware number formatting and robust parsing/normalization of receipt text and dates.
final class ReceiptFormatter {
  /// Collapses whitespace around comma/dot separators: "12 , 34" -> "12,34".
  static final RegExp _reCommaDotSpaces = RegExp(r'(\d)\s*([,.])\s*(\d)');

  /// Detects amount prefix to convert into postfix text.
  static final RegExp _amountPostfixText = RegExp(
    r'[-−–—]?\s*\d+\s*[.,‚،٫·]\s*\d{2}(?!\d)',
  );

  /// Cache of NumberFormat by locale+digits key for performance.
  static final Map<String, NumberFormat> _fmtCache = {};

  /// Maps English and German month names and abbreviations (with umlauts) to numeric month values.
  static const monthMap = {
    'jan': 1,
    'january': 1,
    'januar': 1,
    'feb': 2,
    'february': 2,
    'februar': 2,
    'mar': 3,
    'march': 3,
    'märz': 3,
    'marz': 3,
    'apr': 4,
    'april': 4,
    'may': 5,
    'mai': 5,
    'jun': 6,
    'june': 6,
    'juni': 6,
    'jul': 7,
    'july': 7,
    'juli': 7,
    'aug': 8,
    'august': 8,
    'sep': 9,
    'sept': 9,
    'september': 9,
    'oct': 10,
    'okt': 10,
    'october': 10,
    'oktober': 10,
    'nov': 11,
    'november': 11,
    'dec': 12,
    'dez': 12,
    'december': 12,
    'dezember': 12,
  };

  /// 和暦の元号名→開始西暦年のマッピング
  static const japaneseEraMap = {
    '令和': 2018,
    '平成': 1988,
    '昭和': 1925,
    '大正': 1911,
    '明治': 1867,
  };

  /// Returns a cached `NumberFormat` for the given locale+digits key.
  static NumberFormat _formatter({int decimalDigits = 2}) {
    final key = '${Intl.defaultLocale}_$decimalDigits';
    return _fmtCache.putIfAbsent(key, () {
      return NumberFormat.decimalPatternDigits(
        locale: Intl.defaultLocale,
        decimalDigits: decimalDigits,
      );
    });
  }

  /// Formats [value] using the current locale.
  /// [decimalDigits] defaults to 2 for most currencies, use 0 for JPY.
  static String format(num value, {int decimalDigits = 2}) =>
      _formatter(decimalDigits: decimalDigits).format(value);

  /// Trims [value] and collapses spaces around commas/dots (e.g. `12 , 34` → `12,34`).
  static String trim(String value) {
    return value.trim().replaceAllMapped(
      _reCommaDotSpaces,
      (m) => '${m[1]}${m[2]}${m[3]}',
    );
  }

  /// Removes a leading amount pattern from [text], returning the remainder.
  static String toPostfixText(String text) {
    if (text.isEmpty) return '';
    final m = _amountPostfixText.matchAsPrefix(text.trim());
    if (m == null) return '';
    return text.substring(m.end).trim();
  }

  /// Parses `YYYY-MM-DD` (or mixed separators) into a `DateTime.utc(y,m,d)`; returns null if invalid.
  static DateTime? parseNumericYMD(String token) {
    final parts =
        RegExp(r'\d{1,4}').allMatches(token).map((m) => m.group(0)!).toList();
    if (parts.length < 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    return _ymdUtc(y, m, d);
  }

  /// Parses `DD-MM-YY(YY)` (or mixed separators) into `DateTime.utc`, normalizing 2-digit years to 2000–2099.
  static DateTime? parseNumericDMY(String token) {
    final parts =
        RegExp(r'\d{1,4}').allMatches(token).map((m) => m.group(0)!).toList();
    if (parts.length < 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = _normalizeYear(int.tryParse(parts[2]));
    return _ymdUtc(y, m, d);
  }

  /// Parses day–month-name–year (`1. September 2025`, `1 Sep 25`, EN/DE) into `DateTime.utc`; returns null if invalid.
  static DateTime? parseNameDMY(String token) {
    final re = RegExp(
      r'^\s*(\d{1,2})[.\s\-]+([A-Za-zÄÖÜäöüß.]+)[, ]+(\d{2,4})\s*$',
      caseSensitive: false,
    );
    final m = re.firstMatch(token);
    if (m == null) return null;
    final d = int.tryParse(m.group(1)!);
    final mon = _monthFromName(m.group(2)!);
    final y = _normalizeYear(int.tryParse(m.group(3)!));
    return _ymdUtc(y, mon, d);
  }

  /// Parses month-name–day–year (`September 1, 2025`, `Sep 1 25`) into `DateTime.utc`; returns null if invalid.
  static DateTime? parseNameMDY(String token) {
    final re = RegExp(
      r'^\s*([A-Za-zÄÖÜäöüß.]+)\s*\.?\s*(\d{1,2}),?\s*(\d{2,4})\s*$',
      caseSensitive: false,
    );
    final m = re.firstMatch(token);
    if (m == null) return null;
    final mon = _monthFromName(m.group(1)!);
    final d = int.tryParse(m.group(2)!);
    final y = _normalizeYear(int.tryParse(m.group(3)!));
    return _ymdUtc(y, mon, d);
  }

  /// Normalizes 2-digit years to 2000–2099; returns 4-digit years unchanged; null if invalid.
  static int? _normalizeYear(int? y) {
    if (y == null) return null;
    if (y >= 1000) return y;
    if (y >= 0 && y <= 99) return 2000 + y;
    return null;
  }

  /// Constructs `DateTime.utc(y,m,d)` if the triple is a valid calendar date; otherwise null.
  static DateTime? _ymdUtc(int? y, int? m, int? d) {
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12) return null;
    if (d < 1 || d > 31) return null;
    try {
      return DateTime.utc(y, m, d);
    } catch (_) {
      return null;
    }
  }

  /// Parses `2025年1月15日` into `DateTime.utc`.
  static DateTime? parseKanjiDate(String token) {
    final re = RegExp(r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日');
    final m = re.firstMatch(token);
    if (m == null) return null;
    final y = int.tryParse(m.group(1)!);
    final mon = int.tryParse(m.group(2)!);
    final d = int.tryParse(m.group(3)!);
    return _ymdUtc(y, mon, d);
  }

  /// Parses `令和7年1月15日` into `DateTime.utc` (和暦→西暦変換).
  static DateTime? parseJapaneseEraDate(String token) {
    final re = RegExp(
      r'(令和|平成|昭和|大正|明治)\s*(\d{1,2})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日',
    );
    final m = re.firstMatch(token);
    if (m == null) return null;
    final era = m.group(1)!;
    final eraYear = int.tryParse(m.group(2)!);
    final mon = int.tryParse(m.group(3)!);
    final d = int.tryParse(m.group(4)!);
    if (eraYear == null) return null;
    final baseYear = japaneseEraMap[era];
    if (baseYear == null) return null;
    final y = baseYear + eraYear;
    return _ymdUtc(y, mon, d);
  }

  /// Converts EN/DE month names and abbreviations (with optional dot/umlauts) to a 1–12 month number.
  static int? _monthFromName(String raw) {
    String n = raw.trim().toLowerCase();
    n = n.replaceAll('.', '');

    if (monthMap.containsKey(n)) return monthMap[n];
    if (n.length >= 3) {
      final k = n.substring(0, 3);
      if (monthMap.containsKey(k)) return monthMap[k];
    }
    return null;
  }
}
