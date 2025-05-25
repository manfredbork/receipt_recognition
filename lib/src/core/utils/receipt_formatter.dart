import 'package:intl/intl.dart';

/// Utility class for formatting and parsing monetary values
/// in a locale-aware way for receipt data.
final class ReceiptFormatter {
  /// Formats a number to a localized decimal string with 2 decimal places.
  ///
  /// Example: `2.5` → `"2.50"` (in en_US) or `"2,50"` (in de_DE)
  static String format(num value) => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).format(value);

  /// Parses a localized decimal string back into a numeric value.
  ///
  /// Example: `"2,50"` → `2.5`
  static num parse(String value) => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).parse(value);
}
