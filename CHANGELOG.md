# Changelog

All notable changes to this project will be documented in this file.

## [0.2.5] – 2025-12-14

### ✨ Added
- **New store support**: Added **Kaufland** and **dm** store support (including improved/real-world handling).
- **Parsing support**: Added handling for **asterisk-marked** receipt lines.

### 🛠️ Changed
- **Normalization**: Normalize spaces more consistently to improve matching under OCR spacing glitches.
- **Total-label handling**: Refined label-related conditions to improve robustness.
- **Position creation**:
  - Prefer creating positions from the **same row** when possible.
  - Apply **non-strict** position creation only for **unused amounts** to avoid accidental matches.
- **Build/CI hygiene**: Ignore other build paths to reduce noise and avoid unintended file interactions.
- **Internal**: Dynamic script language adjustments and minor method renaming/cleanup.

### ✅ Tests
- Added and reorganized tests, including expanded integration test assertions (e.g., more unit/quantity/price checks).

---

## [0.2.4] – 2025-12-04

### ✨ Added
- **Extended integration test coverage**: Added some comprehensive integration tests with special validation for deposit positions.

### 🐛 Fixed
- **Total identification**: Fixed a critical bug where totals were not correctly identified when total labels were present.
- **Unit parsing tolerance**: Adjusted vertical tolerance for better multi-line receipt handling.

---

## [0.2.3] – 2025-12-03

### ✨ Added
- **Extended integration tests**: Added comprehensive integration tests for multiple receipt types (EDEKA, LIDL, and ALDI) with validation of store names, totals, purchase dates, positions, and specific line items.
- **Text processor testing support**: Added `debugRunSynchronouslyForTests` flag to `ReceiptTextProcessor` for synchronous parsing in test environments.
- **Truncated frequency calculation**: New `calculateTruncatedFrequency` method that merges truncated leading-token alternatives into their longer counterparts before counting frequency.

### 🛠️ Changed
- **Unified unit parsing**: Merged `_tryParseUnitQuantity` and `_tryParseUnitPrice` into a single `_tryParseUnit` method for more efficient unit detection.
- **Total label detection improvements**:
    - Now uses normalized keys for better matching accuracy
    - Added prefix matching for total labels (e.g., "SUMME EUR" will match "summe")
- **Parser refinements**:
    - Fixed bug where `_findTotalLabel` was incorrectly called instead of `_findTotal` when searching for totals
    - Improved unit text extraction to avoid including numeric portions
    - Enhanced unknown entity filtering to prevent lines with too many numeric characters from being classified as unknown
- **Normalization improvements**:
    - Updated frequency calculation for alternative postfix texts to use truncated frequency method.
    - Moved truncated frequency calculator to the correct normalization method for alternative texts.
    - Refined alternative text frequency calculation in `RecognizedProduct`.
- **Parser simplification**: Reduced complexity by removing overly complicated logic and making the codebase simpler and more maintainable.
- **OCR autocorrection**: Reduced OCR autocorrection aggressiveness for better accuracy.
- **Skew calculation**: Removed outliers from skew angle calculation for more stable alignment.
- **Ignored keywords**: Added "Subtotal" to the list of keywords to ignore during product recognition.
- **Timeout handling**: Improved timeout behavior for better responsiveness.

### 🐛 Fixed
- **Entity type preservation**: Fixed issue where entities were being incorrectly cast, now properly creates new instances with correct types when filtering (e.g., `RecognizedTotal` → `RecognizedAmount`, `RecognizedTotalLabel` → `RecognizedUnknown`)
- **Unit boundary detection**: Changed unit parsing to use `_rightL(line)` instead of `_leftL(line)` for proper right-bound checking
- **Unit parsing**: Fixed a critical bug where unit prices with negative total prices were not correctly handled with proper sign adjustment.
- **Unit validation**: Corrected unit price-quantity validation logic to properly check tolerance thresholds.
- **Parsing stability**: Multiple fixes to improve parsing reliability and reduce edge-case errors.

---

## [0.2.2] – 2025-11-19

### 🛠️ Changed
- **Product recognition threshold**: Increased strictness for position confirmation – now requires **80% of positions** to pass validation (up from 75%) for more reliable receipt parsing.
- **Product name handling**: Improved handling of leading digits – now allows product names with leading digits if they contain **6 or more letters total**, reducing false rejections.

### 🐛 Fixed
- **Normalization**: Removed verbose debug comments from OCR correction logic, improving code clarity.
- **Integration tests**: Corrected asset path reference in integration tests.

### 🧹 Housekeeping
- Removed `.metadata` tracking file from version control in example app.
- Updated `.gitignore` to exclude metadata files going forward.

---

## [0.2.1] – 2025-11-13

### ✨ Added
- Added **Spar** to the default store list.

### 🛠️ Changed
- Store and total-label detection is now **more tolerant** to OCR spacing glitches.
- Store extraction now only considers candidates **above the first amount line**, reducing false positives.
- Improved **skew angle estimation** for more stable item alignment.
- Parser now performs a fallback pass to assign **unmatched amounts**, reducing missing line items.

### 🐛 Fixed
- **Purchase date** handling no longer locks onto early, unstable detections; continuous scans refine it correctly.
- Minor stability improvements in the optimizer and parser.

---

## [0.2.0] – 2025-11-08

### ✨ Added

- **Unit price & quantity parsing**: extract quantity and price-per-unit for line items.
- **`allowedProductGroups`** option to control which product groups are accepted during parsing.
- **Position bounding box** exposure for recognized positions.
- Minor improvements around pseudo positions for better preview/UX.

### 🛠️ Changed

- Tuned defaults for stability and performance (cache size, thresholds, timeouts).
- Normalization tweaks: treat `+` as a normal character; refined space handling; extended patterns.
- Removed legacy keyword groups (discount/deposit) in favor of `allowedProductGroups`.
- Internal type/use cleanups (prefer `double`/`int` where appropriate).
- Purchase date recognition is tuned for better robustness.

### 🐛 Fixed

- **Lost groups during merging**: fixed issues where groups could disappear or be dropped in long/unstable scans.
- **Deposit handling**: corrected parsing so deposit lines don’t corrupt totals or item classification.
- **Product group classification**: fixes to ensure correct group assignment and consistent downstream behavior.
- General stability fixes across optimizer and parser components.

---

## [0.1.9] – 2025-10-27

### ✨ Added

- Unit tests covering additional normalization scenarios.

### 🛠️ Changed

- Adjusted `onScanTimeout` signature in `ReceiptRecognizer`.
- Improved normalization and output: use normalized text consistently and refined purchase date output.
- Tuned optimizer cache for better stability and responsiveness.

### 🐛 Fixed

- Corrected skew angle handling and bounds calculation for accurate receipt alignment.
- Prevented misclassification of prices as product names.

## [0.1.8] - 2024-10-25

### 🐛 Fixed

- **Pass static analysis**: Reformatted `receipt_recognition-dart` to reach 50/50 points

---

## [0.1.7] – 2025-10-24

### ✨ Added

- Integration test for single-image recognition in the example app:
    - `example/integration_test/receipt_recognizer_test.dart`
- `purchaseDate` detection and exposure on `RecognizedReceipt`.
- Configurability via the new options/tuning system:
    - `ReceiptOptions` to control parsing, validation, and scanning behavior.
    - `ReceiptTuning` for adjustable merge/stability thresholds.
    - `kReceiptDefaultOptions` as a sensible baseline.
    - `ReceiptRuntime` helper to apply options during parsing.

### 🛠️ Changed

- `processImage` now always returns a `RecognizedReceipt` (never `null`), even when incomplete or invalid.
- Clarified result semantics for continuous scanning (video):
    - `isValid`: essential structure present and totals are coherent.
    - `isConfirmed`: result stabilized across frames (finalized by optimizer).
- Scanning guidance:
    - Video: stop when `receipt.isValid && receipt.isConfirmed`.
    - Single image: `isConfirmed` typically not achievable; treat `isValid` as sufficient or prompt re-capture.
- Parser and Optimizer refactored and improved for more robust extraction and more stable results across frames.

### 🧹 Deprecated

- `minValidScans` in `ReceiptRecognizer` (constructor parameter) in favor of stability/confirmation rules and tuning via
  `ReceiptOptions`/`ReceiptTuning`.
- Legacy `sum`/`sumLabel` naming: prefer `total` (`RecognizedTotal`) and `totalLabel` (`RecognizedTotalLabel`).
- `RecognizedCompany` is considered legacy; prefer `RecognizedStore`.

---

## [0.1.6] - 2025-09-22

### 🐛 Fixed

- **RecognizedGroup**: Added type annotation to `maxGroupSize` property

### 🛠️ Changed

- Updated to the most recent linter to avoid server side linting issues

---

## [0.1.5] - 2025-09-21

### ✨ Added

- **Configurable stores** support in the parsing pipeline, recognizer now accepts an `options` map that is forwarded to
  the receipt parser

- **Example app updates**:
    - Introduces `opencv_dart` in the example’s dependencies used for image preprocessing

### 🛠️ Changed

- `ReceiptRecognizer` constructor: new optional `options` parameter
- Default scanning cadence: `scanInterval` increased from **50 ms → 100 ms**

---

## [0.1.4] - 2025-09-20

### 🐛 Fixed

- **ReceiptParser**: Checking `minValidScans` on successful scan

### 🛠️ Changed

- **ReceiptNormalizer**: Simplified normalization logic

---

## [0.1.3] - 2025-09-19

### 🐛 Fixed

- **ReceiptRecognizer**: Fixed the scan counter reset issue that was preventing proper scan completion
- **iOS Deployment**: Updated minimum iOS deployment target to 13.0 for compatibility

### 🛠️ Changed

- **ReceiptRecognizer**: Increased default `minValidScans` from 3 to 5 for more reliable scanning

---

## [0.1.2] - 2025-09-18

### 🐛 Fixed

- **Scan Validation**: Fixed the issue where scans could complete prematurely before reaching the minimum valid scan
  count
- **Match Percentage Calculation**: Corrected calculation logic for sum match percentage to use actual values instead of
  scan-weighted values
- **Ignore Keywords**: Added "Subtotal" to the list of keywords to ignore during product recognition

### 🛠️ Changed

- **Product Display**: Updated debug output to use normalized product text for better consistency
- **Recognition Accuracy**: Enhanced filtering of non-product lines to improve overall scan quality

---

## [0.1.1] - 2025-09-09

### 📚 Documentation

- Streamlined README to reflect current capabilities and scope
- Removed outdated roadmap/status references and aligned wording with the present feature set
- Clarified Implementation Status and reorganized sections for better readability
- Minor copyedits for consistency (terminology, headings, and formatting)

---

## [0.1.0] - 2025-06-06

### ✨ Added

* **Stable Sum Detection**: The scanner now identifies the most likely total amount by combining confidence and position
  tracking across multiple frames
* **Live Bounding Boxes**: Detected receipt items are now outlined live on the camera preview, making it easier to see
  what's recognized in real time

### 🛠️ Changed

* **Metadata Filtering**: The engine is better at ignoring irrelevant lines like footer notes or fiscal metadata,
  keeping the product list clean
* **Enhanced Merge Logic**: Optimized how multi-frame receipts are combined, improving structure and reliability even in
  fragmented scans

### 🐛 Fixed

* **Incorrect Totals**: Fixed an issue where prices from unrelated lines could falsely be interpreted as the receipt’s
  sum
* **Layout Glitches**: Resolved occasional misalignments or line skips when processing longer or poorly lit receipts

---

## [0.0.9] - 2025-06-03

### ✨ Added

- **Smarter Scan Confidence Filtering**: The recognition engine can now automatically ignore low-confidence items that
  might distort the total sum
- **Status Getter**: Added a simple flag to detect if scanning is still in progress
- **Improved Example App**: The example app now includes best practice instructions, live scan overlays, and a clearer
  UI for scanning and viewing receipts

### 🛠️ Changed

- **Internal Optimizations**: Minor refactoring and documentation improvements to ensure better readability and
  maintainability of the code

### 🐛 Fixed

- **Sum Calculation Accuracy**: Fixed cases where incorrect items could cause mismatches with the printed total
- **Scan Stability**: Improved reliability of the scan process for varied receipt lengths and layouts

---

## [0.0.8] - 2024-05-29

### ✨ Added

- **Manual Receipt Acceptance**: Added `acceptReceipt()` method to manually accept receipts with validation
  discrepancies
- **Enhanced Validation Flow**: Improved receipt validation with configurable thresholds and detailed status reporting
- **Validation State Tracking**: Added comprehensive validation states (complete, nearlyComplete, incomplete, invalid)
- **Documentation**: Added detailed documentation on validation workflow and manual acceptance

### 🛠️ Changed

- **Implementation Status Table**: Improved formatting of status table in documentation
- **Progress Reporting**: Enhanced `ScanProgress` model with more detailed validation information
- **Validation Logic**: Refined match percentage calculation between calculated and declared sums

### 🐛 Fixed

- **Receipt Merging**: Fixed edge cases in receipt merging that could lead to inaccurate total sums
- **Stability Thresholds**: Adjusted default stability thresholds for more reliable scanning

---

## [0.0.7] - 2024-05-19

### 🐛 Fixed

- **Pass static analysis**: Added curly braces to reach 50/50 points

---

## [0.0.6] - 2024-05-18

### ✨ Added

- Intelligent product name normalization via `ReceiptNormalizer.normalizeFromGroup`
- Graph-based item ordering using `PositionGraph` with fuzzy matching and topological sort
- `CachedReceipt` consolidation with improved trust-based merging logic
- Parallelized parsing and graph resolution using Dart's `compute()` isolates
- Outlier filtering for OCR noise and trailing receipt lines
- Unit tests for name cleaning and group resolution

### 🛠️ Changed

- Restructured `core/` folder for better modularity
- Improved `ReceiptParser._shrinkEntities()` to robustly remove lines below sum/total
- Enhanced debug output when scanning receipts in `ReceiptRecognizer`

### 📚 Documentation

- Added concise DartDoc to all public APIs, data models, and helpers

### ✅ Tests

- Added group-based name cleaning tests
- Validated space vs. no-space consensus logic (e.g. "Co ke Zero" vs. "Coke Zero")

---

## [0.0.5] – 2025-05-05

### 📚 Documentation

- Added comprehensive `dartdoc` comments for all model classes in `lib/src/receipt_models.dart`

---

## [0.0.4] – 2025-05-04

### ✨ Added

- **Optimizer Module**: Introduced a new optimizer module to enhance the performance and efficiency of the receipt
  recognition pipeline
- **Product Name Detection Enhancements**: Implemented advanced techniques for more accurate extraction and recognition
  of product names from receipts

### 🛠️ Changed

- **Company Regex Enhancements**: Updated regular expressions related to company name detection to enhance parsing
  accuracy

### 🐛 Fixed

- **Product Name Extraction**: Resolved issues where certain product names were not being accurately extracted due to
  inconsistent formatting
- **Company Name Detection**: Fixed bugs in the regular expressions that led to incorrect company name identification in
  specific receipt formats
- **Parser Stability**: Addressed edge cases in the parser that previously caused errors when processing receipts with
  uncommon layouts

---

## [0.0.3] - 2025-04-24

### ✅ Added

- **Unit Tests**: Introduced unit tests to enhance code reliability and ensure consistent behavior across updates

### 🛠️ Changed

- **Parser Refactoring**:
    - Moved parsing methods to a dedicated parser module, improving code organization and maintainability
    - Converted parser methods to static, facilitating easier access without instantiating classes

### 🐛 Fixed

- **Company Name Recognition**: Refined regular expressions related to company name detection, enhancing accuracy in
  identifying company names from receipts

---

## [0.0.2] – 2025-04-23

### ✨ Added

- `ReceiptWidget`: A customizable Flutter widget that displays parsed receipt data in a layout resembling a real
  supermarket receipt
- Advanced example demonstrating integration with a live video feed using the `camera` package

### 🛠️ Changed

- Updated `README.md` to include usage examples and details about models etc.

### 🐛 Fixed

- Minor bug fixes and performance improvements

---

## [0.0.1] – 2025-04-20

### ✨ Added

- Initial release of `receipt_recognition`.
- Core functionality to process images of receipts and extract structured data such as store name, items, and total
  amount using Google's ML Kit
- Support for both Android and iOS platforms
