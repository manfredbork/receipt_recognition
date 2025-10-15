/// Contains reusable regex patterns for receipt parsing.
abstract class ReceiptPatterns {
  /// Pattern to match monetary values (e.g., 1,99 or -5.00).
  static final RegExp amount = RegExp(
    r'[-−–—]?\s*\d+\s*[.,‚،٫·]\s*\d{2}(?!\d)',
  );

  /// Pattern to match strings likely to be product descriptions.
  static final RegExp unknown = RegExp(r'[\D\S]{4,}');

  /// Pattern to filter out suspicious or metadata-like product names.
  static final RegExp suspiciousProductName = RegExp(
    r'\bx\s?\d+',
    caseSensitive: false,
  );

  /// Matches numeric dates in the format "01.09.2025" or "1/9/25" with a consistent separator.
  static final RegExp dateDayMonthYearNumeric = RegExp(
    r'\b(\d{1,2}([./-])\d{1,2}\2\d{2,4})\b',
  );

  /// Matches numeric dates in the format "2025-09-01" or "2025/9/1" with a consistent separator.
  static final RegExp dateYearMonthDayNumeric = RegExp(
    r'\b(\d{4}([./-])\d{1,2}\2\d{1,2})\b',
  );

  /// Matches English dates like "1.September 25", "1. September 2025", or "1 September 2025".
  static final RegExp dateDayMonthYearEn = RegExp(
    r'\b(\d{1,2}(?:\.\s*|\s+)(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|'
    r'Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|'
    r'Dec(?:ember)?)\.?,?\s+\d{2,4})\b',
    caseSensitive: false,
  );

  /// Matches U.S. English dates like "September 1, 2025", "Sep 1 25", or "Sep.1,2025".
  static final RegExp dateMonthDayYearEn = RegExp(
    r'\b((Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|'
    r'Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|'
    r'Dec(?:ember)?)\.?\s*\d{1,2},?\s*\d{2,4})\b',
    caseSensitive: false,
  );

  /// Matches German dates like "1.September 25", "1. September 2025", or "1 September 2025".
  static final RegExp dateDayMonthYearDe = RegExp(
    r'\b(\d{1,2}(?:\.\s*|\s+)(Jan(?:uar)?|Feb(?:ruar)?|Mär(?:z)?|Apr(?:il)?|Mai|Jun(?:i)?|'
    r'Jul(?:i)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Okt(?:ober)?|Nov(?:ember)?|'
    r'Dez(?:ember)?)\.?,?\s+\d{2,4})\b',
    caseSensitive: false,
  );
}
