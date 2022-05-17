import 'package:test/test.dart';

import 'package:sc_cli/src/sc.dart';
import 'package:sc_cli/src/sc_api.dart' show ScLiveClient;
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
  group('Prelude', () {
    final env = e();
    env.loadPrelude();
    group('Boolean logic', () {
      test('not', () {
        expect(env.interpretExprString('not true'), ScBoolean.falsitas());
        expect(env.interpretExprString('not 42'), ScBoolean.falsitas());
        expect(env.interpretExprString('not false'), ScBoolean.veritas());
        expect(env.interpretExprString('not nil'), ScBoolean.veritas());
      });
      test('or', () {
        expect(
            env.interpretExprString('or %(just nil) %(just 1)'), ScNumber(1));
        expect(
            env.interpretExprString('or %(just false) %(just 1)'), ScNumber(1));
        expect(env.interpretExprString('or %(just 0) %(just 1)'), ScNumber(0));
      });
      test('when', () {
        expect(env.interpretExprString('when true %(just 42)'), ScNumber(42));
        expect(env.interpretExprString('when false %(just 42)'), ScNil());
        expect(env.interpretExprString('when nil %(just 42)'), ScNil());
      });
      test('first-where', () {
        expect(
            env.interpretExprString('first-where [1 2 3 4] (fn [n] (> n 2))'),
            ScNumber(3));
      });
    });
    group('Collections', () {
      test('Getters', () {
        expect(env.interpretExprString('[1 2 3 4 5 6 7 8 9 10 11] | first'),
            ScNumber(1));
        expect(env.interpretExprString('[1 2 3 4 5 6 7 8 9 10 11] | second'),
            ScNumber(2));
        expect(env.interpretExprString('[1 2 3 4 5 6 7 8 9 10 11] | third'),
            ScNumber(3));
        expect(env.interpretExprString('[1 2 3 4 5 6 7 8 9 10 11] | fourth'),
            ScNumber(4));
        expect(env.interpretExprString('[1 2 3 4 5 6 7 8 9 10 11] | fifth'),
            ScNumber(5));
        expect(env.interpretExprString('[1 2 3 4 5 6 7 8 9 10 11] | sixth'),
            ScNumber(6));
        expect(env.interpretExprString('[1 2 3 4 5 6 7 8 9 10 11] | seventh'),
            ScNumber(7));
        expect(env.interpretExprString('[1 2 3 4 5 6 7 8 9 10 11] | eighth'),
            ScNumber(8));
        expect(env.interpretExprString('[1 2 3 4 5 6 7 8 9 10 11] | ninth'),
            ScNumber(9));
        expect(env.interpretExprString('[1 2 3 4 5 6 7 8 9 10 11] | tenth'),
            ScNumber(10));
      });
      group('Concatenation', () {
        test('mapcat', () {
          expect(env.interpretExprString('mapcat [[1 2] [3 4]] identity'),
              env.interpretExprString('[1 2 3 4]'));
          expect(() => env.interpretExprString('mapcat [1 2 3 4] identity'),
              throwsA(isA<BadArgumentsException>()));
        });
      });
    });
  });
}
