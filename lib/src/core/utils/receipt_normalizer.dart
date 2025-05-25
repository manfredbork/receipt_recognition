/// A utility class for cleaning and formatting receipt strings.
///
/// Methods include fixing decimal separators and trimming trailing unnecessary text.
final class ReceiptNormalizer {
  /// Applies all normalization rules: fixes decimals and trims trailing content.
  ///
  /// - Example: `"Coke 1.99$ x 3"` → `"Coke"`
  static String normalize(String value) {
    final normalizedCommas = normalizeCommas(value);
    final normalizedTail = normalizeTail(normalizedCommas);
    return normalizedTail;
  }

  /// Fixes comma/decimal formatting in numbers within the string.
  ///
  /// - Example: `"1 , 99"` → `"1,99"`
  static String normalizeCommas(String value) {
    return value.replaceAllMapped(
      RegExp(r'(.)\s*([,.])\s*(.)'),
      (match) => '${match[1]}${match[2]}${match[3]}',
    );
  }

  /// Trims trailing numbers, prices, or unnecessary text.
  ///
  /// - Example: `"Coke 1.99$ x 3"` → `"Coke"`
  static String normalizeTail(String value) {
    return value.replaceAllMapped(
      RegExp(r'(.*)(-?\s*\d+\s*[.,]\s*\d{2})(.*)'),
      (match) => '${match[1]}',
    );
  }
}
