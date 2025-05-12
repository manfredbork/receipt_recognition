
# 📷 receipt_recognition

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
import 'package:receipt_recognition/receipt_recognition.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

final receiptRecognizer = ReceiptRecognizer(
  videoFeed: false,
  scanTimeout: Duration(seconds: 10),
  onScanTimeout: () {
    print('Scan timed out.');
  },
  onScanComplete: (receipt) {
    print('Scan complete! Store: ${receipt.company?.formattedValue}');
    print('Total: ${receipt.sum?.formattedValue}');
  },
  onScanUpdate: (progress) {
    if (progress.estimatedPercentage != null) {
      print('In-progress scan: ${progress.estimatedPercentage}% detected so far.');
    }
  },
);

// Load an image (from file, camera, etc.)
final inputImage = InputImage.fromFilePath('path/to/receipt.jpg');

// Process the image
final receipt = await receiptRecognizer.processImage(inputImage);

if (receipt != null) {
  print('Store: ${receipt.company?.formattedValue}');
  for (final item in receipt.positions) {
    print('Product: ${item.product.formattedValue}, Price: ${item.price.formattedValue}');
  }
  print('Total: ${receipt.sum?.formattedValue}');
}
```

### 🎥 Advanced Example: Video Feed Integration

For an advanced use case, we provide an example of using this package with a video feed. You can integrate it with a camera feed (via a package like `camera`), and continuously scan receipts in real time.

Refer to the **[example app](example/lib/main.dart)** for an implementation that uses live camera data to recognize and process receipts as they appear in the frame.

---

### 🧹 Clean Up

```dart
await receiptRecognizer.close();
```

---

## 🧠 Model Overview

| Class                | Description                                                       |
|----------------------|-------------------------------------------------------------------|
| `RecognizedReceipt`  | Represents a full parsed receipt with items, sum, and store name. |
| `RecognizedPosition` | A single line item on the receipt: product + price.               |
| `RecognizedProduct`  | Alphanumeric value for product.                                   |
| `RecognizedPrice`    | Numerical value for price.                                        |
| `RecognizedSum`      | Numerical value for sum.                                          |
| `RecognizedSumLabel` | Represents the detected label for the sum.                        |
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

## 🔮 Roadmap

- [x] Product name normalization
- [ ] Long receipt support and merging mechanism
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
