import 'package:receipt_recognition/receipt_recognition.dart';

abstract class Optimizer {
  void init();

  RecognizedReceipt optimize(RecognizedReceipt receipt);

  void close();
}

final class ReceiptOptimizer implements Optimizer {
  final List<RecognizedGroup> _groups = [];
  final List<RecognizedCompany> _companies = [];
  final List<RecognizedSum> _sums = [];
  final int _maxCacheSize;

  bool _shouldInitialize;

  ReceiptOptimizer({int maxCacheSize = 20})
    : _maxCacheSize = maxCacheSize,
      _shouldInitialize = false;

  @override
  void init() {
    _shouldInitialize = true;
  }

  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt) {
    if (_shouldInitialize) {
      _groups.clear();
      _companies.clear();
      _sums.clear();
      _shouldInitialize = false;
    }

    if (receipt.company != null) {
      _companies.add(receipt.company!);
    }

    if (_companies.length >= _maxCacheSize) {
      _companies.removeAt(0);
    }

    if (receipt.sum != null) {
      _sums.add(receipt.sum!);
    }

    if (_sums.length >= _maxCacheSize) {
      _sums.removeAt(0);
    }

    if (receipt.company == null && _companies.isNotEmpty) {
      final company = ReceiptNormalizer.sortByFrequency(
        _companies.map((c) => c.value).toList(),
      );
      receipt.company = _companies.last.copyWith(value: company.first);
    }

    if (receipt.sum == null && _companies.isNotEmpty) {
      final sum = ReceiptNormalizer.sortByFrequency(
        _sums.map((c) => c.formattedValue).toList(),
      );
      receipt.sum = _sums.last.copyWith(
        value: ReceiptFormatter.parse(sum.first),
      );
    }

    // TODO: Group logic

    return receipt;
  }

  @override
  void close() {
    _groups.clear();
    _companies.clear();
    _sums.clear();
    _shouldInitialize = false;
  }
}
