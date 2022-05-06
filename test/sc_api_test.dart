import 'package:test/test.dart';

import 'package:sc_cli/src/sc_api.dart';
import 'package:sc_cli/src/sc_config.dart';

final client = ScLiveClient(getShortcutHost(), getShortcutApiToken());
final env = ScEnv.fromMap(client, {});

void main() {
  // group('Live Client', () {
  //   test('Epic workflow', () {
  //     expect(env.evalProgram('epic-workflow'), TypeMatcher<ScEpicWorkflow>());
  //   });
  // });
  group('ScNumber', () {
    test('Greater than', () {
      expect(env.evalProgram('>'), ScBoolean.veritas());
      expect(env.evalProgram('> 2'), ScBoolean.veritas());
      expect(env.evalProgram('> 2 1'), ScBoolean.veritas());
      expect(env.evalProgram('> 2 1 0'), ScBoolean.veritas());
      expect(env.evalProgram('> 2 1 0 -1'), ScBoolean.veritas());
      expect(env.evalProgram('> -1 0 1'), ScBoolean.falsitas());
      expect(env.evalProgram('> 1 1'), ScBoolean.falsitas());
    });
    test('Greater than or equal to', () {
      expect(env.evalProgram('>='), ScBoolean.veritas());
      expect(env.evalProgram('>= 2'), ScBoolean.veritas());
      expect(env.evalProgram('>= 2 1'), ScBoolean.veritas());
      expect(env.evalProgram('>= 2 1 0'), ScBoolean.veritas());
      expect(env.evalProgram('>= 2 1 0 -1'), ScBoolean.veritas());
      expect(env.evalProgram('>= 1 1'), ScBoolean.veritas());
      expect(env.evalProgram('>= 1 1 0 0'), ScBoolean.veritas());
      expect(env.evalProgram('>= -1 0 1'), ScBoolean.falsitas());
    });
    test('Less than', () {
      expect(env.evalProgram('<'), ScBoolean.veritas());
      expect(env.evalProgram('< -1'), ScBoolean.veritas());
      expect(env.evalProgram('< -1 0'), ScBoolean.veritas());
      expect(env.evalProgram('< -1 0 1'), ScBoolean.veritas());
      expect(env.evalProgram('< -1 0 1 2'), ScBoolean.veritas());
      expect(env.evalProgram('< -1 -2 1'), ScBoolean.falsitas());
      expect(env.evalProgram('< 2 2'), ScBoolean.falsitas());
    });
    test('Less than or equal to', () {
      expect(env.evalProgram('<='), ScBoolean.veritas());
      expect(env.evalProgram('<= -1'), ScBoolean.veritas());
      expect(env.evalProgram('<= -1 0'), ScBoolean.veritas());
      expect(env.evalProgram('<= -1 0 1'), ScBoolean.veritas());
      expect(env.evalProgram('<= -1 0 1 2'), ScBoolean.veritas());
      expect(env.evalProgram('<= 2 2'), ScBoolean.veritas());
      expect(env.evalProgram('<= 2 2 3 3'), ScBoolean.veritas());
      expect(env.evalProgram('<= -1 -2 1'), ScBoolean.falsitas());
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
    test('Lists', () {
      expect(
          env.evalProgram(
              '["yes", "no", "yep", "nope"] | where %(= (count %) 3)'),
          ScList([ScString('yes'), ScString('yep')]));
      expect(
          env.evalProgram(
              '[{"user" "daniel" "lang" "en"} {"user" "leinad" "lang" "ne"}] | where {.user "daniel"}'),
          ScList([
            ScMap({
              ScString('user'): ScString('daniel'),
              ScString('lang'): ScString('en')
            })
          ]));
      expect(
          env.evalProgram(
              '[{.items [.a] .user .daniel} {.items [.a .b] .user .leinad}] | where {.items %(= (count %) 2)}'),
          env.evalProgram('[{.items [.a .b] .user .leinad}]'));
    });
    test('Nested maps', () {
      // final m = env.evalProgram('{"foo" {"bar" 42}}');
      expect(env.evalProgram('{"foo" {"bar" 42}} | get-in ["foo"]'),
          env.evalProgram('{"bar" 42}'));
      expect(env.evalProgram('{"foo" {"bar" 42}} | get-in ["foo" "bar"]'),
          env.evalProgram('42'));
      expect(env.evalProgram('{"foo" {"bar" 42}} | get-in [.foo]'),
          env.evalProgram('{"bar" 42}'));
      expect(env.evalProgram('{"foo" {"bar" 42}} | get-in [.foo .bar]'),
          env.evalProgram('42'));
    });
    test('Where', () {
      expect(
          (env.evalProgram(
                      '[{"foo" {"bar" 42}} {"foo" {"bar" 36}}] | where {["foo" "bar"] 42}')
                  as ScList)
              .innerList,
          (env.evalProgram('[{"foo" {"bar" 42}}]') as ScList).innerList);
    });
  });
}
