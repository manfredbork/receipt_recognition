/// Built-in default options as a JSON-like map (can be persisted/overridden).
/// Canonicals map to themselves by default. Adjust values if you want alias→canonical.
const Map<String, dynamic> kReceiptDefaultOptions = {
  'storeNames': {
    'Aldi': 'Aldi',
    'Rewe': 'Rewe',
    'Edeka': 'Edeka',
    'Penny': 'Penny',
    'Lidl': 'Lidl',
    'Kaufland': 'Kaufland',
    'Netto': 'Netto',
    'Akzenta': 'Akzenta',
  },
  'totalLabels': {
    'Zu zahlen': 'Zu zahlen',
    'Gesamt': 'Gesamt',
    'Summe': 'Summe',
    'Total': 'Total',
    'Subtotal': 'Subtotal',
  },
  'ignoreKeywords': ['E-Bon', 'Coupon', 'Eingabe', 'Posten'],
  'stopKeywords': ['Geg.', 'Rückgeld', 'Bar', 'Change'],
  'discountKeywords': ['Rabatt', 'Coupon', 'Discount'],
  'depositKeywords': ['Leerg.', 'Leergut', 'Einweg', 'Pfand', 'Deposit'],
  'tuning': {
    'optimizerTotalTolerance': 0.009,
    'optimizerEwmaAlpha': 0.5,
    'optimizerVerticalTolerance': 50,
    'optimizerLoopThreshold': 10,
    'optimizerMaxCacheSize': 12,
    'optimizerConfidenceThreshold': 90,
    'optimizerStabilityThreshold': 40,
    'optimizerAboveCountDecayThreshold': 50,
    'optimizerProductWeight': 1,
    'optimizerPriceWeight': 1,
    'optimizerUnrecognizedProductName': 'Unrecognized items',
  },
};
