/// Contains reusable regex patterns for receipt parsing.
abstract class ReceiptPatterns {
  /// Pattern to match known supermarket or store names.
  static final RegExp companyNames = RegExp(
    r'(Aldi|Rewe|Edeka|Penny|Lidl|Kaufland|Netto|Akzenta)',
    caseSensitive: false,
  );

  /// Pattern to detect common total sum labels on receipts.
  static final RegExp sumLabels = RegExp(
    r'(Zu zahlen|Gesamt|Summe|Total)',
    caseSensitive: false,
  );

  /// Pattern to identify ignorable keywords not related to products.
  static final RegExp ignoreKeywords = RegExp(
    r'(E-Bon|Coupon|Eingabe|Posten|Stk|kg|Subtotal)',
    caseSensitive: false,
  );

  /// Pattern to match monetary values (e.g., 1,99 or -5.00).
  static final RegExp amount = RegExp(r'-?\s*\d+\s*[.,]\s*\d{2}');

  /// Pattern to match strings likely to be product descriptions.
  static final RegExp unknown = RegExp(r'[\D\S]{4,}');

  /// Pattern to filter out suspicious or metadata-like product names.
  static final RegExp suspiciousProductName = RegExp(
    r'\bx\s?\d+',
    caseSensitive: false,
  );
}
