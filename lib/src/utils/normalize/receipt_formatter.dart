import 'package:intl/intl.dart';

/// Utility for formatting and parsing receipt values consistently.
///
/// Provides methods for handling monetary amounts and normalizing text
/// to ensure consistent representation across the application.
final class ReceiptFormatter {
  /// Formats a numeric value as a localized decimal with 2 digits.
  static String format(num value) => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).format(value);

  /// Parses a localized decimal string into a numeric value.
  static num parse(String value) => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).parse(value);

  /// Removes extra spaces around commas or dots in [value].
  static String trim(String value) {
    return value.replaceAllMapped(
      RegExp(r'(\S*)\s*([,.])\s*(\S*)'),
      (match) => '${match[1]}${match[2]}${match[3]}',
    );
  }

  /// Normalizes a raw amount string: trims, unifies dashes to '-', decimals to '.', and strips non [0-9.-] chars.
  static String normalizeAmount(String amount) => trim(amount)
      .replaceAll(RegExp(r'[-−–—]'), '-')
      .replaceAll(RegExp(r'[.,‚،٫·]'), '.')
      .replaceAll(RegExp(r'[^\d.-]'), '');

  /// Parses a date string (EN/DE, numeric/textual) into a [DateTime], or null if unsupported.
  static DateTime? parseDate(String raw) {
    final s = raw
        .trim()
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[–—−]'), '-')
        .replaceAll(RegExp(r'(\d{1,2})\.\s*(?=[A-Za-zÄÖÜäöüß])'), r'$1. ')
        .replaceAll(RegExp(r'\bSept\b\.?', caseSensitive: false), 'Sep');

    final candidates = <({String p, String? locale})>[
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

    final isoIsh = s.replaceAll('/', '-').replaceAll('.', '-');
    final isoTry = DateTime.tryParse(isoIsh);
    if (isoTry != null) return isoTry;

    for (final c in candidates) {
      try {
        final df = DateFormat(c.p, c.locale);
        return df.parseLoose(s);
      } catch (_) {}
    }
    return null;
  }
}
