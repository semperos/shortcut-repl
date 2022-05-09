import 'package:petitparser/matcher.dart';

import 'package:sc_cli/src/sc_api.dart';
import 'package:sc_cli/src/sc_config.dart';
import 'package:sc_cli/src/sc_lang.dart';
import 'package:test/test.dart';

final client = ScLiveClient(getShortcutHost(), getShortcutApiToken());
ScEnv e() => ScEnv.fromMap(client, {});

void main() {
  final scParser = e().scParser;
  group('Eval', () {
    group('Identities', () {
      final env = e();
      test('Numbers', () {
        expect(scEval(env, scRead(env, '42')), ScNumber(42));
        expect(scEval(env, scRead(env, '42.0')), ScNumber(42.0));
        expect(scEval(env, scRead(env, '42e3')), ScNumber(42000));
        expect(scEval(env, scRead(env, '-42')), ScNumber(-42));
      });
    });
    group('Arithmetic', () {
      final env = e();
      test('Addition', () {
        expect(scEval(env, scRead(env, '(+)')), ScNumber(0));
        expect(scEval(env, scRead(env, '(+ 2 3)')), ScNumber(5));
        expect(scEval(env, scRead(env, '(+ 7 -2)')), ScNumber(5));
        expect(scEval(env, scRead(env, '(+ 1 2 3 4 5)')), ScNumber(15));
      });
      test('Subtraction', () {
        expect(scEval(env, scRead(env, '(-)')), ScNumber(0));
        expect(scEval(env, scRead(env, '(- 3 2)')), ScNumber(1));
        expect(scEval(env, scRead(env, '(- -7 2)')), ScNumber(-9));
        expect(scEval(env, scRead(env, '(- 1 2 3 4 5)')), ScNumber(-13));
      });
      test('Multiplication', () {
        expect(scEval(env, scRead(env, '(*)')), ScNumber(1));
        expect(scEval(env, scRead(env, '(* 3)')), ScNumber(3));
        expect(scEval(env, scRead(env, '(* 11 3)')), ScNumber(33));
      });
      test('Division', () {
        expect(() => scEval(env, scRead(env, '(/)')),
            throwsA(isA<BadArgumentsException>()));
        expect(scEval(env, scRead(env, '(/ 4)')), ScNumber(0.25));
        expect(scEval(env, scRead(env, '(/ 16 4)')), ScNumber(4));
      });
      test('Max', () {
        expect(scEval(env, scRead(env, 'max 3 4')), ScNumber(4));
        expect(scEval(env, scRead(env, 'max [3 4]')), ScNumber(4));
        expect(scEval(env, scRead(env, 'max 3 4 2 9 1')), ScNumber(9));
        expect(scEval(env, scRead(env, 'max [3 4 2 9 1]')), ScNumber(9));
      });
      test('Min', () {
        expect(scEval(env, scRead(env, 'min 3 4')), ScNumber(3));
        expect(scEval(env, scRead(env, 'min [3 4]')), ScNumber(3));
        expect(scEval(env, scRead(env, 'min 3 4 2 9 1')), ScNumber(1));
        expect(scEval(env, scRead(env, 'min [3 4 2 9 1]')), ScNumber(1));
      });
    });
  });
  group('Parsing', () {
    test(
      'Numbers',
      () {
        expect(scParser.parse('42').value[0], [ScNumber(42)]);
        expect(scParser.parse('42.0').value[0], [ScNumber(42.0)]);
        expect(scParser.parse('42e3').value[0], [ScNumber(42000)]);
        expect(scParser.parse('-42').value[0], [ScNumber(-42)]);
      },
    );
    test('Quoted symbols', () {
      expect(scParser.parse(".foo").value[0], [ScQuotedSymbol("foo")]);
    });
    test('Strings', () {
      expect(scParser.parse('"alpha"').value[0], [ScString('alpha')]);
      expect(scParser.parse('"alpha ☦️"').value[0], [ScString('alpha ☦️')]);
      expect(scParser.parse('"alpha\n"').value[0], [ScString("alpha\n")]);
      expect(scParser.parse('"foo\\"bar"').value[0], [ScString('foo"bar')]);
    });
    test('Comments', () {
      expect(scParser.parse(';; Wow\n42').value[0], [ScNumber(42)]);
      // For now, this is how we'll handle whole programs that are a comment: a nil will be appended before it's parsed + evaluated.
      expect(scParser.accept(';\nnil'), true);
    });
  });

  group('Evaluating', () {
    final env = e();
    test('Multiple expressions', () {
      expect(() => env.evalProgram('1 2 3'),
          throwsA(TypeMatcher<UninvocableException>()));
      expect(env.evalProgram('(fn [] 1 2 3)'), ScNumber(3));
    });
    test('Piped expressions', () {
      // expect(readProgram('identity 42 | + 3'), 42);
      expect(env.evalProgram('()'), ScNil());
      expect(env.evalProgram('42'), ScNumber(42));
      expect(env.evalProgram('0.42'), ScNumber(0.42));
      expect(env.evalProgram('+'), ScNumber(0));
      expect(env.evalProgram('(+ 2 3)'), ScNumber(5));
      expect(env.evalProgram('+ 2 3'), ScNumber(5));
      expect(env.evalProgram('- 2 3'), ScNumber(-1));
      expect(env.evalProgram('* 2 3'), ScNumber(6));
      expect(env.evalProgram('/ 9 3'), ScNumber(3));
      expect(env.evalProgram('+ 2 3 | + 4'), ScNumber(9));
      expect(env.evalProgram('+ 2 3 | + 4 | * 10 5'), ScNumber(450));
      expect(env.evalProgram('+ 2 3 | + 4 | * 4 | / 36'), ScNumber(1));
      expect(env.evalProgram('+ 2 3 | - 4 '), ScNumber(1));
      expect(env.evalProgram('+ 2 3 | - _ 4 '), ScNumber(1));
      expect(env.evalProgram('+ 2 3 | - 4 _ '), ScNumber(-1));
      expect(env.evalProgram('+ 2 3 | + 4 | * 4 _ | / _ 36'), ScNumber(1));
      expect(() => env.evalProgram('+ _ 2'),
          throwsA(TypeMatcher<MisplacedPipedArg>()));
      expect(() => env.evalProgram('+ 3 2 | * 4 _ _'),
          throwsA(TypeMatcher<ExtraneousPipedArg>()));
    });
    test('Piped Expressions, edge cases', () {
      expect(env.evalProgram('284 | + 1'), ScNumber(285));
    });
  });

  group('Defining', () {
    test('Evaluation', () {
      final env = e();
      env.evalProgram('def a + 42 2');
      expect(env[ScSymbol('a')], ScNumber(44));
      env.evalProgram(r'''def double
      value %(* % 2)''');
      expect(env.evalProgram('double 21'), ScNumber(42));
    });
    test('Def invocation', () {
      final env = e();
      final prog =
          r"""(def with-estimate value (fn [story estimate] (extend story { "estimate" estimate })))""";
      expect(scParser.accept(prog), true);
      expect(env.evalProgram(prog), TypeMatcher<ScFunction>());
      final fn = env.evalProgram(prog) as ScFunction;
      expect(fn.params.length, 2);
      expect(env.bindings, contains(ScSymbol('with-estimate')));
    });
  });

  group('Functions', () {
    test('With fn', () {
      final env = e();
      expect(scParser.parse('(fn alpha [a b] b)').value[0][0],
          TypeMatcher<ScFunction>());
      expect(env.evalProgram('(fn [])'), ScNil());
      expect(() => env.evalProgram('(fn [a])'),
          throwsA(isA<BadArgumentsException>()));
      expect(env.evalProgram('((fn answer [] 42))'), ScNumber(42));
      expect(env.evalProgram('((fn answer [] 42 26))'), ScNumber(26));
      expect(env.evalProgram('(fn a [a] a) 26'), ScNumber(26));
      expect(env.evalProgram('(fn higher [f n] (f 1 n)) + 26'), ScNumber(27));
      expect(
          env.evalProgram(
              '(fn nested [coll n] (map coll (fn mapper [item] (* item n)))) [1 2 3] 3'),
          env.evalProgram('[3 6 9]'));
      expect(
          env.evalProgram(
              '(fn shadowing [x n] (map x (fn mapper [x] (* x n)))) [1 2 3] 3'),
          env.evalProgram('[3 6 9]'));
    });
  });

  group('Anonymous functions', () {
    final env = e();
    test('Zero arguments', () {
      expect(env.evalProgram('invoke %()'), ScNil());
      expect(env.evalProgram('invoke %(+)'), ScNumber(0));
      expect(env.evalProgram('invoke %(*)'), ScNumber(1));
    });
    test('Single argument', () {
      expect(env.evalProgram('invoke %(+ % 1) 2'), ScNumber(3));
      expect(env.evalProgram('invoke %(split %) "alpha\nbeta"'),
          ScList([ScString('alpha'), ScString('beta')]));
      expect(env.evalProgram('invoke %(get {.a 42} %1) .a'), ScNumber(42));
      expect(env.evalProgram('invoke %(get {.a 42} %1) .b'), ScNil());
    });
    test('Multiple arguments', () {
      expect(env.evalProgram('invoke %(- %2 %1) 8 10'), ScNumber(2));
      expect(env.evalProgram('invoke %(get {.a "alpha"} %1-a-key) .a'),
          ScString('alpha'));
      expect(env.evalProgram('invoke %(get %2-map %1-key) .a {.a "alpha"}'),
          ScString('alpha'));
    });
    test('Nested %', () {
      expect(env.evalProgram('invoke %(= (count %) 3) "yes"'),
          ScBoolean.veritas());
      expect(env.evalProgram('invoke %(= (+ (count %) 1) 4) "yes"'),
          ScBoolean.veritas());
      expect(env.evalProgram('invoke %(= (+ (+ (count %) 1) 1) 5) "yes"'),
          ScBoolean.veritas());
      expect(env.evalProgram('invoke %(= (+ (+ (+ (count %) 1) 1) 1) 6) "yes"'),
          ScBoolean.veritas());
      expect(
          env.evalProgram(
              'invoke %(= (* (+ (+ (+ (count %) 1) 1) 1) 3) 18) "yes"'),
          ScBoolean.veritas());
    });
    test('As used with if', () {
      expect(env.evalProgram('if true %(just 42) %(just 24)'), ScNumber(42));
      expect(
          env.evalProgram(
              'get {.a "alpha"} .b | if %(just "found it") %(just "no dice")'),
          ScString('no dice'));
    });
  });
}
