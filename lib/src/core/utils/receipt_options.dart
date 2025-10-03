import 'package:receipt_recognition/receipt_recognition.dart';

/// A typed wrapper for "label -> canonical" maps with a precompiled regex.
final class DetectionMap {
  final RegExp regexp;
  final Map<String, String> mapping;

  DetectionMap._(this.regexp, this.mapping);

  /// Builds a case-insensitive map from label→canonical and compiles one regex
  /// matching any label. Returns a safe never-match regex when the map is empty.
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

  String? detect(String text) {
    final m = regexp.stringMatch(text);
    if (m == null) return null;
    return mapping[m.toLowerCase()];
  }

  String get pattern => regexp.pattern;

  bool hasMatch(String s) => regexp.hasMatch(s);
}

/// Typed wrapper for simple keyword lists compiled into a single regex.
final class KeywordSet {
  final List<String> keywords;
  final RegExp regexp;

  KeywordSet._(this.keywords, this.regexp);

  /// Builds a case-insensitive keyword set and compiles one alternation regex.
  /// Returns a safe never-match regex when the list is empty.
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

  bool hasMatch(String text) => regexp.hasMatch(text);
}

/// Strongly-typed, user-configurable options for the parser.
final class ReceiptOptions {
  final DetectionMap storeNames;
  final DetectionMap totalLabels;

  final KeywordSet ignoreKeywords;
  final KeywordSet stopKeywords;
  final KeywordSet foodKeywords;
  final KeywordSet nonFoodKeywords;
  final KeywordSet discountKeywords;
  final KeywordSet depositKeywords;

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
  /// Handy for tests, defaults, or disabling features.
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

  /// Builds options from a JSON-like map, safely picking string-only maps/lists
  /// for each field and ignoring non-string entries.
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
