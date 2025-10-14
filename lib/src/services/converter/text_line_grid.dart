import 'dart:collection';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// A sparse 2D grid where each occupied cell stores a mutable `List<TextLine>`.
///
/// Cells are created lazily on first write, so memory usage stays low when the
/// grid is large but mostly empty. Reading a never-written cell yields an
/// empty, unmodifiable list.
///
/// Typical operations:
/// - `addLine(row, col, line)` to append a line to a cell (auto-creates the cell)
/// - `linesAt(row, col)` to read a cell’s list (unmodifiable view)
/// - `removeLine(row, col, line)` / `removeAt(row, col, index)`
/// - `clearCell(row, col)` / `clearRow(row)` / `clearColumn(col)` / `clearAll()`
/// - iterate all content via `flattened` or `forEachCell`
///
/// Example:
/// ```dart
/// final grid = TextLineGrid();
/// grid.addLine(2, 5, someTextLine);
/// final cell = grid.linesAt(2, 5); // unmodifiable view
/// ```
class TextLineGrid {
  /// Backing map: `row -> (col -> List<TextLine>)`.
  final Map<int, Map<int, List<TextLine>>> _cells =
      <int, Map<int, List<TextLine>>>{};

  /// Approximate count of non-empty rows currently stored.
  int get rowCountApprox => _cells.length;

  /// Returns true if no cells are stored (i.e., the grid is entirely empty).
  bool get isEmpty => _cells.isEmpty;

  /// Returns an unmodifiable view of the list at `(row, col)`.
  ///
  /// For cells that were never written, returns an empty unmodifiable list.
  List<TextLine> linesAt(int row, int col) =>
      UnmodifiableListView<TextLine>(_cells[row]?[col] ?? const <TextLine>[]);

  /// Returns the current length of the list at `(row, col)`.
  ///
  /// Returns `0` for cells that were never written.
  int cellLength(int row, int col) => _cells[row]?[col]?.length ?? 0;

  /// Returns `true` if the grid has a stored list at `(row, col)`.
  ///
  /// Note: a cell is removed from storage when it becomes empty.
  bool hasCell(int row, int col) => _cells[row]?.containsKey(col) ?? false;

  /// Adds `line` to the cell at `(row, col)`, creating the cell if needed.
  void addLine(int row, int col, TextLine line) {
    final rowMap = _cells.putIfAbsent(row, () => <int, List<TextLine>>{});
    final list = rowMap.putIfAbsent(col, () => <TextLine>[]);
    list.add(line);
  }

  /// Adds all `lines` to the cell at `(row, col)`, creating the cell if needed.
  void addAll(int row, int col, Iterable<TextLine> lines) {
    if (lines.isEmpty) return;
    final rowMap = _cells.putIfAbsent(row, () => <int, List<TextLine>>{});
    final list = rowMap.putIfAbsent(col, () => <TextLine>[]);
    list.addAll(lines);
  }

  /// Removes the first occurrence of `line` from the cell at `(row, col)`.
  ///
  /// Returns `true` if a line was removed; otherwise `false`.
  /// Automatically prunes the cell/row from storage if it becomes empty.
  bool removeLine(int row, int col, TextLine line) {
    final list = _cells[row]?[col];
    if (list == null) return false;
    final removed = list.remove(line);
    _pruneIfEmpty(row, col);
    return removed;
  }

  /// Removes and returns the line at `index` from the cell at `(row, col)`.
  ///
  /// Throws if the cell does not exist or `index` is out of range.
  /// Automatically prunes the cell/row from storage if it becomes empty.
  TextLine removeAt(int row, int col, int index) {
    final rowMap = _cells[row];
    if (rowMap == null || !rowMap.containsKey(col)) {
      throw StateError('Cell ($row,$col) does not exist.');
    }
    final removed = rowMap[col]!.removeAt(index);
    _pruneIfEmpty(row, col);
    return removed;
  }

  /// Clears the list at `(row, col)`. Does nothing if the cell does not exist.
  ///
  /// Automatically prunes the cell/row from storage.
  void clearCell(int row, int col) {
    final list = _cells[row]?[col];
    if (list == null) return;
    list.clear();
    _pruneIfEmpty(row, col, alreadyCleared: true);
  }

  /// Clears all cells in the given `row`. Does nothing if the row does not exist.
  void clearRow(int row) {
    final rowMap = _cells[row];
    if (rowMap == null) return;
    rowMap.clear();
    _cells.remove(row);
  }

  /// Clears all cells in the given `col` across all existing rows.
  void clearColumn(int col) {
    final rowsToDelete = <int>[];
    _cells.forEach((r, rowMap) {
      rowMap.remove(col);
      if (rowMap.isEmpty) rowsToDelete.add(r);
    });
    for (final r in rowsToDelete) {
      _cells.remove(r);
    }
  }

  /// Clears all stored cells and rows.
  void clearAll() => _cells.clear();

  /// Calls `visit(row, col, list)` for each occupied cell with its triple.
  ///
  /// The provided `list` is the **mutable** internal list; do not hold it
  /// beyond the callback unless you defensively copy it.
  void forEachCell(void Function(int row, int col, List<TextLine> list) visit) {
    _cells.forEach((r, rowMap) {
      rowMap.forEach((c, list) => visit(r, c, list));
    });
  }

  /// Returns a lazy iterable of all lines in all stored cells (row-major by map order).
  Iterable<TextLine> get flattened sync* {
    for (final rowMap in _cells.values) {
      for (final list in rowMap.values) {
        yield* list;
      }
    }
  }

  /// Returns the set of row indices currently stored.
  Set<int> get occupiedRows => _cells.keys.toSet();

  /// Returns the set of column indices currently stored for `row`, or empty set if none.
  Set<int> occupiedCols(int row) => _cells[row]?.keys.toSet() ?? <int>{};

  /// Removes the cell at `(row, col)` from storage if it is empty, and removes
  /// the row if it has no remaining cells.
  void _pruneIfEmpty(int row, int col, {bool alreadyCleared = false}) {
    final rowMap = _cells[row];
    if (rowMap == null) return;
    final list = rowMap[col];
    final empty = alreadyCleared || (list != null && list.isEmpty);
    if (empty) {
      rowMap.remove(col);
      if (rowMap.isEmpty) {
        _cells.remove(row);
      }
    }
  }
}
