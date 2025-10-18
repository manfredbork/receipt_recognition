import 'package:intl/intl.dart';

/// Utility for locale-aware number formatting and robust parsing/normalization of receipt text and dates.
final class ReceiptFormatter {
  /// Collapses whitespace around comma/dot separators: "12 , 34" -> "12,34".
  static final RegExp _reCommaDotSpaces = RegExp(r'\s*([,.])\s*');

  /// Matches any Unicode dash/minus-like character to normalize as ASCII '-'.
  static final RegExp _reAnyDash = RegExp(r'[‐-‒–—−-]');

  /// Matches decimal marks observed on receipts (commas, Arabic marks, middle-dot variants).
  static final RegExp _reDecimalMarks = RegExp(r'[.,‚،٫·]');

  /// Collapses any whitespace to a single space.
  static final RegExp _reWs = RegExp(r'\s+');

  /// Matches characters that are not digits, '.' or '-'.
  static final RegExp _reNotNum = RegExp(r'[^0-9.\-]');

  /// Detects trailing minus patterns like "12,34-".
  static final RegExp _reTrailingMinus = RegExp(r'^\s*(.+?)\s*-\s*$');

  /// Detects parentheses negatives like "(12,34)".
  static final RegExp _reParenNegative = RegExp(r'^\s*\(\s*(.+?)\s*\)\s*$');

  /// Cache of NumberFormat by locale for performance.
  static final Map<String?, NumberFormat> _fmtCache = {};

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

  /// Returns a cached `NumberFormat` for `Intl.defaultLocale` with exactly two fraction digits.
  static NumberFormat _formatter() =>
      _fmtCache.putIfAbsent(Intl.defaultLocale, () {
        return NumberFormat.decimalPatternDigits(
          locale: Intl.defaultLocale,
          decimalDigits: 2,
        );
      });

  /// Formats [value] using the current locale with two decimal places (via `NumberFormat`).
  static String format(num value) => _formatter().format(value);

  /// Parses a localized decimal string using the current locale; throws on invalid input.
  static num parse(String value) => _formatter().parse(value);

  /// Trims [value] and collapses spaces around commas/dots (e.g. `12 , 34` → `12,34`).
  static String trim(String value) {
    return value.replaceAllMapped(_reCommaDotSpaces, (m) => m.group(1)!).trim();
  }

  /// Normalizes a raw amount string to a plain ASCII decimal:
  /// converts dash variants and negatives, unifies decimal marks to `.`,
  /// removes thousand separators and non-numeric chars, returns e.g. `-1234.56`.
  static String normalizeAmount(String amount) {
    if (amount.isEmpty) return amount;

    String s = amount.replaceAll('\u00A0', ' ').replaceAll(_reWs, ' ').trim();

    final paren = _reParenNegative.firstMatch(s);
    bool negative = false;
    if (paren != null) {
      s = paren.group(1)!;
      negative = true;
    }

    s = s.replaceAll(_reAnyDash, '-');

    final trail = _reTrailingMinus.firstMatch(s);
    if (trail != null) {
      s = '-${trail.group(1)!}';
    }

    s = s.replaceAll(_reDecimalMarks, '.');

    s = s.replaceAll(' ', '');

    s = s.replaceAll(_reNotNum, '');

    final lastDot = s.lastIndexOf('.');
    if (lastDot != -1) {
      final before = s.substring(0, lastDot).replaceAll('.', '');
      final after = s.substring(lastDot + 1);
      s = '$before.$after';
    }

    if (s.contains('-')) {
      s = s.replaceAll('-', '');
      s = '-$s';
    }

    if (negative && !s.startsWith('-')) s = '-$s';

    return s;
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
