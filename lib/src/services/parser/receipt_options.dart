import 'package:receipt_recognition/src/services/parser/index.dart';

/// How user config should interact with built-in defaults.
enum MergePolicy {
  /// Keep defaults and add/override with user config (defaults ∪ user).
  extend,

  /// Ignore defaults completely and use only user config.
  replace,
}

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
  },
  'ignoreKeywords': [
    'E-Bon',
    'Coupon',
    'Eingabe',
    'Posten',
    'Subtotal',
    'Stk x',
    'kg x',
  ],
  'stopKeywords': ['Geg.', 'Rückgeld', 'Bar', 'Change'],
  'foodKeywords': ['B', '2', 'BW'],
  'nonFoodKeywords': ['A', '1', 'AW'],
  'discountKeywords': ['Rabatt', 'Coupon', 'Discount'],
  'depositKeywords': ['Leerg.', 'Leergut', 'Einweg', 'Pfand', 'Deposit'],
};

/// Strongly-typed, user-configurable options for the parser, including
/// factory helpers to build and merge with built-in defaults.
final class ReceiptOptions {
  /// Map of store aliases to canonical names.
  final DetectionMap storeNames;

  /// Map of total labels (e.g., “Total”, “Summe”) to canonical label.
  final DetectionMap totalLabels;

  /// Keywords that should be ignored during parsing.
  final KeywordSet ignoreKeywords;

  /// Keywords that indicate parsing should stop.
  final KeywordSet stopKeywords;

  /// Keywords that classify an item as food.
  final KeywordSet foodKeywords;

  /// Keywords that classify an item as non-food.
  final KeywordSet nonFoodKeywords;

  /// Keywords that indicate discounts.
  final KeywordSet discountKeywords;

  /// Keywords that indicate deposits/returns.
  final KeywordSet depositKeywords;

  /// Creates a new options object with explicit maps/sets.
  ReceiptOptions({
    required this.storeNames,
    required this.totalLabels,
    required this.ignoreKeywords,
    required this.stopKeywords,
    required this.foodKeywords,
    required this.nonFoodKeywords,
    required this.discountKeywords,
    required this.depositKeywords,
  });

  /// Returns a minimal config with all maps/lists empty (no matches).
  factory ReceiptOptions.empty() => ReceiptOptions(
    storeNames: DetectionMap.fromMap(const {}),
    totalLabels: DetectionMap.fromMap(const {}),
    ignoreKeywords: KeywordSet.fromList(const []),
    stopKeywords: KeywordSet.fromList(const []),
    foodKeywords: KeywordSet.fromList(const []),
    nonFoodKeywords: KeywordSet.fromList(const []),
    discountKeywords: KeywordSet.fromList(const []),
    depositKeywords: KeywordSet.fromList(const []),
  );

  /// Builds options from a JSON-like map (e.g., from user config).
  factory ReceiptOptions.fromJsonLike(Map<String, dynamic> json) {
    Map<String, String> pickStrMap(dynamic v) {
      if (v is Map) {
        return Map.fromEntries(
          v.entries
              .where((e) => e.key is String && e.value is String)
              .map((e) => MapEntry(e.key as String, e.value as String)),
        );
      }
      return const {};
    }

    List<String> pickStrList(dynamic v) {
      if (v is List) return v.whereType<String>().toList();
      return const [];
    }

    return ReceiptOptions(
      storeNames: DetectionMap.fromMap(pickStrMap(json['storeNames'])),
      totalLabels: DetectionMap.fromMap(pickStrMap(json['totalLabels'])),
      ignoreKeywords: KeywordSet.fromList(pickStrList(json['ignoreKeywords'])),
      stopKeywords: KeywordSet.fromList(pickStrList(json['stopKeywords'])),
      foodKeywords: KeywordSet.fromList(pickStrList(json['foodKeywords'])),
      nonFoodKeywords: KeywordSet.fromList(
        pickStrList(json['nonFoodKeywords']),
      ),
      discountKeywords: KeywordSet.fromList(
        pickStrList(json['discountKeywords']),
      ),
      depositKeywords: KeywordSet.fromList(
        pickStrList(json['depositKeywords']),
      ),
    );
  }

  /// Serializes options to a JSON-like map.
  Map<String, dynamic> toJsonLike() => {
    'storeNames': storeNames.mapping,
    'totalLabels': totalLabels.mapping,
    'ignoreKeywords': ignoreKeywords.keywords,
    'stopKeywords': stopKeywords.keywords,
    'foodKeywords': foodKeywords.keywords,
    'nonFoodKeywords': nonFoodKeywords.keywords,
    'discountKeywords': discountKeywords.keywords,
    'depositKeywords': depositKeywords.keywords,
  };

  /// Returns options built solely from built-in JSON defaults (no user overrides).
  static ReceiptOptions defaults() =>
      ReceiptOptions.fromJsonLike(kReceiptDefaultOptions);

  /// Builds options using **only** user input (no defaults).
  static ReceiptOptions userOnly(ReceiptOptions? opts) =>
      opts ?? ReceiptOptions.empty();

  /// Builds effective options by merging [opts] with built-in JSON defaults.
  ///
  /// - [MergePolicy.extend]: defaults ∪ user (user wins on duplicates)
  /// - [MergePolicy.replace]: only user (ignore defaults)
  static ReceiptOptions withDefaults(
    ReceiptOptions? opts, {
    MergePolicy storeNames = MergePolicy.extend,
    MergePolicy totalLabels = MergePolicy.extend,
    MergePolicy ignoreKeywords = MergePolicy.extend,
    MergePolicy stopKeywords = MergePolicy.extend,
    MergePolicy foodKeywords = MergePolicy.extend,
    MergePolicy nonFoodKeywords = MergePolicy.extend,
    MergePolicy discountKeywords = MergePolicy.extend,
    MergePolicy depositKeywords = MergePolicy.extend,
  }) {
    final user = opts ?? ReceiptOptions.empty();
    final def = ReceiptOptions.defaults();

    return ReceiptOptions(
      storeNames: _dmMerge(def.storeNames, user.storeNames, storeNames),
      totalLabels: _dmMerge(def.totalLabels, user.totalLabels, totalLabels),
      ignoreKeywords: _ksMerge(
        def.ignoreKeywords,
        user.ignoreKeywords,
        ignoreKeywords,
      ),
      stopKeywords: _ksMerge(def.stopKeywords, user.stopKeywords, stopKeywords),
      foodKeywords: _ksMerge(def.foodKeywords, user.foodKeywords, foodKeywords),
      nonFoodKeywords: _ksMerge(
        def.nonFoodKeywords,
        user.nonFoodKeywords,
        nonFoodKeywords,
      ),
      discountKeywords: _ksMerge(
        def.discountKeywords,
        user.discountKeywords,
        discountKeywords,
      ),
      depositKeywords: _ksMerge(
        def.depositKeywords,
        user.depositKeywords,
        depositKeywords,
      ),
    );
  }

  /// Merges default and user keyword sets according to [p].
  static KeywordSet _ksMerge(
    KeywordSet defaults,
    KeywordSet user,
    MergePolicy p,
  ) {
    if (p == MergePolicy.replace) return user;
    final out = <String>{...defaults.keywords, ...user.keywords};
    return KeywordSet.fromList(out.toList());
  }

  /// Merges default and user detection maps according to [p] (user wins on duplicates).
  static DetectionMap _dmMerge(
    DetectionMap defaults,
    DetectionMap user,
    MergePolicy p,
  ) {
    if (p == MergePolicy.replace) return user;
    final merged = <String, String>{};
    merged.addAll(defaults.mapping);
    merged.addAll(user.mapping);
    return DetectionMap.fromMap(merged);
  }
}

/// A typed wrapper for "label -> canonical" maps with a precompiled regex.
final class DetectionMap {
  /// Precompiled alternation regex matching any label (case-insensitive).
  final RegExp regexp;

  /// Lowercased label→canonical mapping used for lookups.
  final Map<String, String> mapping;

  DetectionMap._(this.regexp, this.mapping);

  /// Builds a case-insensitive mapping and one regex; returns a never-match regex if empty.
  factory DetectionMap.fromMap(Map<String, String> map) {
    if (map.isEmpty) {
      return DetectionMap._(
        RegExp(ReceiptConstants.neverMatchLiteral),
        const {},
      );
    }

    final patterns = <String>[];
    final normalized = <String, String>{};

    for (final e in map.entries) {
      final k = e.key.trim();
      if (k.isEmpty) continue;
      patterns.add(RegExp.escape(k));
      normalized[k.toLowerCase()] = e.value;
    }

    final pattern = '(${patterns.join('|')})';
    return DetectionMap._(
      RegExp(pattern, caseSensitive: false),
      Map.unmodifiable(normalized),
    );
  }

  /// Returns the canonical value if any label in [text] matches, otherwise null.
  String? detect(String text) {
    final m = regexp.stringMatch(text);
    if (m == null) return null;
    return mapping[m.toLowerCase()];
  }

  /// The alternation pattern string used by [regexp].
  String get pattern => regexp.pattern;

  /// True if [s] contains any of the configured labels.
  bool hasMatch(String s) => regexp.hasMatch(s);
}

/// Typed wrapper for simple keyword lists compiled into a single regex.
final class KeywordSet {
  /// Original keyword list (as provided).
  final List<String> keywords;

  /// Precompiled alternation regex matching any keyword (case-insensitive).
  final RegExp regexp;

  KeywordSet._(this.keywords, this.regexp);

  /// Builds a case-insensitive keyword set and one alternation regex (never-match if empty).
  factory KeywordSet.fromList(List<String> list) {
    if (list.isEmpty) {
      return KeywordSet._(const [], RegExp(ReceiptConstants.neverMatchLiteral));
    }
    final escaped =
        list
            .map((k) => RegExp.escape(k.trim()))
            .where((k) => k.isNotEmpty)
            .toList();
    final pattern = '(${escaped.join('|')})';
    return KeywordSet._(
      List.unmodifiable(list),
      RegExp(pattern, caseSensitive: false),
    );
  }

  /// True if [text] contains any keyword.
  bool hasMatch(String text) => regexp.hasMatch(text);
}
