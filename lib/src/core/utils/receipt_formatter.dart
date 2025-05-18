import 'package:intl/intl.dart';

final class ReceiptFormatter {
  static String format(num value) => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).format(value);

  static num parse(String value) => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).parse(value);

  static String normalizeCommas(String value) {
    return value.replaceAllMapped(
      RegExp(r'(\d)\s*([,.])\s*(\d)'),
          (match) => '${match[1]}${match[2]}${match[3]}',
    );
  }
}
