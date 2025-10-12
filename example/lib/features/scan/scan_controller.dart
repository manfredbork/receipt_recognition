import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

class ScanController extends ChangeNotifier {
  ScanController() : _lastReceipt = RecognizedReceipt.empty() {
    _recognizer = ReceiptRecognizer(
      onScanUpdate: _onScanUpdate,
      onScanComplete: _onScanComplete,
      onScanTimeout: _onScanTimeout,
    );
  }

  late final ReceiptRecognizer _recognizer;

  RecognizedReceipt _lastReceipt;
  RecognizedScanProgress? _progress;
  bool _busy = false;

  RecognizedReceipt get lastReceipt => _lastReceipt;

  RecognizedScanProgress? get progress => _progress;

  double get progressPercent =>
      (_progress?.estimatedPercentage ?? 0).toDouble();

  bool get busy => _busy;

  /// Feed one frame; returns the latest recognized receipt snapshot.
  /// Caller decides whether to navigate (receipt.isValid && receipt.isConfirmed).
  Future<RecognizedReceipt> processImage(InputImage image) async {
    if (_busy) return _lastReceipt;

    _busy = true;
    try {
      _lastReceipt = await _recognizer.processImage(image);
      notifyListeners();
      return _lastReceipt;
    } catch (e) {
      debugPrint('processImage error: $e');
      return _lastReceipt;
    } finally {
      _busy = false;
    }
  }

  /// Optional manual accept: promotes current merged receipt to accepted.
  Future<RecognizedReceipt> acceptCurrent() async {
    final accepted = _recognizer.acceptReceipt(_lastReceipt);
    _lastReceipt = accepted;
    notifyListeners();
    return accepted;
  }

  Future<void> disposeAsync() => _recognizer.close();

  void _onScanUpdate(RecognizedScanProgress p) {
    _progress = p;

    final merged = p.mergedReceipt;
    if (merged != null) {
      _lastReceipt = merged;
    }
    notifyListeners();
  }

  void _onScanComplete(RecognizedReceipt r) {
    _lastReceipt = r;
    notifyListeners();
  }

  void _onScanTimeout() {
    notifyListeners();
  }
}
