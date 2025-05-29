import 'package:intl/intl.dart';

/// Utility for formatting and parsing receipt values consistently.
///
/// Provides methods for handling monetary amounts and normalizing text
/// to ensure consistent representation across the application.
final class ReceiptFormatter {
  static String format(num value) => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).format(value);

  static num parse(String value) => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).parse(value);

  static String trim(String value) {
    return value.replaceAllMapped(
      RegExp(r'(\S*)\s*([,.])\s*(\S*)'),
      (match) => '${match[1]}${match[2]}${match[3]}',
    );
  }
}
