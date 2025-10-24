/// Public API for the `receipt_recognition` package.
///
/// Note: Files under `lib/src/**` must NOT import this file.
/// They should import specific internal files instead, e.g.
/// `package:receipt_recognition/src/...`.
library;

/// ── Public models (foundations → low-level → line items → receipt-level) ──
export 'src/models/index.dart'
    show
        /// Foundations
        Valuable,
        Confidence,
        Operation,
        RecognizedEntity,
        /// Low-level entities
        RecognizedUnknown,
        RecognizedBounds,
        RecognizedStore,
        RecognizedCompany,
        RecognizedPurchaseDate,
        /// Line-item layer
        RecognizedProduct,
        RecognizedPrice,
        RecognizedAmount,
        RecognizedTotalLabel,
        RecognizedTotal,
        CalculatedTotal,
        RecognizedPosition,
        RecognizedGroup,
        /// Receipt layer
        RecognizedReceipt,
        RecognizedScanProgress,
        ReceiptValidationResult,
        ReceiptCompleteness;

/// High-level recognizer (public entry point)
export 'src/services/ocr/receipt_recognizer.dart' show ReceiptRecognizer;

/// ── Public services ──
export 'src/services/optimizer/receipt_optimizer.dart'
    show Optimizer, ReceiptOptimizer;

/// ── Configuration & runtime ──
/// Options + tuning + merge semantics + default baseline
export 'src/utils/configuration/index.dart'
    show
        ReceiptOptions,
        ReceiptTuning,
        MergePolicy,
        kReceiptDefaultOptions,
        ReceiptRuntime;

/// ── Logger + debug output ──
export 'src/utils/logging/index.dart' show ReceiptLogger;
