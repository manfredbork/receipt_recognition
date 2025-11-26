import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:receipt_recognition/src/models/index.dart';

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
      '${p.product.text}|${p.price.value.toStringAsFixed(2)}|${p.timestamp.millisecondsSinceEpoch}';

  /// Generates a compact identifier string for a [RecognizedGroup],
  /// including its hash and current member count.
  static String grpKey(RecognizedGroup g) =>
      'G${g.hashCode.toRadixString(16)}(${g.members.length})';

  /// Logs a detailed summary of the [receipt] and optional its [validation] result.
  ///
  /// Prints store, positions, calculated sum, detected sum, and final sum label for debugging.
  static void logReceipt(
    RecognizedReceipt receipt, {
    ReceiptValidationResult? validation,
  }) {
    if (receipt.isNotEmpty) {
      if (validation != null) {
        debugPrint('✅ Validation status: ${validation.status}');
        debugPrint('💬 Message: ${validation.message}');
      }
      debugPrint('🏪 Supermarket: ${receipt.store?.formattedValue ?? 'N/A'}');
      debugPrint(
        '📅 Purchase datetime: ${receipt.purchaseDate?.formattedValue ?? 'N/A'}',
      );
      const int padFullWidth = 30;
      final int padHalfWidth = padFullWidth ~/ 2;
      for (final position in receipt.positions) {
        final product = position.product.normalizedText;
        final price = position.price.formattedValue;
        final confidence = position.confidence;
        final stability = position.stability;
        final distribution =
            position.product.alternativeTextPercentages.entries
                .map((e) => '${e.key} ${e.value}%')
                .toList();
        debugPrint(
          '${'🛍️  $product'.padRight(padFullWidth)}${'💰  $price'.padRight(padHalfWidth)}'
          '${'🗄  ${position.product.productGroup}'.padRight(padHalfWidth)}'
          '${'🏷️  ${position.product.unit.quantity.formattedValue} × ${position.product.unit.price.formattedValue}'.padRight(padHalfWidth)}'
          '${'📈  $confidence % Confidence'.padRight(padFullWidth)}'
          '${'⚖️  $stability % Stability'.padRight(padFullWidth)}'
          '${'📊  Distribution: $distribution '.padRight(padFullWidth)}',
        );
      }
      debugPrint(
        '🧮 Calculated total: ${receipt.calculatedTotal.formattedValue}',
      );
      debugPrint('🧾 Total in receipt: ${receipt.total?.formattedValue}');
      debugPrint(
        '📌 Optimizer final total label: ${receipt.totalLabel?.formattedValue}',
      );
    }
  }
}
