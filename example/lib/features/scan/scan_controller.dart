import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Controller that orchestrates live scanning and exposes scan state.
class ScanController extends ChangeNotifier {
  late final ReceiptRecognizer _recognizer;
  final int _nearlyCompleteThreshold = 90;

  RecognizedScanProgress _progress = RecognizedScanProgress.empty();
  RecognizedReceipt _lastReceipt;
  int _bestPercent = 0;
  bool _busy = false;
  bool _manuallyAccepted = false;

  /// Creates a controller and wires recognition callbacks.
  ScanController() : _lastReceipt = RecognizedReceipt.empty() {
    _recognizer = ReceiptRecognizer(
      nearlyCompleteThreshold: _nearlyCompleteThreshold,
      onScanUpdate: _onScanUpdate,
      onScanComplete: _onScanComplete,
      onScanTimeout: _onScanTimeout,
    );
  }

  /// Current best recognized receipt snapshot.
  RecognizedReceipt get receipt => _lastReceipt;

  /// Current frame delta positions (added and updated).
  List<RecognizedPosition> get positions =>
      _progress.addedPositions + _progress.updatedPositions;

  /// Threshold at which the result is considered nearly complete.
  int get nearlyCompleteThreshold => _nearlyCompleteThreshold;

  /// Highest observed completeness percentage.
  int get bestPercent => _bestPercent;

  /// Indicates whether processing is ongoing.
  bool get isBusy => _busy;

  /// True when the receipt is finalized or manually accepted.
  bool get isAccepted =>
      (receipt.isValid && receipt.isConfirmed) || _manuallyAccepted;

  /// Resets the best completeness percentage.
  void resetBestPercent() {
    _bestPercent = 0;
    notifyListeners();
  }

  /// Processes a single input image and updates state.
  Future<void> processImage(InputImage image) async {
    if (isBusy || isAccepted) return;

    _busy = true;
    try {
      _lastReceipt = await _recognizer.processImage(image);
      notifyListeners();
      return;
    } catch (e) {
      return;
    } finally {
      _busy = false;
    }
  }

  /// Accepts the current receipt and marks scanning as complete.
  Future<void> acceptCurrent() async {
    _lastReceipt = _recognizer.acceptReceipt(_lastReceipt);
    _bestPercent = 100;
    _manuallyAccepted = true;
    _busy = false;
    notifyListeners();
  }

  /// Disposes underlying recognizer resources asynchronously.
  Future<void> disposeAsync() => _recognizer.close();

  /// Callback: updates progress and merges the latest snapshot.
  void _onScanUpdate(RecognizedScanProgress p) {
    if (isAccepted) return;
    _progress = p;
    _bestPercent =
        p.estimatedPercentage > bestPercent
            ? p.estimatedPercentage
            : bestPercent;
    _lastReceipt = p.mergedReceipt;
    notifyListeners();
  }

  /// Callback: sets the final receipt when scanning completes.
  void _onScanComplete(RecognizedReceipt r) {
    if (isAccepted) return;
    _lastReceipt = r;
    if (_bestPercent < 100) _bestPercent = 100;
    notifyListeners();
  }

  /// Callback: accepts the current snapshot on timeout.
  void _onScanTimeout(RecognizedReceipt r) {
    if (isAccepted) return;
    _lastReceipt = r;
    acceptCurrent();
  }
}
