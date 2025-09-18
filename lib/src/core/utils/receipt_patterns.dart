/// Contains reusable regex patterns for receipt parsing.
abstract class ReceiptPatterns {
  /// Pattern to match known supermarket or store names.
  static final RegExp company = RegExp(
    r'(Aldi|Rewe|Edeka|Penny|Lidl|Kaufland|Netto|Akzenta)',
    caseSensitive: false,
  );

  /// Pattern to detect common total sum labels on receipts.
  static final RegExp sumLabel = RegExp(
    r'(Zu zahlen|Gesamt|Summe|Total)',
    caseSensitive: false,
  );

  /// Pattern indicating where parsing should stop (e.g., refunds or change lines).
  static final RegExp stopKeywords = RegExp(
    r'(Geg.|Rückgeld|Bar)',
    caseSensitive: false,
  );

  /// Pattern to identify ignorable keywords not related to products.
  static final RegExp ignoreKeywords = RegExp(
    r'(E-Bon|Coupon|Eingabe|Posten|Stk|kg|Subtotal)',
    caseSensitive: false,
  );

  /// Pattern to match invalid number formats (e.g., 1.234,00).
  static final RegExp invalidAmount = RegExp(r'\d+\s*[.,]\s*\d{3,}');

  /// Pattern to match monetary values (e.g., 1,99 or -5.00).
  static final RegExp amount = RegExp(r'-?\s*\d+\s*[.,]\s*\d{2}');

  /// Pattern to match strings likely to be product descriptions.
  static final RegExp unknown = RegExp(r'[\D\S]{4,}');

  /// Pattern to exclude lines with likely metadata or quantity info.
  static final RegExp likelyNotProduct = RegExp(
    r'(\bx\s?\d+)|(\d+[,.]\d{2}/\w+)|(\d+\s*(Pcs|Stk|kg|g))|(^\s*\d+[,.]\d{2}\s*$)',
    caseSensitive: false,
  );

  /// Pattern to detect unit prices like "2,99/kg" or "0,89/100g".
  static final RegExp unitPrice = RegExp(
    r'\d+[,.]\d{2}/\w+',
    caseSensitive: false,
  );

  /// Pattern to detect quantity-like words (e.g. "2 Pcs", "0,3kg").
  static final RegExp quantityMetadata = RegExp(
    r'\d+\s*(Pcs|Stk|kg|g)',
    caseSensitive: false,
  );

  /// Pattern to detect price-like numbers not paired with labels.
  static final RegExp standalonePrice = RegExp(r'^\s*\d+[,.]\d{2}\s*$');

  /// Pattern to match integers that look like product metadata (e.g., 1, 189).
  static final RegExp standaloneInteger = RegExp(r'^\s*\d+\s*$');

  /// Price-like patterns that might appear on the left but are not product names.
  static final RegExp misleadingPriceLikeLeft = RegExp(
    r'^\s*-?\d+\s*[.,]\s*\d{2}\s*([€$¢£]?\s*(x\s*\d*)?)?$',
    caseSensitive: false,
  );

  /// Pattern to filter out suspicious or metadata-like product names.
  static final RegExp suspiciousProductName = RegExp(
    r'\bx\s?\d+',
    caseSensitive: false,
  );
}
