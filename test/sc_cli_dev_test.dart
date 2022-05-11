import 'package:sc_cli/sc_cli_dev.dart';
import 'package:test/test.dart';

void main() {
  group('Dev CLI', () {
    // For now, just ensure sc_cli_dev.dart compiles.
    test('Eval', () {
      expect(startDevReplServerIsolateFn, TypeMatcher<Function>());
    });
  });
}
