import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fw;

/// OCR text utilities (stateless).
final class ReceiptOcrText {
  /// Normalizes OCR text (lowercase, lookalikes → letters, keep [a-z0-9], collapse spaces).
  static String normalize(String input) {
    final s = input.toLowerCase();
    final buf = StringBuffer();
    for (final uc in s.codeUnits) {
      final c = String.fromCharCode(uc);
      switch (c) {
        case '0':
          buf.write('o');
          break;
        case '1':
        case 'i':
          buf.write('l');
          break;
        case '5':
          buf.write('s');
          break;
        case '8':
          buf.write('b');
          break;
        default:
          if (RegExp(r'[a-z0-9]').hasMatch(c)) {
            buf.write(c);
          } else {
            buf.write(' ');
          }
      }
    }
    return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Fuzzy similarity for OCR strings in [0,1] (best of tokenSet/sort/partial).
  static double similarity(String a, String b) {
    final x = normalize(a), y = normalize(b);
    if (x.isEmpty && y.isEmpty) return 1.0;
    if (x.isEmpty || y.isEmpty) return 0.0;
    final r1 = fw.tokenSetRatio(x, y);
    final r2 = fw.tokenSortRatio(x, y);
    final r3 = fw.partialRatio(x, y);
    final best = r1 > r2 ? (r1 > r3 ? r1 : r3) : (r2 > r3 ? r2 : r3);
    return best / 100.0;
  }

  /// Token set (≥ [minLen] chars) from OCR-normalized text.
  static Set<String> tokens(String input, {int minLen = 2}) {
    final x = normalize(input);
    return x.split(' ').where((t) => t.length >= minLen).toSet();
  }

  /// First token from OCR-normalized text (brand proxy) or empty string.
  static String brand(String input) {
    final x = normalize(input).split(' ').where((t) => t.isNotEmpty).toList();
    return x.isEmpty ? '' : x.first;
  }
}
