import 'package:sc_cli/src/sc_lang.dart';
import 'package:test/test.dart';

import 'package:sc_cli/src/sc_api.dart';
import 'package:sc_cli/src/sc_config.dart';

final client = ScLiveClient(getShortcutHost(), getShortcutApiToken());

ScEnv e() => ScEnv.fromMap(client, {});

void main() {
  // group('Live Client', () {
  //   test('Epic workflow', () {
  //     expect(env.evalProgram('epic-workflow'), TypeMatcher<ScEpicWorkflow>());
  //   });
  // });
  group('Code loading', () {
    test('via load function', () {
      final env = e();
      expect(
          () => env.interpretExprString(
              r'''load "test/test_resources/test_unparsable.shortcut"'''),
          throwsA(isA<PrematureEndOfProgram>()));
      expect(
          env.interpretExprString(
              r'''load "test/test_resources/test.shortcut"'''),
          TypeMatcher<ScExpr>());
      expect(env.bindings, contains(ScSymbol('with-estimate')));
      expect(env.interpretExprString("double 21"), ScNumber(42));
    });
  });
  group('ScNumber', () {
    final env = e();
    test('Greater than', () {
      expect(env.interpretExprString('>'), ScBoolean.veritas());
      expect(env.interpretExprString('> 2'), ScBoolean.veritas());
      expect(env.interpretExprString('> 2 1'), ScBoolean.veritas());
      expect(env.interpretExprString('> 2 1 0'), ScBoolean.veritas());
      expect(env.interpretExprString('> 2 1 0 -1'), ScBoolean.veritas());
      expect(env.interpretExprString('> -1 0 1'), ScBoolean.falsitas());
      expect(env.interpretExprString('> 1 1'), ScBoolean.falsitas());
    });
    test('Greater than or equal to', () {
      expect(env.interpretExprString('>='), ScBoolean.veritas());
      expect(env.interpretExprString('>= 2'), ScBoolean.veritas());
      expect(env.interpretExprString('>= 2 1'), ScBoolean.veritas());
      expect(env.interpretExprString('>= 2 1 0'), ScBoolean.veritas());
      expect(env.interpretExprString('>= 2 1 0 -1'), ScBoolean.veritas());
      expect(env.interpretExprString('>= 1 1'), ScBoolean.veritas());
      expect(env.interpretExprString('>= 1 1 0 0'), ScBoolean.veritas());
      expect(env.interpretExprString('>= -1 0 1'), ScBoolean.falsitas());
    });
    test('Less than', () {
      expect(env.interpretExprString('<'), ScBoolean.veritas());
      expect(env.interpretExprString('< -1'), ScBoolean.veritas());
      expect(env.interpretExprString('< -1 0'), ScBoolean.veritas());
      expect(env.interpretExprString('< -1 0 1'), ScBoolean.veritas());
      expect(env.interpretExprString('< -1 0 1 2'), ScBoolean.veritas());
      expect(env.interpretExprString('< -1 -2 1'), ScBoolean.falsitas());
      expect(env.interpretExprString('< 2 2'), ScBoolean.falsitas());
    });
    test('Less than or equal to', () {
      expect(env.interpretExprString('<='), ScBoolean.veritas());
      expect(env.interpretExprString('<= -1'), ScBoolean.veritas());
      expect(env.interpretExprString('<= -1 0'), ScBoolean.veritas());
      expect(env.interpretExprString('<= -1 0 1'), ScBoolean.veritas());
      expect(env.interpretExprString('<= -1 0 1 2'), ScBoolean.veritas());
      expect(env.interpretExprString('<= 2 2'), ScBoolean.veritas());
      expect(env.interpretExprString('<= 2 2 3 3'), ScBoolean.veritas());
      expect(env.interpretExprString('<= -1 -2 1'), ScBoolean.falsitas());
    });
  });
  group('ScString', () {
    test('isBlank', () {
      expect(ScString('').isBlank(), true);
      expect(ScString(' ').isBlank(), true);
      expect(ScString(' a').isBlank(), false);
      expect(ScString('\t').isBlank(), true);
      expect(ScString('\n').isBlank(), true);
      expect(ScString('  \n\t\t\n ').isBlank(), true);
      expect(ScString('a  \n\t\t\n ').isBlank(), false);
      expect(ScString('  \n\ta\t\n ').isBlank(), false);
      expect(ScString('  \n\t\t\n a').isBlank(), false);
    });
  });
  group('Collections', () {
    final env = e();
    test('Lists', () {
      expect(
          env.interpretExprString(
              '["yes", "no", "yep", "nope"] | where %(= (count %) 3)'),
          ScList([ScString('yes'), ScString('yep')]));
      expect(
          env.interpretExprString(
              '[{"user" "daniel" "lang" "en"} {"user" "leinad" "lang" "ne"}] | where {.user "daniel"}'),
          ScList([
            ScMap({
              ScString('user'): ScString('daniel'),
              ScString('lang'): ScString('en')
            })
          ]));
      expect(
          env.interpretExprString(
              '[{.items [.a] .user .daniel} {.items [.a .b] .user .leinad}] | where {.items %(= (count %) 2)}'),
          env.interpretExprString('[{.items [.a .b] .user .leinad}]'));
    });
    test('Nested maps', () {
      // final m = env.evalProgram('{"foo" {"bar" 42}}');
      expect(env.interpretExprString('{"foo" {"bar" 42}} | get-in ["foo"]'),
          env.interpretExprString('{"bar" 42}'));
      expect(
          env.interpretExprString('{"foo" {"bar" 42}} | get-in ["foo" "bar"]'),
          env.interpretExprString('42'));
      expect(env.interpretExprString('{"foo" {"bar" 42}} | get-in [.foo]'),
          env.interpretExprString('{"bar" 42}'));
      expect(env.interpretExprString('{"foo" {"bar" 42}} | get-in [.foo .bar]'),
          env.interpretExprString('42'));
    });
    test('Where', () {
      expect(
          (env.interpretExprString(
                      '[{"foo" {"bar" 42}} {"foo" {"bar" 36}}] | where {["foo" "bar"] 42}')
                  as ScList)
              .innerList,
          (env.interpretExprString('[{"foo" {"bar" 42}}]') as ScList)
              .innerList);
    });
  });
}
