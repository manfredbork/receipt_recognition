import 'package:receipt_recognition/src/utils/configuration/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';

/// How user config should interact with built-in defaults.
enum MergePolicy {
  /// Keep defaults and add/override with user config (defaults ∪ user).
  extend,

  /// Ignore defaults completely and use only user config.
  override,
}

/// A literal that won't ever occur in receipt text → safe never-match regex.
const String neverMatchLiteral = r'(?!)';

/// Strongly-typed, user-configurable options for the parser with merge helpers.
final class ReceiptOptions {
  /// Map of store aliases to canonical names.
  final DetectionMap storeNames;

  /// Map of total labels (e.g., “Total”, “Summe”) to canonical label.
  final DetectionMap totalLabels;

  /// Keywords that should be ignored during parsing.
  final KeywordSet ignoreKeywords;

  /// Keywords that indicate parsing should stop.
  final KeywordSet stopKeywords;

  /// Whitelist of product group keywords allowed as item candidates.
  final KeywordSet allowedProductGroups;

  /// Numeric/string tuning applied across the parser/optimizer.
  final ReceiptTuning tuning;

  /// Private constructor for raw typed parts.
  ReceiptOptions._internal({
    required this.storeNames,
    required this.totalLabels,
    required this.ignoreKeywords,
    required this.stopKeywords,
    required this.allowedProductGroups,
    required this.tuning,
  });

  /// Public constructor that mirrors the layered user config structure.
  ///
  /// - [extend]: union-merged with defaults (user wins on duplicates)
  /// - [override]: fully replaces defaults per provided key
  /// - [tuning]: ALWAYS override-only (top-level, not part of extend/override)
  factory ReceiptOptions({
    Map<String, dynamic>? extend,
    Map<String, dynamic>? override,
    Map<String, dynamic>? tuning,
  }) {
    final def = ReceiptOptions.defaults();

    Map<String, dynamic> mapOrEmpty(dynamic v) =>
        v is Map<String, dynamic> ? v : const <String, dynamic>{};
    final ext = mapOrEmpty(extend);
    final ovw = mapOrEmpty(override);
    final tun = mapOrEmpty(tuning);

    Map<String, String> pickStrMap(dynamic v) =>
        v is Map
            ? Map<String, String>.fromEntries(
              v.entries
                  .where((e) => e.key is String && e.value is String)
                  .map((e) => MapEntry(e.key as String, e.value as String)),
            )
            : <String, String>{};

    List<String> pickStrList(dynamic v) =>
        v is List ? v.whereType<String>().toList() : const <String>[];

    DetectionMap resolveMap({
      required DetectionMap defaults,
      required String key,
    }) {
      if (ovw.containsKey(key)) {
        return DetectionMap.fromMap(pickStrMap(ovw[key]));
      }
      return _dmMerge(
        defaults,
        DetectionMap.fromMap(pickStrMap(ext[key])),
        MergePolicy.extend,
      );
    }

    KeywordSet resolveList({
      required KeywordSet defaults,
      required String key,
    }) {
      if (ovw.containsKey(key)) {
        return KeywordSet.fromList(pickStrList(ovw[key]));
      }
      return _ksMerge(
        defaults,
        KeywordSet.fromList(pickStrList(ext[key])),
        MergePolicy.extend,
      );
    }

    final storeNames = resolveMap(defaults: def.storeNames, key: 'storeNames');
    final totalLabels = resolveMap(
      defaults: def.totalLabels,
      key: 'totalLabels',
    );

    final ignoreKeywords = resolveList(
      defaults: def.ignoreKeywords,
      key: 'ignoreKeywords',
    );
    final stopKeywords = resolveList(
      defaults: def.stopKeywords,
      key: 'stopKeywords',
    );
    final allowedProductGroups = resolveList(
      defaults: def.allowedProductGroups,
      key: 'allowedProductGroups',
    );

    final tuningResolved =
        tun.isNotEmpty ? ReceiptTuning.fromJsonLike(tun) : def.tuning;

    return ReceiptOptions._internal(
      storeNames: storeNames,
      totalLabels: totalLabels,
      ignoreKeywords: ignoreKeywords,
      stopKeywords: stopKeywords,
      allowedProductGroups: allowedProductGroups,
      tuning: tuningResolved,
    );
  }

  /// Convenience: build from a layered JSON map {extend, override, tuning}.
  factory ReceiptOptions.fromLayeredJson(Map<String, dynamic>? json) =>
      ReceiptOptions(
        extend: json?['extend'] as Map<String, dynamic>?,
        override: json?['override'] as Map<String, dynamic>?,
        tuning: json?['tuning'] as Map<String, dynamic>?,
      );

  /// Returns a minimal config with all maps/lists empty (no matches).
  factory ReceiptOptions.empty() => ReceiptOptions._internal(
    storeNames: DetectionMap.fromMap(const {}),
    totalLabels: DetectionMap.fromMap(const {}),
    ignoreKeywords: KeywordSet.fromList(const []),
    stopKeywords: KeywordSet.fromList(const []),
    allowedProductGroups: KeywordSet.fromList(const []),
    tuning: ReceiptTuning.fromJsonLike(const {}),
  );

  /// Builds options from a flat JSON-like map (no layered rules).
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

    return ReceiptOptions._internal(
      storeNames: DetectionMap.fromMap(pickStrMap(json['storeNames'])),
      totalLabels: DetectionMap.fromMap(pickStrMap(json['totalLabels'])),
      ignoreKeywords: KeywordSet.fromList(pickStrList(json['ignoreKeywords'])),
      stopKeywords: KeywordSet.fromList(pickStrList(json['stopKeywords'])),
      allowedProductGroups: KeywordSet.fromList(
        pickStrList(json['allowedProductGroups']),
      ),
      tuning: ReceiptTuning.fromJsonLike(
        json['tuning'] as Map<String, dynamic>?,
      ),
    );
  }

  /// Serializes options to a flat JSON-like map (no layered rules).
  Map<String, dynamic> toJsonLike() => {
    'storeNames': storeNames.mapping,
    'totalLabels': totalLabels.mapping,
    'ignoreKeywords': ignoreKeywords.keywords,
    'stopKeywords': stopKeywords.keywords,
    'allowedProductGroups': allowedProductGroups.keywords,
    'tuning': tuning.toJsonLike(),
  };

  /// Returns options built solely from built-in JSON defaults (no user overrides).
  static ReceiptOptions defaults() =>
      ReceiptOptions.fromJsonLike(kReceiptDefaultOptions);

  /// 日本語レシート用のデフォルト設定を返す。
  factory ReceiptOptions.japanese() =>
      ReceiptOptions.fromJsonLike(kReceiptDefaultOptionsJa);

  /// Merges default and user keyword sets according to [p].
  static KeywordSet _ksMerge(
    KeywordSet defaults,
    KeywordSet user,
    MergePolicy p,
  ) {
    if (p == MergePolicy.override) return user;
    final out = <String>{...defaults.keywords, ...user.keywords};
    return KeywordSet.fromList(out.toList());
  }

  /// Merges default and user detection maps according to [p] (user wins on duplicates).
  static DetectionMap _dmMerge(
    DetectionMap defaults,
    DetectionMap user,
    MergePolicy p,
  ) {
    if (p == MergePolicy.override) return user;
    final merged =
        <String, String>{}
          ..addAll(defaults.mapping)
          ..addAll(user.mapping);
    return DetectionMap.fromMap(merged);
  }
}

/// The regex matches each configured label allowing optional single spaces between characters,
/// and lookups are normalized by stripping whitespace and lowercasing.
final class DetectionMap {
  /// Precompiled alternation regex matching any label (case-insensitive).
  final RegExp regexp;

  /// Lowercased, space-stripped label→canonical mapping used for lookups.
  final Map<String, String> mapping;

  /// Private constructor with precompiled regex and mapping.
  DetectionMap._(this.regexp, this.mapping);

  /// Builds a case-insensitive mapping and one tolerant regex; returns a never-match regex if empty.
  factory DetectionMap.fromMap(Map<String, String> map) {
    if (map.isEmpty) {
      return DetectionMap._(RegExp(neverMatchLiteral), const {});
    }

    final patterns = <String>[];
    final normalized = <String, String>{};

    for (final e in map.entries) {
      final k = e.key.trim();
      if (k.isEmpty) continue;
      final p = _optionalSpacesPattern(k);
      if (p.isEmpty) continue;
      patterns.add(p);
      normalized[ReceiptNormalizer.normalizeKey(k)] = e.value;
    }

    final pattern = '(${patterns.join('|')})';
    return DetectionMap._(
      RegExp(pattern, caseSensitive: false),
      Map.unmodifiable(normalized),
    );
  }

  /// Returns the canonical value if any label in [text] matches; otherwise null.
  String? detect(String text) {
    final m = regexp.stringMatch(text);
    if (m == null) return null;
    return mapping[ReceiptNormalizer.normalizeKey(m)];
  }

  /// Returns the alternation pattern string used by [regexp].
  String get pattern => regexp.pattern;

  /// Returns true if [s] contains any of the configured labels.
  bool hasMatch(String s) => regexp.hasMatch(s);
}

/// Typed wrapper for simple keyword lists compiled into a single tolerant regex.
/// Each keyword is matched allowing optional single spaces between characters.
final class KeywordSet {
  /// Original keyword list (as provided).
  final List<String> keywords;

  /// Precompiled alternation regex matching any keyword (case-insensitive).
  final RegExp regexp;

  /// Private constructor with original keywords and precompiled regex.
  KeywordSet._(this.keywords, this.regexp);

  /// Builds a case-insensitive keyword set and one tolerant alternation regex (never-match if empty).
  factory KeywordSet.fromList(List<String> list) {
    if (list.isEmpty) {
      return KeywordSet._(const [], RegExp(neverMatchLiteral));
    }

    final patterns =
        list
            .map((k) => _optionalSpacesPattern(k.trim()))
            .where((p) => p.isNotEmpty)
            .toList();

    if (patterns.isEmpty) {
      return KeywordSet._(const [], RegExp(neverMatchLiteral));
    }

    final pattern = '(${patterns.join('|')})';
    return KeywordSet._(
      List.unmodifiable(list),
      RegExp(pattern, caseSensitive: false),
    );
  }

  /// Returns true if [text] contains any keyword.
  bool hasMatch(String text) => regexp.hasMatch(text);
}

/// Build a regex pattern that allows zero-or-one space between each character
/// of the provided literal. Example: "Aldi" → A\s?l\s?d\s?i
String _optionalSpacesPattern(String literal) {
  final stripped = literal.replaceAll(RegExp(r'\s+'), '');
  if (stripped.isEmpty) return '';
  final runes = stripped.runes.toList();
  final parts = <String>[];
  for (var i = 0; i < runes.length; i++) {
    final ch = String.fromCharCode(runes[i]);
    parts.add(RegExp.escape(ch));
    if (i < runes.length - 1) parts.add(r'\s?');
  }
  return parts.join();
}
