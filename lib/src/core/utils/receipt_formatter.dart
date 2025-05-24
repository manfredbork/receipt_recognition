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

  /// Normalizes a string by applying all normalization rules sequentially.
  ///
  /// - Replaces commas and spaces around decimal points with standard formats.
  /// - Removes unnecessary trailing content.
  ///
  /// Example:
  ///   Input: `"1. 99 extra"`
  ///   Output: `"1.99"`
  static String normalize(String value) {
    return normalizeTail(normalizeCommas(value));
  }

  /// Normalizes comma usage in strings for consistent decimal representation.
  ///
  /// - Example:
  ///   Input: `"1 , 99"`
  ///   Output: `"1,99"`
  static String normalizeCommas(String value) {
    return value.replaceAllMapped(
      RegExp(r'(\d)\s*([,.])\s*(\d)'),
      (match) => '${match[1]}${match[2]}${match[3]}',
    );
  }

  /// Removes trailing unnecessary content from a value string after normalization.
  ///
  /// - Example:
  ///   Input: `"1.99 extra text"`
  ///   Output: `"1.99"`
  static String normalizeTail(String value) {
    return value.replaceAllMapped(
      RegExp(r'(.*)(-?\s*\d+\s*[.,]\s*\d{2})(.*)'),
      (match) => '${match[1]}',
    );
  }
}
