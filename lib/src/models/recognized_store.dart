import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';

/// Store name recognized from a receipt.
final class RecognizedStore extends RecognizedEntity<String> {
  /// Creates a store entity from [value] and [line].
  const RecognizedStore({required super.value, required super.line});

  /// Returns a copy with updated fields.
  RecognizedStore copyWith({String? value, TextLine? line}) =>
      RecognizedStore(value: value ?? this.value, line: line ?? this.line);

  @override
  String format(String value) => value.toUpperCase();
}

/// Company name recognized from a receipt.
final class RecognizedCompany extends RecognizedStore {
  /// Creates a company entity from [value] and [line].
  const RecognizedCompany({required super.value, required super.line});
}
