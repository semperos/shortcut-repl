import 'package:petitparser/petitparser.dart';

import 'package:sc_cli/src/sc_api.dart';
import 'package:sc_cli/src/sc_util.dart';

ScExpr scRead(ScEnv env, String input) {
  // import 'package:petitparser/debug.dart';
  // final lp = trace(env.scParser);
  return env.scParser.readProgram(env, input);
}

ScExpr scEval(ScEnv env, ScExpr expr) {
  return expr.eval(env);
}

void scPrint(ScEnv env, ScExpr expr) {
  // previewAnsi('Foreground', foregroundColors, false);
  // previewAnsi('Background', backgroundColors, false);
  // previewAnsi('Styles', styles, false);
  return expr.print(env);
}

ScExpr scInvoke(ScEnv env, ScBaseInvocable invocable, ScList args) {
  return invocable.invoke(env, args);
}

/// LISP grammar definition
/// Adapted from: https://github.com/petitparser/dart-petitparser-examples/blob/main/lib/src/lisp/grammar.dart
class PipedLispGrammarDefinition extends GrammarDefinition {
  @override
  Parser start() => ref0(program);

  Parser program() =>
      (ref0(atom).star() & (ref0(pipe) & ref0(atom).plus()).star()).end();

  Parser atom() => ref0(atomChoice).trim(ref0(space));
  Parser atomChoice() =>
      ref0(anonymousInvocable) |
      ref0(invocation) |
      ref0(list) |
      ref0(map) |
      ref0(number) |
      ref0(aString) |
      // Special syntax before ScSymbol
      ref0(define) |
      // ref0(fn) |
      ref0(pipedArg) |
      // ScSymbol after special syntax that conflicts
      ref0(dottedSymbol) |
      ref0(symbol);

  Parser anonymousInvocable() =>
      char('%') & ref2(bracket, '()', ref0(atom).star());
  Parser invocation() => ref2(bracket, '()', ref0(atom).star());
  Parser list() => ref2(bracket, '[]', ref0(atom).star());
  Parser map() => ref2(bracket, '{}', ref0(atom).star());

  Parser number() => ref0(numberToken).flatten('Number expected');
  Parser numberToken() =>
      anyOf('-+').optional() &
      char('0').or(digit().plus()) &
      char('.').seq(digit().plus()).optional() &
      anyOf('eE').seq(anyOf('-+').optional()).seq(digit().plus()).optional();

  Parser aString() => ref2(bracket, '""', ref0(character).star());
  Parser character() => ref0(characterEscape) | ref0(characterRaw);
  Parser characterEscape() => char('\\') & any();
  Parser characterRaw() => pattern('^"');

  // This handles `def` when top-level. See `invocation` for handling it
  // within parens.
  Parser define() {
    return ref0(defineToken) &
        ref0(space).plus() &
        ref0(symbol) &
        ref0(space).plus() &
        ref0(program);
  }

  // Parser fn() {
  //   return ref0(fnToken) &
  //       ref0(space).plus() &
  //       ref0(symbol) &
  //       ref0(space).plus() &
  //       ref0(list).plus() &
  //       ref0(program);
  // }

  Parser defineToken() => string('def'); // string('define') | string('def');
  // Parser fnToken() => string('fn'); // string('define') | string('def');

  Parser symbol() => ref0(symbolToken).flatten('Symbol expected');
  Parser dottedSymbol() =>
      ref0(dottedSymbolToken).flatten('Dotted symbol expected');
  Parser symbolToken() =>
      // NB: Pipe is not supported as a first symbol character.
      pattern('a-zA-Z!\$%&*/:<=>?@\\^_~+-\\.') &
      pattern('a-zA-Z0-9!\$%&*/:<=>?@\\^_|~+-\\.').star();
  Parser dottedSymbolToken() =>
      // NB: Pipe is not supported as a first symbol character.
      char('.') &
      pattern('a-zA-Z!\$%&*/:<=>?@\\^_~+-\\.') &
      pattern('a-zA-Z0-9!\$%&*/:<=>?@\\^_|~+-\\.').star();
  Parser pipe() => ref0(pipeToken);
  Parser pipeToken() => char('|');
  // Could be a symbol, but making special bc of central purpose.
  Parser pipedArg() => ref0(pipedArgToken);
  Parser pipedArgToken() => char('_');

  Parser space() => whitespace() | ref0(comma) | ref0(comment);
  Parser comma() => char(',');
  Parser comment() => char(';') & Token.newlineParser().neg().star();

  Parser bracket(String brackets, Parser parser) =>
      char(brackets[0]) & parser & char(brackets[1]);
}

/// LISP parser definition.
class PipedLispParserDefinition extends PipedLispGrammarDefinition {
  PipedLispParserDefinition(this.env);
  final ScEnv env;

  @override
  Parser anonymousInvocable() => super.anonymousInvocable().map((each) {
        List<int> argsNths = [];
        final List<ScExpr> exprs = List<ScExpr>.from(each[1][1]);
        rewriteAnonymousArgs(exprs, argsNths);

        final expectedNumNths = [];
        for (var i = 0; i < argsNths.length; i++) {
          expectedNumNths.add(i);
        }
        argsNths.sort();
        if (expectedNumNths.equals(argsNths)) {
          return ScAnonymousFunction(
              'anonymous', env, argsNths.length, ScList(exprs.toList()));
        } else {
          throw BadAnonymousInvocableException(
              "The %-prefixed arguments in an anonymous function must be %1 through % followed by the highest number argument. Expected $expectedNumNths but found $argsNths");
        }
      });

  @override
  Parser invocation() => super.invocation().map((each) {
        final List<ScExpr> exprs = List<ScExpr>.from(each[1]);
        if (exprs.isEmpty) {
          return ScNil();
        } else if (exprs.first == ScSymbol('def')) {
          exprs.removeAt(0); // remove thd def symbol
          if (exprs.length >= 2) {
            final defName = exprs[0];
            if (defName is ScSymbol) {
              final defBody = exprs.skip(1).toList();
              return ScDefinition(
                  defName, ScList([ScList(defBody), ScList([])]));
            } else {
              throw BadDef(
                  "The `def` form expects a symbol for its name, but received a ${defName.informalTypeName()}");
            }
          } else {
            throw BadDef("A definition must have at least a name and a value.");
          }
        } else if (exprs.first == ScSymbol('fn')) {
          exprs.removeAt(0); // remove the fn symbol
          if (exprs.isEmpty) {
            throw BadFn(
                "A function definition must have at least a list of parameters.");
          }

          final maybeFnName = exprs[0];
          ScSymbol fnName;
          if (maybeFnName is ScSymbol) {
            fnName = maybeFnName;
            exprs.removeAt(0);
          } else {
            fnName = gensym(prefix: 'fn');
          }

          if (exprs.isEmpty) {
            throw BadFn(
                "A function definition must have at least a list of parameters, but found only a name.");
          }
          var fnParams = exprs[0];
          ScList fnBody = listsToScLists(exprs.skip(1).toList());
          if (fnParams is ScList) {
            if (fnParams.innerList.every((element) => element is ScSymbol)) {
              return ScFunction(fnName.toString(), env, fnParams, fnBody);
            } else {
              throw BadFn(
                  "The parameters of a function must be symbols in a list, but received ${scExprToValue(fnParams)}.");
            }
          } else {
            throw BadFn(
                "The parameters of a function must be a list, but found a ${fnParams.informalTypeName()}");
          }
        } else {
          return ScInvocation(ScList(exprs));
        }
      });

  @override
  Parser list() => super.list().map((each) {
        final List<ScExpr> values = List<ScExpr>.from(each[1]);
        return ScList(values);
      });

  @override
  Parser map() => super.map().map((each) {
        final List<ScExpr> rawEntries = List<ScExpr>.from(each[1]);
        if (rawEntries.length.isOdd) {
          throw BadMap(
              'Maps require an even number of items, as many keys as values.',
              rawEntries);
        } else {
          return ScMap(Map.fromEntries(
              partitionAll(2, rawEntries).map((e) => MapEntry(e[0], e[1]))));
        }
      });

  @override
  Parser aString() => super
      .aString()
      .map((each) => ScString(String.fromCharCodes(each[1].cast<int>())));

  @override
  Parser characterEscape() => super.characterEscape().map((each) {
        String ch = each[1];
        switch (ch) {
          case 'n':
            return 10;
          case 'r':
            return 13;
          case 'f':
            return 12;
          case 'b':
            return 8;
          case 't':
            return 9;
          case 'v':
            return 11;
          default:
            return ch.codeUnitAt(0);
        }
      });

  @override
  Parser characterRaw() =>
      super.characterRaw().map((each) => each.codeUnitAt(0));

  @override
  Parser dottedSymbol() => super.dottedSymbol().map((symbolString) {
        // Strip off initial "quoting" character.
        String symStr = (symbolString as String).substring(1);
        // NB: Not sure why trailing commas are being parsed as part of ScDottedSymbol, but they are.
        symStr = symStr.replaceAll(',', '');
        return ScDottedSymbol(symStr);
      });

  @override
  Parser symbol() => super.symbol().map((symStr) => ScSymbol(symStr));

  @override
  Parser define() => super.define().map((definition) {
        final definitionName = definition[2] as ScSymbol;
        final definitionBodyRaw = definition.skip(4).toList().first;
        ScList definitionBody = listsToScLists(definitionBodyRaw);
        return ScDefinition(definitionName, definitionBody);
      });

  @override
  Parser number() => super.number().map((each) => ScNumber(num.parse(each)));

  @override
  Parser pipedArgToken() => super.pipedArgToken().map((each) => pipedArg);

  @override
  Parser pipeToken() => super.pipeToken().map((each) => LispParserPipe());
}

void rewriteAnonymousArgs(List<ScExpr> exprs, List<int> argsNths) {
  for (int i = 0; i < exprs.length; i++) {
    final e = exprs[i];
    if (e is ScSymbol) {
      if (isAnonymousArg(e)) {
        final rewritten = rewriteAnonymousArg(e);
        final nth = nthOfArg(e);
        argsNths.add(nth);
        exprs[i] = rewritten;
      }
    } else if (e is ScInvocation) {
      final nestedExprs = e.exprs;
      rewriteAnonymousArgs(nestedExprs.innerList, argsNths);
    }
  }
}

ScList listsToScLists(List<dynamic> parsedValues) {
  List<ScExpr> list = [];
  for (final value in parsedValues) {
    if (value is List) {
      list.add(listsToScLists(value));
    } else {
      list.add(value);
    }
  }
  return ScList(list);
}

/// Parse piped expressions.
ScInvocation windUpPipes(ScEnv env, ScList scListExprs) {
  final headExprs = scListExprs[0] as ScList;
  final tailExprs = scListExprs[1] as ScList;
  if (headExprs.isEmpty) {
    return ScInvocation(ScList([]));
  } else if (tailExprs.isEmpty) {
    // NB: Edit in concert with below.
    if (headExprs.length == 1) {
      final value = headExprs[0];
      if (value is ScInvocation) {
        return value;
      } else if (value is ScSymbol) {
        if (env.isBound(value)) {
          final binding = env[value]!;
          if (binding is ScBaseInvocable) {
            return ScInvocation(ScList([binding]));
          } else {
            return ScInvocation(ScList([ScFnIdentity(), binding]));
          }
        } else {
          throw UndefinedSymbolException(
              value, "The read symbol `$value` is undefined.");
        }
      } else if (value is ScBaseInvocable) {
        // NB: Functions are generally invoked, rather than returned as values themselves.
        return ScInvocation(ScList([value]));
      } else {
        return ScInvocation(ScList([ScFnIdentity(), value]));
      }
    } else {
      if (headExprs.contains(pipedArg)) {
        throw MisplacedPipedArg("Piped arguments only make sense after pipes.");
      }
      return ScInvocation(headExprs);
    }
  } else {
    // Neither head nor tail is empty
    // NB: Edit in concert with above.
    ScInvocation innermostInvocation;
    if (headExprs.length == 1) {
      final value = headExprs[0];
      if (value is ScInvocation) {
        innermostInvocation = value;
      } else if (value is ScSymbol) {
        if (env.isBound(value)) {
          final binding = env[value]!;
          if (binding is ScBaseInvocable) {
            innermostInvocation = ScInvocation(ScList([binding]));
          } else {
            innermostInvocation =
                ScInvocation(ScList([ScFnIdentity(), binding]));
          }
        } else {
          throw UndefinedSymbolException(
              value, "The read symbol `$value` is undefined.");
        }
      } else if (value is ScBaseInvocable) {
        // NB: Functions are generally invoked, rather than returned as values themselves.
        innermostInvocation = ScInvocation(ScList([value]));
      } else {
        innermostInvocation = ScInvocation(ScList([ScFnIdentity(), value]));
      }
    } else {
      if (headExprs.contains(pipedArg)) {
        throw MisplacedPipedArg("Piped arguments only make sense after pipes.");
      }
      innermostInvocation = ScInvocation(headExprs);
    }

    // This skip skips the Pipe
    ScList pipedExpr = ScList.from((tailExprs[0] as ScList).skip(1))[0];
    final pipedArgIdx = pipedExpr.indexOf(pipedArg);
    if (pipedArgIdx != -1) {
      final anotherPipedArgIdx = pipedExpr.lastIndexOf(pipedArg);
      if (anotherPipedArgIdx != pipedArgIdx) {
        throw ExtraneousPipedArg(
            "Only one piped arg per piped expression is supported.");
      }
      pipedExpr[pipedArgIdx] = innermostInvocation;
    } else {
      // NB: This implemented thread-last as the default.
      // pipedExpr.add(innermostInvocation);

      // Thread-first as the default:
      //  - Item 0 is the invocable
      //  - Put innermostInvocation as the first _argument_ to that invocable.
      pipedExpr.insert(1, innermostInvocation);
    }
    final nextInvocation = ScInvocation(pipedExpr);
    if (tailExprs.length == 1) {
      return nextInvocation;
    } else {
      // Recursion. Could tie in pipedExpr from above, but for now this is fine.
      var lastInvocation = nextInvocation;
      // This skip skips the nextInvocation specified above.
      for (final scList in tailExprs.skip(1).innerList) {
        // This skip skips the Pipe
        final piped = ScList.from((scList as ScList).skip(1))[0];
        final pai = piped.indexOf(pipedArg);
        if (pai != -1) {
          piped[pai] = lastInvocation;
        } else {
          // NB: This implemented thread-last as the default.
          // piped.add(lastInvocation);
          piped.insert(1, lastInvocation);
        }
        lastInvocation = ScInvocation(piped);
      }
      return lastInvocation;
    }
  }
}

extension ScParsing on Parser {
  /// Return an [ScList] of all [ScExpr] in the given [input] program.
  ScInvocation readProgram(ScEnv env, String input) {
    final parseResult = parse(input);
    if (parseResult.isSuccess) {
      final parsedValues = List<List<dynamic>>.from(parseResult.value);
      final scExprs = listsToScLists(parsedValues);
      final invocation = windUpPipes(env, scExprs);
      return invocation;
    } else {
      final pointer = (' ' * parseResult.position) + '^';
      throw LispParserException(
          "${parseResult.message}\n${parseResult.buffer}\n$pointer");
    }
  }

  /// Return the first [ScExpr] found in the given [input] program. Parses the
  /// entire [input].
  ScExpr readString(String input) {
    final parseResult = parse(input);
    return listsToScLists(parseResult.value);
  }
}

/// Singletons

final pipedArg = LispParserPipedArg();

class LispParserPipedArg implements ScExpr {
  /// The piped argument symbol
  factory LispParserPipedArg() => _instance;

  /// Private ctor for [LispParserPipedArg]
  LispParserPipedArg._internal();

  /// Singleton instance of [LispParserPipedArg]
  static final LispParserPipedArg _instance = LispParserPipedArg._internal();

  @override
  ScExpr eval(ScEnv env) {
    // Tagged as ScExpr for consistency; not evaluatable on its own.
    throw UnimplementedError();
  }

  @override
  void print(ScEnv env) {
    // Tagged as ScExpr for consistency; not printable on its own.
  }

  @override
  String printToString(ScEnv env) {
    // Tagged as ScExpr for consistency; not printable on its own.
    throw UnimplementedError();
  }

  @override
  String informalTypeName() {
    // Tagged as ScExpr for consistency; type name not meaningful.
    throw UnimplementedError();
  }
}

class LispParserPipe implements ScExpr {
  /// The | symbol
  static final LispParserPipe _instance = LispParserPipe._internal();

  /// Private ctor for [LispParserPipe]
  factory LispParserPipe() => _instance;

  /// Singleton instance of [LispParserPipe]
  LispParserPipe._internal();

  @override
  ScExpr eval(ScEnv env) {
    // Tagged as ScExpr for consistency; not evaluatable on its own.
    throw UnimplementedError();
  }

  @override
  void print(ScEnv env) {
    // Tagged as ScExpr for consistency; not printable on its own.
  }

  @override
  String printToString(ScEnv env) {
    // Tagged as ScExpr for consistency; not printable on its own.
    throw UnimplementedError();
  }

  @override
  String informalTypeName() {
    // Tagged as ScExpr for consistency; type name not meaningful.
    throw UnimplementedError();
  }
}

/// Functions

ScSymbol rewriteAnonymousArg(ScSymbol sym) {
  if (sym == ScSymbol('%')) {
    return ScSymbol('%1');
  } else {
    return ScSymbol(sym.toString().substring(0, 2));
  }
}

int gensymNum = 0;
ScSymbol gensym({prefix = 'gensym'}) {
  gensymNum++;
  return ScSymbol("$prefix$gensymNum");
}

/// Exceptions

class BadString extends ExceptionWithMessage {
  BadString(String message) : super(message);
}

class BadMap extends ExceptionWithMessage {
  final List<dynamic> rawEntries;
  BadMap(String message, this.rawEntries) : super(message);
}

class BadDef extends ExceptionWithMessage {
  BadDef(String message) : super(message);
}

class BadFn extends ExceptionWithMessage {
  BadFn(String message) : super(message);
}

class BadAnonymousInvocableException extends ExceptionWithMessage {
  BadAnonymousInvocableException(String? message) : super(message);
}

class MisplacedPipedArg extends ExceptionWithMessage {
  MisplacedPipedArg(String message) : super(message);
}

class ExtraneousPipedArg extends ExceptionWithMessage {
  ExtraneousPipedArg(String message) : super(message);
}

class LispParserException extends ExceptionWithMessage {
  LispParserException(String message) : super(message);
}
