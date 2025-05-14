import 'recognized_receipt.dart';

abstract class Optimizer {
  Optimizer({required bool videoFeed});

  void init();

  RecognizedReceipt optimize(RecognizedReceipt receipt);

  void close();
}
