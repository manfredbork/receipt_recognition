import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Builds a directed graph of recognized receipt positions and determines
/// the most likely correct order of items using topological sorting.
///
/// The graph is constructed from the most trustworthy position of each
/// [PositionGroup]. Edges are added based on fuzzy text similarity,
/// timestamps, and pricing heuristics.
class PositionGraph {
  /// The list of position groups to be resolved into a linear order.
  final List<PositionGroup> groups;

  /// Directed adjacency list used for graph traversal.
  final Map<RecognizedPosition, Set<RecognizedPosition>> adjacency = {};

  /// All nodes (positions) included in the graph.
  final Set<RecognizedPosition> allPositions = {};

  /// Maximum fuzzy match ratio before items are considered similar
  /// and not linked.
  final int fuzzyThreshold;

  /// Constructs a [PositionGraph] using the most trustworthy position
  /// from each group as graph nodes.
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

  /// Returns a list of recognized positions sorted in likely receipt order.
  ///
  /// Performs a topological sort on the graph. If a cycle is detected or
  /// the graph is incomplete, a fallback sort is used.
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

  /// Fallback sort used when topological sorting fails (e.g. due to cycles).
  ///
  /// Sorts positions by timestamp, then by positionIndex (scan order),
  /// trustworthiness, and fuzzy distinctiveness.
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
