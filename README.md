# 📷 receipt_recognition

[![Pub Version](https://img.shields.io/pub/v/receipt_recognition)](https://pub.dev/packages/receipt_recognition)
[![Pub Points](https://img.shields.io/pub/points/receipt_recognition)](https://pub.dev/packages/receipt_recognition/score)
[![Likes](https://img.shields.io/pub/likes/receipt_recognition)](https://pub.dev/packages/receipt_recognition)
[![License](https://img.shields.io/github/license/manfredbork/receipt_recognition)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/manfredbork/receipt_recognition)](https://github.com/manfredbork/receipt_recognition/commits/main)

A Flutter package for scanning and extracting structured data from supermarket receipts using **Google's ML Kit**. Ideal for building expense tracking apps, loyalty programs, or any system needing receipt parsing.

---

## ✨ Features

- 🧾 Detect and extract text from printed receipts
- 🛒 Optimized for typical supermarket layouts
- 🔍 Identifies line items, totals, and store names
- ⚡ Fast and efficient ML Kit text recognition
- 📱 Works on Android and iOS
- 🔧 Easy API with callback support

---

## 🚀 Getting Started

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  receipt_recognition: ^<latest_version>
```

Then run:

```bash
flutter pub get
```

### Platform Setup

#### Android

Update `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

#### iOS

Update `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is needed to scan receipts.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Photo library access is needed to select receipt images.</string>
```

---

### 📦 Basic Usage

```dart
import 'package:flutter/material.dart';
import 'package:receipt_recognition/receipt_recognition.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

// Create a receipt recognizer
final receiptRecognizer = ReceiptRecognizer(
  singleScan: true,
  onScanComplete: (receipt) {
    // Handle the recognized receipt
    print('Company: ${receipt.company?.value}');
    print('Total: ${receipt.sum?.formattedValue}');
    
    for (final position in receipt.positions) {
      print('${position.product.formattedValue}: ${position.price.formattedValue}');
    }
  },
  onScanUpdate: (progress) {
    // Track scanning progress
    print('Scan progress: ${progress.estimatedPercentage}%');
    print('Added positions: ${progress.addedPositions.length}');
  },
);

// Process an image
Future<void> processReceiptImage(InputImage inputImage) async {
  final receipt = await receiptRecognizer.processImage(inputImage);
  if (receipt != null) {
    // Receipt was successfully recognized
  }
}

// Don't forget to close the receipt recognizer when done
@override
void dispose() {
  receiptRecognizer.close();
  super.dispose();
}
```

### 🎥 Advanced Example: Video Feed Integration

For an advanced use case, we provide an example of using this package with a video feed. You can integrate it with a camera feed (via a package like `camera`), and continuously scan receipts in real time.

Refer to the **[example app](example/lib/main.dart)** for an implementation that uses live camera data to recognize and process receipts as they appear in the frame.

---

## 🧠 Model Overview

| Class                | Description                                                       |
|----------------------|-------------------------------------------------------------------|
| `RecognizedReceipt`  | Represents a full parsed receipt with items, sum, and store name. |
| `RecognizedPosition` | A single line item on the receipt: product + price.               |
| `RecognizedProduct`  | Alphanumeric value for product.                                   |
| `RecognizedPrice`    | Numerical value for price.                                        |
| `RecognizedSum`      | Numerical value for sum.                                          |
| `RecognizedCompany`  | Specialized entity for the store name.                            |

---

## 🧾 Model Structure

```text
RecognizedReceipt
├── company: RecognizedCompany
│   └── value: String (e.g., "Walmart")
├── sum: RecognizedSum
│   └── value: num (e.g., 23.45)
└── positions: List<RecognizedPosition>
     ├── RecognizedPosition
     │   ├── product: RecognizedProduct
     │   │   └── value: "Milk"
     │   └── price: RecognizedPrice
     │       └── value: 2.49
     └── ...
```

---

## 📦 Release Notes

See the [CHANGELOG.md](CHANGELOG.md) for a complete list of updates and version history.

---

## 🔮 Roadmap

- [x] Product name normalization
- [x] Long receipt support and merging mechanism
- [ ] TSE detection and categorization
- [ ] Tax and discount detection
- [ ] Smart OCR region selection
- [ ] Multi-language receipt support

---

## 🤝 Contributing

Contributions, suggestions, and bug reports are welcome! Feel free to open an issue or PR.

---

## 📄 License

This package is released under the [MIT License](LICENSE).
