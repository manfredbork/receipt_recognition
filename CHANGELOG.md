
# Changelog

All notable changes to this project will be documented in this file.

## [0.0.5] – 2025-05-05

### Added
- Added comprehensive `dartdoc` comments for all model classes in `lib/src/receipt_models.dart`

---

## [0.0.4] – 2025-05-04

### Added

- **Optimizer Module**: Introduced a new optimizer module to enhance the performance and efficiency of the receipt recognition pipeline.
- **Product Name Detection Enhancements**: Implemented advanced techniques for more accurate extraction and recognition of product names from receipts.

### Changed

- **Company Regex Enhancements**: Updated regular expressions related to company name detection to enhance parsing accuracy.

### Fixed

- **Product Name Extraction**: Resolved issues where certain product names were not being accurately extracted due to inconsistent formatting.
- **Company Name Detection**: Fixed bugs in the regular expressions that led to incorrect company name identification in specific receipt formats.
- **Parser Stability**: Addressed edge cases in the parser that previously caused errors when processing receipts with uncommon layouts.

---

## [0.0.3] - 2025-04-24

### Added

- **Unit Tests**: Introduced unit tests to enhance code reliability and ensure consistent behavior across updates.

### Changed

- **Parser Refactoring**:
    - Moved parsing methods to a dedicated parser module, improving code organization and maintainability.
    - Converted parser methods to static, facilitating easier access without instantiating classes.

### Fixed

- **Company Name Recognition**: Refined regular expressions related to company name detection, enhancing accuracy in identifying company names from receipts.

---

## [0.0.2] – 2025-04-23

### Added
- `ReceiptWidget`: A customizable Flutter widget that displays parsed receipt data in a layout resembling a real supermarket receipt.
- Advanced example demonstrating integration with a live video feed using the `camera` package.

### Changed
- Updated `README.md` to include usage examples and details about models etc.

### Fixed
- Minor bug fixes and performance improvements.

---

## [0.0.1] – 2025-04-20

### Added
- Initial release of `receipt_recognition`.
- Core functionality to process images of receipts and extract structured data such as store name, items, and total amount using Google's ML Kit.
- Support for both Android and iOS platforms.
