import 'recognized_position.dart';

class PositionGraph {
  final List<RecognizedPosition> positions;
  final Map<RecognizedPosition, Set<RecognizedPosition>> adj = {};

  PositionGraph(this.positions) {
    for (final pos in positions) {
      adj[pos] = {};
    }
    _buildEdges();
  }

  void _buildEdges() {
    for (int i = 0; i < positions.length; i++) {
      for (int j = i + 1; j < positions.length; j++) {
        final posA = positions[i];
        final posB = positions[j];
        final similarity = _similarity(posA, posB);
        if (similarity > 0.7) {
          if (posA.timestamp.isBefore(posB.timestamp)) {
            adj[posA]!.add(posB);
          } else {
            adj[posB]!.add(posA);
          }
        }
      }
    }
  }

  double _similarity(RecognizedPosition a, RecognizedPosition b) {
    final nameSimilarity = _stringSimilarity(a.product.value, b.product.value);
    final priceDiff = (a.price.value - b.price.value).abs();
    final priceSimilarity = priceDiff < 0.01 ? 1.0 : 0.0;
    return (nameSimilarity + priceSimilarity) / 2;
  }

  double _stringSimilarity(String a, String b) {
    if (a == b) return 1.0;
    return 0.0; // Replace with better algorithm if needed
  }

  List<RecognizedPosition> sort() {
    final visited = <RecognizedPosition>{};
    final onStack = <RecognizedPosition>{};
    final stack = <RecognizedPosition>[];
    bool hasCycle = false;

    void dfs(RecognizedPosition node) {
      if (hasCycle) return;
      visited.add(node);
      onStack.add(node);
      for (final neighbor in adj[node]!) {
        if (!visited.contains(neighbor)) {
          dfs(neighbor);
        } else if (onStack.contains(neighbor)) {
          hasCycle = true;
          return;
        }
      }
      onStack.remove(node);
      stack.add(node);
    }

    for (final node in positions) {
      if (!visited.contains(node)) {
        dfs(node);
      }
    }

    if (hasCycle) {
      positions.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return positions;
    }

    return stack.reversed.toList();
  }
}
