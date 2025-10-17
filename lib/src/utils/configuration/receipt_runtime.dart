import 'package:receipt_recognition/src/utils/configuration/index.dart';

/// Process-wide runtime that exposes the active options and tuning knobs.
final class ReceiptRuntime {
  ReceiptRuntime._();

  /// Global singleton instance.
  static final ReceiptRuntime instance = ReceiptRuntime._();

  /// Current effective options (merged user/defaults).
  ReceiptOptions _options = ReceiptOptions.defaults();

  /// Current effective options.
  static ReceiptOptions get options => instance._options;

  /// Current effective tuning (shortcut to options.tuning).
  static ReceiptTuning get tuning => options.tuning;

  /// Replace the active options globally.
  static void setOptions(ReceiptOptions options) {
    instance._options = options;
  }

  /// Run [fn] with [options] temporarily active.
  static T runWithOptions<T>(ReceiptOptions options, T Function() fn) {
    final prev = instance._options;
    instance._options = options;
    try {
      return fn();
    } finally {
      instance._options = prev;
    }
  }
}
