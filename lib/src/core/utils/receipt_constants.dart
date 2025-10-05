/// Centralized constants shared between receipt parsing and optimization.
class ReceiptConstants {
  /// Vertical tolerance (in pixels) for comparing bounding box alignment.
  static const int boundingBoxBuffer = 20;

  /// Sum tolerance tight and more precise below 1 cent.
  static const double sumTolerance = 0.009;

  /// A literal that won't ever occur in receipt text → safe never-match regex.
  static const String neverMatchLiteral = r'___NEVER_MATCH___';

  /// Allowed tolerance in cents when matching delta between sums.
  static const int outlierTau = 1;

  /// Maximum number of candidate items considered for removal.
  static const int outlierMaxCandidates = 12;

  /// Confidence threshold (0–100) above which items are trusted.
  static const int outlierLowConfThreshold = 35;

  /// Minimum alternative texts required to trust an item.
  static const int outlierMinSamples = 3;

  /// Extra score penalty if an item looks like a suspect keyword.
  static const int outlierSuspectBonus = 50;

  /// Max identical iterations before stopping optimization.
  static const int optimizerLoopThreshold = 10;

  /// Confirmations required before a sum is accepted.
  static const int optimizerSumConfirmationThreshold = 3;

  /// Default maximum cache size for normal precision mode.
  static const int optimizerPrecisionNormal = 15;

  /// Increased maximum cache size for high precision mode.
  static const int optimizerPrecisionHigh = 25;

  /// Minimum confidence score (0–100) for groups to be stable.
  static const int optimizerConfidenceThreshold = 70;

  /// Minimum confidence score (0–100) for groups to be very stable.
  static const int optimizerHighConfidenceThreshold = 90;

  /// Minimum confidence score (0–100) for groups to be almost perfect.
  static const int optimizerHighestConfidenceThreshold = 98;

  /// Minimum stability score (0–100) required for groups.
  static const int optimizerStabilityThreshold = 60;

  /// Expiration time (ms) after which unstable groups are removed.
  static const int optimizerInvalidateIntervalMs = 2000;

  /// EWMA smoothing factor for vertical order learning.
  static const double optimizerEwmaAlpha = 0.3;

  /// Pairwise count threshold before halving to avoid overflow.
  static const int optimizerAboveCountDecayThreshold = 50;

  /// Minimum number of positions required for sum validation.
  static const int optimizerMinPositionsForSum = 2;

  /// Minimum fuzzy similarity required to merge product text variants.
  static const double optimizerVariantMinSim = 0.85;

  /// Minimum Jaccard similarity of product tokens required to merge items.
  static const double minProductSimToMerge = 0.5;

  /// Generic quarter fraction (25%) used by multiple heuristics
  static const double heuristicQuarter = 0.25;
}
