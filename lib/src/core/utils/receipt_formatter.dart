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
}
