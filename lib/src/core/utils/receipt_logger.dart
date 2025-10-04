import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Centralized logger for receipt recognition.
///
/// Provides structured JSON logs and human-readable summaries of optimized
/// receipts. Logging is only active in debug mode when [kRecogVerbose] is true.
/// Includes helpers for generating compact keys for positions and groups.
final class ReceiptLogger {
  /// Global toggle to enable or disable verbose recognition logs.
  static bool kRecogVerbose = false;

  /// Writes a structured one-liner log entry if verbose logging is enabled.
  ///
  /// Logs are JSON-encoded for easy parsing and are only printed in debug mode.
  static void log(String cat, Map<String, Object?> data) {
    if (!kRecogVerbose || !kDebugMode) return;
    debugPrint('🧾[$cat] ${jsonEncode(data)}');
  }

  /// Generates a compact identifier string for a [RecognizedPosition],
  /// including product text, price, and timestamp.
  static String posKey(RecognizedPosition p) =>
      '${p.product.normalizedText}|${p.price.value.toStringAsFixed(2)}|${p.timestamp.millisecondsSinceEpoch}';

  /// Generates a compact identifier string for a [RecognizedGroup],
  /// including its hash and current member count.
  static String grpKey(RecognizedGroup g) =>
      'G${g.hashCode.toRadixString(16)}(${g.members.length})';

  /// Logs a detailed summary of the [optimizedReceipt] and its [validation] result.
  ///
  /// Prints company, positions, calculated sum, detected sum, and final sum label for debugging.
  static void logReceipt(
    RecognizedReceipt optimizedReceipt,
    ReceiptValidationResult validation,
  ) {
    if (optimizedReceipt.positions.isNotEmpty) {
      debugPrint('🧾${'-' * 48}');
      debugPrint('✅ Validation status: ${validation.status}');
      debugPrint('💬 Message: ${validation.message}');
      debugPrint('🧾${'-' * 48}');
      debugPrint('🏪 Supermarket: ${optimizedReceipt.company?.value ?? 'N/A'}');
      const int padFullWidth = 30;
      final int padHalfWidth = (padFullWidth / 2).toInt();
      for (final position in optimizedReceipt.positions) {
        final product = position.product.normalizedText;
        final price = position.price.formattedValue;
        final confidence = position.confidence;
        final stability = position.stability;
        debugPrint(
          '${'🛍️  $product'.padRight(padFullWidth)}${'💰  $price'.padRight(padHalfWidth)}'
          '${'📈  $confidence % Confidence'.padRight(padHalfWidth)}'
          '${'⚖️  $stability % Stability'.padRight(padHalfWidth)}',
        );
      }
      debugPrint(
        '🧮 Calculated sum: ${optimizedReceipt.calculatedSum.formattedValue}',
      );
      debugPrint('🧾 Sum in receipt: ${optimizedReceipt.sum?.formattedValue}');
      debugPrint(
        '📌 Optimizer final sum label: ${optimizedReceipt.sumLabel?.formattedValue}',
      );
    }
  }
}
