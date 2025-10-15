import 'package:intl/intl.dart';

/// Utility for formatting and parsing receipt values consistently.
///
/// Provides methods for handling monetary amounts and normalizing text
/// to ensure consistent representation across the application.
final class ReceiptFormatter {
  /// Collapses whitespace around comma/dot separators: "12 , 34" -> "12,34".
  static final RegExp _reCommaDotSpaces = RegExp(r'\s*([,.])\s*');

  /// Matches any Unicode dash/minus-like character to normalize as ASCII '-'.
  /// Includes hyphen, non-breaking hyphen, en/em dashes, figure dash, minus sign.
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

  /// Returns a cached localized NumberFormat with two decimal digits.
  static NumberFormat _formatter() =>
      _fmtCache.putIfAbsent(Intl.defaultLocale, () {
        return NumberFormat.decimalPatternDigits(
          locale: Intl.defaultLocale,
          decimalDigits: 2,
        );
      });

  /// Formats a numeric value as a localized decimal with 2 digits.
  static String format(num value) => _formatter().format(value);

  /// Parses a localized decimal string into a numeric value.
  static num parse(String value) => _formatter().parse(value);

  /// Removes extra spaces around commas or dots in [value] and trims ends.
  static String trim(String value) {
    return value.replaceAllMapped(_reCommaDotSpaces, (m) => m.group(1)!).trim();
  }

  /// Normalizes a raw amount string:
  /// - Unifies dash variants to '-', handles trailing minus and ( ... ) negatives.
  /// - Unifies decimal marks to '.'.
  /// - Removes thousand separators (keeps only the last '.').
  /// - Strips non [0-9.-] chars and collapses whitespace.
  static String normalizeAmount(String amount) {
    if (amount.isEmpty) return amount;

    var s = amount.replaceAll('\u00A0', ' ').replaceAll(_reWs, ' ').trim();

    final paren = _reParenNegative.firstMatch(s);
    var negative = false;
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

  /// Parses a date string (EN/DE, numeric/textual) into a [DateTime], or null if unsupported.
  static DateTime? parseDate(String raw) {
    if (raw.trim().isEmpty) return null;

    var s = raw
        .trim()
        .replaceAll('\u00A0', ' ')
        .replaceAll(_reWs, ' ')
        .replaceAll(RegExp(r'[–—−]'), '-')
        .replaceAll(RegExp(r'(\d{1,2})\.\s*(?=[A-Za-zÄÖÜäöüß])'), r'$1. ')
        .replaceAll(RegExp(r'\bSept\b\.?', caseSensitive: false), 'Sep');

    final isoIsh = s.replaceAll('/', '-').replaceAll('.', '-');
    final isoTry = DateTime.tryParse(isoIsh);
    if (isoTry != null) return isoTry;

    for (final df in _dateFormats) {
      try {
        return df.parseLoose(s);
      } catch (_) {}
    }
    return null;
  }

  /// Cached list of DateFormats tried for textual/numeric EN/DE dates.
  static final List<DateFormat> _dateFormats =
      (() {
        const specs = <({String p, String? locale})>[
          (p: 'dd.MM.yyyy', locale: null),
          (p: 'd.M.yyyy', locale: null),
          (p: 'dd.MM.yy', locale: null),
          (p: 'd.M.yy', locale: null),
          (p: 'dd-MM-yyyy', locale: null),
          (p: 'd-M-yyyy', locale: null),
          (p: 'dd/MM/yyyy', locale: null),
          (p: 'd/M/yyyy', locale: null),
          (p: 'yyyy-MM-dd', locale: null),
          (p: 'yyyy/M/d', locale: null),
          (p: 'yyyy.MM.dd', locale: null),
          (p: 'd. MMMM yyyy', locale: 'en'),
          (p: 'd MMMM yyyy', locale: 'en'),
          (p: 'd. MMM yyyy', locale: 'en'),
          (p: 'd MMM yyyy', locale: 'en'),
          (p: 'MMMM d, yyyy', locale: 'en'),
          (p: 'MMM d, yyyy', locale: 'en'),
          (p: 'MMMM d yyyy', locale: 'en'),
          (p: 'MMM d yyyy', locale: 'en'),
          (p: 'd. MMMM yyyy', locale: 'de'),
          (p: 'd MMMM yyyy', locale: 'de'),
          (p: 'd. MMM yyyy', locale: 'de'),
          (p: 'd MMM yyyy', locale: 'de'),
          (p: 'd. MMM yy', locale: 'de'),
          (p: 'd MMM yy', locale: 'de'),
          (p: 'd. MMM yy', locale: 'en'),
          (p: 'd MMM yy', locale: 'en'),
        ];

        return [for (final s in specs) DateFormat(s.p, s.locale)];
      })();
}
