import 'package:receipt_recognition/src/utils/configuration/index.dart';

/// Numeric/string tuning knobs for parsing/optimization.
final class ReceiptTuning {
  /// Total tolerance tight and more precise below 1 cent.
  final double optimizerTotalTolerance;

  /// Vertical tolerance (in pixels) for comparing bounding box alignment.
  final int optimizerVerticalTolerance;

  /// Max identical iterations before stopping optimization.
  final int optimizerLoopThreshold;

  /// Default maximum cache size for normal precision mode.
  final int optimizerMaxCacheSize;

  /// Minimum confidence score (0–100) for groups to be stable.
  final int optimizerConfidenceThreshold;

  /// Minimum stability score (0–100) required for groups.
  final int optimizerStabilityThreshold;

  /// EWMA smoothing factor for vertical order learning.
  final double optimizerEwmaAlpha;

  /// Pairwise count threshold before halving to avoid overflow.
  final int optimizerAboveCountDecayThreshold;

  /// Minimum fuzzy similarity required to merge product text variants.
  final double optimizerVariantMinSim;

  /// Minimum Jaccard similarity of product tokens required to merge items.
  final double optimizerMinProductSimToMerge;

  /// Private real constructor
  ReceiptTuning._internal({
    required this.optimizerTotalTolerance,
    required this.optimizerVerticalTolerance,
    required this.optimizerLoopThreshold,
    required this.optimizerMaxCacheSize,
    required this.optimizerConfidenceThreshold,
    required this.optimizerStabilityThreshold,
    required this.optimizerEwmaAlpha,
    required this.optimizerAboveCountDecayThreshold,
    required this.optimizerVariantMinSim,
    required this.optimizerMinProductSimToMerge,
  });

  /// Public constructor with **optional** named params.
  /// Any omitted field falls back to the default from `kReceiptDefaultOptions['tuning']`.
  factory ReceiptTuning({
    double? optimizerTotalTolerance,
    int? optimizerVerticalTolerance,
    int? optimizerLoopThreshold,
    int? optimizerMaxCacheSize,
    int? optimizerConfidenceThreshold,
    int? optimizerStabilityThreshold,
    double? optimizerEwmaAlpha,
    int? optimizerAboveCountDecayThreshold,
    double? optimizerVariantMinSim,
    double? optimizerMinProductSimToMerge,
  }) {
    final def = ReceiptTuning.fromJsonLike(
      kReceiptDefaultOptions['tuning'] as Map<String, dynamic>?,
    );
    return ReceiptTuning._internal(
      optimizerTotalTolerance:
          optimizerTotalTolerance ?? def.optimizerTotalTolerance,
      optimizerVerticalTolerance:
          optimizerVerticalTolerance ?? def.optimizerVerticalTolerance,
      optimizerLoopThreshold:
          optimizerLoopThreshold ?? def.optimizerLoopThreshold,
      optimizerMaxCacheSize: optimizerMaxCacheSize ?? def.optimizerMaxCacheSize,
      optimizerConfidenceThreshold:
          optimizerConfidenceThreshold ?? def.optimizerConfidenceThreshold,
      optimizerStabilityThreshold:
          optimizerStabilityThreshold ?? def.optimizerStabilityThreshold,
      optimizerEwmaAlpha: optimizerEwmaAlpha ?? def.optimizerEwmaAlpha,
      optimizerAboveCountDecayThreshold:
          optimizerAboveCountDecayThreshold ??
          def.optimizerAboveCountDecayThreshold,
      optimizerVariantMinSim:
          optimizerVariantMinSim ?? def.optimizerVariantMinSim,
      optimizerMinProductSimToMerge:
          optimizerMinProductSimToMerge ?? def.optimizerMinProductSimToMerge,
    );
  }

  /// Convenience: build strictly from the defaults table.
  factory ReceiptTuning.defaults() => ReceiptTuning.fromJsonLike(
    kReceiptDefaultOptions['tuning'] as Map<String, dynamic>?,
  );

  /// Builds tuning from a JSON-like map, falling back **per-field** to defaults,
  /// without hardcoded numeric literals. Also supports legacy key aliases.
  factory ReceiptTuning.fromJsonLike(Map<String, dynamic>? json) {
    final Map<String, dynamic> d =
        (kReceiptDefaultOptions['tuning'] as Map<String, dynamic>?) ?? const {};

    final Map<String, dynamic> u = json ?? const {};

    final Map<String, dynamic> merged =
        <String, dynamic>{}
          ..addAll(d)
          ..addAll(u);

    T numCast<T extends num>(num v) =>
        (T == int ? v.toInt() : v.toDouble()) as T;

    T numFromKeys<T extends num>(List<String> keys) {
      for (final k in keys) {
        final v = merged[k];
        if (v is num) return numCast<T>(v);
      }
      throw StateError('Missing tuning value for keys: ${keys.join(", ")}');
    }

    return ReceiptTuning._internal(
      optimizerTotalTolerance: numFromKeys<double>(['optimizerTotalTolerance']),
      optimizerVerticalTolerance: numFromKeys<int>([
        'optimizerVerticalTolerance',
      ]),
      optimizerLoopThreshold: numFromKeys<int>(['optimizerLoopThreshold']),
      optimizerMaxCacheSize: numFromKeys<int>(['optimizerMaxCacheSize']),
      optimizerConfidenceThreshold: numFromKeys<int>([
        'optimizerConfidenceThreshold',
      ]),
      optimizerStabilityThreshold: numFromKeys<int>([
        'optimizerStabilityThreshold',
      ]),
      optimizerEwmaAlpha: numFromKeys<double>(['optimizerEwmaAlpha']),
      optimizerAboveCountDecayThreshold: numFromKeys<int>([
        'optimizerAboveCountDecayThreshold',
      ]),
      optimizerVariantMinSim: numFromKeys<double>(['optimizerVariantMinSim']),
      optimizerMinProductSimToMerge: numFromKeys<double>([
        'optimizerMinProductSimToMerge',
      ]),
    );
  }

  /// Serializes tuning to a JSON-like map.
  Map<String, dynamic> toJsonLike() => {
    'optimizerTotalTolerance': optimizerTotalTolerance,
    'optimizerVerticalTolerance': optimizerVerticalTolerance,
    'optimizerLoopThreshold': optimizerLoopThreshold,
    'optimizerMaxCacheSize': optimizerMaxCacheSize,
    'optimizerConfidenceThreshold': optimizerConfidenceThreshold,
    'optimizerStabilityThreshold': optimizerStabilityThreshold,
    'optimizerEwmaAlpha': optimizerEwmaAlpha,
    'optimizerAboveCountDecayThreshold': optimizerAboveCountDecayThreshold,
    'optimizerVariantMinSim': optimizerVariantMinSim,
    'optimizerMinProductSimToMerge': optimizerMinProductSimToMerge,
  };
}
