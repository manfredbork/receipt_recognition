import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

class PositionGraph {
  final List<PositionGroup> groups;
  final Map<RecognizedPosition, Set<RecognizedPosition>> adjacency = {};
  final Set<RecognizedPosition> allPositions = {};
  final int fuzzyThreshold;

  PositionGraph(this.groups, {this.fuzzyThreshold = 90}) {
    for (final group in groups) {
      final pos = group.mostTrustworthyPosition();
      allPositions.add(pos);
      adjacency.putIfAbsent(pos, () => {});
    }

    for (final a in allPositions) {
      for (final b in allPositions) {
        if (a == b) continue;
        if (_shouldLink(a, b)) {
          adjacency[a]!.add(b);
        }
      }
    }
  }

  bool _shouldLink(RecognizedPosition a, RecognizedPosition b) {
    if (a.timestamp.isAfter(b.timestamp)) return false;
    if (a.product.value == b.product.value) return false;
    if (b.price.value < 0 || a.price.value < 0) return false;
    final score = ratio(a.product.value, b.product.value);
    return score < fuzzyThreshold;
  }

  List<RecognizedPosition> resolveOrder() {
    final visited = <RecognizedPosition>{};
    final visiting = <RecognizedPosition>{};
    final sorted = <RecognizedPosition>[];

    bool visit(RecognizedPosition node) {
      if (visited.contains(node)) return true;
      if (visiting.contains(node)) return false;
      visiting.add(node);

      for (final neighbor in adjacency[node]!) {
        if (!visit(neighbor)) return false;
      }

      visiting.remove(node);
      visited.add(node);
      sorted.add(node);
      return true;
    }

    for (final node in allPositions) {
      if (!visited.contains(node)) {
        if (!visit(node)) {
          return _fallbackSort();
        }
      }
    }

    return sorted.reversed.toList();
  }

  List<RecognizedPosition> _fallbackSort() {
    final sorted = allPositions.toList();

    sorted.sort((a, b) {
      final tsCompare = a.timestamp.compareTo(b.timestamp);
      if (tsCompare != 0) return tsCompare;

      final indexCompare = a.positionIndex.compareTo(b.positionIndex);
      if (indexCompare != 0) return indexCompare;

      final trustDiff = b.trustworthiness.compareTo(a.trustworthiness);

      if (trustDiff != 0) return trustDiff;

      final fuzzyA = allPositions
          .where((other) => other != a)
          .map((other) => ratio(a.product.value, other.product.value))
          .fold<int>(0, (sum, r) => sum + r);

      final fuzzyB = allPositions
          .where((other) => other != b)
          .map((other) => ratio(b.product.value, other.product.value))
          .fold<int>(0, (sum, r) => sum + r);

      return fuzzyB.compareTo(fuzzyA);
    });

    return sorted;
  }
}
