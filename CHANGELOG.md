# Changelog

All notable changes to this project will be documented in this file.

## [0.1.4] - 2025-09-20

### 🐛 Fixed
- **ReceiptParser**: Checking `minValidScans` on successful scan

### 🛠️ Changed
- **ReceiptNormalizer**: Simplified normalization logic

---

## [0.1.3] - 2025-09-19

### 🐛 Fixed
- **ReceiptRecognizer**: Fixed scan counter reset issue that was preventing proper scan completion
- **iOS Deployment**: Updated minimum iOS deployment target to 13.0 for compatibility

### 🛠️ Changed
- **ReceiptRecognizer**: Increased default `minValidScans` from 3 to 5 for more reliable scanning

### 🧩 Notes
- No breaking API changes
- Improved scanning stability and iOS deployment compatibility

---

## [0.1.2] - 2025-09-18

### 🐛 Fixed
- **Scan Validation**: Fixed the issue where scans could complete prematurely before reaching the minimum valid scan count
- **Match Percentage Calculation**: Corrected calculation logic for sum match percentage to use actual values instead of scan-weighted values
- **Ignore Keywords**: Added "Subtotal" to the list of keywords to ignore during product recognition

### 🛠️ Changed
- **Product Display**: Updated debug output to use normalized product text for better consistency
- **Recognition Accuracy**: Enhanced filtering of non-product lines to improve overall scan quality

### 🧩 Notes
- No API changes
- Improved scanning reliability and accuracy

---

## [0.1.1] - 2025-09-09

### 📚 Documentation
- Streamlined README to reflect current capabilities and scope.
- Removed outdated roadmap/status references and aligned wording with the present feature set.
- Clarified Implementation Status and reorganized sections for better readability.
- Minor copyedits for consistency (terminology, headings, and formatting).

### 🧩 Notes
- No API changes.
- No functional changes to recognition logic.

---

## [0.1.0] - 2025-06-06

### ✨ Added

* **Stable Sum Detection**: The scanner now identifies the most likely total amount by combining confidence and position tracking across multiple frames.
* **Live Bounding Boxes**: Detected receipt items are now outlined live on the camera preview, making it easier to see what's recognized in real time.

### 🛠️ Changed

* **Metadata Filtering**: The engine is better at ignoring irrelevant lines like footer notes or fiscal metadata, keeping the product list clean.
* **Enhanced Merge Logic**: Optimized how multi-frame receipts are combined, improving structure and reliability even in fragmented scans.

### 🐛 Fixed

* **Incorrect Totals**: Fixed an issue where prices from unrelated lines could falsely be interpreted as the receipt’s sum.
* **Layout Glitches**: Resolved occasional misalignments or line skips when processing longer or poorly lit receipts.

---

## [0.0.9] - 2025-06-03

### ✨ Added
- **Smarter Scan Confidence Filtering**: The recognition engine can now automatically ignore low-confidence items that might distort the total sum.
- **Status Getter**: Added a simple flag to detect if scanning is still in progress.
- **Improved Example App**: The example app now includes best practice instructions, live scan overlays, and a clearer UI for scanning and viewing receipts.

### 🛠️ Changed
- **Internal Optimizations**: Minor refactoring and documentation improvements to ensure better readability and maintainability of the code.

### 🐛 Fixed
- **Sum Calculation Accuracy**: Fixed cases where incorrect items could cause mismatches with the printed total.
- **Scan Stability**: Improved reliability of the scan process for varied receipt lengths and layouts.

---

## [0.0.8] - 2024-05-29

### ✨ Added
- **Manual Receipt Acceptance**: Added `acceptReceipt()` method to manually accept receipts with validation discrepancies
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
- **Pass static analysis**: Added curly braces to reach 50/50 points.

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
- **Optimizer Module**: Introduced a new optimizer module to enhance the performance and efficiency of the receipt recognition pipeline.
- **Product Name Detection Enhancements**: Implemented advanced techniques for more accurate extraction and recognition of product names from receipts.

### 🛠️ Changed
- **Company Regex Enhancements**: Updated regular expressions related to company name detection to enhance parsing accuracy.

### 🐛 Fixed
- **Product Name Extraction**: Resolved issues where certain product names were not being accurately extracted due to inconsistent formatting.
- **Company Name Detection**: Fixed bugs in the regular expressions that led to incorrect company name identification in specific receipt formats.
- **Parser Stability**: Addressed edge cases in the parser that previously caused errors when processing receipts with uncommon layouts.

---

## [0.0.3] - 2025-04-24

### ✅ Added
- **Unit Tests**: Introduced unit tests to enhance code reliability and ensure consistent behavior across updates.

### 🛠️ Changed
- **Parser Refactoring**:
  - Moved parsing methods to a dedicated parser module, improving code organization and maintainability.
  - Converted parser methods to static, facilitating easier access without instantiating classes.

### 🐛 Fixed
- **Company Name Recognition**: Refined regular expressions related to company name detection, enhancing accuracy in identifying company names from receipts.

---

## [0.0.2] – 2025-04-23

### ✨ Added
- `ReceiptWidget`: A customizable Flutter widget that displays parsed receipt data in a layout resembling a real supermarket receipt.
- Advanced example demonstrating integration with a live video feed using the `camera` package.

### 🛠️ Changed
- Updated `README.md` to include usage examples and details about models etc.

### 🐛 Fixed
- Minor bug fixes and performance improvements.

---

## [0.0.1] – 2025-04-20

### ✨ Added
- Initial release of `receipt_recognition`.
- Core functionality to process images of receipts and extract structured data such as store name, items, and total amount using Google's ML Kit.
- Support for both Android and iOS platforms.
