import 'package:sc_cli/src/sc_util.dart';
import 'package:test/test.dart';

void main() {
  test('partition, uniform', () {
    expect(partitionAll(3, [1, 2, 3, 4, 5, 6]), [
      [1, 2, 3],
      [4, 5, 6]
    ]);
  });
  test('partition, ragged', () {
    expect(partitionAll(3, [1, 2, 3, 4, 5, 6, 7]), [
      [1, 2, 3],
      [4, 5, 6],
      [7]
    ]);
  });
  test('levenshtein distance', () {
    expect("foo".levenshteinDistance("for"), 1);
    expect("foo".levenshteinDistance("far"), 2);
    expect("foo".levenshteinDistance("car"), 3);
  });
}
