import 'dart:math';

List partitionAll(int itemsPerPartition, List list) {
  if (list.isEmpty) {
    return list;
  } else {
    var newList = [];
    var partList = [];
    var partIdx = 1;
    for (var item in list) {
      if (partIdx % itemsPerPartition == 0) {
        partList.add(item);
        newList.add(partList);

        partIdx = 1;
        partList = [];
      } else {
        partList.add(item);
        partIdx += 1;
      }
    }

    // Support non-uniform partitions
    if (partList.isNotEmpty) {
      newList.add(partList);
    }
    return newList;
  }
}

// ## Levenshtein Distance

// Adapted from https://github.com/Makepad-fr/dart_levenshtein/blob/master/lib/src/levenshtein_base.dart

/// An extension to get the tail of the string. Something like syntaxic sugar
/// to avoid substring every time.
extension on String {
  String get tail {
    return substring(1);
  }
}

/// Computes the minimum number of single-character edits (insertions, deletions or substitutions)
/// required to change the [str1] into the [str2]
Future<int> levenshteinDistance(String str1, String str2) async {
  return str1.levenshteinDistance(str2);
}

extension StringMatcher on String {
  /// Computes the minimum number of single-character edits (insertions, deletions or substitutions)
  /// required to change the current String into the [other]
  int levenshteinDistance(String other) {
    if (isEmpty) return other.length;
    if (other.isEmpty) return length;
    if (this[0] == other[0]) {
      return substring(1).levenshteinDistance(other.tail);
    } else {
      return 1 +
          [
            levenshteinDistance(other.substring(1)),
            substring(1).levenshteinDistance(other),
            substring(1).levenshteinDistance(other.substring(1))
          ].reduce(min);
    }
  }
}

/// Adapted from https://github.com/arhamcode/print_table/blob/master/lib/print_table.dart
String tableString(List<List<String>> models, List<String> header) {
  var retString = StringBuffer('');
  var cols = header.length;
  var colLength = List<int>.filled(cols, 0);
  if (models.any((model) => model.length != cols)) {
    throw Exception('Column\'s no. of each model does not match.');
  }

  //preparing colLength.
  for (var i = 0; i < cols; i++) {
    var _chunk = <String>[];
    _chunk.add(header[i]);
    for (var model in models) {
      _chunk.add(model[i]);
    }
    colLength[i] = ([for (var c in _chunk) c.length]..sort()).last;
  }
  // here we got prepared colLength.

  String fillSpace(int maxSpace, String text) {
    return text.padLeft(maxSpace) + ' | ';
  }

  void addRow(List<String> model, List<List<String>> row) {
    var l = <String>[];
    for (var i = 0; i < cols; i++) {
      var max = colLength[i];
      l.add(fillSpace(max, model[i]));
    }
    row.add(l);
  }

  var rowList = <List<String>>[];
  addRow(header, rowList);
  var topBar = List<String>.generate(cols, (i) => '-' * colLength[i]);
  addRow(topBar, rowList);
  for (final model in models) {
    addRow(model, rowList);
  }
  for (final row in rowList) {
    var rowText = row.join();
    rowText = rowText.substring(0, rowText.length - 2);
    retString.writeln(rowText);
  }

  return retString.toString();
}
