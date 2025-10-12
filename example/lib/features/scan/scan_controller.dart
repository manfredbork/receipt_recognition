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

  double _bestPercent = 0;

  double get bestPercent => _bestPercent;

  void resetBestPercent() {
    _bestPercent = 0;
    notifyListeners();
  }

  RecognizedReceipt get lastReceipt => _lastReceipt;

  double get progressPercent =>
      (_progress?.estimatedPercentage ?? 0).toDouble();

  RecognizedScanProgress? get progress => _progress;

  bool get busy => _busy;

  Future<RecognizedReceipt> processImage(InputImage image) async {
    if (_busy) return _lastReceipt;

    _busy = true;
    try {
      _lastReceipt = await _recognizer.processImage(image);
      notifyListeners();
      return _lastReceipt;
    } catch (e) {
      return _lastReceipt;
    } finally {
      _busy = false;
    }
  }

  Future<RecognizedReceipt> acceptCurrent() async {
    final accepted = _recognizer.acceptReceipt(_lastReceipt);
    _lastReceipt = accepted;
    _bestPercent = _bestPercent < 100 ? 100 : _bestPercent;
    notifyListeners();
    return accepted;
  }

  Future<void> disposeAsync() => _recognizer.close();

  void clearOverlay() {
    _progress = null;
    notifyListeners();
  }

  void _onScanUpdate(RecognizedScanProgress p) {
    _progress = p;
    final merged = p.mergedReceipt;
    if (merged != null) _lastReceipt = merged;
    notifyListeners();
  }

  void _onScanComplete(RecognizedReceipt r) {
    _lastReceipt = r;
    if (_bestPercent < 100) _bestPercent = 100;
    notifyListeners();
  }

  void _onScanTimeout() {
    notifyListeners();
  }
}
