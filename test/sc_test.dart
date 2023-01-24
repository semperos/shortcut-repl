import 'package:test/test.dart';

import 'package:sc_cli/src/sc.dart';
import 'package:sc_cli/src/sc_api.dart' show ScLiveClient;
import 'package:sc_cli/src/sc_config.dart';

final client = ScLiveClient(
    getShortcutApiHost(), getShortcutApiToken(), getShortcutAppCookie());

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
          () => env.interpret(
              r'''load "test/test_resources/test_unparsable.shortcut"'''),
          throwsA(isA<PrematureEndOfProgram>()));
      expect(env.interpret(r'''load "test/test_resources/test.shortcut"'''),
          TypeMatcher<ScExpr>());
      expect(env.bindings, contains(ScSymbol('with-estimate')));
      expect(env.interpret("double 21"), ScNumber(42));
    });
  });
  group('REPL facilities', () {
    test('*1 *2 *3', () {
      final env = e();
      env.isReplMode = true;
      env.interpret('"a"');
      expect(env.interpret('*1'), ScString('a'));
      env.interpret('"b"');
      expect(env.interpret('*1'), ScString('b'));
      expect(env.interpret('*2'), ScString('a'));
      env.interpret('"c"');
      expect(env.interpret('*1'), ScString('c'));
      expect(env.interpret('*2'), ScString('b'));
      expect(env.interpret('*3'), ScString('a'));
    });
  });
  group('Numbers', () {
    final env = e();
    group('Arithmetic', () {
      final env = e();
      test('Addition', () {
        expect(env.interpret('(+)'), ScNumber(0));
        expect(env.interpret('(+ 2 3)'), ScNumber(5));
        expect(env.interpret('(+ 7 -2)'), ScNumber(5));
        expect(env.interpret('(+ 1 2 3 4 5)'), ScNumber(15));
      });
      test('Subtraction', () {
        expect(env.interpret('(-)'), ScNumber(0));
        expect(env.interpret('(- 3 2)'), ScNumber(1));
        expect(env.interpret('(- -7 2)'), ScNumber(-9));
        expect(env.interpret('(- 1 2 3 4 5)'), ScNumber(-13));
      });
      test('Multiplication', () {
        expect(env.interpret('(*)'), ScNumber(1));
        expect(env.interpret('(* 3)'), ScNumber(3));
        expect(env.interpret('(* 11 3)'), ScNumber(33));
      });
      test('Division', () {
        expect(
            () => env.interpret('(/)'), throwsA(isA<BadArgumentsException>()));
        expect(env.interpret('(/ 4)'), ScNumber(0.25));
        expect(env.interpret('(/ 16 4)'), ScNumber(4));
      });
      test('Max', () {
        expect(env.interpret('max 3 4'), ScNumber(4));
        expect(env.interpret('max [3 4]'), ScNumber(4));
        expect(env.interpret('max 3 4 2 9 1'), ScNumber(9));
        expect(env.interpret('max [3 4 2 9 1]'), ScNumber(9));
      });
      test('Min', () {
        expect(env.interpret('min 3 4'), ScNumber(3));
        expect(env.interpret('min [3 4]'), ScNumber(3));
        expect(env.interpret('min 3 4 2 9 1'), ScNumber(1));
        expect(env.interpret('min [3 4 2 9 1]'), ScNumber(1));
      });
    });

    test('Greater than', () {
      expect(env.interpret('>'), ScBoolean.veritas());
      expect(env.interpret('> 2'), ScBoolean.veritas());
      expect(env.interpret('> 2 1'), ScBoolean.veritas());
      expect(env.interpret('> 2 1 0'), ScBoolean.veritas());
      expect(env.interpret('> 2 1 0 -1'), ScBoolean.veritas());
      expect(env.interpret('> -1 0 1'), ScBoolean.falsitas());
      expect(env.interpret('> 1 1'), ScBoolean.falsitas());
    });
    test('Greater than or equal to', () {
      expect(env.interpret('>='), ScBoolean.veritas());
      expect(env.interpret('>= 2'), ScBoolean.veritas());
      expect(env.interpret('>= 2 1'), ScBoolean.veritas());
      expect(env.interpret('>= 2 1 0'), ScBoolean.veritas());
      expect(env.interpret('>= 2 1 0 -1'), ScBoolean.veritas());
      expect(env.interpret('>= 1 1'), ScBoolean.veritas());
      expect(env.interpret('>= 1 1 0 0'), ScBoolean.veritas());
      expect(env.interpret('>= -1 0 1'), ScBoolean.falsitas());
    });
    test('Less than', () {
      expect(env.interpret('<'), ScBoolean.veritas());
      expect(env.interpret('< -1'), ScBoolean.veritas());
      expect(env.interpret('< -1 0'), ScBoolean.veritas());
      expect(env.interpret('< -1 0 1'), ScBoolean.veritas());
      expect(env.interpret('< -1 0 1 2'), ScBoolean.veritas());
      expect(env.interpret('< -1 -2 1'), ScBoolean.falsitas());
      expect(env.interpret('< 2 2'), ScBoolean.falsitas());
    });
    test('Less than or equal to', () {
      expect(env.interpret('<='), ScBoolean.veritas());
      expect(env.interpret('<= -1'), ScBoolean.veritas());
      expect(env.interpret('<= -1 0'), ScBoolean.veritas());
      expect(env.interpret('<= -1 0 1'), ScBoolean.veritas());
      expect(env.interpret('<= -1 0 1 2'), ScBoolean.veritas());
      expect(env.interpret('<= 2 2'), ScBoolean.veritas());
      expect(env.interpret('<= 2 2 3 3'), ScBoolean.veritas());
      expect(env.interpret('<= -1 -2 1'), ScBoolean.falsitas());
    });
  });
  group('Strings', () {
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
  group('date-time', () {
    final env = e();
    test('plus-*', () {
      expect(env.interpret('dt "2022-01-01" | plus-days 2'),
          env.interpret('dt "2022-01-03"'));
    });
    test('minus-*', () {
      expect(env.interpret('dt "2022-01-01" | minus-days 2'),
          env.interpret('dt "2021-12-30"'));
    });
    test('*-since', () {
      expect(env.interpret('dt "2022-01-31" | days-since (dt "2022-01-15")'),
          ScNumber(16));
    });
    test('*-since', () {
      expect(env.interpret('dt "2022-01-01" | days-until (dt "2022-01-15")'),
          ScNumber(14));
    });
    test('Field Functions', () {
      expect(env.interpret('dt "2023-06-16T14:34:43.042Z" | year'),
          ScNumber(2023));
      expect(
          env.interpret('dt "2023-06-16T14:34:43.042Z" | month'), ScNumber(6));
      expect(env.interpret('dt "2023-06-16T14:34:43.042Z" | date-of-month'),
          ScNumber(16));
      expect(env.interpret('dt "2023-06-16T14:34:43.042Z" | day-of-week'),
          ScString('Friday'));
      expect(
          env.interpret('dt "2023-06-16T14:34:43.042Z" | hour'), ScNumber(14));
      expect(env.interpret('dt "2023-06-16T14:34:43.042Z" | minute'),
          ScNumber(34));
      expect(env.interpret('dt "2023-06-16T14:34:43.042Z" | second'),
          ScNumber(43));
      expect(env.interpret('dt "2023-06-16T14:34:43.042Z" | millisecond'),
          ScNumber(42));
      expect(env.interpret('dt "2023-06-16T14:34:43.042998Z" | microsecond'),
          ScNumber(998));
    });
    test('calculateWeekOfYear', () {
      expect(calculateWeekOfYear(DateTime.parse('2022-01-03')), 1); // Monday
      expect(calculateWeekOfYear(DateTime.parse('2022-01-04')), 1);
      expect(calculateWeekOfYear(DateTime.parse('2022-01-05')), 1);
      expect(calculateWeekOfYear(DateTime.parse('2022-01-06')), 1);
      expect(calculateWeekOfYear(DateTime.parse('2022-01-07')), 1);
      expect(calculateWeekOfYear(DateTime.parse('2022-01-08')), 1); // Saturday
      expect(calculateWeekOfYear(DateTime.parse('2022-01-10')), 2); // Monday
      expect(calculateWeekOfYear(DateTime.parse('2022-01-11')), 2);
      expect(calculateWeekOfYear(DateTime.parse('2022-01-12')), 2);
      expect(calculateWeekOfYear(DateTime.parse('2022-01-13')), 2);
      expect(calculateWeekOfYear(DateTime.parse('2022-01-14')), 2);
      expect(calculateWeekOfYear(DateTime.parse('2022-01-15')), 2); // Saturday
      expect(calculateWeekOfYear(DateTime.parse('2022-01-17')), 3); // Monday
      expect(calculateWeekOfYear(DateTime.parse('2022-12-31')), 52);
      expect(calculateWeekOfYear(DateTime.parse('2010-01-01')), 53);
    });
  });
  group('Collections', () {
    final env = e();
    group('Lists', () {
      test('filter/where', () {
        expect(
            env.interpret(
                '["yes", "no", "yep", "nope"] | where %(= (count %) 3)'),
            ScList([ScString('yes'), ScString('yep')]));
        expect(
            env.interpret(
                '[{"user" "daniel" "lang" "en"} {"user" "leinad" "lang" "ne"}] | where {.user "daniel"}'),
            env.interpret(r'''[{"user" "daniel" "lang" "en"}]'''));
        expect(
            env.interpret(
                '[{.items [.a] .user .daniel} {.items [.a .b] .user .leinad}] | where {.items %(= (count %) 2)}'),
            env.interpret('[{.items [.a .b] .user .leinad}]'));
      });
      test('reduce', () {
        expect(env.interpret('reduce [] +'), ScNumber(0));
        expect(env.interpret('reduce [] *'), ScNumber(1));
        expect(env.interpret('reduce [] 42 +'), ScNumber(42));
        expect(env.interpret('reduce [1 2] 42 +'), ScNumber(45));
      });
      group('subset?', () {
        test('strings', () {
          expect(env.interpret('subset? "" ""'), ScBoolean.veritas());
          expect(env.interpret('subset? "" "a"'), ScBoolean.veritas());
          expect(env.interpret('subset? "a" "a"'), ScBoolean.veritas());
          expect(env.interpret('subset? "a" "abc"'), ScBoolean.veritas());
          expect(env.interpret('subset? "x" "abc"'), ScBoolean.falsitas());
          expect(env.interpret('subset? "xy" "abc"'), ScBoolean.falsitas());
        });
        test('lists', () {
          expect(env.interpret('subset? [] []'), ScBoolean.veritas());
          expect(env.interpret('subset? [] [1]'), ScBoolean.veritas());
          expect(env.interpret('subset? [1] [1 2 3]'), ScBoolean.veritas());
          expect(env.interpret('subset? [1 2] [1 2 3]'), ScBoolean.veritas());
          expect(env.interpret('subset? [2 3] [1 2 3]'), ScBoolean.veritas());
          expect(env.interpret('subset? [3] [1 2 3]'), ScBoolean.veritas());
          expect(env.interpret('subset? [4] [1 2 3]'), ScBoolean.falsitas());
          expect(env.interpret('subset? [4 5] [1 2 3]'), ScBoolean.falsitas());
        });
        test('maps', () {
          expect(env.interpret('subset? {} {}'), ScBoolean.veritas());
          expect(env.interpret('subset? {} {.a 42}'), ScBoolean.veritas());
          expect(env.interpret('subset? {.a 42} {.a 42}'), ScBoolean.veritas());
          expect(env.interpret('subset? {.a 42 .b 23} {.a 42 .b 23}'),
              ScBoolean.veritas());
          expect(env.interpret('subset? {.a 42 .b 23} {.a 42 .b 23 .c 1}'),
              ScBoolean.veritas());
          expect(env.interpret('subset? {.a 42 .b 23 .c 2} {.a 42 .b 23 .c 1}'),
              ScBoolean.falsitas());
        });
      });
    });
    test('Nested maps', () {
      expect(env.interpret('{"foo" {"bar" 42}} | get-in ["foo"]'),
          env.interpret('{"bar" 42}'));
      expect(env.interpret('{"foo" {"bar" 42}} | get-in ["foo" "bar"]'),
          env.interpret('42'));
      expect(env.interpret('{"foo" {"bar" 42}} | get-in [.foo]'),
          env.interpret('{"bar" 42}'));
      expect(env.interpret('{"foo" {"bar" 42}} | get-in [.foo .bar]'),
          env.interpret('42'));
    });
    test('Where', () {
      expect(
          (env.interpret(
                      '[{"foo" {"bar" 42}} {"foo" {"bar" 36}}] | where {["foo" "bar"] 42}')
                  as ScList)
              .innerList,
          (env.interpret('[{"foo" {"bar" 42}}]') as ScList).innerList);
    });
  });
  group('Prelude', () {
    final env = e();
    group('Boolean logic', () {
      test('not', () {
        expect(env.interpret('not true'), ScBoolean.falsitas());
        expect(env.interpret('not 42'), ScBoolean.falsitas());
        expect(env.interpret('not false'), ScBoolean.veritas());
        expect(env.interpret('not nil'), ScBoolean.veritas());
      });
      test('or', () {
        expect(env.interpret('or %(just nil) %(just 1)'), ScNumber(1));
        expect(env.interpret('or %(just false) %(just 1)'), ScNumber(1));
        expect(env.interpret('or %(just 0) %(just 1)'), ScNumber(0));
      });
      test('when', () {
        expect(env.interpret('when true %(just 42)'), ScNumber(42));
        expect(env.interpret('when false %(just 42)'), ScNil());
        expect(env.interpret('when nil %(just 42)'), ScNil());
      });
      test('first-where', () {
        expect(env.interpret('first-where [1 2 3 4] (fn [n] (> n 2))'),
            ScNumber(3));
      });
    });
    group('Mathematics', () {
      test('Sum', () {
        expect(env.interpret('sum [1 2 3 4 5]'), ScNumber(15));
        expect(env.interpret('sum []'), ScNumber(0));
      });
      test('Average', () {
        expect(env.interpret('avg [0 100 0 100]'), ScNumber(50.0));
        // NB: Also test of mutable/immutable reduce.
        env.interpret(
            'def avg-safe value (fn [coll] ((fn [cnt] (/ (reduce coll +) cnt)) (count coll)))');
        expect(env.interpret('avg [0 100 0 100]'),
            env.interpret('avg-safe [0 100 0 100]'));
      });
    });
    group('Collections', () {
      test('Accessors', () {
        expect(env.interpret('[1 2 3 4 5 6 7 8 9 10 11] | first'), ScNumber(1));
        expect(
            env.interpret('[1 2 3 4 5 6 7 8 9 10 11] | second'), ScNumber(2));
        expect(env.interpret('[1 2 3 4 5 6 7 8 9 10 11] | third'), ScNumber(3));
        expect(
            env.interpret('[1 2 3 4 5 6 7 8 9 10 11] | fourth'), ScNumber(4));
        expect(env.interpret('[1 2 3 4 5 6 7 8 9 10 11] | fifth'), ScNumber(5));
        expect(env.interpret('[1 2 3 4 5 6 7 8 9 10 11] | sixth'), ScNumber(6));
        expect(
            env.interpret('[1 2 3 4 5 6 7 8 9 10 11] | seventh'), ScNumber(7));
        expect(
            env.interpret('[1 2 3 4 5 6 7 8 9 10 11] | eighth'), ScNumber(8));
        expect(env.interpret('[1 2 3 4 5 6 7 8 9 10 11] | ninth'), ScNumber(9));
        expect(
            env.interpret('[1 2 3 4 5 6 7 8 9 10 11] | tenth'), ScNumber(10));
      });
      group('Concatenation', () {
        test('mapcat', () {
          expect(env.interpret('mapcat [[1 2] [3 4]] identity'),
              env.interpret('[1 2 3 4]'));
          expect(() => env.interpret('mapcat [1 2 3 4] identity'),
              throwsA(isA<BadArgumentsException>()));
        });
      });
    });
  });
}
