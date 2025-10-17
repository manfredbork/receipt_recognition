import 'package:receipt_recognition/src/utils/configuration/index.dart';

/// Numeric/string tuning knobs for parsing/optimization.
final class ReceiptTuning {
  /// Total tolerance tight and more precise below 1 cent.
  final double totalTolerance;

  /// Generic quarter fraction (25%) used by multiple heuristics.
  final double heuristicQuarter;

  /// Vertical tolerance (in pixels) for comparing bounding box alignment.
  final int verticalTolerance;

  /// Allowed tolerance in cents when matching delta between totals.
  final int outlierTau;

  /// Maximum number of candidate items considered for removal.
  final int outlierMaxCandidates;

  /// Confidence threshold (0–100) above which items are trusted.
  final int outlierLowConfThreshold;

  /// Minimum alternative texts required to trust an item.
  final int outlierMinSamples;

  /// Extra score penalty if an item looks like a suspect keyword.
  final int outlierSuspectBonus;

  /// Max identical iterations before stopping optimization.
  final int optimizerLoopThreshold;

  /// Default maximum cache size for normal precision mode.
  final int optimizerPrecisionNormal;

  /// Increased maximum cache size for high precision mode.
  final int optimizerPrecisionHigh;

  /// Minimum confidence score (0–100) for groups to be stable.
  final int optimizerConfidenceThreshold;

  /// Minimum stability score (0–100) required for groups.
  final int optimizerStabilityThreshold;

  /// Expiration time (ms) after which unstable groups are removed.
  final int optimizerInvalidateIntervalMs;

  /// EWMA smoothing factor for vertical order learning.
  final double optimizerEwmaAlpha;

  /// Pairwise count threshold before halving to avoid overflow.
  final int optimizerAboveCountDecayThreshold;

  /// Minimum fuzzy similarity required to merge product text variants.
  final double optimizerVariantMinSim;

  /// Minimum Jaccard similarity of product tokens required to merge items.
  final double optimizerMinProductSimToMerge;

  // Private real constructor
  ReceiptTuning._internal({
    required this.totalTolerance,
    required this.heuristicQuarter,
    required this.verticalTolerance,
    required this.outlierTau,
    required this.outlierMaxCandidates,
    required this.outlierLowConfThreshold,
    required this.outlierMinSamples,
    required this.outlierSuspectBonus,
    required this.optimizerLoopThreshold,
    required this.optimizerPrecisionNormal,
    required this.optimizerPrecisionHigh,
    required this.optimizerConfidenceThreshold,
    required this.optimizerStabilityThreshold,
    required this.optimizerInvalidateIntervalMs,
    required this.optimizerEwmaAlpha,
    required this.optimizerAboveCountDecayThreshold,
    required this.optimizerVariantMinSim,
    required this.optimizerMinProductSimToMerge,
  });

  /// Public constructor with **optional** named params.
  /// Any omitted field falls back to the default from `kReceiptDefaultOptions['tuning']`.
  factory ReceiptTuning({
    double? totalTolerance,
    double? heuristicQuarter,
    int? verticalTolerance,
    int? outlierTau,
    int? outlierMaxCandidates,
    int? outlierLowConfThreshold,
    int? outlierMinSamples,
    int? outlierSuspectBonus,
    int? optimizerLoopThreshold,
    int? optimizerPrecisionNormal,
    int? optimizerPrecisionHigh,
    int? optimizerConfidenceThreshold,
    int? optimizerStabilityThreshold,
    int? optimizerInvalidateIntervalMs,
    double? optimizerEwmaAlpha,
    int? optimizerAboveCountDecayThreshold,
    double? optimizerVariantMinSim,
    double? optimizerMinProductSimToMerge,
  }) {
    final def = ReceiptTuning.fromJsonLike(
      kReceiptDefaultOptions['tuning'] as Map<String, dynamic>?,
    );
    return ReceiptTuning._internal(
      totalTolerance: totalTolerance ?? def.totalTolerance,
      heuristicQuarter: heuristicQuarter ?? def.heuristicQuarter,
      verticalTolerance: verticalTolerance ?? def.verticalTolerance,
      outlierTau: outlierTau ?? def.outlierTau,
      outlierMaxCandidates: outlierMaxCandidates ?? def.outlierMaxCandidates,
      outlierLowConfThreshold:
          outlierLowConfThreshold ?? def.outlierLowConfThreshold,
      outlierMinSamples: outlierMinSamples ?? def.outlierMinSamples,
      outlierSuspectBonus: outlierSuspectBonus ?? def.outlierSuspectBonus,
      optimizerLoopThreshold:
          optimizerLoopThreshold ?? def.optimizerLoopThreshold,
      optimizerPrecisionNormal:
          optimizerPrecisionNormal ?? def.optimizerPrecisionNormal,
      optimizerPrecisionHigh:
          optimizerPrecisionHigh ?? def.optimizerPrecisionHigh,
      optimizerConfidenceThreshold:
          optimizerConfidenceThreshold ?? def.optimizerConfidenceThreshold,
      optimizerStabilityThreshold:
          optimizerStabilityThreshold ?? def.optimizerStabilityThreshold,
      optimizerInvalidateIntervalMs:
          optimizerInvalidateIntervalMs ?? def.optimizerInvalidateIntervalMs,
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
      totalTolerance: numFromKeys<double>(['totalTolerance']),
      heuristicQuarter: numFromKeys<double>(['heuristicQuarter']),
      verticalTolerance: numFromKeys<int>(['verticalTolerance']),
      outlierTau: numFromKeys<int>(['outlierTau']),
      outlierMaxCandidates: numFromKeys<int>(['outlierMaxCandidates']),
      outlierLowConfThreshold: numFromKeys<int>(['outlierLowConfThreshold']),
      outlierMinSamples: numFromKeys<int>(['outlierMinSamples']),
      outlierSuspectBonus: numFromKeys<int>(['outlierSuspectBonus']),
      optimizerLoopThreshold: numFromKeys<int>(['optimizerLoopThreshold']),
      optimizerPrecisionNormal: numFromKeys<int>(['optimizerPrecisionNormal']),
      optimizerPrecisionHigh: numFromKeys<int>(['optimizerPrecisionHigh']),
      optimizerConfidenceThreshold: numFromKeys<int>([
        'optimizerConfidenceThreshold',
      ]),
      optimizerStabilityThreshold: numFromKeys<int>([
        'optimizerStabilityThreshold',
      ]),
      optimizerInvalidateIntervalMs: numFromKeys<int>([
        'optimizerInvalidateIntervalMs',
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
    'totalTolerance': totalTolerance,
    'heuristicQuarter': heuristicQuarter,
    'verticalTolerance': verticalTolerance,
    'outlierTau': outlierTau,
    'outlierMaxCandidates': outlierMaxCandidates,
    'outlierLowConfThreshold': outlierLowConfThreshold,
    'outlierMinSamples': outlierMinSamples,
    'outlierSuspectBonus': outlierSuspectBonus,
    'optimizerLoopThreshold': optimizerLoopThreshold,
    'optimizerPrecisionNormal': optimizerPrecisionNormal,
    'optimizerPrecisionHigh': optimizerPrecisionHigh,
    'optimizerConfidenceThreshold': optimizerConfidenceThreshold,
    'optimizerStabilityThreshold': optimizerStabilityThreshold,
    'optimizerInvalidateIntervalMs': optimizerInvalidateIntervalMs,
    'optimizerEwmaAlpha': optimizerEwmaAlpha,
    'optimizerAboveCountDecayThreshold': optimizerAboveCountDecayThreshold,
    'optimizerVariantMinSim': optimizerVariantMinSim,
    'optimizerMinProductSimToMerge': optimizerMinProductSimToMerge,
  };
}
