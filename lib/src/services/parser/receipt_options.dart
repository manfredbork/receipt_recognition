import 'package:receipt_recognition/src/services/parser/index.dart';

/// Strongly-typed, user-configurable options for the parser.
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
  /// Prefer constructing this with user data only (no defaults),
  /// then call `ReceiptOptionsMerger.withDefaults(...)`.
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
  /// Useful for tests or when you explicitly want *no* built-in patterns.
  /// For production use, prefer [ReceiptOptionsMerger.withDefaults] so your
  /// user config extends the built-ins.
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

  /// Builds options from a JSON-like map.
  @Deprecated(
    'Parse user config, then merge via ReceiptOptionsMerger.withDefaults(...)',
  )
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
