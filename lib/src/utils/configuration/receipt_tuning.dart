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

  /// Creates a new tuning configuration from required values.
  ReceiptTuning({
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

  /// Builds tuning from a JSON-like map using safe defaults.
  factory ReceiptTuning.fromJsonLike(Map<String, dynamic>? json) {
    final j = json ?? const {};
    T numAs<T extends num>(String k, T d) {
      final v = j[k];
      if (v is num) return (T == int ? v.toInt() : v.toDouble()) as T;
      return d;
    }

    return ReceiptTuning(
      totalTolerance: numAs<double>('totalTolerance', 0.009),
      heuristicQuarter: numAs<double>('heuristicQuarter', 0.25),
      verticalTolerance: numAs<int>('verticalTolerance', 25),
      outlierTau: numAs<int>('outlierTau', 1),
      outlierMaxCandidates: numAs<int>('outlierMaxCandidates', 12),
      outlierLowConfThreshold: numAs<int>('outlierLowConfThreshold', 35),
      outlierMinSamples: numAs<int>('outlierMinSamples', 3),
      outlierSuspectBonus: numAs<int>('outlierSuspectBonus', 50),
      optimizerLoopThreshold: numAs<int>('optimizerLoopThreshold', 10),
      optimizerPrecisionNormal: numAs<int>('optimizerPrecisionNormal', 20),
      optimizerPrecisionHigh: numAs<int>('optimizerPrecisionHigh', 20),
      optimizerConfidenceThreshold: numAs<int>(
        'optimizerConfidenceThreshold',
        90,
      ),
      optimizerStabilityThreshold: numAs<int>(
        'optimizerStabilityThreshold',
        50,
      ),
      optimizerInvalidateIntervalMs: numAs<int>(
        'optimizerInvalidateIntervalMs',
        3000,
      ),
      optimizerEwmaAlpha: numAs<double>('optimizerEwmaAlpha', 0.3),
      optimizerAboveCountDecayThreshold: numAs<int>(
        'optimizerAboveCountDecayThreshold',
        50,
      ),
      optimizerVariantMinSim: numAs<double>('optimizerVariantMinSim', 0.85),
      optimizerMinProductSimToMerge: numAs<double>(
        'optimizerMinProductSimToMerge',
        0.5,
      ),
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
