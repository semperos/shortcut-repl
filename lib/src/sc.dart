import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math';

import 'package:chalkdart/chalk.dart';
import 'package:chalkdart/colorutils.dart';
import 'package:intl/intl.dart';
import 'package:petitparser/petitparser.dart';
import 'package:sc_cli/sc_static.dart';
import 'package:sc_cli/src/sc_api.dart' show ScClient, handleJsonNonEncodable;
import 'package:sc_cli/src/sc_async.dart';
import 'package:sc_cli/src/sc_config.dart';
import 'package:sc_cli/src/sc_lang.dart';
import 'package:sc_cli/src/sc_style.dart';

class ScEnv {
  ScInteractivityState interactivityState;

  ScMap membersById = ScMap({});
  ScMap teamsById = ScMap({});
  ScMap workflowsById = ScMap({});
  ScMap workflowStatesById = ScMap({});
  ScMap customFieldsById = ScMap({});
  ScMap customFieldEnumValuesById = ScMap({});
  ScEpicWorkflow? epicWorkflow;
  late final String baseConfigDirPath;

  /// Prefer [ScEnv.fromMap] or [ScEnv.readFromDisk]
  ScEnv(this.client)
      : isReplMode = false,
        isAnsiEnabled = true,
        isAccessibleColors = false,
        isPrintJson = false,
        interactivityState = ScInteractivityState.normal,
        out = stdout,
        err = stderr,
        history = [];

  late Parser<dynamic> scParser;

  File? envFile;
  File? historyFile;
  List<String> history;

  int displayWidth = 120;

  int indentIndex = 0;
  int indentSize = 2;

  Map<ScString, int> resolutionDepth = {};

  ReplAnswer lastAnswer = ReplAnswer.no;
  bool isExpectingBindingAnswer = false;
  ScSymbol? symbolBeingDefined;
  bool bindNextValue = false;

  /// Is the environment a REPL or script being evaluated non-interactively?
  bool isReplMode;

  /// Should strings be printed using ANSI color codes?
  bool isAnsiEnabled;

  bool isAccessibleColors;

  bool isPrintJson;

  /// Client to Shortcut API
  final ScClient client;

  /// The [parentEntity] represents the Shortcut entity that is the current parent/container.
  ScEntity? parentEntity;
  late List<ScEntity> parentEntityHistory;
  int parentEntityHistoryCursor = 0;

  // TODO Create a base namespace that symbols auto-resolve to, so if someone accidentally shadows one of these they can `undef` there's and get back the original.
  // TODO These keys need to be derived from canonicalName and additional aliases need to be added to the classes that need them.
  /// IDEA Have the functions here mapped to their _classes_ so that debug mode can re-construct them with each evaluation for better code reloading support.
  /// The default bindings of this [ScEnv] give identifiers values in code.
  static Map<ScSymbol, dynamic> defaultBindings = {
    ScSymbol('*1'): ScNil(),
    ScSymbol('*2'): ScNil(),
    ScSymbol('*3'): ScNil(),

    ScSymbol('true'): ScBoolean.veritas(),
    ScSymbol('false'): ScBoolean.falsitas(),
    ScSymbol('if'): ScFnIf(),
    ScSymbol('assert'): ScFnAssert(),

    ScSymbol('nil'): ScNil(),

    ScSymbol('invoke'): ScFnInvoke(),
    ScSymbol('apply'): ScFnApply(),
    ScSymbol('id'): ScFnIdentity(),
    ScSymbol('identity'): ScFnIdentity(),
    ScSymbol('just'): ScFnIdentity(),
    ScSymbol('return'): ScFnIdentity(),
    ScSymbol('value'): ScFnIdentity(), // esp. for fn as value
    ScSymbol('type'): ScFnType(),
    ScSymbol('undef'): ScFnUndef(),
    ScSymbol('resolve'): ScFnResolve(),

    ScSymbol('dt'): ScFnDateTime(),
    ScSymbol('now'): ScFnDateTimeNow(),
    ScSymbol('to-utc'): ScFnDateTimeToUtc(),
    ScSymbol('to-local'): ScFnDateTimeToLocal(),
    ScSymbol('before?'): ScFnDateTimeIsBefore(),
    ScSymbol('after?'): ScFnDateTimeIsAfter(),
    ScSymbol('year'): ScFnDateTimeField(ScDateTimeFormat.year),
    ScSymbol('month'): ScFnDateTimeField(ScDateTimeFormat.month),
    ScSymbol('week-of-year'): ScFnDateTimeField(ScDateTimeFormat.weekOfYear),
    ScSymbol('date-of-month'): ScFnDateTimeField(ScDateTimeFormat.dateOfMonth),
    ScSymbol('day-of-week'): ScFnDateTimeField(ScDateTimeFormat.dayOfWeek),
    ScSymbol('hour'): ScFnDateTimeField(ScDateTimeFormat.hour),
    ScSymbol('minute'): ScFnDateTimeField(ScDateTimeFormat.minute),
    ScSymbol('second'): ScFnSecond(),
    ScSymbol('millisecond'): ScFnDateTimeField(ScDateTimeFormat.millisecond),
    ScSymbol('microsecond'): ScFnDateTimeField(ScDateTimeFormat.microsecond),
    ScSymbol('plus-microseconds'):
        ScFnDateTimePlus(ScDateTimeUnit.microseconds),
    ScSymbol('plus-milliseconds'):
        ScFnDateTimePlus(ScDateTimeUnit.milliseconds),
    ScSymbol('plus-seconds'): ScFnDateTimePlus(ScDateTimeUnit.seconds),
    ScSymbol('plus-minutes'): ScFnDateTimePlus(ScDateTimeUnit.minutes),
    ScSymbol('plus-hours'): ScFnDateTimePlus(ScDateTimeUnit.hours),
    ScSymbol('plus-days'): ScFnDateTimePlus(ScDateTimeUnit.days),
    ScSymbol('plus-weeks'): ScFnDateTimePlus(ScDateTimeUnit.weeks),
    ScSymbol('minus-microseconds'):
        ScFnDateTimeMinus(ScDateTimeUnit.microseconds),
    ScSymbol('minus-milliseconds'):
        ScFnDateTimeMinus(ScDateTimeUnit.milliseconds),
    ScSymbol('minus-seconds'): ScFnDateTimeMinus(ScDateTimeUnit.seconds),
    ScSymbol('minus-minutes'): ScFnDateTimeMinus(ScDateTimeUnit.minutes),
    ScSymbol('minus-hours'): ScFnDateTimeMinus(ScDateTimeUnit.hours),
    ScSymbol('minus-days'): ScFnDateTimeMinus(ScDateTimeUnit.days),
    ScSymbol('minus-weeks'): ScFnDateTimeMinus(ScDateTimeUnit.weeks),
    ScSymbol('microseconds-until'):
        ScFnDateTimeUntil(ScDateTimeUnit.microseconds),
    ScSymbol('milliseconds-until'):
        ScFnDateTimeUntil(ScDateTimeUnit.milliseconds),
    ScSymbol('seconds-until'): ScFnDateTimeUntil(ScDateTimeUnit.seconds),
    ScSymbol('minutes-until'): ScFnDateTimeUntil(ScDateTimeUnit.minutes),
    ScSymbol('hours-until'): ScFnDateTimeUntil(ScDateTimeUnit.hours),
    ScSymbol('days-until'): ScFnDateTimeUntil(ScDateTimeUnit.days),
    ScSymbol('weeks-until'): ScFnDateTimeUntil(ScDateTimeUnit.weeks),
    ScSymbol('microseconds-since'):
        ScFnDateTimeSince(ScDateTimeUnit.microseconds),
    ScSymbol('milliseconds-since'):
        ScFnDateTimeSince(ScDateTimeUnit.milliseconds),
    ScSymbol('seconds-since'): ScFnDateTimeSince(ScDateTimeUnit.seconds),
    ScSymbol('minutes-since'): ScFnDateTimeSince(ScDateTimeUnit.minutes),
    ScSymbol('hours-since'): ScFnDateTimeSince(ScDateTimeUnit.hours),
    ScSymbol('days-since'): ScFnDateTimeSince(ScDateTimeUnit.days),
    ScSymbol('weeks-since'): ScFnDateTimeSince(ScDateTimeUnit.weeks),

    // REPL Helpers

    ScSymbol('help'): ScFnHelp(),
    ScSymbol('?'): ScFnHelp(),
    ScSymbol('print'): ScFnPrint(''),
    ScSymbol('println'): ScFnPrint('\n'),
    ScSymbol('pr-str'): ScFnPrStr(),

    // Parent Entity History

    ScSymbol('b'): ScFnBackward(),
    ScSymbol('back'): ScFnBackward(),
    ScSymbol('backward'): ScFnBackward(),
    ScSymbol('f'): ScFnForward(),
    ScSymbol('forward'): ScFnForward(),
    ScSymbol('history'): ScFnHistory(),
    ScSymbol('p'): ScFnBackward(),
    ScSymbol('prev'): ScFnBackward(),
    ScSymbol('previous'): ScFnBackward(),
    ScSymbol('n'): ScFnForward(),
    ScSymbol('next'): ScFnForward(),
    ScSymbol('..'): ScNil(),

    // Collections

    ScSymbol('for-each'): ScFnMap(),
    ScSymbol('map'): ScFnMap(),
    ScSymbol('reduce'): ScFnReduce(),
    ScSymbol('concat'): ScFnConcat(),
    ScSymbol('extend'): ScFnExtend(),
    ScSymbol('keys'): ScFnKeys(),
    ScSymbol('select'): ScFnSelect(),
    ScSymbol('where'): ScFnWhere(),
    ScSymbol('filter'): ScFnWhere(),
    ScSymbol('limit'): ScFnTake(),
    ScSymbol('take'): ScFnTake(),
    ScSymbol('skip'): ScFnDrop(),
    ScSymbol('drop'): ScFnDrop(),
    ScSymbol('distinct'): ScFnDistinct(),
    ScSymbol('uniq'): ScFnDistinct(),
    ScSymbol('reverse'): ScFnReverse(),

    ScSymbol('search'): ScFnSearch(),
    ScSymbol('grep'): ScFnSearch(),
    ScSymbol('me'): ScFnMe(),
    ScSymbol('whoami'): ScFnMe(),
    ScSymbol('find-stories'): ScFnFindStories(),

    ScSymbol('+'): ScFnAdd(),
    ScSymbol('-'): ScFnSubtract(),
    ScSymbol('*'): ScFnMultiply(),
    ScSymbol('/'): ScFnDivide(),
    ScSymbol('mod'): ScFnModulo(),
    ScSymbol('='): ScFnEquals(),
    ScSymbol('>'): ScFnGreaterThan(),
    ScSymbol('>='): ScFnGreaterThanOrEqualTo(),
    ScSymbol('<'): ScFnLessThan(),
    ScSymbol('<='): ScFnLessThanOrEqualTo(),
    ScSymbol('max'): ScFnMax(),
    ScSymbol('min'): ScFnMin(),

    ScSymbol('when-nil'): ScFnWhenNil(),
    ScSymbol('get'): ScFnGet(),
    ScSymbol('get-in'): ScFnGetIn(),
    ScSymbol('count'): ScFnCount(),
    ScSymbol('len'): ScFnCount(),
    ScSymbol('length'): ScFnCount(),
    ScSymbol('split'): ScFnSplit(),
    ScSymbol('join'): ScFnJoin(),
    ScSymbol('sort'): ScFnSort(),
    ScSymbol('contains?'): ScFnContains(),
    ScSymbol('subset?'): ScFnIsSubset(),

    ScSymbol('file'): ScFnFile(),
    ScSymbol('read-file'): ScFnReadFile(),
    ScSymbol('write-file'): ScFnWriteFile(),
    ScSymbol('clip'): ScFnClipboard(),
    ScSymbol('clipboard'): ScFnClipboard(),
    ScSymbol('interpret'): ScFnInterpret(),
    ScSymbol('load'): ScFnLoad(),
    ScSymbol('open'): ScFnOpen(),
    ScSymbol('edit'): ScFnEdit(),

    ScSymbol('color'): ScFnColor(),

    // Entities

    ScSymbol('default'): ScFnDefault(),
    ScSymbol('defaults'): ScFnDefaults(),
    ScSymbol('setup'): ScFnSetup(),

    ScSymbol('cd'): ScFnCd(),
    ScSymbol('ls'): ScFnLs(),
    ScSymbol('cwd'): ScFnCwd(),
    ScSymbol('.'): ScFnCwd(),
    ScSymbol('pwd'): ScFnPwd(),
    ScSymbol('data'): ScFnData(),
    ScSymbol('details'): ScFnDetails(),
    ScSymbol('summary'): ScFnSummary(),
    ScSymbol('fetch'): ScFnFetch(),
    ScSymbol('fetch-all'): ScFnFetchAll(),
    ScSymbol('create'): ScFnCreate(),
    ScSymbol('create-comment'): ScFnCreateComment(),
    ScSymbol('create-epic'): ScFnCreateEpic(),
    ScSymbol('create-iteration'): ScFnCreateIteration(),
    ScSymbol('create-label'): ScFnCreateLabel(),
    ScSymbol('create-milestone'): ScFnCreateMilestone(),
    ScSymbol('create-story'): ScFnCreateStory(),
    ScSymbol('create-task'): ScFnCreateTask(),
    ScSymbol('new'): ScFnCreate(),
    ScSymbol('new-comment'): ScFnCreateComment(),
    ScSymbol('new-epic'): ScFnCreateEpic(),
    ScSymbol('new-iteration'): ScFnCreateIteration(),
    ScSymbol('new-label'): ScFnCreateLabel(),
    ScSymbol('new-milestone'): ScFnCreateMilestone(),
    ScSymbol('new-story'): ScFnCreateStory(),
    ScSymbol('new-task'): ScFnCreateTask(),
    ScSymbol('!'): ScFnUpdate(),
    ScSymbol('update!'): ScFnUpdate(),
    ScSymbol('mv!'): ScFnMv(),
    // ScSymbol('unstarted'): ScFnUnstarted(),
    // ScSymbol('in-progress'): ScFnInProgress(),
    // ScSymbol('done'): ScFnDone(),
    ScSymbol('next-state!'): ScFnNextState(),
    ScSymbol('prev-state!'): ScFnPreviousState(),
    ScSymbol('previous-state!'): ScFnPreviousState(),
    ScSymbol('story'): ScFnStory(),
    ScSymbol('st'): ScFnStory(),
    ScSymbol('stories'): ScFnStories(),
    ScSymbol('task'): ScFnTask(),
    ScSymbol('tk'): ScFnTask(),
    ScSymbol('comment'): ScFnComment(),
    ScSymbol('cm'): ScFnComment(),
    ScSymbol('epic-comment'): ScFnEpicComment(),
    ScSymbol('ec'): ScFnEpicComment(),
    ScSymbol('epic'): ScFnEpic(),
    ScSymbol('ep'): ScFnEpic(),
    ScSymbol('epics'): ScFnEpics(),
    ScSymbol('milestone'): ScFnMilestone(),
    ScSymbol('mi'): ScFnMilestone(),
    ScSymbol('milestones'): ScFnMilestones(),
    ScSymbol('iteration'): ScFnIteration(),
    ScSymbol('it'): ScFnIteration(),
    ScSymbol('iterations'): ScFnIterations(),
    ScSymbol('member'): ScFnMember(),
    ScSymbol('mb'): ScFnMember(),
    ScSymbol('members'): ScFnMembers(),
    ScSymbol('team'): ScFnTeam(),
    ScSymbol('tm'): ScFnTeam(),
    ScSymbol('teams'): ScFnTeams(),
    ScSymbol('label'): ScFnLabel(),
    ScSymbol('lb'): ScFnLabel(),
    ScSymbol('labels'): ScFnLabels(),
    ScSymbol('custom-fields'): ScFnCustomFields(),
    ScSymbol('custom-field'): ScFnCustomField(),
    ScSymbol('cf'): ScFnCustomField(),
    ScSymbol('workflow'): ScFnWorkflow(),
    ScSymbol('wf'): ScFnWorkflow(),
    ScSymbol('workflows'): ScFnWorkflows(),
    ScSymbol('epic-workflow'): ScFnEpicWorkflow(),
    ScSymbol('ew'): ScFnEpicWorkflow(),
  };

  final Map<ScSymbol, ScString> runtimeHelp = {
    ScSymbol('first'): ScString("Returns the first element of a collection."),
    ScSymbol('second'): ScString("Returns the second element of a collection."),
    ScSymbol('third'): ScString("Returns the third element of a collection."),
    ScSymbol('fourth'): ScString("Returns the fourth element of a collection."),
    ScSymbol('fifth'): ScString("Returns the fifth element of a collection."),
    ScSymbol('sixth'): ScString("Returns the sixth element of a collection."),
    ScSymbol('seventh'):
        ScString("Returns the seventh element of a collection."),
    ScSymbol('eighth'): ScString("Returns the eighth element of a collection."),
    ScSymbol('ninth'): ScString("Returns the ninth element of a collection."),
    ScSymbol('tenth'): ScString("Returns the tenth element of a collection."),
    ScSymbol('not'):
        ScString("Returns true if falsey; return false if truthy."),
    ScSymbol('or'): ScString(
        "Returns the first argument that is truthy, or the last argument if none are truthy.`"),
    ScSymbol('when'): ScString(
        "If the condition is truthy, invokes the function provided, else returns `nil`."),
    ScSymbol('first-where'): ScString(
        "Returns the first item of the collection where the map spec or function provided returns truthy."),
    ScSymbol('sum'):
        ScString("Returns the sum of the numbers in the collection."),
    ScSymbol('avg'): ScString(
        "Returns the arithmetic mean of the numbers in the collection."),
    ScSymbol('mapcat'): ScString(
        "Apply the function to every item in the collection, then concatenate all the resulting collections."),
    // Archived
    ScSymbol('query-archived'): ScString(
        "Use with `find-stories`, narrow results to archived stories."),
    ScSymbol('query-not-archived'): ScString(
        "Use with `find-stories`, narrow results to stories that aren't archived (default state of new stories)."),
    // Completed At
    ScSymbol('query-completed-at-start'): ScString(
        "Use with `find-stories`, narrow results to stories completed after the given date-time."),
    ScSymbol('query-completed-at-after'): ScString(
        "Use with `find-stories`, narrow results to stories completed after the given date-time."),
    ScSymbol('query-completed-after'): ScString(
        "Use with `find-stories`, narrow results to stories completed after the given date-time."),
    ScSymbol('query-completed-at-end'): ScString(
        "Use with `find-stories`, narrow results to stories completed before the given date-time."),
    ScSymbol('query-completed-at-before'): ScString(
        "Use with `find-stories`, narrow results to stories completed before the given date-time."),
    ScSymbol('query-completed-before'): ScString(
        "Use with `find-stories`, narrow results to stories completed before the given date-time."),
    // Created At
    ScSymbol('query-created-at-start'): ScString(
        "Use with `find-stories`, narrow results to stories created after the given date-time."),
    ScSymbol('query-created-at-after'): ScString(
        "Use with `find-stories`, narrow results to stories created after the given date-time."),
    ScSymbol('query-created-after'): ScString(
        "Use with `find-stories`, narrow results to stories created after the given date-time."),
    ScSymbol('query-created-at-end'): ScString(
        "Use with `find-stories`, narrow results to stories created before the given date-time."),
    ScSymbol('query-created-before'): ScString(
        "Use with `find-stories`, narrow results to stories created before the given date-time."),
    ScSymbol('query-created-before'): ScString(
        "Use with `find-stories`, narrow results to stories created before the given date-time."),
    ScSymbol('query-created-at-start'): ScString(
        "Use with `find-stories`, narrow results to stories created after the given date-time."),
    // Deadline
    ScSymbol('query-deadline-end'): ScString(
        "Use with `find-stories`, narrow results to stories with a deadline before the given date-time."),
    ScSymbol('query-deadline-before'): ScString(
        "Use with `find-stories`, narrow results to stories with a deadline before the given date-time."),
    ScSymbol('query-deadline-start'): ScString(
        "Use with `find-stories`, narrow results to stories with a deadline after the given date-time."),
    ScSymbol('query-deadline-after'): ScString(
        "Use with `find-stories`, narrow results to stories with a deadline after the given date-time."),
    // Epic
    ScSymbol('query-epic'): ScString(
        "Use with `find-stories`, narrow results to stories in the given epic."),
    ScSymbol('query-epics'): ScString(
        "Use with `find-stories`, narrow results to stories in the given epics."),
  };

  Map<ScSymbol, dynamic> bindings =
      Map<ScSymbol, dynamic>.from(defaultBindings);

  IOSink out;
  IOSink err;

  ScExpr? operator [](ScSymbol bindingKey) {
    return bindings[bindingKey];
  }

  void operator []=(ScSymbol symbol, ScExpr expr) {
    bindings[symbol] = expr;
  }

  void removeBinding(ScSymbol symbol) {
    bindings.remove(symbol);
  }

  bool isBound(ScSymbol symbol) {
    return this[symbol] != null;
  }

  factory ScEnv.readFromDisk({
    required ScClient client,
    isReplMode = false,
    isAnsiEnabled = false,
    isAccessibleColors = false,
    isPrintJson = false,
    required IOSink out,
    required IOSink err,
    required String baseConfigDirPath,
  }) {
    final envFile = getEnvFile(baseConfigDirPath);
    String contents = envFile.readAsStringSync();
    if (contents.isEmpty) {
      contents = '{"format": "2022.1"}';
    }
    final historyFile = getHistoryFile(baseConfigDirPath);
    final history = historyFile.readAsLinesSync();
    final json = jsonDecode(contents);
    ScEnv env = ScEnv(client);
    env.baseConfigDirPath = baseConfigDirPath;
    env.envFile = envFile;
    env.history = history;
    env.historyFile = historyFile;
    env.isAnsiEnabled = isAnsiEnabled;
    env.isAccessibleColors = isAccessibleColors;
    env.isPrintJson = isPrintJson;
    env.isReplMode = isReplMode;
    env = ScEnv.extendEnvfromMap(env, json);
    return env;
  }

  /// Used in tests.
  factory ScEnv.fromMap(ScClient client, Map<String, dynamic> data) {
    var env = ScEnv(client);
    env = ScEnv.extendEnvfromMap(env, data);
    return env;
  }

  static ScEnv extendEnvfromMap(ScEnv env, Map<String, dynamic> data) {
    ScEntity? parentEntity;
    final p = data['parent'] as Map<String, dynamic>?;
    if (p == null) {
      parentEntity = null;
    } else {
      parentEntity = entityFromEnvJson(p);
      if (parentEntity != null) {
        unawaited(fetchParentAsync(env, parentEntity));
      }
    }

    env.parentEntity = parentEntity;
    // TODO Work out options > config > default flow
    // env.isPrintJson = data['printAsJson'] ?? false;

    final defaultWorkflowId = data['defaultWorkflowId'];
    if (defaultWorkflowId != null) {
      env[ScSymbol('__sc_default-workflow-id')] = ScNumber(defaultWorkflowId);
    }

    final defaultWorkflowStateId = data['defaultWorkflowStateId'];
    if (defaultWorkflowStateId != null) {
      env[ScSymbol('__sc_default-workflow-state-id')] =
          ScNumber(defaultWorkflowStateId);
    }

    final defaultTeamId = data['defaultTeamId'];
    if (defaultTeamId != null) {
      env[ScSymbol('__sc_default-team-id')] = ScString(defaultTeamId);
    }

    final parserDefinition = PipedLispParserDefinition(env);
    final pipedLispParser = parserDefinition.build();
    env.scParser = pipedLispParser;

    final parentHistory = data['parentHistory'];
    if (parentHistory == null) {
      env.parentEntityHistory = [];
    } else {
      final List<ScEntity> l = [];
      try {
        if (parentHistory is List) {
          for (final item in parentHistory) {
            final entity = entityFromEnvJson(item);
            if (entity != null) {
              l.add(entity);
            }
          }
        }
      } catch (_) {
        stderr.writeln(
            "Your ${env.envFile} failed to load correctly. Please fix its JSON if you manually edited it, or remove it for a new one to be generated.");
      }
      env.parentEntityHistory = l;
      if (parentEntity != null) {
        setParentEntity(env, parentEntity);
      }
    }

    env.loadPrelude();

    return env;
  }

  ScExpr interpretAll(String sourceName, List<String> sourceLines) {
    ScExpr returnValue = ScNil();
    final multiLineExprString = StringBuffer();
    for (var i = 0; i < sourceLines.length; i++) {
      final line = sourceLines[i];
      final trimmed = line;
      if (multiLineExprString.isNotEmpty) {
        // Continue building up multi-line program.
        multiLineExprString.write("$trimmed\n");
        final currentProgram = multiLineExprString.toString();
        if (scParser.accept(currentProgram)) {
          try {
            returnValue = interpret(currentProgram);
          } catch (e) {
            if (e is LispParserException) {
              final parseResult = e.parseResult;
              final column = parseResult.position;
              final row = i + 1;
              throw InterpretationException(
                  "Parsing failed at line $row column $column in source code $sourceName");
            } else {
              rethrow;
            }
          }
          multiLineExprString.clear();
        } else if (i == sourceLines.length - 1) {
          throw PrematureEndOfProgram(
              "The code in $sourceName fails to load because the file ended in the middle of parsing. Check matching delimiters and try again.");
        } else {
          continue;
        }
      } else if (trimmed.startsWith(';') || trimmed.startsWith('#')) {
        // Given how the parser is written, a program cannot just
        // be comments. However, given we're doing "one program
        // per line" here, we need to do something a bit janky
        // to satisfy both constraints.
        //
        // Editing the parser involved a lot of changes. This is
        // good enough.
        returnValue = interpret('$line\nnil');
      } else if (!scParser.accept(trimmed)) {
        // Allow multi-line programs
        multiLineExprString.write("$trimmed\n");
        final currentExprString = multiLineExprString.toString();
        // Single-line parenthetical program
        if (scParser.accept(currentExprString)) {
          try {
            returnValue = interpret(currentExprString);
          } catch (e) {
            if (e is LispParserException) {
              final parseResult = e.parseResult;
              final column = parseResult.position;
              final row = i + 1;
              throw InterpretationException(
                  "Parsing failed at line $row column $column in source code $sourceName");
            } else {
              rethrow;
            }
          }
          multiLineExprString.clear();
        } else if (i == sourceLines.length - 1) {
          throw PrematureEndOfProgram(
              "The code in $sourceName fails to load because the file ended in the middle of parsing. Check matching delimiters and try again.");
        } else {
          continue;
        }
      } else {
        try {
          returnValue = interpret(line);
        } catch (e) {
          if (e is LispParserException) {
            final parseResult = e.parseResult;
            final column = parseResult.position;
            final row = i + 1;
            throw InterpretationException(
                "Parsing failed at line $row column $column in source code $sourceName");
          } else {
            rethrow;
          }
        }
      }
    }
    return returnValue;
  }

  ScExpr interpret(String exprString) {
    final expr = scEval(this, readExprString(exprString));
    if (isReplMode) {
      final trimmed = exprString.trim();
      if (trimmed == '*1' || trimmed == '*2' || trimmed == '*3') {
        // Pass: Let user check these values without affecting them.
      } else {
        final star2 = this[ScSymbol('*2')];
        final star1 = this[ScSymbol('*1')];
        if (star2 != null) this[ScSymbol('*3')] = star2;
        if (star1 != null) this[ScSymbol('*2')] = star1;
        this[ScSymbol('*1')] = expr;
      }
    }
    return expr;
  }

  ScExpr readExprString(String exprString) {
    return scRead(this, exprString);
  }

  /// Prelude/core/definitions of the language beyond the absolute basics which
  /// have been implemented directly in Dart. These will have markedly worse
  /// error messages compared to those built-in ones.
  void loadPrelude() {
    final prelude = r'''
;; Accessors
def first   value (fn first [coll] (get coll 0))
;; `second` is custom to handle both coll and date-time values
def third   value (fn third [coll] (get coll 2))
def fourth  value (fn fourth [coll] (get coll 3))
def fifth   value (fn fifth [coll] (get coll 4))
def sixth   value (fn sixth [coll] (get coll 5))
def seventh value (fn seventh [coll] (get coll 6))
def eighth  value (fn eighth [coll] (get coll 7))
def ninth   value (fn ninth [coll] (get coll 8))
def tenth   value (fn tenth [coll] (get coll 9))
def last    value (fn last [coll] (get coll (- (count coll) 1)))

;; Conditionals
def not         value (fn not [x] (if x %(value false) %(value true)))
def or          value (fn or [this that] ((fn [this-res] (if this-res %(value this-res) that)) (this)))
def when        value (fn when [condition then-branch] (if condition then-branch %(identity nil)))
def first-where value (fn first-where [coll where-clause] (first (where coll where-clause)))

;; Mathematics
def sum value (fn sum [coll] (reduce coll 0 +))
def avg value (fn avg [coll] (/ (reduce coll +) (count coll)))

;; Collections
def mapcat value (fn mapcat [coll f] (apply (map coll f) concat))

;; Query Builders
def query-archived     {.archived true}
def query-not-archived {.archived false}

def query-completed-at-start value (fn query-completed-at-start [dt]
 (assert (= "date-time" (type dt))
         (concat "query-completed-at-start expects a date-time, but received a " (type dt)))
 {.completed_at_start dt})
def query-completed-at-after value query-completed-at-start
def query-completed-after value query-completed-at-start

def query-completed-at-end value (fn query-completed-at-end [dt]
 (assert (= "date-time" (type dt))
         (concat "query-completed-at-start expects a date-time, but received a " (type dt)))
 {.completed_at_end dt})
def query-completed-at-before value query-completed-at-end
def query-completed-before value query-completed-at-end

def query-created-at-start value (fn query-created-at-start [dt]
 (assert (= "date-time" (type dt))
         (concat "query-created-at-start expects a date-time, but received a " (type dt)))
 {.created_at_start dt})
def query-created-at-after value query-created-at-start
def query-created-after value query-created-at-start

def query-created-at-end value (fn query-created-at-end [dt]
 (assert (= "date-time" (type dt))
         (concat "query-created-at-start expects a date-time, but received a " (type dt)))
 {.created_at_end dt})
def query-created-at-before value query-created-at-end
def query-created-before value query-created-at-end

def query-deadline-start value (fn query-deadline-start [dt]
 (assert (= "date-time" (type dt))
         (concat "query-deadline-start expects a date-time, but received a " (type dt)))
 {.deadline_start dt})
def query-deadline-after value query-deadline-start

def query-deadline-end value (fn query-deadline-end [dt]
 (assert (= "date-time" (type dt))
         (concat "query-deadline-end expects a date-time, but received a " (type dt)))
 {.deadline_end dt})
def query-deadline-before value query-deadline-end

def query-epic  value (fn query-epic [epic] {.epic_id epic})
def query-epics value (fn query-epics [epics] {.epic_ids epics})

def query-estimate value (fn query-estimate [estimate] {.estimate estimate})
def query-external-id value (fn query-estimate [external-id] {.external_id external-id})

def query-group value (fn query-group [group] {.group_id group})
def query-team value (fn query-team [team] {.team_id team})
def query-groups value (fn query-groups [groups] {.group_ids groups})
def query-teams value (fn query-teams [teams] {.team_ids teams})

def query-includes-description {.includes_description true}
def query-not-include-description {.includes_description true}
def query-has-description {.includes_description true}
def query-not-have-description {.includes_description true}

def query-iteration  value (fn query-iteration [iteration] {.iteration_id iteration})
def query-iterations value (fn query-iterations [iterations] {.iteration_ids iterations})

def query-label-name value (fn query-label-name [label-name] {.label_name label-name})
def query-labels value (fn query-labels [labels] {.label_ids labels})


def query-owner value (fn query-owner [member]
 (assert (subset? [(type member)] ["member" "string"])
         (concat "query-owned-by expects a member (or its ID), but received a " (type member)))
 {.owner_id member})

def query-owners value (fn query-owners [members]
  (assert (= "list" (type members))
          (concat "query-owners expects a list, but received a " (type members)))
  (assert (subset? (distinct (map members %(type %))) ["member" "string"])
          (concat "query-owners expects a list of members, but received a list with types " (map members type)))
  {.owner_ids members})

def query-requested-by value (fn query-requested-by [member]
 (assert (subset? [(type member)] ["member" "string"])
         (concat "query-requested-by expects a member, but received a " (type member)))
 {.requested_by_id member})

def query-bug                {.story_type "bug"}
def query-story-type-bug     {.story_type "bug"}
def query-chore              {.story_type "chore"}
def query-story-type-chore   {.story_type "chore"}
def query-feature            {.story_type "feature"}
def query-story-type-feature {.story_type "feature"}

def query-updated-at-start value (fn query-updated-at-start [dt]
 (assert (= "date-time" (type dt))
         (concat "query-updated-at-start expects a date-time, but received a " (type dt)))
 {.updated_at_start dt})
def query-updated-at-after value query-updated-at-start

def query-updated-at-end value (fn query-updated-at-end [dt]
 (assert (= "date-time" (type dt))
         (concat "query-updated-at-start expects a date-time, but received a " (type dt)))
 {.updated_at_at_end dt})
def query-updated-at-before value query-updated-at-end

def query-workflow-state value (fn query-workflow-state [workflow-state] {.workflow_state_id workflow-state})
def query-state value (fn query-state [workflow-state] {.workflow_state_id workflow-state})

def query-workflow-state-types value (fn query-workflow-state-types [wf-state-types] {.workflow_state_types wf-state-types})
def query-state-types          value (fn query-state-types [wf-state-types] {.workflow_state_types wf-state-types})

def query-unfinished   {.workflow_state_types ["unstarted" "started"]}
def query-incomplete   query-unfinished
def query-not-done     query-unfinished
def query-not-finished query-unfinished

def query-started     {.workflow_state_types ["started"]}
def query-in-progress query-started

def query-finished {.workflow_state_types ["done"]}
def query-complete query-finished
def query-done     query-finished

def epic-is-unstarted   {.state "to do"}
def epic-is-todo        {.state "to do"}
def epic-is-in-progress {.state "in progress"}
def epic-is-started     {.state "in progress"}
def epic-is-done        {.state "done"}
def epic-is-finished    {.state "done"}
def epic-is-completed   {.state "done"}

def story-is-unstarted   {[.workflow_state_id .type] "unstarted"}
def story-is-todo        {[.workflow_state_id .type] "unstarted"}
def story-is-in-progress {[.workflow_state_id .type] "started"}
def story-is-started     {[.workflow_state_id .type] "started"}
def story-is-done        {[.workflow_state_id .type] "done"}
def story-is-finished    {[.workflow_state_id .type] "done"}
def story-is-completed   {[.workflow_state_id .type] "done"}

def story-is-archived {.archived true}
def story-is-not-archived {.archived false};
def story-is-blocked {.blocked true}
def story-is-blocker {.blocker true}

def story-is-completed-at value (fn story-is-completed-at [completed-at] {.completed_at completed-at})
def story-was-completed-at value (fn story-was-completed-at [completed-at] {.completed_at completed-at})

def story-is-completed-at-override value (fn story-is-completed-at-override [completed-at] {.completed_at_override completed-at})
def story-was-completed-at-override value (fn story-was-completed-at-override [completed-at] {.completed_at_override completed-at})

def story-is-created-at value (fn story-is-created-at [created-at] {.created_at created-at})
def story-was-created-at value (fn story-was-created-at [created-at] {.created_at created-at})

;; TODO Custom fields

def story-is-cycle-time-greater-than value (fn story-is-cycle-time-greater-than [cycle-time] {.cycle_time (fn [t] (> t cycle-time))})
def story-has-cycle-time-greater-than value (fn story-has-cycle-time-greater-than [cycle-time] {.cycle_time (fn [t] (> t cycle-time))})
def story-is-cycle-time-less-than value (fn story-is-cycle-time-less-than [cycle-time] {.cycle_time (fn [t] (< t cycle-time))})
def story-has-cycle-time-less-than value (fn story-has-cycle-time-less-than [cycle-time] {.cycle_time (fn [t] (< t cycle-time))})
def story-is-cycle-time-of value (fn story-is-cycle-time-of [cycle-time] {.cycle_time cycle-time})
def story-has-cycle-time-of value (fn story-has-cycle-time-of [cycle-time] {.cycle_time cycle-time})

def story-is-deadline-of value (fn story-is-deadline-of [deadline] {.deadline deadline})
def story-has-deadline-of value (fn story-has-deadline-of [deadline] {.deadline deadline})
def story-is-deadline-after value (fn story-is-deadline-after [deadline] {.deadline (fn [dt] (after? dt deadline))})
def story-has-deadline-after value (fn story-has-deadline-after [deadline] {.deadline (fn [dt] (after? dt deadline))})
def story-is-deadline-before value (fn story-is-deadline-before [deadline] {.deadline (fn [dt] (before? dt deadline))})
def story-has-deadline-before value (fn story-has-deadline-before [deadline] {.deadline (fn [dt] (before? dt deadline))})

def story-is-description-includes value (fn story-is-description-includes [desc] {.description (fn [s] (contains? s desc))})
def story-is-description-contains value (fn story-is-description-contains [desc] {.description (fn [s] (contains? s desc))})
def story-has-description-including value (fn story-has-description-including [desc] {.description (fn [s] (contains? s desc))})
def story-has-description-containing value (fn story-has-description-containing [desc] {.description (fn [s] (contains? s desc))})

def story-is-in-epic value (fn story-is-in-epic [epic] {.epic_id epic})
def story-is-epic-id value (fn story-is-epic-id [epic] {.epic_id epic})
def story-has-epic-id value (fn story-has-epic-id [epic] {.epic_id epic})

def story-is-estimate value (fn story-is-estimate [est] {.estimate est})
def story-has-estimate value (fn story-has-estimate [est] {.estimate est})
def story-is-estimate-greater-than value (fn story-is-estimate-greater-than [est] {.estimate (fn [e] (> (when-nil e 0) est))})
def story-has-estimate-greater-than value (fn story-has-estimate-greater-than [est] {.estimate (fn [e] (> (when-nil e 0) est))})
def story-is-estimate-less-than value (fn story-is-estimate-less-than [est] {.estimate (fn [e] (< (when-nil e 0) est))})
def story-has-estimate-less-than value (fn story-has-estimate-less-than [est] {.estimate (fn [e] (< (when-nil e 0) est))})

def story-is-external-id value (fn story-is-external-id [ext-id] {.external_id ext-id})
def story-has-external-id value (fn story-has-external-id [ext-id] {.external_id ext-id})

def story-is-external-links value (fn story-is-external-links [links]
                                      (if (= "list" (type links))
                                        %(just {.external_links (fn [lnks] (subset? links lnks))})
                                        %(just {.external_links (fn [lnks] (contains? lnks links))})))
def story-has-external-links value (fn story-has-external-links [links]
                                       (if (= "list" (type links))
                                         %(just {.external_links (fn [lnks] (subset? links lnks))})
                                         %(just {.external_links (fn [lnks] (contains? lnks links))})))

def story-is-followers value (fn story-is-followers [followers] {.follower_ids (fn [flwrs] (subset? followers flwrs))})
def story-has-followers value (fn story-has-followers [followers] {.follower_ids (fn [flwrs] (subset? followers flwrs))})
def story-is-follower-ids value (fn story-is-follower-ids [followers] {.follower_ids (fn [flwrs] (subset? followers flwrs))})
def story-has-follower-ids value (fn story-has-follower-ids [followers] {.follower_ids (fn [flwrs] (subset? followers flwrs))})

def story-is-group value (fn story-is-group [group] {.group_id group})
def story-is-team value (fn story-is-team [group] {.group_id group})
def story-is-owned-by-group value (fn story-is-owned-by-group [group] {.group_id group})
def story-is-owned-by-team value (fn story-is-owned-by-team [group] {.group_id group})

def story-is-group-mentions value (fn story-is-group-mentions [groups] {.group_mention_ids (fn [gmis] (subset? groups gmis))})
def story-is-group-mention-ids value (fn story-is-group-mention-ids [groups] {.group_mention_ids (fn [gmis] (subset? groups gmis))})
def story-has-group-mentions value (fn story-has-group-mentions [groups] {.group_mention_ids (fn [gmis] (subset? groups gmis))})
def story-has-group-mention-ids value (fn story-has-group-mention-ids [groups] {.group_mention_ids (fn [gmis] (subset? groups gmis))})
def story-is-team-mentions value (fn story-is-team-mentions [groups] {.group_mention_ids (fn [gmis] (subset? groups gmis))})
def story-is-team-mention-ids value (fn story-is-team-mention-ids [groups] {.group_mention_ids (fn [gmis] (subset? groups gmis))})
def story-has-team-mentions value (fn story-has-team-mentions [groups] {.group_mention_ids (fn [gmis] (subset? groups gmis))})
def story-has-team-mention-ids value (fn story-has-team-mention-ids [groups] {.group_mention_ids (fn [gmis] (subset? groups gmis))})

def story-is-iteration value (fn story-is-iteration [iteration] {.iteration_id iteration})
def story-has-iteration value (fn story-has-iteration [iteration] {.iteration_id iteration})
def story-is-in-iteration value (fn story-is-in-iteration [iteration] {.iteration_id iteration})

def story-is-labels value (fn story-is-labels [labels] {.label_ids (fn [lbls] (subset? labels lbls))})
def story-has-labels value (fn story-has-labels [labels] {.label_ids (fn [lbls] (subset? labels lbls))})
def story-is-label-ids value (fn story-is-label-ids [labels] {.label_ids (fn [lbls] (subset? labels lbls))})
def story-has-label-ids value (fn story-has-label-ids [labels] {.label_ids (fn [lbls] (subset? labels lbls))})

;; TODO Investigate why higher-order function not working for story-is-label-names

def iteration-is-unstarted   {.status "unstarted"}
def iteration-is-todo        {.status "unstarted"}
def iteration-is-in-progress {.status "started"}
def iteration-is-started     {.status "started"}
def iteration-is-done        {.status "done"}
def iteration-is-finished    {.status "done"}
def iteration-is-completed   {.status "done"}

def type-is-story     value (fn type-is-story [x] (= "story" (type x)))
def type-is-epic      value (fn type-is-epic [x] (= "epic" (type x)))
def type-is-milestone value (fn type-is-milestone [x] (= "milestone" (type x)))
def type-is-iteration value (fn type-is-iteration [x] (= "iteration" (type x)))

;; Entities

def comments value .comments

;; Entity States

def story-states         value (fn story-states [entity] (ls (.workflow_id (fetch entity))))
def epic-states          value (fn epic-states [entity] (ls (epic-workflow)))
def workflow-state-types ["unstarted" "started" "done"]

;; Entity Updates

def add-label value (fn add-label [story label-name] (! story .labels [{.name label-name}]))
def add-labels value (fn add-labels [story label-names] (! story .labels (map label-names %(just {.name %}))))

def set-custom-field value (fn set-custom-field [story field-id value-id] (! story .custom_fields [{.field_id field-id .value_id value-id}]))
def add-custom-field value set-custom-field

def my-stories value (fn my-stories []
 (find-stories (extend
                 (query-owner (me))
                 query-not-finished
                 query-not-archived)))

def current-stories value (fn current-stories [entity]
 (if (= "member" (type entity))
   %(find-stories (extend
                   (query-owner entity)
                   query-not-finished
                   query-not-archived))
   %(find-stories (extend
                   (query-group entity)
                   query-not-finished
                   query-not-archived))))

def recent-stories value (fn recent-stories [entity]
 (if (= "member" (type entity))
   %(find-stories (extend
                   (query-owner entity)
                   query-done
                   (query-completed-after (minus-weeks (now) 2))
                   query-not-archived))
   %(find-stories (extend
                   (query-group entity)
                   query-done
                   (query-completed-after (minus-weeks (now) 2))
                   query-not-archived))))


def my-iterations value (fn my-iterations []
  (map (where (map (my-stories) .iteration_id) identity) fetch))

def current-iteration value (fn current-iteration [team]
  (where (iterations team) iteration-is-in-progress))

def current-epics value (fn current-epics [team]
  (where (epics team) epic-is-in-progress))

;; TODO Consider best way to prompt folks to setup defaults. Printing here does it in all the tests.
; def -priv-defaults defaults
; when (= nil (.team -priv-defaults)) %(println "[INFO] Don't forget to set a default team with `default .team <your team>`")
; when (= nil (.workflow -priv-defaults)) %(println "[INFO] Don't forget to set a default workflow with `default .workflow <your workflow>`")
; when (= nil (.workflow-state -priv-defaults)) %(println "[INFO] Don't forget to set a default workflow state with `default .workflow-state <your workflow state>`")
''';
    interpretAll("<built-in prelude source>", prelude.split('\n'));
  }

  void writeHistory() {
    // NB: Truncation to max history length happens in cli_repl land.
    if (historyFile != null) {
      File hf = historyFile!;
      final sink = hf.openWrite(mode: FileMode.writeOnly);
      for (final line in history) {
        sink.writeln(line);
      }
      sink.close();
    }
  }

  Iterable<String> autoCompletionsFrom(String autoCompletePrefix) {
    List<String> matches = [];

    // Matches on keys of `cd`ed-into parent entity
    if (autoCompletePrefix.startsWith('.')) {
      final actualPrefix = autoCompletePrefix.substring(1);

      if (parentEntity != null) {
        final pe = parentEntity!;
        final keys = pe.data.keys.toList();
        for (final k in keys) {
          if (k is ScString) {
            final kStr = k.value;
            if (kStr.startsWith(actualPrefix)) {
              matches.add(kStr);
            }
          }
        }
      }
      for (final s in knownJsonFields) {
        if (s.startsWith(actualPrefix)) {
          matches.add(s);
        }
      }
    } else {
      // All bindings in the [ScEnv]
      matches.addAll(bindings.keys
          .map((sym) => sym.toString())
          .where((s) => s.startsWith(autoCompletePrefix))
          .toList());
    }

    List<String> dedupedMatches = [];
    for (final item in matches) {
      if (!dedupedMatches.contains(item)) {
        dedupedMatches.add(item);
      }
    }
    return dedupedMatches;
  }

  indentString() => ' ' * (indentSize * indentIndex);

  String stringWithIndent(String s) {
    return indentString() + s;
  }

  String style(String s, Object o, {List<String>? styles}) {
    if (isAnsiEnabled) {
      var palette = defaultDarkPalette;
      if (isAccessibleColors) {
        palette = colorBlindDarkPalette;
      }
      if (o is ScExpr) {
        return styleStringForScExpr(palette, o, s, styles: styles);
      } else {
        return styleString(palette, o.toString(), s, styles: styles);
      }
    } else {
      return s;
    }
  }

  String toJson() {
    JsonEncoder jsonEncoder = JsonEncoder.withIndent('  ');
    Map<String, dynamic> m = {};
    // Because otherwise the JSON is malformed when written
    if (parentEntity != null) {
      final pe = parentEntity!;

      String title;
      if (pe is ScTask) {
        final desc = pe.data[ScString('description')];
        if (desc is ScString) {
          title = desc.value;
        } else {
          title = '<No description found>';
        }
      } else if (pe is ScMember) {
        final profile = pe.data[ScString('profile')];
        if (profile is ScMap) {
          final name = profile[ScString('name')];
          if (name is ScString) {
            title = name.value;
          } else {
            title = '<No name in member profile found>';
          }
        } else {
          title = '<No member profile found>';
        }
      } else {
        final name = pe.data[ScString('name')];
        if (name is ScString) {
          title = name.value;
        } else if (pe.title != null) {
          title = pe.title!.value;
        } else {
          title = '<No name: fetch the entity>';
        }
      }

      m['parent'] = {
        'entityType': pe.typeName(),
        'entityId': pe.idString,
        'entityTitle': title,
      };

      ScExpr? entityContainerId;
      if (pe is ScComment) {
        entityContainerId = pe.storyId;
      } else if (pe is ScEpicComment) {
        entityContainerId = pe.epicId;
      } else if (pe is ScTask) {
        entityContainerId = pe.storyId;
      }

      if (entityContainerId != null) {
        if (entityContainerId is ScString) {
          m['parent']['entityContainerId'] = entityContainerId.value;
        } else {
          m['parent']['entityContainerId'] = entityContainerId.toString();
        }
      }
    }

    final rawDefaultWorkflowId = this[ScSymbol('__sc_default-workflow-id')];
    if (rawDefaultWorkflowId != null) {
      if (rawDefaultWorkflowId is ScNumber) {
        m['defaultWorkflowId'] = rawDefaultWorkflowId.value;
      } else if (rawDefaultWorkflowId is ScString) {
        m['defaultWorkflowId'] = int.tryParse(rawDefaultWorkflowId.value)!;
      }
    }

    final rawDefaultWorkflowStateId =
        this[ScSymbol('__sc_default-workflow-state-id')];
    if (rawDefaultWorkflowStateId != null) {
      if (rawDefaultWorkflowStateId is ScNumber) {
        m['defaultWorkflowStateId'] = rawDefaultWorkflowStateId.value;
      } else if (rawDefaultWorkflowStateId is ScString) {
        m['defaultWorkflowStateId'] =
            int.tryParse(rawDefaultWorkflowStateId.value)!;
      }
    }

    final rawDefaultTeamId = this[ScSymbol('__sc_default-team-id')];
    if (rawDefaultTeamId != null) {
      if (rawDefaultTeamId is ScString) {
        m['defaultTeamId'] = rawDefaultTeamId.value;
      }
    }

    final List<Map<String, dynamic>> pH = [];
    for (final entity in parentEntityHistory) {
      final title = entity.calculateTitle();
      final m = {
        'entityType': entity.typeName(),
        'entityId': entity.idString,
        'entityTitle': title,
      };

      ScExpr? entityContainerId;
      if (entity is ScComment) {
        entityContainerId = entity.storyId;
      } else if (entity is ScEpicComment) {
        entityContainerId = entity.epicId;
      } else if (entity is ScTask) {
        entityContainerId = entity.storyId;
      }

      if (entityContainerId != null) {
        if (entityContainerId is ScString) {
          m['entityContainerId'] = entityContainerId.value;
        } else {
          m['entityContainerId'] = entityContainerId.toString();
        }
      }

      pH.add(m);
    }
    m['parentHistory'] = pH;

    return jsonEncoder.convert(m);
  }

  void writeToDisk() {
    if (envFile != null) {
      final ef = envFile!;
      final sink = ef.openWrite(mode: FileMode.writeOnly);
      final json = toJson();
      sink.write(json);
      sink.close();
    }
  }

  void writeCachesToDisk() {
    if (membersById.isNotEmpty) {
      final f = getCacheMembersFile(baseConfigDirPath);
      final sink = f.openWrite(mode: FileMode.writeOnly);
      final json = membersById.toJson();
      sink.write(json);
      sink.close();
    }
    if (teamsById.isNotEmpty) {
      final f = getCacheTeamsFile(baseConfigDirPath);
      final sink = f.openWrite(mode: FileMode.writeOnly);
      final json = teamsById.toJson();
      sink.write(json);
      sink.close();
    }
    if (workflowsById.isNotEmpty) {
      final f = getCacheWorkflowsFile(baseConfigDirPath);
      final sink = f.openWrite(mode: FileMode.writeOnly);
      final json = workflowsById.toJson();
      sink.write(json);
      sink.close();
    }
    if (customFieldsById.isNotEmpty) {
      final f = getCacheCustomFieldsFile(baseConfigDirPath);
      final sink = f.openWrite(mode: FileMode.writeOnly);
      final json = customFieldsById.toJson();
      sink.write(json);
      sink.close();
    }
    if (epicWorkflow != null) {
      final f = getCacheEpicWorkflowFile(baseConfigDirPath);
      final sink = f.openWrite(mode: FileMode.writeOnly);
      final json = epicWorkflow?.data.toJson();
      sink.write(json);
      sink.close();
    }
  }

  Future<void> loadCachesFromDisk() async {
    try {
      final membersFile = getCacheMembersFile(baseConfigDirPath);
      final teamsFile = getCacheTeamsFile(baseConfigDirPath);
      final customFieldsFile = getCacheCustomFieldsFile(baseConfigDirPath);
      final workflowsFile = getCacheWorkflowsFile(baseConfigDirPath);
      final epicWorkflowFile = getCacheEpicWorkflowFile(baseConfigDirPath);

      final membersStr = await membersFile.readAsString();
      final teamsStr = await teamsFile.readAsString();
      final customFieldsStr = await customFieldsFile.readAsString();
      final workflowsStr = await workflowsFile.readAsString();
      final epicWorkflowStr = await epicWorkflowFile.readAsString();

      final membersMap = jsonDecode(membersStr) as Map;
      final teamsMap = jsonDecode(teamsStr) as Map;
      final customFieldsMap = jsonDecode(customFieldsStr) as Map;
      final workflowsMap = jsonDecode(workflowsStr) as Map;
      final epicWorkflowMap =
          jsonDecode(epicWorkflowStr) as Map<String, dynamic>;

      // These are stored as JSON objects based on their cache
      final membersMaps = membersMap.values;
      final teamsMaps = teamsMap.values;
      final customFieldsMaps = customFieldsMap.values;
      final workflowsMaps = workflowsMap.values;

      final members =
          ScList(membersMaps.map((e) => ScMember.fromMap(this, e)).toList());
      final teams =
          ScList(teamsMaps.map((e) => ScTeam.fromMap(this, e)).toList());
      final customFields = ScList(
          customFieldsMaps.map((e) => ScCustomField.fromMap(this, e)).toList());
      final workflows = ScList(
          workflowsMaps.map((e) => ScWorkflow.fromMap(this, e)).toList());
      if (epicWorkflowMap.isEmpty) {
        final epicWorkflowFn = ScFnEpicWorkflow();
        epicWorkflow =
            epicWorkflowFn.invoke(this, ScList([])) as ScEpicWorkflow;
      } else {
        epicWorkflow = ScEpicWorkflow.fromMap(this, epicWorkflowMap);
      }

      cacheMembers(members);
      cacheTeams(teams);
      cacheCustomFields(customFields);
      cacheWorkflows(workflows);
      cacheEpicWorkflow(epicWorkflow!);
    } catch (e, st) {
      stderr.writeln(e);
      stderr.writeln(st);
      stderr.writeln(
          '[ERROR] Your cache files are malformed. Please delete the "cache*.json" files in $baseConfigDirPath');
    }
  }

  void interactiveStartBinding(ScSymbol symbol) {
    symbolBeingDefined = symbol;
  }

  void addAnonymousFunctionBindings(ScList args) {
    for (int i = 0; i < args.length; i++) {
      final sym = ScSymbol('%${i + 1}');
      this[sym] = args[i];
    }
  }

  void removeAnonymousFunctionBindings(ScList args) {
    for (int i = 0; i < args.length; i++) {
      final sym = ScSymbol('%${i + 1}');
      removeBinding(sym);
    }
  }

  void startInteractionCreateEntity(ScString? entityType) {
    interactivityState = ScInteractivityState.startCreateEntity;
    if (entityType != null) {
      this[ScSymbol('__sc_entity-type')] = entityType;
    }
  }

  void finishInteractionCreateEntity() {
    interactivityState = ScInteractivityState.normal;
  }

  void cacheMembers(ScList members) {
    ScMap m = ScMap({});
    for (final member in members.innerList) {
      final memberId = (member as ScMember).id;
      m[memberId] = member;
    }
    membersById = m;
  }

  ScMember resolveMember(ScEnv env, ScString memberId) {
    final maybeCachedMember = membersById[memberId];
    if (maybeCachedMember != null) {
      return maybeCachedMember as ScMember;
    } else {
      final member = ScMember(memberId);
      if (env.resolutionDepth[memberId] == null) {
        env.resolutionDepth[memberId] = 0;
      }
      final resolutionDepth = env.resolutionDepth[memberId]!;
      if (resolutionDepth > 2) {
        env.resolutionDepth[memberId] = 0;
        return member;
      } else {
        env.resolutionDepth[memberId] = resolutionDepth + 1;
        waitOn(member.fetch(this));
        membersById[memberId] = member;
        return member;
      }
    }
  }

  void cacheTeams(ScList teams) {
    ScMap m = ScMap({});
    for (final team in teams.innerList) {
      final teamId = (team as ScTeam).id;
      m[teamId] = team;
    }
    teamsById = m;
  }

  ScTeam resolveTeam(ScEnv env, ScString teamId) {
    final maybeCachedTeam = teamsById[teamId];
    if (maybeCachedTeam != null) {
      return maybeCachedTeam as ScTeam;
    } else {
      final team = ScTeam(teamId);
      if (env.resolutionDepth[teamId] == null) {
        env.resolutionDepth[teamId] = 0;
      }
      final resolutionDepth = env.resolutionDepth[teamId]!;
      if (resolutionDepth > 2) {
        env.resolutionDepth[teamId] = 0;
        return team;
      } else {
        env.resolutionDepth[teamId] = resolutionDepth + 1;
        waitOn(team.fetch(this));
        teamsById[teamId] = team;
        return team;
      }
    }
  }

  void cacheWorkflows(ScList workflows) {
    ScMap m = ScMap({});
    ScMap statesM = ScMap({});
    for (final workflow in workflows.innerList) {
      final workflowId = (workflow as ScWorkflow).id;
      m[workflowId] = workflow;
      final states = workflow.data[ScString('states')];
      for (final state in (states as ScList).innerList) {
        final workflowStateId = (state as ScWorkflowState).id;
        statesM[workflowStateId] = state;
      }
    }
    workflowsById = m;
    workflowStatesById = statesM;
  }

  void cacheCustomFields(ScList customFields) {
    ScMap m = ScMap({});
    ScMap valuesM = ScMap({});
    for (final customField in customFields.innerList) {
      final customFieldId = (customField as ScCustomField).id;
      m[customFieldId] = customField;
      final customFieldEnumValues = customField.data[ScString('values')];
      if (customFieldEnumValues is ScList) {
        for (final customFieldEnumValue in customFieldEnumValues.innerList) {
          if (customFieldEnumValue is ScCustomFieldEnumValue) {
            valuesM[customFieldEnumValue.id] = customFieldEnumValue;
          }
        }
      }
    }
    customFieldsById = m;
    customFieldEnumValuesById = valuesM;
  }

  ScCustomField resolveCustomField(ScString customFieldId) {
    final maybeCachedCustomField = customFieldsById[customFieldId];
    if (maybeCachedCustomField != null) {
      return maybeCachedCustomField as ScCustomField;
    } else {
      final customField = ScCustomField(customFieldId);
      waitOn(customField.fetch(this));
      customFieldsById[customFieldId] = customField;
      return customField;
    }
  }

  ScCustomFieldEnumValue resolveCustomFieldEnumValue(
      ScString customFieldEnumValueId) {
    final maybeCachedCustomFieldEnumValue =
        customFieldEnumValuesById[customFieldEnumValueId];
    if (maybeCachedCustomFieldEnumValue != null) {
      return maybeCachedCustomFieldEnumValue as ScCustomFieldEnumValue;
    } else {
      return ScCustomFieldEnumValue(customFieldEnumValueId);
    }
  }

  ScWorkflow resolveWorkflow(ScString workflowId) {
    final maybeCachedWorkflow = workflowsById[workflowId];
    if (maybeCachedWorkflow != null) {
      return maybeCachedWorkflow as ScWorkflow;
    } else {
      final workflow = ScWorkflow(workflowId);
      waitOn(workflow.fetch(this));
      workflowsById[workflowId] = workflow;
      return workflow;
    }
  }

  ScWorkflowState resolveWorkflowState(ScString workflowStateId) {
    final maybeCachedWorkflowState = workflowStatesById[workflowStateId];
    if (maybeCachedWorkflowState != null) {
      return maybeCachedWorkflowState as ScWorkflowState;
    } else {
      return ScWorkflowState(workflowStateId);
    }
  }

  void cacheEpicWorkflow(ScEpicWorkflow fetchedEpicWorkflow) {
    epicWorkflow = fetchedEpicWorkflow;
  }

  ScEpicWorkflow resolveEpicWorkflow() {
    if (epicWorkflow != null) {
      return epicWorkflow!;
    } else {
      final epicWorkflowFn = ScFnEpicWorkflow();
      epicWorkflow = epicWorkflowFn.invoke(this, ScList([])) as ScEpicWorkflow;
      return epicWorkflow!;
    }
  }

  ScEpicWorkflowState resolveEpicWorkflowState(ScString epicWorkflowStateId) {
    if (epicWorkflow == null) {
      resolveEpicWorkflow();
    }
    final epicStates = epicWorkflow?.data[ScString('epic_states')] as ScList;
    for (final epicState in epicStates.innerList) {
      final es = epicState as ScEpicWorkflowState;
      if (es.id == epicWorkflowStateId) {
        return es;
      }
    }
    throw BadArgumentsException(
        "Couldn't resolve epic workflow state with ID $epicWorkflowStateId");
  }

  void addFnBindings(ScList params, ScList args) {
    for (int i = 0; i < params.length; i++) {
      // ScSymbol type is checked by caller
      final sym = params[i] as ScSymbol;
      final arg = args[i];
      this[sym] = arg;
    }
  }

  void removeFnBindings(ScList params, ScList args) {
    for (final param in params.innerList) {
      final sym = param as ScSymbol;
      removeBinding(sym);
    }
  }

  /// Tip: Check for args.isEmpty && env.parentEntity == null before calling this where needed (e.g., for fns that can do meaningful work in the absence of both an explicit arg or a parent entity).
  ScEntity resolveArgEntity(ScList args, String fnName,
      {forceFetch = false, nthArg = 'first', forceParent = false}) {
    ScEntity entity;
    if (forceParent) {
      if (parentEntity == null) {
        throw BadArgumentsException(
            "Developer error: The `$fnName` function expected to find parent entity defined, but didn't.");
      } else {
        entity = parentEntity!;
        if (entity.data.isEmpty && !forceFetch) waitOn(entity.fetch(this));
        if (forceFetch) entity.fetch(this);
      }
    } else if (args.isEmpty) {
      if (parentEntity == null) {
        throw BadArgumentsException(
            "If calling The `$fnName` function with no arguments, a parent entity must be active (`cd` into one).");
      } else {
        entity = parentEntity!;
        if (entity.data.isEmpty && !forceFetch) waitOn(entity.fetch(this));
        if (forceFetch) waitOn(entity.fetch(this));
      }
    } else {
      final maybeEntity = args[0];
      if (maybeEntity is ScEntity) {
        entity = maybeEntity;
        if (entity.data.isEmpty && !forceFetch) waitOn(entity.fetch(this));
        if (forceFetch) entity.fetch(this);
        args.innerList.removeAt(0);
      } else if (maybeEntity is ScNumber) {
        entity = waitOn(fetchId(this, maybeEntity.value.toString()));
        args.innerList.removeAt(0);
      } else if (maybeEntity is ScString) {
        entity = waitOn(fetchId(this, maybeEntity.value));
        args.innerList.removeAt(0);
      } else {
        throw BadArgumentsException(
            "The `$fnName` function's $nthArg argument must be an entity or its ID, but received a ${maybeEntity.typeName()}");
      }
    }
    return entity;
  }
}

Future<ScExpr> ls(ScEnv env) async {
  final parent = env.parentEntity;
  if (parent == null) {
    return await env.client.getCurrentMember(env);
  } else if (parent.data.isEmpty) {
    await parent.fetch(env);
    return parent.ls(env);
  } else {
    return parent.ls(env);
  }
}

abstract class AbstractScExpr {
  ScExpr eval(ScEnv env);
  void print(ScEnv env);
  String printToString(ScEnv env);
  String toJson();
  String typeName();
}

class ScExpr extends AbstractScExpr {
  /// ScExprs evaluate to themselves by default.
  @override
  ScExpr eval(ScEnv env) {
    return this;
  }

  @override
  void print(ScEnv env) {
    env.out.write(printToString(env));
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return toJson();
    } else {
      return toString();
    }
  }

  @override
  String toJson() {
    return toString();
  }

  @override
  String typeName() {
    return 'expression';
  }
}

extension ObjectToScExpr on Object {
  ScExpr toScExpr() {
    return ScNil();
  }
}

extension NumToScExpr on num {
  ScExpr toScExpr() {
    return ScNumber(this);
  }
}

extension StringToScExpr on String {
  ScExpr toScExpr() {
    return ScString(this);
  }
}

extension DateTimeToScExpr on DateTime {
  ScExpr toScExpr() {
    return ScDateTime(this);
  }
}

extension on String {
  String capitalize() {
    return "${substring(0, 1).toUpperCase()}${substring(1).toLowerCase()}";
  }
}

class ScNil extends ScExpr {
  static final ScNil _instance = ScNil._internal();
  ScNil._internal();
  factory ScNil() => _instance;

  @override
  String toString() {
    return 'nil';
  }

  @override
  String typeName() {
    return 'nil';
  }

  @override
  String printToString(ScEnv env) {
    return env.style('nil', styleNil);
  }
}

class ScBoolean extends ScExpr {
  static final ScBoolean _instanceTrue = ScBoolean._internalTrue();
  static final ScBoolean _instanceFalse = ScBoolean._internalFalse();
  ScBoolean._internalTrue();
  ScBoolean._internalFalse();
  factory ScBoolean.veritas() => _instanceTrue;
  factory ScBoolean.falsitas() => _instanceFalse;
  factory ScBoolean.fromBool(bool b) {
    if (b) {
      return ScBoolean.veritas();
    } else {
      return ScBoolean.falsitas();
    }
  }

  bool toBool() {
    return this == ScBoolean.veritas() ? true : false;
  }

  factory ScBoolean.fromTruthy(ScExpr expr) {
    if (isTruthy(expr)) {
      return ScBoolean.veritas();
    } else {
      return ScBoolean.falsitas();
    }
  }

  static bool isTruthy(ScExpr expr) {
    return !(expr == ScBoolean.falsitas() || expr == ScNil());
  }

  @override
  String toString() {
    if (this == _instanceTrue) {
      return "true";
    } else {
      return "false";
    }
  }

  @override
  String printToString(ScEnv env) {
    return env.style(super.printToString(env), this);
  }

  @override
  String typeName() {
    return 'boolean';
  }
}

class ScNumber extends ScExpr implements Comparable {
  ScNumber(this.value);
  final num value;

  @override
  String toString() {
    return value.toString();
  }

  @override
  String printToString(ScEnv env) {
    return env.style(super.printToString(env), this);
  }

  @override
  String typeName() {
    return 'number';
  }

  @override
  bool operator ==(Object other) {
    return other is ScNumber && value == other.value;
  }

  bool operator >(ScNumber n) {
    return value > n.value;
  }

  bool operator <(ScNumber n) {
    return value < n.value;
  }

  bool operator >=(ScNumber n) {
    return value >= n.value;
  }

  bool operator <=(ScNumber n) {
    return value <= n.value;
  }

  @override
  int get hashCode => 31 + value.hashCode;

  @override
  int compareTo(other) {
    if (other is ScNumber) {
      return value.compareTo(other.value);
    } else if (other is ScExpr) {
      throw BadArgumentsException(
          "You cannot sort a number with a ${other.typeName()}");
    } else {
      throw BadArgumentsException(
          "You cannot sort a number with a ${other.runtimeType}");
    }
  }

  ScNumber add(ScNumber other) {
    return ScNumber(value + other.value);
  }

  ScNumber subtract(ScNumber other) {
    return ScNumber(value - other.value);
  }

  ScNumber multiply(ScNumber other) {
    return ScNumber(value * other.value);
  }

  ScNumber divide(ScNumber other) {
    return ScNumber(value / other.value);
  }
}

class ScString extends ScExpr implements Comparable {
  ScString(this.value);
  final String value;

  @override
  String toString() {
    return "\"${value.toString().replaceAll('"', '\\"')}\"";
  }

  @override
  String printToString(ScEnv env) {
    return env.style(toString(), this);
  }

  @override
  String typeName() {
    return 'string';
  }

  ScList split({required ScString separator}) {
    return ScList(
        value.split(separator.value).map((s) => ScString(s)).toList());
  }

  @override
  bool operator ==(Object other) => other is ScString && value == other.value;

  @override
  int get hashCode => 31 + value.hashCode;

  @override
  int compareTo(other) {
    if (other is ScString) {
      return value.compareTo(other.value);
    } else if (other is String) {
      return value.compareTo(other);
    } else if (other is ScExpr) {
      throw UnsupportedError(
          "You cannot sort a string with a ${other.typeName()}");
    } else {
      throw UnsupportedError(
          "You cannot sort a string with a ${other.runtimeType}");
    }
  }

  static final isBlankRegExp = RegExp(r'^\s*$');
  bool isBlank() {
    return value.isEmpty || isBlankRegExp.hasMatch(value);
  }
}

class ScDateTime extends ScExpr implements Comparable {
  ScDateTime(this.value);
  final DateTime value;

  @override
  String toString() {
    return value.toString();
  }

  @override
  String printToString(ScEnv env) {
    final sb = StringBuffer();
    sb.write(lParen(env));
    sb.write("dt ");
    sb.write(env.style('"${toString()}"', this));
    sb.write(rParen(env));
    return sb.toString();
  }

  @override
  String typeName() {
    return 'date-time';
  }

  @override
  bool operator ==(Object other) => other is ScDateTime && value == other.value;

  @override
  int get hashCode => 31 + value.hashCode;

  @override
  int compareTo(other) {
    if (other is ScDateTime) {
      return value.compareTo(other.value);
    } else if (other is DateTime) {
      return value.compareTo(other);
    } else if (other is ScExpr) {
      throw UnsupportedError(
          "You cannot sort a string with a ${other.typeName()}");
    } else {
      throw UnsupportedError(
          "You cannot sort a string with a ${other.runtimeType}");
    }
  }
}

/// Adapted from https://github.com/petitparser/dart-petitparser-examples/blob/main/lib/src/lisp/name.dart
class ScSymbol extends ScExpr implements Comparable {
  /// Factory for new symbol cells.
  factory ScSymbol(String name) =>
      _interned.putIfAbsent(name, () => ScSymbol._internal(name));

  /// Internal constructor for symbol.
  ScSymbol._internal(this._name);

  /// The interned symbols.
  static final Map<String, ScSymbol> _interned = {};

  /// The name of the symbol.
  final String _name;

  /// Returns the string representation of the symbolic name.
  @override
  String toString() => _name;

  @override
  String printToString(ScEnv env) {
    String str = toString();
    if (env.isPrintJson) {
      str = '"$str"';
    }
    return env.style(str, this);
  }

  @override
  String typeName() {
    return 'symbol';
  }

  @override
  ScExpr eval(ScEnv env) {
    if (env.bindings.containsKey(this)) {
      return env.bindings[this];
    } else if (isAnonymousArg(this)) {
      return this;
    } else {
      throw UndefinedSymbolException(this, "Symbol `$this` is undefined.");
    }
  }

  @override
  int compareTo(other) {
    if (other is ScSymbol) {
      return _name.compareTo(other._name);
    } else if (other is ScDottedSymbol) {
      return _name.compareTo(other._name);
    } else if (other is ScString) {
      return _name.compareTo(other.value);
    } else if (other is String) {
      return _name.compareTo(other);
    } else if (other is ScExpr) {
      throw UnsupportedError(
          "You cannot sort a symbol with a ${other.typeName()}");
    } else {
      throw UnsupportedError(
          "You cannot sort a symbol with a ${other.runtimeType}");
    }
  }
}

class ScDottedSymbol extends ScExpr implements ScBaseInvocable {
  /// Factory for new symbol cells.
  factory ScDottedSymbol(String name) =>
      _interned.putIfAbsent(name, () => ScDottedSymbol._internal(name));

  /// Internal constructor for symbol.
  ScDottedSymbol._internal(this._name);

  String get name => toString();

  /// The interned symbols.
  static final Map<String, ScDottedSymbol> _interned = {};

  /// The name of the symbol.
  final String _name;

  ScSymbol get scSymbol => ScSymbol(_name);

  /// Returns the string representation of the symbolic name.
  @override
  String toString() => ".$_name";

  @override
  String printToString(ScEnv env) {
    String str = super.printToString(env);
    if (env.isPrintJson) {
      str = '"$_name"';
    }
    return env.style(str, this);
  }

  @override
  String typeName() {
    return 'dotted symbol';
  }

  @override
  ScExpr eval(ScEnv env) {
    return this;
  }

  @override
  String get help =>
      'Dotted symbol evaluates to itself, but can be invoked to `get` itself out of collections';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""If there is a parent entity defined (you've `cd`ed into an entity), then a dotted symbol will try to look itself up in the data of that entity.

When used within a structure that gets serialized to JSON and sent to Shortcut, dotted symbols become simple strings of their names (e.g., .name => "name").
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      if (env.parentEntity == null) {
        return this;
      } else {
        final getFn = ScFnGet();
        return getFn.invoke(env, ScList([env.parentEntity!, this]));
      }
    } else if (args.length == 1) {
      final arg = args[0];
      if (arg is ScMap || arg is ScEntity) {
        args.insertMutable(1, this);
        final getFn = ScFnGet();
        return getFn.invoke(env, args);
      } else {
        if (env.parentEntity != null) {
          // NB: Arg is a "default if not found" value when pulling out of the parent entity
          final getFn = ScFnGet();
          return getFn.invoke(env, ScList([env.parentEntity!, this, arg]));
        } else {
          throw BadArgumentsException(
              "If you pass only 1 argument to a dotted symbol, it must either be a map/entity you expect to contain your symbol, or you must be in a parent entity and the argument is considered the default-if-not-found value. Your parent entity is `nil` and you passed this dotted symbol an argument of type ${arg.typeName()}");
        }
      }
    } else if (args.length == 2) {
      // NB: Assumes arg 2 is a "default if not found" which [ScFnGet] supports.
      args.insertMutable(1, this);
      final getFn = ScFnGet();
      return getFn.invoke(env, args);
    } else {
      throw BadArgumentsException(
          "Dotted symbols expect either no arguments, 1 map/entity argument, or 1 map/entity argument and a default-if-not-found value.");
    }
  }

  @override
  Set<List<String>> arities = {
    ["map-or-entity"],
    ["map-or-entity" "default-if-missing"]
  };

  @override

  /// This should never be used.
  String canonicalName = '<dotted symbol>';
}

class ScFile extends ScExpr {
  final File file;
  ScFile(this.file);

  @override
  String toString() {
    return file.path;
  }

  @override
  String typeName() {
    return 'file';
  }

  @override
  String printToString(ScEnv env) {
    final sb = StringBuffer();
    sb.write(lParen(env));
    sb.write("file ");
    sb.write(env.style('"${file.path}"', this));
    sb.write(rParen(env));
    return sb.toString();
  }

  ScString readAsStringSync({Encoding encoding = utf8}) {
    return ScString(file.readAsStringSync(encoding: encoding));
  }
}

// ScFns

abstract class ScBaseInvocable extends ScExpr {
  String canonicalName = '<fn>';

  Set<List<String>> arities = {};

  @override
  String typeName() {
    return 'built-in function';
  }

  @override
  void print(ScEnv env) {
    // env.out.write("<function: $name>");
    env.out.write("<function>");
  }

  ScExpr invoke(ScEnv env, ScList args);
  String get help;
  String get helpFull;
}

/// Class of functions defined in Piped Lisp using `fn`
class ScFunction extends ScBaseInvocable {
  ScFunction(this.name, this.env, this.params, this.bodyExprs) : super();
  final String name;
  final ScEnv env;
  final ScList params;
  final ScList bodyExprs;

  @override
  String get canonicalName => name;

  @override
  Set<List<String>> get arities =>
      {List<ScExpr>.from(params.innerList).map((e) => e.toString()).toList()};

  ScList get getExprs => ScList(List<ScExpr>.from(bodyExprs.innerList));

  @override
  String typeName() {
    return 'function';
  }

  @override
  String get help => "";

  @override
  String get helpFull => '';

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != params.length) {
      // NB: Support fns leveraging implicit env.parentEntity
      if (1 == (params.length - args.length)) {
        if (env.parentEntity != null) {
          args.insertMutable(0, env.parentEntity!);
        } else {
          throw BadArgumentsException(
              "The function expects ${params.length} arguments, but received ${args.length}");
        }
      } else {
        throw BadArgumentsException(
            "The function expects ${params.length} arguments, but received ${args.length}");
      }
    }

    if (bodyExprs.isEmpty) {
      return ScNil();
    } else {
      final originalBindings = Map<ScSymbol, dynamic>.from(env.bindings);
      env.addFnBindings(params, args);
      final theseExprs = getExprs;
      final evaledItems = theseExprs.mapMutable((e) => e.eval(env));
      ScExpr result;
      if (evaledItems.first is ScBaseInvocable) {
        final invocable = evaledItems.first as ScBaseInvocable;
        final returnValue = invocable.invoke(env, theseExprs.skip(1));
        result = returnValue;
      } else {
        result = evaledItems[evaledItems.length - 1];
      }
      // NB: Without proper nested environments, this can remove things bound
      //     before this function was ever invoked, and so is buggy at this time.
      // env.removeFnBindings(params, args);
      env.bindings = originalBindings;
      return result;
    }
  }
}

class ScAnonymousFunction extends ScBaseInvocable {
  ScAnonymousFunction(this.name, this.env, this.numArgs, this.exprs) : super();
  final String name;
  final ScEnv env;
  final int numArgs;
  final ScList exprs;

  @override
  String get canonicalName => name;

  @override
  Set<List<String>> get arities {
    List<String> l = [];
    for (var i = 0; i < numArgs; i++) {
      l.add("arg-${i + 1}");
    }
    return {l};
  }

  ScList get getExprs => ScList(List<ScExpr>.from(exprs.innerList));

  @override
  String typeName() {
    return 'anonymous function';
  }

  @override
  String get help => "";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""Neither do standalone `fn` definitions yet; keep an eye out!""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != numArgs) {
      // NB: Support anon fns leveraging implicit env.parentEntity
      if (1 == (numArgs - args.length)) {
        if (env.parentEntity != null) {
          args.insertMutable(0, env.parentEntity!);
        }
      } else {
        throw BadArgumentsException(
            "The anonymous function expects $numArgs arguments, but received ${args.length}");
      }
    }

    if (exprs.isEmpty) {
      return ScNil();
    } else {
      env.addAnonymousFunctionBindings(args);
      final theseExprs = getExprs;
      final preEvalFirstItem = theseExprs.first;
      final evaledItems = theseExprs.mapMutable((e) {
        if (e is ScSymbol) {
          if (isAnonymousArg(e)) {
            final nth = nthOfArg(e);
            ScExpr arg = args[nth];
            return arg.eval(env);
          } else {
            return e.eval(env);
          }
        } else {
          return e.eval(env);
        }
      });
      if (evaledItems.first is ScBaseInvocable) {
        final invocable = evaledItems.first as ScBaseInvocable;
        final returnValue = invocable.invoke(env, theseExprs.skip(1));
        env.removeAnonymousFunctionBindings(args);
        return returnValue;
      } else if (preEvalFirstItem == ScDottedSymbol('.')) {
        // Special case given how shell-like this whole app is.
        if (evaledItems.first == ScNil()) {
          throw NoParentEntity(
              "No parent entity found. You can only use `..` when you've used `cd` to move into a child entity.");
        } else {
          final returnValue =
              ScInvocation(ScList([ScSymbol('cd'), ScSymbol('..')]));
          env.removeAnonymousFunctionBindings(args);
          return returnValue;
        }
      } else {
        throw UninvocableException(evaledItems);
      }
    }
  }
}

class ScFnIdentity extends ScBaseInvocable {
  static final ScFnIdentity _instance = ScFnIdentity._internal();
  ScFnIdentity._internal();
  factory ScFnIdentity() => _instance;

  @override
  String get canonicalName => 'identity';

  @override
  Set<List<String>> get arities => {
        ["value"]
      };

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      return args.first;
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` functions expects 1 argument, but received ${args.length} arguments.");
    }
  }

  @override
  String get help => "Returns the value it's given.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""You can use `identity` to return a function as a value, rather than invoking it which is the default. This is a way to alias built-in functions or define your own using anonymous function syntax:

def add identity +""";
}

class ScFnType extends ScBaseInvocable {
  static final ScFnType _instance = ScFnType._internal();
  ScFnType._internal();
  factory ScFnType() => _instance;

  @override
  String get canonicalName => 'type';

  @override
  Set<List<String>> get arities => {
        ["value"]
      };
  @override
  String get help => "Returns the name of the type of the value as a string.";

  @override
  String get helpFull =>
      r"""The language provided by this program is a rudimentary Lisp called "Piped Lisp". Its data types are:

  - number
  - string
  - list
  - map
  - function
  - entity

  The `entity` type has the following sub-types:

  - comment
  - epic
  - epic comment
  - epic workflow
  - epic workflow state
  - iteration
  - label
  - member
  - milestone
  - story
  - team
  - task
  - workflow
  - workflow state

  While the Shortcut API and data model support other entities, they are not represented as first-class entities in this tool at this time. Consult the JSON structure of Shortcut API endpoints that include them for further information.
  """;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      return ScString(args[0].typeName());
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects one argument, but received ${args.length}");
    }
  }
}

class ScFnUndef extends ScBaseInvocable {
  static final ScFnUndef _instance = ScFnUndef._internal();
  ScFnUndef._internal();
  factory ScFnUndef() => _instance;

  @override
  String get canonicalName => 'undef';

  @override
  Set<List<String>> get arities => {
        ["symbol"]
      };
  @override
  String get help =>
      "Remove the symbol with the given string or dotted symbol name from the environment's bindings.";

  @override
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final toUnbind = args[0];
      if (toUnbind is ScString) {
        env.removeBinding(ScSymbol(toUnbind.value));
      } else if (toUnbind is ScDottedSymbol) {
        env.removeBinding(ScSymbol(toUnbind._name));
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects either a string or dotted symbol, but received a ${toUnbind.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects only 1 argument, but received ${args.length}");
    }
    return ScNil();
  }
}

class ScFnResolve extends ScBaseInvocable {
  static final ScFnResolve _instance = ScFnResolve._internal();
  ScFnResolve._internal();
  factory ScFnResolve() => _instance;

  @override
  String get canonicalName => 'resolve';

  @override
  Set<List<String>> get arities => {
        ["string-or-dotted-symbol"]
      };

  @override
  String get help =>
      "Attempt to resolve the given string/dotted symbol, returning `nil` if that symbol has no definition in the current environment.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""

This supports dynamic programming and optionally replacing or updating an existing binding.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final x = args[0];
      String symName;
      if (x is ScDottedSymbol) {
        symName = x._name;
      } else if (x is ScString) {
        symName = x.value;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects a string or dotted symbol argument, but received a ${x.typeName()}");
      }
      final boundValue = env.bindings[ScSymbol(symName)];
      if (boundValue == null) {
        return ScNil();
      } else {
        return boundValue;
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnDateTime extends ScBaseInvocable {
  static final ScFnDateTime _instance = ScFnDateTime._internal();
  ScFnDateTime._internal();
  factory ScFnDateTime() => _instance;

  @override
  String get canonicalName => 'date-time';

  @override
  Set<List<String>> get arities => {
        ["date-time-string"]
      };
  @override
  String get help => 'Returns a date-time value for the given string.';

  @override
  String get helpFull =>
      help +
      "\n\n" +
      r"""
Creates a date-time object from an acceptable string.

Examples of valid date-time strings are (taken from Dart's documentation):

    "2012-02-27"
    "2012-02-27 13:27:00"
    "2012-02-27 13:27:00.123456789z"
    "2012-02-27 13:27:00,123456789z"
    "20120227 13:27:00"
    "20120227T132700"
    "20120227"
    "+20120227"
    "2012-02-27T14Z"
    "2012-02-27T14+00:00"
    "-123450101 00:00:00 Z": in the year -12345.
    "2002-02-27T14:00:00-0500": Same as "2002-02-27T19:00:00Z"

For more details, see the Dart `DateTime.parse()` documentation:

https://api.dart.dev/stable/dart-core/DateTime/parse.html""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final dateTimeStr = args[0];
      if (dateTimeStr is ScString) {
        final dateTimeString = dateTimeStr.value;
        final dt = DateTime.tryParse(dateTimeString);
        if (dt == null) {
          throw BadArgumentsException(
              "The `$canonicalName` function couldn't parse the string you provided: $dateTimeStr");
        } else {
          return ScDateTime(dt);
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's argument must be a string, but received a ${dateTimeStr.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects a single string argument, which must be parseable by Dart's `DateTime.parse()` method.");
    }
  }
}

class ScFnDateTimeNow extends ScBaseInvocable {
  static final ScFnDateTimeNow _instance = ScFnDateTimeNow._internal();
  ScFnDateTimeNow._internal();
  factory ScFnDateTimeNow() => _instance;

  @override
  String get canonicalName => 'now';

  @override
  Set<List<String>> get arities => {[]};

  @override
  String get help => 'Returns the current date-time in your local timezone.';

  @override
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 0) {
      return ScDateTime(DateTime.now());
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 0 arguments, but received ${args.length} arguments.");
    }
  }
}

class ScFnDateTimeToUtc extends ScBaseInvocable {
  static final ScFnDateTimeToUtc _instance = ScFnDateTimeToUtc._internal();
  ScFnDateTimeToUtc._internal();
  factory ScFnDateTimeToUtc() => _instance;

  @override
  String get canonicalName => 'to-utc';

  @override
  Set<List<String>> get arities => {
        ["date-time"]
      };

  @override
  String get help => "Convert the date-time to be in the UTC time zone.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""

This does not change the actual instant in history that this date-time represents. It marks the date-time as being in the UTC time zone, so that default string representations add 'Z' for the timezone qualifier.

See also:
  to-local""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final dateTime = args[0];
      if (dateTime is ScDateTime) {
        final dt = dateTime.value;
        if (dt.isUtc) {
          env.err
              .writeln("The date-time value is already in the UTC time zone.");
          return dateTime;
        } else {
          final utcDt = dt.toUtc();
          return ScDateTime(utcDt);
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects a date-time argument, but received a ${dateTime.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnDateTimeToLocal extends ScBaseInvocable {
  static final ScFnDateTimeToLocal _instance = ScFnDateTimeToLocal._internal();
  ScFnDateTimeToLocal._internal();
  factory ScFnDateTimeToLocal() => _instance;

  @override
  String get canonicalName => 'to-local';

  @override
  Set<List<String>> get arities => {
        ["date-time"]
      };

  @override
  String get help => "Convert the date-time to be in the local time zone.";
  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""

This does not change the actual instant in history that this date-time represents. It marks the date-time as being in the local time zone (as discoverable on your system, which may vary based on operating system and locale settings), so that default string representations include the appropriate timezone identifier.

See also:
  to-utc""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final dateTime = args[0];
      if (dateTime is ScDateTime) {
        final dt = dateTime.value;
        if (dt.isUtc) {
          final localDt = dt.toLocal();
          return ScDateTime(localDt);
        } else {
          env.err.writeln(
              "The date-time value is already in the local time zone.");
          return dateTime;
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects a date-time argument, but received a ${dateTime.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnDateTimeIsBefore extends ScBaseInvocable {
  static final ScFnDateTimeIsBefore _instance =
      ScFnDateTimeIsBefore._internal();
  ScFnDateTimeIsBefore._internal();
  factory ScFnDateTimeIsBefore() => _instance;

  @override
  String get canonicalName => 'before?';

  @override
  Set<List<String>> get arities => {
        ["date-time-earlier", "date-time-later"]
      };

  @override
  String get help => "Returns true if the first date is before the second.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""

See also:
  after?""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 2) {
      final dateTime1 = args[0];
      final dateTime2 = args[1];
      if (dateTime1 is ScDateTime) {
        if (dateTime2 is ScDateTime) {
          final dt1 = dateTime1.value;
          final dt2 = dateTime2.value;
          return ScBoolean.fromBool(dt1.isBefore(dt2));
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function's second argument must be a date-time, but received a ${dateTime1.typeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's first argument must be a date-time, but received a ${dateTime1.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 2 arguments, but received ${args.length} arguments.");
    }
  }
}

class ScFnDateTimeIsAfter extends ScBaseInvocable {
  static final ScFnDateTimeIsAfter _instance = ScFnDateTimeIsAfter._internal();
  ScFnDateTimeIsAfter._internal();
  factory ScFnDateTimeIsAfter() => _instance;

  @override
  String get canonicalName => 'after?';

  @override
  Set<List<String>> get arities => {
        ["date-time-later", "date-time-earlier"]
      };

  @override
  String get help => "Returns true if the first date is after the second.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""

See also:
  before?""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 2) {
      final dateTime1 = args[0];
      final dateTime2 = args[1];
      if (dateTime1 is ScDateTime) {
        if (dateTime2 is ScDateTime) {
          final dt1 = dateTime1.value;
          final dt2 = dateTime2.value;
          return ScBoolean.fromBool(dt1.isAfter(dt2));
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function's second argument must be a date-time, but received a ${dateTime1.typeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's first argument must be a date-time, but received a ${dateTime1.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 2 arguments, but received ${args.length} arguments.");
    }
  }
}

class ScFnDateTimePlus extends ScBaseInvocable {
  ScDateTimeUnit unit;

  static final Map<ScDateTimeUnit, ScFnDateTimePlus> _instances = {
    ScDateTimeUnit.microseconds: ScFnDateTimePlus._internalMicroseconds(),
    ScDateTimeUnit.milliseconds: ScFnDateTimePlus._internalMilliseconds(),
    ScDateTimeUnit.seconds: ScFnDateTimePlus._internalSeconds(),
    ScDateTimeUnit.minutes: ScFnDateTimePlus._internalMinutes(),
    ScDateTimeUnit.hours: ScFnDateTimePlus._internalHours(),
    ScDateTimeUnit.days: ScFnDateTimePlus._internalDays(),
    ScDateTimeUnit.weeks: ScFnDateTimePlus._internalWeeks(),
  };

  ScFnDateTimePlus._internalMicroseconds() : unit = ScDateTimeUnit.microseconds;
  ScFnDateTimePlus._internalMilliseconds() : unit = ScDateTimeUnit.milliseconds;
  ScFnDateTimePlus._internalSeconds() : unit = ScDateTimeUnit.seconds;
  ScFnDateTimePlus._internalMinutes() : unit = ScDateTimeUnit.minutes;
  ScFnDateTimePlus._internalHours() : unit = ScDateTimeUnit.hours;
  ScFnDateTimePlus._internalDays() : unit = ScDateTimeUnit.days;
  ScFnDateTimePlus._internalWeeks() : unit = ScDateTimeUnit.weeks;

  factory ScFnDateTimePlus(ScDateTimeUnit unit) => _instances[unit]!;

  @override
  String get canonicalName {
    switch (unit) {
      case ScDateTimeUnit.microseconds:
        return 'plus-microseconds';
      case ScDateTimeUnit.milliseconds:
        return 'plus-milliseconds';
      case ScDateTimeUnit.seconds:
        return 'plus-seconds';
      case ScDateTimeUnit.minutes:
        return 'plus-minutes';
      case ScDateTimeUnit.hours:
        return 'plus-hours';
      case ScDateTimeUnit.days:
        return 'plus-days';
      case ScDateTimeUnit.weeks:
        return 'plus-weeks';
    }
  }

  @override
  Set<List<String>> get arities => {
        ["date-time", "number"]
      };

  @override
  String get help =>
      "Returns a date-time value that is N units further into the future. Accepts a date-time value and a variable number of arguments (or a list of arguments).";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
Consult Dart's DateTime class documentation for more information: https://api.dart.dev/stable/dart-core/DateTime-class.html

NB: The `-weeks` variants are implemented using a Dart `Duration` of 7 days.

See also:
  minus-* functions""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw BadArgumentsException(
          "The `plus-*` date-time functions expect at least 1 argument: a date-time value.");
    } else {
      final dt = args[0];
      if (dt is ScDateTime) {
        if (args.length == 1) {
          return dt;
        } else if (args.length == 2) {
          final arg = args[1];
          if (arg is ScList) {
            return addAllToDateTime(dt, unit, arg);
          } else {
            return addAllToDateTime(dt, unit, ScList([arg]));
          }
        } else {
          return addAllToDateTime(dt, unit, args.skip(1));
        }
      } else {
        throw BadArgumentsException(
            "The `plus-*` date-time functions expect their first argument to be a date-time value, but received a ${dt.typeName()}");
      }
    }
  }
}

class ScFnDateTimeMinus extends ScBaseInvocable {
  ScDateTimeUnit unit;

  static final Map<ScDateTimeUnit, ScFnDateTimeMinus> _instances = {
    ScDateTimeUnit.microseconds: ScFnDateTimeMinus._internalMicroseconds(),
    ScDateTimeUnit.milliseconds: ScFnDateTimeMinus._internalMilliseconds(),
    ScDateTimeUnit.seconds: ScFnDateTimeMinus._internalSeconds(),
    ScDateTimeUnit.minutes: ScFnDateTimeMinus._internalMinutes(),
    ScDateTimeUnit.hours: ScFnDateTimeMinus._internalHours(),
    ScDateTimeUnit.days: ScFnDateTimeMinus._internalDays(),
    ScDateTimeUnit.weeks: ScFnDateTimeMinus._internalWeeks(),
  };

  ScFnDateTimeMinus._internalMicroseconds()
      : unit = ScDateTimeUnit.microseconds;
  ScFnDateTimeMinus._internalMilliseconds()
      : unit = ScDateTimeUnit.milliseconds;
  ScFnDateTimeMinus._internalSeconds() : unit = ScDateTimeUnit.seconds;
  ScFnDateTimeMinus._internalMinutes() : unit = ScDateTimeUnit.minutes;
  ScFnDateTimeMinus._internalHours() : unit = ScDateTimeUnit.hours;
  ScFnDateTimeMinus._internalDays() : unit = ScDateTimeUnit.days;
  ScFnDateTimeMinus._internalWeeks() : unit = ScDateTimeUnit.weeks;

  factory ScFnDateTimeMinus(ScDateTimeUnit unit) => _instances[unit]!;

  @override
  String get canonicalName {
    switch (unit) {
      case ScDateTimeUnit.microseconds:
        return 'minus-microseconds';
      case ScDateTimeUnit.milliseconds:
        return 'minus-milliseconds';
      case ScDateTimeUnit.seconds:
        return 'minus-seconds';
      case ScDateTimeUnit.minutes:
        return 'minus-minutes';
      case ScDateTimeUnit.hours:
        return 'minus-hours';
      case ScDateTimeUnit.days:
        return 'minus-days';
      case ScDateTimeUnit.weeks:
        return 'minus-weeks';
    }
  }

  @override
  Set<List<String>> get arities => {
        ["date-time", "number"]
      };

  @override
  String get help =>
      "Returns a date-time value that is N units further into the past. Accepts a date-time value and a variable number of arguments (or a list of arguments).";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""

Consult Dart's DateTime class documentation for more information: https://api.dart.dev/stable/dart-core/DateTime-class.html

NB: The `-weeks` variants are implemented using a Dart `Duration` of 7 days.

See also:
  plus-* functions""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw BadArgumentsException(
          "The `minus-*` date-time functions expect at least 1 argument: a date-time value.");
    } else {
      final dt = args[0];
      if (dt is ScDateTime) {
        if (args.length == 1) {
          return dt;
        } else if (args.length == 2) {
          final arg = args[1];
          if (arg is ScList) {
            return addAllToDateTime(dt, unit, arg, mustNegate: true);
          } else {
            return addAllToDateTime(dt, unit, ScList([arg]), mustNegate: true);
          }
        } else {
          return addAllToDateTime(dt, unit, args.skip(1), mustNegate: true);
        }
      } else {
        throw BadArgumentsException(
            "The `minus-*` date-time functions expect their first argument to be a date-time value, but received a ${dt.typeName()}");
      }
    }
  }
}

class ScFnDateTimeUntil extends ScBaseInvocable {
  ScDateTimeUnit unit;

  static final Map<ScDateTimeUnit, ScFnDateTimeUntil> _instances = {
    ScDateTimeUnit.microseconds: ScFnDateTimeUntil._internalMicroseconds(),
    ScDateTimeUnit.milliseconds: ScFnDateTimeUntil._internalMilliseconds(),
    ScDateTimeUnit.seconds: ScFnDateTimeUntil._internalSeconds(),
    ScDateTimeUnit.minutes: ScFnDateTimeUntil._internalMinutes(),
    ScDateTimeUnit.hours: ScFnDateTimeUntil._internalHours(),
    ScDateTimeUnit.days: ScFnDateTimeUntil._internalDays(),
    ScDateTimeUnit.weeks: ScFnDateTimeUntil._internalWeeks(),
  };

  ScFnDateTimeUntil._internalMicroseconds()
      : unit = ScDateTimeUnit.microseconds;
  ScFnDateTimeUntil._internalMilliseconds()
      : unit = ScDateTimeUnit.milliseconds;
  ScFnDateTimeUntil._internalSeconds() : unit = ScDateTimeUnit.seconds;
  ScFnDateTimeUntil._internalMinutes() : unit = ScDateTimeUnit.minutes;
  ScFnDateTimeUntil._internalHours() : unit = ScDateTimeUnit.hours;
  ScFnDateTimeUntil._internalDays() : unit = ScDateTimeUnit.days;
  ScFnDateTimeUntil._internalWeeks() : unit = ScDateTimeUnit.weeks;

  factory ScFnDateTimeUntil(ScDateTimeUnit unit) => _instances[unit]!;

  @override
  String get canonicalName {
    switch (unit) {
      case ScDateTimeUnit.microseconds:
        return 'microseconds-until';
      case ScDateTimeUnit.milliseconds:
        return 'milliseconds-until';
      case ScDateTimeUnit.seconds:
        return 'seconds-until';
      case ScDateTimeUnit.minutes:
        return 'minutes-until';
      case ScDateTimeUnit.hours:
        return 'hours-until';
      case ScDateTimeUnit.days:
        return 'days-until';
      case ScDateTimeUnit.weeks:
        return 'weeks-until';
    }
  }

  @override
  Set<List<String>> get arities => {
        ["date-time-later"],
        ["date-time-earlier", "date-time-later"]
      };

  @override
  String get help =>
      'Returns the duration between two date-time values in the given units (defaults to `now` if only one date-time given), expecting the second to be in the future.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
If the second date-time is in the past, a negative value is returned.

Consult Dart's DateTime class documentation for more information: https://api.dart.dev/stable/dart-core/DateTime-class.html

See also:
  *-since functions
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final nowFn = ScFnDateTimeNow();
      final dtA = nowFn.invoke(env, ScList([])) as ScDateTime;
      final dtB = args[0];
      if (dtB is ScDateTime) {
        return dateTimeDifference(dtA, dtB, unit, mustNegate: true);
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects only date-time values, but received a first argument of type ${dtB.typeName()}");
      }
    } else if (args.length == 2) {
      final dtA = args[0];
      final dtB = args[1];
      if (dtA is ScDateTime) {
        if (dtB is ScDateTime) {
          return dateTimeDifference(dtA, dtB, unit, mustNegate: true);
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function expects only date-time values, but received a second argument of type ${dtB.typeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects only date-time values, but received a first argument of type ${dtB.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 or 2 date-time arguments, but received ${args.length} arguments.");
    }
  }
}

class ScFnDateTimeSince extends ScBaseInvocable {
  ScDateTimeUnit unit;

  static final Map<ScDateTimeUnit, ScFnDateTimeSince> _instances = {
    ScDateTimeUnit.microseconds: ScFnDateTimeSince._internalMicroseconds(),
    ScDateTimeUnit.milliseconds: ScFnDateTimeSince._internalMilliseconds(),
    ScDateTimeUnit.seconds: ScFnDateTimeSince._internalSeconds(),
    ScDateTimeUnit.minutes: ScFnDateTimeSince._internalMinutes(),
    ScDateTimeUnit.hours: ScFnDateTimeSince._internalHours(),
    ScDateTimeUnit.days: ScFnDateTimeSince._internalDays(),
    ScDateTimeUnit.weeks: ScFnDateTimeSince._internalWeeks(),
  };

  ScFnDateTimeSince._internalMicroseconds()
      : unit = ScDateTimeUnit.microseconds;
  ScFnDateTimeSince._internalMilliseconds()
      : unit = ScDateTimeUnit.milliseconds;
  ScFnDateTimeSince._internalSeconds() : unit = ScDateTimeUnit.seconds;
  ScFnDateTimeSince._internalMinutes() : unit = ScDateTimeUnit.minutes;
  ScFnDateTimeSince._internalHours() : unit = ScDateTimeUnit.hours;
  ScFnDateTimeSince._internalDays() : unit = ScDateTimeUnit.days;
  ScFnDateTimeSince._internalWeeks() : unit = ScDateTimeUnit.weeks;

  factory ScFnDateTimeSince(ScDateTimeUnit unit) => _instances[unit]!;

  @override
  String get canonicalName {
    switch (unit) {
      case ScDateTimeUnit.microseconds:
        return 'microseconds-since';
      case ScDateTimeUnit.milliseconds:
        return 'milliseconds-since';
      case ScDateTimeUnit.seconds:
        return 'seconds-since';
      case ScDateTimeUnit.minutes:
        return 'minutes-since';
      case ScDateTimeUnit.hours:
        return 'hours-since';
      case ScDateTimeUnit.days:
        return 'days-since';
      case ScDateTimeUnit.weeks:
        return 'weeks-since';
    }
  }

  @override
  Set<List<String>> get arities => {
        ["date-time-earlier"],
        ["date-time-later", "date-time-earlier"]
      };

  @override
  String get help =>
      'Returns the duration between two date-time values in the given units (defaults to `now` if only one date-time given), expecting the second to be in the past.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
If the second date-time is in the future, a negative value is returned.

Consult Dart's DateTime class documentation for more information: https://api.dart.dev/stable/dart-core/DateTime-class.html

See also:
  *-until functions
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final nowFn = ScFnDateTimeNow();
      final dtA = nowFn.invoke(env, ScList([])) as ScDateTime;
      final dtB = args[0];
      if (dtB is ScDateTime) {
        return dateTimeDifference(dtA, dtB, unit);
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects only date-time values, but received a first argument of type ${dtB.typeName()}");
      }
    } else if (args.length == 2) {
      final dtA = args[0];
      final dtB = args[1];
      if (dtA is ScDateTime) {
        if (dtB is ScDateTime) {
          return dateTimeDifference(dtA, dtB, unit);
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function expects only date-time values, but received a second argument of type ${dtB.typeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects only date-time values, but received a first argument of type ${dtB.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 or 2 date-time arguments, but received ${args.length} arguments.");
    }
  }
}

class ScFnDateTimeField extends ScBaseInvocable {
  ScDateTimeFormat format;

  static final Map<ScDateTimeFormat, ScFnDateTimeField> _instances = {
    ScDateTimeFormat.year: ScFnDateTimeField._internalYear(),
    ScDateTimeFormat.month: ScFnDateTimeField._internalMonth(),
    ScDateTimeFormat.weekOfYear: ScFnDateTimeField._internalWeekOfYear(),
    ScDateTimeFormat.dateOfMonth: ScFnDateTimeField._internalDateOfMonth(),
    ScDateTimeFormat.dayOfWeek: ScFnDateTimeField._internalDayOfWeek(),
    ScDateTimeFormat.hour: ScFnDateTimeField._internalHour(),
    ScDateTimeFormat.minute: ScFnDateTimeField._internalMinute(),
    ScDateTimeFormat.second: ScFnDateTimeField._internalSecond(),
    ScDateTimeFormat.millisecond: ScFnDateTimeField._internalMillisecond(),
    ScDateTimeFormat.microsecond: ScFnDateTimeField._internalMicrosecond(),
  };

  ScFnDateTimeField._internalYear() : format = ScDateTimeFormat.year;
  ScFnDateTimeField._internalMonth() : format = ScDateTimeFormat.month;
  ScFnDateTimeField._internalWeekOfYear()
      : format = ScDateTimeFormat.weekOfYear;
  ScFnDateTimeField._internalDateOfMonth()
      : format = ScDateTimeFormat.dateOfMonth;
  ScFnDateTimeField._internalDayOfWeek() : format = ScDateTimeFormat.dayOfWeek;
  ScFnDateTimeField._internalHour() : format = ScDateTimeFormat.hour;
  ScFnDateTimeField._internalMinute() : format = ScDateTimeFormat.minute;
  ScFnDateTimeField._internalSecond() : format = ScDateTimeFormat.second;
  ScFnDateTimeField._internalMillisecond()
      : format = ScDateTimeFormat.millisecond;
  ScFnDateTimeField._internalMicrosecond()
      : format = ScDateTimeFormat.microsecond;

  factory ScFnDateTimeField(ScDateTimeFormat format) => _instances[format]!;

  @override
  String get canonicalName {
    switch (format) {
      case ScDateTimeFormat.year:
        return 'year';
      case ScDateTimeFormat.month:
        return 'month';
      case ScDateTimeFormat.weekOfYear:
        return 'week-of-year';
      case ScDateTimeFormat.dateOfMonth:
        return 'date-of-month';
      case ScDateTimeFormat.dayOfWeek:
        return 'day-of-week';
      case ScDateTimeFormat.hour:
        return 'hour';
      case ScDateTimeFormat.minute:
        return 'minute';
      case ScDateTimeFormat.second:
        return 'second';
      case ScDateTimeFormat.millisecond:
        return 'millisecond';
      case ScDateTimeFormat.microsecond:
        return 'microsecond';
    }
  }

  static final weekdays = {
    1: ScString('Monday'),
    2: ScString('Tuesday'),
    3: ScString('Wednesday'),
    4: ScString('Thursday'),
    5: ScString('Friday'),
    6: ScString('Saturday'),
    7: ScString('Sunday'),
  };

  @override
  Set<List<String>> get arities => {
        ["date-time"]
      };

  @override
  String get help => "Returns given part of the date-time value.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
All of these are supported directly by Dart except for the week-of-year variant. Confirm that its calculation matches your expectations.

Consult Dart's DateTime class documentation for more information: https://api.dart.dev/stable/dart-core/DateTime-class.html

See also:
  dt
  plus-* functions
  minus-* functions
  *-since functions
  *-until functions""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final dateTime = args[0];
      if (dateTime is ScDateTime) {
        final dt = dateTime.value;
        switch (format) {
          case ScDateTimeFormat.year:
            return ScNumber(dt.year);
          case ScDateTimeFormat.month:
            return ScNumber(dt.month);
          case ScDateTimeFormat.weekOfYear:
            return ScNumber(calculateWeekOfYear(dt));
          case ScDateTimeFormat.dateOfMonth:
            return ScNumber(dt.day);
          case ScDateTimeFormat.dayOfWeek:
            return ScFnDateTimeField.weekdays[dt.weekday]!;
          case ScDateTimeFormat.hour:
            return ScNumber(dt.hour);
          case ScDateTimeFormat.minute:
            return ScNumber(dt.minute);
          case ScDateTimeFormat.second:
            return ScNumber(dt.second);
          case ScDateTimeFormat.millisecond:
            return ScNumber(dt.millisecond);
          case ScDateTimeFormat.microsecond:
            return ScNumber(dt.microsecond);
        }
      } else {
        throw BadArgumentsException(
            "The date-time field functions expect a date-time argument, but received a ${dateTime.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The date-time field functions expect only 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnIf extends ScBaseInvocable {
  static final ScFnIf _instance = ScFnIf._internal();
  ScFnIf._internal();
  factory ScFnIf() => _instance;

  @override
  String get canonicalName => 'if';

  @override
  Set<List<String>> get arities => {
        ["condition", "then-nullary-function", "else-nullary-function"]
      };

  @override
  String get help =>
      "If the first argument is truthy, invoke the first function; else the second.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""The "then" and "else" functions expect zero arguments.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != 3) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 3 arguments: a truthy value, a 'then' function, and an 'else' function.");
    } else {
      final ScExpr truthy = args.first;
      final ScExpr thenInv = args[1];
      final ScExpr elseInv = args[2];
      if (thenInv is! ScBaseInvocable) {
        throw BadArgumentsException(
            "The `$canonicalName` function expects its second argument to be a function, but received a ${thenInv.typeName()}");
      }
      if (elseInv is! ScBaseInvocable) {
        throw BadArgumentsException(
            "The `$canonicalName` function expects its third argument to be a function, but received a ${thenInv.typeName()}");
      }
      if (truthy == ScBoolean.falsitas() || truthy == ScNil()) {
        // Else
        return elseInv.invoke(env, ScList([]));
      } else {
        return thenInv.invoke(env, ScList([]));
      }
    }
  }
}

class ScFnAssert extends ScBaseInvocable {
  static final ScFnAssert _instance = ScFnAssert._internal();
  ScFnAssert._internal();
  factory ScFnAssert() => _instance;

  @override
  String get canonicalName => 'assert';

  @override
  Set<List<String>> get arities => {
        ["condition", "failure-message"]
      };

  @override
  String get help => "Throw an error if the assertion doesn't hold.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
The first argument is tested for truthiness.

If it is falsey, then an error is thrown. The second argument, expected to be a string, is used as the message for this error.

If it is truthy, then nil is returned.

See also:
  if
  type
  when""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 2) {
      final condition = args[0];
      final message = args[1];
      final cond = ScBoolean.fromTruthy(condition);
      if (cond.toBool()) {
        return ScNil();
      } else {
        String msg;
        if (message is ScString) {
          msg = message.value;
        } else {
          msg = message.toString();
        }
        throw ScAssertionError(msg);
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 2 arguments, but received ${args.length} arguments.");
    }
  }
}

class ScFnSelect extends ScBaseInvocable {
  static final ScFnSelect _instance = ScFnSelect._internal();
  ScFnSelect._internal();
  factory ScFnSelect() => _instance;

  @override
  String get canonicalName => 'select';

  @override
  String get help =>
      "Returns a new map that only contains the entries specified by the given keys.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""The first argument must be a map or an entity. A sub-map is returned consisting only of the keys specified by the rest of the arguments to this function.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    ScExpr? sourceMap;
    ScExpr? selector;
    if (args.length > 2) {
      sourceMap = args[0];
      selector = args.skip(1);
    } else if (args.length == 2) {
      sourceMap = args[0];
      selector = args[1];
    } else if (args.length == 1) {
      selector = args[0];
      if (env.parentEntity != null) {
        final pe = env.parentEntity!;
        sourceMap = pe;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects either an explicit map or entity as its first argument, or that you have `cd`ed into an entity. Received a selector but no source to select from.");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function takes at most 2 arguments (a map/entity and a selector list), but received ${args.length} arguments.");
    }

    if (selector is! ScList) {
      throw BadArgumentsException(
          "The `$canonicalName` function's second argument must be a list of keys to select.");
    } else {
      if (sourceMap is ScMap) {
        final getFn = ScFnGet();
        final notFound = ScSymbol('__sc_not-found');
        final targetMap = ScMap({});
        for (final key in selector.innerList) {
          final value = getFn.invoke(env, ScList([sourceMap, key, notFound]));
          if (value != notFound) {
            targetMap[key] = value;
          }
        }
        return targetMap;
      } else if (sourceMap is ScEntity) {
        final getFn = ScFnGet();
        final notFound = ScSymbol('__sc_not-found');
        final targetMap = ScMap({});
        for (final key in selector.innerList) {
          final value = getFn.invoke(env, ScList([sourceMap, key, notFound]));
          if (value != notFound) {
            targetMap[key] = value;
          }
        }
        return targetMap;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects a map/entity and a list of keys to select out of it.");
      }
    }
  }
}

// TODO There's a bug in the map spec matching when more than one entry is provided.
class ScFnWhere extends ScBaseInvocable {
  static final ScFnWhere _instance = ScFnWhere._internal();
  ScFnWhere._internal();
  factory ScFnWhere() => _instance;

  @override
  String get canonicalName => 'where';

  @override
  Set<List<String>> get arities => {
        ["collection", "map-spec-or-fn"]
      };

  @override
  String get help =>
      'Returns items from a collection that match the given map spec or function.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""This function is a tool for finding items in collections.

= If the first argument is a list: =

== If the second argument is a function: ==

The list is filtered by invoking the function with each item, keeping only those for which the function returns a truthy value.

== If the second argument is a map: ==

This map is treated as a map spec, which is to say a map that defines what should be found in each item of the list. This also means that every item in the list must be a map.

Only those items are returned which match the map spec.

=== Map Spec ===

A key that is a list in your map spec is treated as a selector into the target map (i.e., as if passed to `get-in`). Other keys are treated as literal keys to be found in the target map.

A value that is a function will be invoked with the value of the entry in the target map; if the function returns a truthy value, the entry remains, otherwise it is excluded from the return value.

A value that is any other type is treated as a literal value to be found in the target map at the given entry. If the value equals what is found there, then that entry remains, otherwise it is excluded from the return value.

= If the first argument is a map: =

The second argument is expected to be a function that takes two arguments: a key and value. Each entry's key and value will be passed to this function, but only those for which this function returns truthy will remain in the final map returned.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != 2) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects two arguments: a collection and a map of where clauses.");
    }
    final ScExpr coll = args[0];
    final ScExpr notFound = ScSymbol("__sc_not-found");
    if (coll is ScList) {
      final ScExpr secondArg = args[1];
      if (secondArg is ScBaseInvocable) {
        return coll.where((expr) {
          return ScBoolean.fromTruthy(secondArg.invoke(env, ScList([expr])));
        });
      } else if (secondArg is ScMap) {
        final whereMap = secondArg;
        return coll.where((expr) {
          if (expr is ScMap || expr is ScEntity) {
            bool allMatch = true;
            for (final whereKey in whereMap.keys) {
              ScExpr exprValue;
              if (whereKey is ScList) {
                final getInFn = ScFnGetIn();
                exprValue =
                    getInFn.invoke(env, ScList([expr, whereKey, notFound]));
              } else {
                final getFn = ScFnGet();
                exprValue =
                    getFn.invoke(env, ScList([expr, whereKey, notFound]));
              }
              if (exprValue == notFound) {
                allMatch = false;
              } else {
                final whereValue = whereMap[whereKey];
                if (whereValue is ScBaseInvocable) {
                  allMatch = ScBoolean.isTruthy(
                      whereValue.invoke(env, ScList([exprValue])));
                } else {
                  allMatch = exprValue == whereValue;
                }
              }
            }
            return ScBoolean.fromBool(allMatch);
          } else {
            throw BadArgumentsException(
                "The `$canonicalName` function using a map spec requires that each item in your list be a map, but found ${expr.typeName()}");
          }
        });
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's second argument must be a function when passing a list as the first argument.");
      }
    } else if (coll is ScMap) {
      final secondArg = args[1];
      if (secondArg is ScBaseInvocable) {
        if (secondArg is ScAnonymousFunction) {
          if (secondArg.numArgs != 2) {
            throw BadArgumentsException(
                "The function passed to `where` must accept 2 arguments (a key and value from the map), but found a function that expects ${secondArg.numArgs} arguments.");
          }
        }
        return coll.where((k, v) {
          return ScBoolean.fromTruthy(secondArg.invoke(env, ScList([k, v])));
        });
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's second argument must be a function when passing a map as the first argument.");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function's first argument must be either a list or map, but received ${coll.typeName()}");
    }
  }
}

class ScFnTake extends ScBaseInvocable {
  static final ScFnTake _instance = ScFnTake._internal();
  ScFnTake._internal();
  factory ScFnTake() => _instance;

  @override
  String get canonicalName => 'take';

  @override
  Set<List<String>> get arities => {
        ["collection", "number-to-keep"]
      };

  @override
  String get help =>
      'Limit the number of items in the collection to the given number.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""If provided a number, that many items starting at the beginning of the collection are returned.

If provided a function, this behaves as a "take while", returning as many items as return truthy for the given function, stopping at the first that doesn't.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != 2) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects two arguments: a collection and a limit of how many items to return.");
    }
    final ScExpr coll = args.first;
    if (coll is ScList) {
      final taker = args[1];
      if (taker is ScBaseInvocable) {
        return coll.takeWhile((expr) {
          return ScBoolean.fromTruthy(taker.invoke(env, ScList([expr])));
        });
      } else if (taker is ScNumber) {
        final theNum = taker.value;
        if (theNum is int) {
          if (theNum > coll.length) {
            return coll;
          } else {
            return coll.sublist(0, theNum);
          }
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function's second argument must be an integer.");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's second argument must be an integer.");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function's first argument must be either a list, but received ${coll.typeName()}");
    }
  }
}

class ScFnDrop extends ScBaseInvocable {
  static final ScFnDrop _instance = ScFnDrop._internal();
  ScFnDrop._internal();
  factory ScFnDrop() => _instance;

  @override
  String get canonicalName => 'drop';

  @override
  Set<List<String>> get arities => {
        ["collection", "number-to-skip"]
      };

  @override
  String get help => 'Skip the first N items of the given collection.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""If provided a number, that many items starting at the beginning of the collection are returned.

If provided a function, this behaves as a "skip while", skipping as many items as return truthy for the given function, stopping at the first that doesn't.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != 2) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects two arguments: a collection and a number of items to skip.");
    }
    final ScExpr coll = args.first;
    if (coll is ScList) {
      final skipper = args[1];
      if (skipper is ScBaseInvocable) {
        return coll.skipWhile((expr) {
          return ScBoolean.fromTruthy(skipper.invoke(env, ScList([expr])));
        });
      } else if (skipper is ScNumber) {
        final theNum = skipper.value;
        if (theNum is int) {
          if (theNum > coll.length) {
            return ScList([]);
          } else {
            return coll.sublist(theNum, coll.length);
          }
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function's second argument must be an integer.");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's second argument must be an integer.");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function's first argument must be either a list, but received ${coll.typeName()}");
    }
  }
}

class ScFnDistinct extends ScBaseInvocable {
  static final ScFnDistinct _instance = ScFnDistinct._internal();
  ScFnDistinct._internal();
  factory ScFnDistinct() => _instance;

  @override
  String get canonicalName => 'distinct';

  @override
  Set<List<String>> get arities => {
        ["collection"]
      };

  @override
  String get help =>
      "Returns a new collection with only distinct items from the original based on = equality.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
This function is immutable, returning a new collection and leaving the original intact.

NB: Equality for entities (e.g., stories, epics, etc.) is based solely on ID. If two entities have the same ID, they're considered equal, even if the underlying data for two instances is radically different.

See also:
  count
  sort""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final coll = args[0];
      if (coll is ScList) {
        final l = ScList([]);
        for (final item in coll.innerList) {
          if (!l.contains(item)) {
            l.addMutable(item);
          }
        }
        return l;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects a list argument, but received a ${coll.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnReverse extends ScBaseInvocable {
  static final ScFnReverse _instance = ScFnReverse._internal();
  ScFnReverse._internal();
  factory ScFnReverse() => _instance;

  @override
  String get canonicalName => 'reverse';

  @override
  Set<List<String>> get arities => {
        ["collection"]
      };

  @override
  String get help =>
      "Returns a new collection with items from the original collection in reverse order.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""

See also:
  count
  distinct
  sort""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final coll = args[0];
      if (coll is ScList) {
        final copy = List<ScExpr>.from(coll.innerList);
        return ScList(copy.reversed.toList());
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects a list argument, but received a ${coll.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnHelp extends ScBaseInvocable {
  static final ScFnHelp _instance = ScFnHelp._internal();
  ScFnHelp._internal();
  factory ScFnHelp() => _instance;

  @override
  String get canonicalName => '?';

  @override
  Set<List<String>> get arities => {
        [],
        ["fn-or-string"]
      };

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      env.out.writeln('Available commands:');
      ScMap m = ScMap({});
      env.bindings.forEach((key, value) {
        if (value is ScBaseInvocable) {
          final rawHelp = value.help;
          if (rawHelp.isNotEmpty) {
            m[key] = ScString(rawHelp);
          }
        }
        m[key] ??=
            env.runtimeHelp[key] ?? ScString("a ${value.typeName()} value");
      });
      final ks = m.keys.toList();
      ks.sort();
      printTable(env, ks, m);
      env.out.writeln(env.style(
          'Try `? "example"` to search through all function names and help strings.',
          styleInfo));
    } else {
      final query = args[0];
      if (query is ScDottedSymbol) {
        final value = env.bindings[query.scSymbol];
        final rtHelp = env.runtimeHelp[query.scSymbol];
        String typeName = '<unknown>';
        if (value != null) {
          typeName = (value as ScExpr).typeName();
        }
        if (rtHelp is ScString) {
          env.out.writeln(env.style("[$typeName] ${rtHelp.value}", styleTitle));
        } else {
          env.out.writeln(env.style(
              '$query <map-or-entity> [<default-if-nil>]', styleTitle));
        }
      } else if (query is ScBaseInvocable) {
        if (query.arities.isNotEmpty) {
          env.out.writeln(env.style('Function signatures: ', styleTitle));
          final arities = query.arities.toList();
          arities.sort((la, lb) => la.length.compareTo(lb.length));
          for (final arity in query.arities) {
            final wrapped = arity.map((e) {
              if (e == '...') {
                return e;
              } else {
                return "<$e>";
              }
            });
            String params = wrapped.join(' ');
            if (params.isNotEmpty) {
              params = ' $params';
            }
            final fnName = query.canonicalName;
            if (fnName.isNotEmpty) {
              env.out.writeln(env.style('  $fnName$params', styleTitle));
            }
          }
        }
        env.out.writeln();
        final rawHelp = query.helpFull;
        if (rawHelp.isEmpty) {
          env.out.writeln(env.style(
              env.runtimeHelp[ScSymbol(query.canonicalName)]?.value ??
                  '<No help found>',
              styleTitle));
        } else {
          env.out.writeln(env.style(query.helpFull, styleTitle));
        }
      } else if (query is ScString) {
        final searchFn = ScFnSearch();
        final bindingsWithHelp = ScMap({});
        env.bindings.forEach((key, value) {
          if (value is ScBaseInvocable) {
            bindingsWithHelp[key] = ScString(value.helpFull);
          } else {
            bindingsWithHelp[key] = value;
          }
        });
        final matchingBindings =
            searchFn.invoke(env, ScList([bindingsWithHelp, query]));
        if (matchingBindings is ScMap) {
          ScMap m = ScMap({});
          matchingBindings.innerMap.forEach((key, _) {
            final boundValue = env.bindings[key];
            if (boundValue is ScBaseInvocable) {
              m[key] = ScString(boundValue.help);
            } else {
              m[key] = boundValue;
            }
          });
          final ks = m.keys.toList();
          ks.sort();
          printTable(env, ks, m);
          // NB: Don't feel great about somewhat pretty-printing rather than giving data.
          return ScNil();
        } else {
          return ScMap({});
        }
      } else {
        env.out.writeln("<No help found>");
      }
    }
    return ScNil();
  }

  @override
  String get help =>
      'Print help documentation. Provide a function to get specific help.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""With no arguments, prints a listing of all default language bindings and their help summaries.

With an argument that is a function, prints the full help for that function.

With an argument that is a string, searches through bindings (both name and full help text if available) and returns matching ones.

For more help, consult:

 - Shortcut API Documentation: https://shortcut.com/api/rest/v3
 - This tool's GitHub repository: https://github.com/semperos/shortcut-cli
""";
}

class ScFnPrint extends ScBaseInvocable {
  ScFnPrint(this.strToAppend) : super();
  String strToAppend;

  @override
  String get canonicalName => 'print';

  @override
  Set<List<String>> get arities => {
        [],
        ["value", "..."]
      };

  @override
  String get help => "Print values to the output stream.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""The output stream is STDOUT by default. A future version of this program might make the output stream destination configurable; keep an eye out!""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      env.out.write(strToAppend);
    } else {
      final joined = args.join(separator: ScString(' '));
      env.out.write("${joined.value}$strToAppend");
    }
    return ScNil();
  }
}

class ScFnPrStr extends ScBaseInvocable {
  static final ScFnPrStr _instance = ScFnPrStr._internal();
  ScFnPrStr._internal();
  factory ScFnPrStr() => _instance;

  @override
  String get canonicalName => 'pr-str';

  @override
  Set<List<String>> get arities => {
        ["value"]
      };

  @override
  String get help => "Returns a readable string of the given argument.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
A readable string is one that PL can read and evaluate as code.

Use `concat` if you want to construct a string from parts.

See also:
  concat
  print""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final expr = args[0];
      final isAnsiEnabled = env.isAnsiEnabled;
      env.isAnsiEnabled = false;
      final exprStr = expr.printToString(env);
      env.isAnsiEnabled = isAnsiEnabled;
      return ScString(exprStr);
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnDefaults extends ScBaseInvocable {
  static final ScFnDefaults _instance = ScFnDefaults._internal();
  ScFnDefaults._internal();
  factory ScFnDefaults() => _instance;

  @override
  String get canonicalName => 'defaults';

  @override
  Set<List<String>> get arities => {[]};

  @override
  String get help =>
      "Returns a map of all Shortcut workspace-level defaults set via `setup` or `default`.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
When creating Stories, you need to supply a workflow state. In order to support making story creation and the creation of other entities easier, you are encouraged to set defaults using `setup` for a guided process, or `default` to set individual defaults manually.

This function returns a map with keys that are the canonical default names and values that are the values you've chosen. These keys map to the domain of Shortcut the application (e.g., 'team' instead of 'group'), but see the help documentation for `default` for more details.

See also:
  default
  setup
  teams
  workflows""";

  static ScList defaults = ScList(
      [ScString('team'), ScString('workflow'), ScString('workflow-state')]);

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      final defaultFn = ScFnDefault();
      final m = ScMap({});
      for (final x in defaults.innerList) {
        final s = x as ScString;
        m[s] = defaultFn.invoke(env, ScList([s]));
      }
      return m;
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 0 arguments, but received ${args.length}");
    }
  }
}

class ScFnDefault extends ScBaseInvocable {
  static final ScFnDefault _instance = ScFnDefault._internal();
  ScFnDefault._internal();
  factory ScFnDefault() => _instance;

  @override
  String get canonicalName => 'default';

  @override
  Set<List<String>> get arities => {
        ["default-key"],
        ["default-key", "default-value"]
      };

  static List<String> identifiers = [
    "group",
    "group_id",
    "group-id",
    "team",
    "workflow",
    "workflow_id",
    "workflow_state",
    "workflow_state_id",
    "workflow-id",
    "workflow-state",
    "workflow-state-id"
  ];

  @override
  String get help => "Retrieve a default value, or set a new one.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""If one argument is provided, the default value for that identifier is returned.

If two arguments are provided, the second argument is the new default value for the given identifier.

Identifiers are:

 - "team"
 - "workflow"
 - "workflow_state"

See also:
  defaults
  setup
  teams
  workflows
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final identifier = args[0];
      String id;
      if (identifier is ScString) {
        id = identifier.value;
      } else if (identifier is ScDottedSymbol) {
        id = identifier._name;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's first argument must be a string or dotted symbol of one of ${identifiers.join(', ')}");
      }

      if (identifiers.contains(id)) {
        switch (id) {
          case 'group':
          case 'group_id':
          case 'group-id':
          case 'team':
            final teamId = env[ScSymbol('__sc_default-team-id')];
            if (teamId is ScString) {
              return env.resolveTeam(env, teamId);
            } else {
              return ScNil();
            }
          case 'workflow':
          case 'workflow_id':
          case 'workflow-id':
            final workflowId = env[ScSymbol('__sc_default-workflow-id')];
            if (workflowId is ScNumber) {
              return env.resolveWorkflow(ScString(workflowId.value.toString()));
            } else {
              return ScNil();
            }
          case 'workflow_state':
          case 'workflow-state':
          case 'workflow_state_id':
          case 'workflow-state-id':
            final workflowStateId =
                env[ScSymbol('__sc_default-workflow-state-id')];
            if (workflowStateId is ScNumber) {
              return env.resolveWorkflowState(
                  ScString(workflowStateId.value.toString()));
            } else {
              return ScNil();
            }
          default:
            return ScNil();
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's first argument must be a string or dotted symbol of one of ${identifiers.join(', ')}");
      }
    } else if (args.length == 2) {
      final identifier = args[0];
      String id;
      if (identifier is ScString) {
        id = identifier.value;
      } else if (identifier is ScDottedSymbol) {
        id = identifier._name;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's first argument must be a string or dotted symbol of one of ${identifiers.join(', ')}");
      }

      if (identifiers.contains(id)) {
        final newValue = args[1];
        ScExpr v;
        if (newValue is ScEntity) {
          v = newValue.id;
        } else {
          v = newValue;
        }

        switch (id) {
          case 'group':
          case 'group_id':
          case 'group-id':
          case 'team':
            env[ScSymbol('__sc_default-team-id')] = v;
            break;
          case 'workflow':
          case 'workflow_id':
          case 'workflow-id':
            env[ScSymbol('__sc_default-workflow-id')] = v;
            break;
          case 'workflow_state':
          case 'workflow-state':
          case 'workflow_state_id':
          case 'workflow-state-id':
            env[ScSymbol('__sc_default-workflow-state-id')] = v;
            break;
        }
        env.writeToDisk();
        return v;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's first argument must be a string or dotted symbol of one of ${identifiers.join(', ')}");
      }
    } else {
      throw UnimplementedError();
    }
  }
}

class ScFnSetup extends ScBaseInvocable {
  static final ScFnSetup _instance = ScFnSetup._internal();
  ScFnSetup._internal();
  factory ScFnSetup() => _instance;

  @override
  String get canonicalName => 'setup';

  @override
  Set<List<String>> get arities => {[]};

  @override
  String get help =>
      "Setup your local environment's default workflow, workflow state, and team.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""Interactive entity creation (in particular, stories) is meant to be as painless as possible. This requires some initial setup of defaults, which this function handles.

Invoking `setup` starts an interaction at the REPL where you're shown all the workflows defined in your workspace and prompted to pick your default one.

After supplying the ID of the workflow you want as your default, it will prompt you to pick one of the given workflow _states_ within that workflow to be your default workflow state when creating new stories.

After supplying that default workflow state ID, it will show you all the teams defined in your workspace and ask you to enter the ID of the one that should be your default when creating stories, epics, iterations, and milestones.

Note: These defaults are only meaningful for the quick, interactive entity creation functions. If you use The `new-*` functions and supply a full map as the body of the request, you have complete control over the entity's workflow state and team.
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      env.interactivityState = ScInteractivityState.startSetup;
      return ScNil();
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects no arguments.");
    }
  }
}

class ScFnCd extends ScBaseInvocable {
  static final ScFnCd _instance = ScFnCd._internal();
  ScFnCd._internal();
  factory ScFnCd() => _instance;

  @override
  String get canonicalName => 'cd';

  @override
  Set<List<String>> get arities => {
        [],
        ["entity"]
      };

  @override
  String get help =>
      r"""Change the current parent entity ("directory") you're operating in.""";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""Shortcut's domain model treats stories as containers for tasks; epics as containers for stories; milestones as containers for epics.

You can `cd` into an entity to make that entity your current "parent entity." Many of the built-in functions assume you are inside a parent entity and change their behavior accordingly.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      env.parentEntity = null;
      env.parentEntityHistoryCursor = 0;
      return ScNil();
    } else if (args.length == 1) {
      final newParentEntity = args[0];
      final oldParentEntity = env.parentEntity;
      env.parentEntityHistoryCursor = 0;
      if (newParentEntity == ScDottedSymbol('.')) {
        if (oldParentEntity is ScTask) {
          return fetchAndSetParentEntity(env, oldParentEntity.storyId);
        } else if (oldParentEntity is ScStory) {
          return fetchAndSetParentEntity(env, oldParentEntity.epicId);
        } else if (oldParentEntity is ScEpic) {
          return fetchAndSetParentEntity(env, oldParentEntity.milestoneId);
        } else if (oldParentEntity is ScComment) {
          final parentId = oldParentEntity.parentId;
          if (parentId != null) {
            final parentComment = ScComment(oldParentEntity.storyId, parentId);
            final entity = waitOn(parentComment.fetch(env));
            setParentEntity(env, entity);
            return entity;
          } else {
            return fetchAndSetParentEntity(env, oldParentEntity.storyId);
          }
        } else if (oldParentEntity is ScEpicComment) {
          final parentId = oldParentEntity.parentId;
          if (parentId != null) {
            final parentComment =
                ScEpicComment(oldParentEntity.epicId, parentId);
            final entity = waitOn(parentComment.fetch(env));
            setParentEntity(env, entity);
            return entity;
          } else {
            return fetchAndSetParentEntity(env, oldParentEntity.epicId);
          }
        } else {
          env.parentEntity = null;
          env.parentEntityHistoryCursor = 0;
          return ScNil();
        }
      } else if (newParentEntity is ScEntity) {
        setParentEntity(env, newParentEntity);
        // Feature: Keep the env.json up-to-date with most recent parent entity.
        return newParentEntity;
      } else if (newParentEntity is ScNumber || newParentEntity is ScString) {
        ScString id;
        if (newParentEntity is ScNumber) {
          id = ScString(newParentEntity.value.toString());
        } else {
          id = newParentEntity as ScString;
        }
        if (oldParentEntity is ScStory) {
          try {
            final task = waitOn(
                env.client.getTask(env, oldParentEntity.idString, id.value));
            env.parentEntity = task;
            setParentEntity(env, task);
            return task;
          } catch (_) {
            // I believe the waitOn causes this to be an AsyncError wrapping an EntityNotFoundException ^
            // Copied from else branch below
            final fetchFn = ScFnFetch();
            final entity = fetchFn.invoke(env, ScList([id])) as ScEntity;
            setParentEntity(env, entity);
            return entity;
          }
        } else {
          final fetchFn = ScFnFetch();
          final entity = fetchFn.invoke(env, ScList([id])) as ScEntity;
          setParentEntity(env, entity);
          return entity;
        }
      } else {
        throw BadArgumentsException(
            'The argument to `$canonicalName` must be .. or a Shortcut entity or an entity ID.');
      }
    } else {
      throw BadArgumentsException(
          'The `$canonicalName` function expects an entity to move into.');
    }
  }
}

class ScFnHistory extends ScBaseInvocable {
  static final ScFnHistory _instance = ScFnHistory._internal();
  ScFnHistory._internal();
  factory ScFnHistory() => _instance;

  @override
  String get canonicalName => 'history';

  @override
  Set<List<String>> get arities => {[]};

  @override
  String get help =>
      "Returns history of parent entities you have `cd`ed into, in reverse order so latest are at the bottom. Max 100 entries.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""Every time you `cd` into an entity, that entity is saved to a list. This function returns that list, reversed so most recent are at the bottom (most visible at the console).

Note that Shortcut tasks can be `cd`ed into, but at this time are not persisted to the history due to a limitation in the JSON format chosen to store parent entities and the fact that to fetch a task you must know its story ID.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isNotEmpty) {
      throw BadArgumentsException(
          "The `$canonicalName` function takes no arguments, but received ${args.length}");
    } else {
      return ScList(env.parentEntityHistory.reversed.toList());
    }
  }
}

class ScFnBackward extends ScBaseInvocable {
  static final ScFnBackward _instance = ScFnBackward._internal();
  ScFnBackward._internal();
  factory ScFnBackward() => _instance;

  @override
  String get canonicalName => 'backward';

  @override
  Set<List<String>> get arities => {[]};

  @override
  String get help =>
      "Change your parent entity to the previous one in your history.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
This tool preserves the history of every entity you have `cd`ed into, up to the last 100. It writes this history to disk in your env.json file.

You can use the `forward` and `backward` functions which are also aliased as `f` and `b` as well as `n` and `p` respectively for those accustomed to 'next' and 'previous'.

History is stored as a simple list, not a tree.

See also:
  cwd
  .
  forward
  history
  pwd""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      if (env.parentEntityHistoryCursor == 0) {
        // 0 is always cwd
        env.parentEntityHistoryCursor = 1;
      }
      if (env.parentEntityHistoryCursor < env.parentEntityHistory.length) {
        final previousParentEntity =
            env.parentEntityHistory[env.parentEntityHistoryCursor];
        setParentEntity(env, previousParentEntity, isHistory: false);
        env.parentEntityHistoryCursor++;
        return previousParentEntity;
      } else {
        env.err.writeln(env.style(
            ";; [WARN] No previous parent found in history; you've reached the beginning of time.",
            'warn'));
        return ScNil();
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects no arguments, but received ${args.length}");
    }
  }
}

class ScFnForward extends ScBaseInvocable {
  static final ScFnForward _instance = ScFnForward._internal();
  ScFnForward._internal();
  factory ScFnForward() => _instance;

  @override
  String get canonicalName => 'forward';

  @override
  Set<List<String>> get arities => {[]};

  @override
  String get help =>
      "Change your parent entity to the next one in your history.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
This tool preserves the history of every entity you have `cd`ed into, up to the last 100. It writes this history to disk in your env.json file.

You can use the `forward` and `backward` functions which are also aliased as `f` and `b` as well as `n` and `p` respectively for those accustomed to 'next' and 'previous'.

History is stored as a simple list, not a tree.

See also:
  backward
  cwd
  .
  history
  pwd""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      if (env.parentEntityHistoryCursor == 0) {
        env.err.writeln(env.style(
            ";; [WARN] No subsequent parent found in history; you're back to the latest.",
            'warn'));
        return ScNil();
      } else {
        env.parentEntityHistoryCursor--;
        final nextParentEntity =
            env.parentEntityHistory[env.parentEntityHistoryCursor];
        setParentEntity(env, nextParentEntity, isHistory: false);
        return nextParentEntity;
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects no arguments, but received ${args.length}");
    }
  }
}

class ScFnLs extends ScBaseInvocable {
  static final ScFnLs _instance = ScFnLs._internal();
  ScFnLs._internal();
  factory ScFnLs() => _instance;

  @override
  String get canonicalName => 'ls';

  @override
  Set<List<String>> get arities => {
        [],
        ["entity"]
      };

  @override
  String get help => 'List items within a context.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
As far as makes sense, you can use `ls` with any Shortcut entity.

At time of writing, this function behaves as follows for each entity:

- In a milestone:  lists epics
- In an epic:      lists stories
- In an iteration: lists stories
- In a label:      lists stories
- In a story:      lists tasks
- In a team:       lists members
- In a member:     lists stories the member is an owner of
- In a workflow:   lists workflow states

See also:
  epics
  find-stories
  iterations
  labels
  milestones
  stories
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    ScEntity entity = env.resolveArgEntity(args, canonicalName);
    return waitOn(entity.ls(env));
  }
}

class ScFnCwd extends ScBaseInvocable {
  static final ScFnCwd _instance = ScFnCwd._internal();
  ScFnCwd._internal();
  factory ScFnCwd() => _instance;

  @override
  String get canonicalName => 'cwd';

  @override
  Set<List<String>> get arities => {[]};

  static String cwdHelp =
      '[Help] `cd` into a Shortcut entity or entity ID to use `cwd`, `pwd`, and `.`';

  @override
  String get help =>
      'Returns the working "directory"—the current parent entity you have `cd`ed into.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""

This function re-fetches the current parent entity, so you can quickly evaluate `.` to pull down the most recent data from Shortcut.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      if (env.parentEntity != null) {
        final pe = env.parentEntity!;
        waitOn(pe.fetch(env));
        return pe;
      } else {
        env.out.writeln(env.style(cwdHelp, styleInfo));
        return ScNil();
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function doesn't take any arguments.");
    }
  }
}

class ScFnPwd extends ScBaseInvocable {
  static final ScFnPwd _instance = ScFnPwd._internal();
  ScFnPwd._internal();
  factory ScFnPwd() => _instance;

  @override
  String get canonicalName => 'pwd';

  @override
  Set<List<String>> get arities => {[]};

  @override
  String get help =>
      'Print the working "directory"—the current parent entity we have `cd`ed into.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
This prints a subset of the important metadata of the given entity, as well as the entity's description.

See also:
  .
  cwd
  data
  details
  summary""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      if (env.parentEntity != null) {
        final pe = env.parentEntity!;
        waitOn(pe.fetch(env));
        pe.printSummary(env);
        final description = pe.data[ScString('description')];
        if (description is ScString && !description.isBlank()) {
          env.out.writeln(env.style('-' * env.displayWidth, styleSubdued));
          env.out.writeln(wrap(description.value, 80, ''));
        }
        return ScNil();
      } else {
        env.out.writeln(env.style(ScFnCwd.cwdHelp, 'warn'));
        return ScNil();
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function doesn't take any arguments.");
    }
  }
}

class ScFnMv extends ScBaseInvocable {
  static final ScFnMv _instance = ScFnMv._internal();
  ScFnMv._internal();
  factory ScFnMv() => _instance;

  @override
  String get canonicalName => 'mv!';

  @override
  Set<List<String>> get arities => {
        ["entity-to-move", "target-container-entity"]
      };

  @override
  String get help =>
      "Move a Shortcut entity from one container to another (e.g., a story to an epic).";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
This function works for the following 'movements' of entities:

- A story to an epic
- A story to an iteration
- A story to a team
- An epic to a milestone
- An epic to a team

See also:
  !
  update!""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != 2) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 2 arguments: a child entity and a new parent entity to move it to, but received ${args.length} arguments.");
    } else {
      ScEntity childEntity = env.resolveArgEntity(args, canonicalName);
      ScEntity parentEntity =
          env.resolveArgEntity(args, canonicalName, nthArg: 'second');

      // Mv logic
      if (childEntity is ScStory) {
        if (parentEntity is ScEpic) {
          return waitOn(env.client.updateStory(
              env, childEntity.idString, {'epic_id': parentEntity.idString}));
        } else if (parentEntity is ScIteration) {
          return waitOn(env.client.updateStory(env, childEntity.idString,
              {'iteration_id': parentEntity.idString}));
        } else if (parentEntity is ScTeam) {
          return waitOn(env.client.updateStory(
              env, childEntity.idString, {'group_id': parentEntity.idString}));
        } else {
          throw BadArgumentsException(
              "A story can only be moved to an epic, iteration, or team, but you tried to move it to a ${parentEntity.typeName()}");
        }
      } else if (childEntity is ScEpic) {
        if (parentEntity is ScMilestone) {
          return waitOn(env.client.updateEpic(env, childEntity.idString,
              {'milestone_id': parentEntity.idString}));
        } else if (parentEntity is ScTeam) {
          return waitOn(env.client.updateEpic(
              env, childEntity.idString, {'group_id': parentEntity.idString}));
        } else {
          throw BadArgumentsException(
              "An epic can only be moved to a milestone or team, but you tried to move it to a ${parentEntity.typeName()}");
        }
      } else {
        throw BadArgumentsException(
            "You tried to mv a ${childEntity.typeName()} to a ${parentEntity.typeName()}, but that is unsupported.");
      }
    }
  }
}

class ScFnData extends ScBaseInvocable {
  static final ScFnData _instance = ScFnData._internal();
  ScFnData._internal();
  factory ScFnData() => _instance;

  @override
  String get canonicalName => 'data';

  @override
  Set<List<String>> get arities => {
        [],
        ["entity"]
      };

  @override
  String get help => "Returns the entity's complete, raw data.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
Returns a PL representation of the data returned by Shortcut's API for the given entity.

If you want the original JSON, you'll need to use the --json flag with this program to have it output JSON.

The underlying data of multiple entities is adapted to handle resolving certain IDs to entities, for the sake of better ergonomics at the REPL.

This function will fetch from remote if it detects the entity is "empty" (constructed only from an ID) and needs to be refreshed.

See also:
  details
  keys
  summary""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      final pe = env.parentEntity;
      if (pe != null) {
        final entityData = pe.data;
        // Statefully fill in data if needed.
        if (entityData.isEmpty) waitOn(pe.fetch(env));
        return pe.data;
      } else {
        throw BadArgumentsException(
            "You've called `data` with no arguments but also don't have a parent entity set. First `cd` into an entity and try again, or pass the entity directly to this function.");
      }
    } else if (args.length > 1) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects either a single entity as argument, or you can invoke it with no arguments if you've already `cd`ed into an entity.");
    } else {
      final ScExpr entity = args.first;
      if (entity is ScEntity) {
        return entity.data;
      } else {
        throw BadArgumentsException(
            "If provided, the argument to `data` must be an entity, but received ${entity.typeName()}");
      }
    }
  }
}

class ScFnDetails extends ScBaseInvocable {
  static final ScFnDetails _instance = ScFnDetails._internal();
  ScFnDetails._internal();
  factory ScFnDetails() => _instance;

  @override
  String get canonicalName => 'details';

  @override
  Set<List<String>> get arities => {
        [],
        ["entity"]
      };

  @override
  String get help => "Returns the entity's most important details as a map.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
Prints a table of entries that are the core entries for most entities within Shortcut.

If `summary` or `pwd` doesn't show what you expect and `data` is too much, `details` is a middle ground between the two.

See also:
  cwd
  data
  keys
  pwd
  summary""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      final pe = env.parentEntity;
      if (pe != null) {
        final entityData = pe.data;
        // Statefully fill in data if needed.
        if (entityData.isEmpty) waitOn(pe.fetch(env));
        return details(pe);
      } else {
        throw BadArgumentsException(
            "You've called `details` with no arguments but also don't have a parent entity set. First `cd` into an entity and try again, or pass the entity directly to this function.");
      }
    } else if (args.length > 1) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects either a single entity as argument, or you can invoke it with no arguments if you've already `cd`ed into an entity.");
    } else {
      final ScExpr entity = args.first;
      if (entity is ScEntity) {
        return details(entity);
      } else {
        throw BadArgumentsException(
            "If provided, the argument to `details` must be an entity, but received ${entity.typeName()}");
      }
    }
  }
}

class ScFnSummary extends ScBaseInvocable {
  static final ScFnSummary _instance = ScFnSummary._internal();
  ScFnSummary._internal();
  factory ScFnSummary() => _instance;

  @override
  String get canonicalName => 'summary';

  @override
  Set<List<String>> get arities => {
        [],
        ["entity"]
      };

  @override
  String get help => "Returns a summary of the Shortcut entity's state.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
The same as `pwd` but for the entity provided as an argument.

This _prints_ a summary and returns `nil`.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    ScEntity entity = env.resolveArgEntity(args, canonicalName);
    if (entity.data.isEmpty) waitOn(entity.fetch(env));
    return entity.printSummary(env);
  }
}

class ScFnInvoke extends ScBaseInvocable {
  static final ScFnInvoke _instance = ScFnInvoke._internal();
  ScFnInvoke._internal();
  factory ScFnInvoke() => _instance;

  @override
  String get canonicalName => 'invoke';

  @override
  Set<List<String>> get arities => {
        ["function"],
        ["function", "argument", "..."]
      };

  @override
  String get help => "Invoke the provided function.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""Function invocation happens by default in many syntactic positions:

- A function evaluated by itself
- A function evaluated by itself with arguments following
- A function evaluted as the first item after a pipe |
- A function evaluated as an item in a list
- A function evaluated as a key or value in a map

If you find yourself needing to invoke a function in a position it's otherwise treated as a value, you can use this `invoke` function to do so.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    // The invocable + one argument for now
    final ScExpr invocable = args.first;
    if (invocable is ScAnonymousFunction) {
      final argsForInvocable = args.skip(1);
      if (argsForInvocable.length != invocable.numArgs) {
        throw BadArgumentsException(
            "The anonymous function expects ${invocable.numArgs} arguments but received ${argsForInvocable.length}");
      } else {
        return invocable.invoke(env, argsForInvocable);
      }
    } else if (invocable is ScBaseInvocable) {
      final argsForInvocable = args.skip(1);
      return invocable.invoke(env, argsForInvocable);
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects its first argument to be a function, but received a ${invocable.typeName()}");
    }
  }
}

class ScFnApply extends ScBaseInvocable {
  static final ScFnApply _instance = ScFnApply._internal();
  ScFnApply._internal();
  factory ScFnApply() => _instance;

  @override
  String get canonicalName => 'apply';

  @override
  Set<List<String>> get arities => {
        ["function", "list-of-args"]
      };

  @override
  String get help => "Apply the given function to the list of arguments.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
If you need to invoke a function with a number of arguments known only at runtime, use this function to call that function as if the list of arguments were passed directly.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 2) {
      final itsArgs = args[0];
      final invocable = args[1];
      if (itsArgs is ScList) {
        if (invocable is ScBaseInvocable) {
          return invocable.invoke(env, itsArgs);
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function expects its second argument to be a function, but received a ${invocable.typeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects its first argument to be a list, but received a ${itsArgs.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 2 arguments: a list of args and an function to invoke with them.");
    }
  }
}

class ScFnMap extends ScBaseInvocable {
  static final ScFnMap _instance = ScFnMap._internal();
  ScFnMap._internal();
  factory ScFnMap() => _instance;

  @override
  String get canonicalName => 'map';

  @override
  Set<List<String>> get arities => {
        ["collection", "function"]
      };

  @override
  String get help =>
      "Invoke a function for each item in a list, returning the list of return values.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
Rather than a loop, this function allows traversing every item of a collection and returning a new collection that is the result of invoking the given function with each item as its sole argument.

This function is immutable, leaving the original collection intact.

See also:
  concat
  filter
  join
  reduce
  sort
  take""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != 2) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 2 arguments: a list and a function.");
    } else {
      final list = args[0];
      final invocable = args[1];
      if (list is! ScList) {
        throw BadArgumentsException(
            "The first argument to `map` or `for-each` must be a list, but received ${list.typeName()}");
      }
      if (invocable is! ScBaseInvocable) {
        throw BadArgumentsException(
            "The second argument to `map` or `for-each` must be a function, but received ${invocable.typeName()}");
      }
      List<ScExpr> ret = [];
      for (final item in list.innerList) {
        ret.add(invocable.invoke(env, ScList([item])));
      }
      return ScList(ret);
    }
  }
}

class ScFnReduce extends ScBaseInvocable {
  static final ScFnReduce _instance = ScFnReduce._internal();
  ScFnReduce._internal();
  factory ScFnReduce() => _instance;

  @override
  String get canonicalName => 'reduce';

  @override
  Set<List<String>> get arities => {
        ["collection", "reducing-fn"],
        ["collection", "starting-accumulator", "reducing-fn"]
      };

  @override
  String get help =>
      "Reduce a list of things down to a single value. Takes a list, an optional starting accumulator, and a function of (acc, item).";

  @override
  // TODO: implement helpFull
  String get helpFull =>
      help +
      '\n\n' +
      r"""
NB: For Clojure developers, `reduce` has similar signature expectations, with the obvious exception of the position of the collection in the function parameters.

If the collection is empty:
  The function is expected to have a 0-arity that can be invoked to provide the return value of the reduction.
If the collection has 1 item:
  That item is returned without invoking the function.
Otherwise:
  If a starting accumulator is provided, that is used with the reducing function.
  If a starting accumulator is not provided and the collection has 2 or more elements:
    The first item of the collection is used as the starting accumulator, then the rest of the collection has the reducing function applied.

NB: Although Piped Lisp does not support implementing your own multi-arity functions, several built-in functions do support multiple arities and work well with reduce (e.g., `+` and other arithmetic functions).
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length < 2 || args.length > 3) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 2 or 3 arguments: a list, an optional starting accumulator, and a function of (acc, item), but received ${args.length} arguments.");
    } else {
      final list = args[0];
      if (list is ScList) {
        if (args.length == 2) {
          // list + fn

          final invocable = args[1];
          if (invocable is ScBaseInvocable) {
            if (list.isEmpty) {
              try {
                final defaultValue = invocable.invoke(env, ScList([]));
                return defaultValue;
              } catch (e) {
                throw BadArgumentsException(
                    "The `$canonicalName` function expects a starting accumulator or a function that can be invoked with zero arguments when the collection passed in is empty. The collection is empty, no accumulator was passed, and the function threw an exception.");
              }
            }
            return list.reduce(
                (acc, item) => invocable.invoke(env, ScList([acc, item])));
          } else {
            throw BadArgumentsException(
                "When passing two arguments to `reduce`, the second argument must be a function, but received ${invocable.typeName()}");
          }
        } else {
          // list + acc + fn
          final startingAcc = args[1];
          if (list.isEmpty) {
            return startingAcc;
          } else {
            final invocable = args[2];
            if (invocable is ScBaseInvocable) {
              final listCopy = ScList(List<ScExpr>.from(list.innerList));
              listCopy.insertMutable(0, startingAcc);
              return listCopy.reduce(
                  (acc, item) => invocable.invoke(env, ScList([acc, item])));
            } else {
              throw BadArgumentsException(
                  "When passing three arguments to `reduce`, the third argument must be a function, but received ${invocable.typeName()}");
            }
          }
        }
      } else {
        throw BadArgumentsException(
            "The first argument to `reduce` must be a list, but received ${list.typeName()}");
      }
    }
  }
}

class ScFnConcat extends ScBaseInvocable {
  static final ScFnConcat _instance = ScFnConcat._internal();
  ScFnConcat._internal();
  factory ScFnConcat() => _instance;

  @override
  String get canonicalName => 'concat';

  @override
  Set<List<String>> get arities => {
        [],
        ["collection", "..."]
      };

  @override
  String get help => 'Combine multiple collections into one.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScList([]);
    } else {
      final sample = args[0];
      if (sample is ScString) {
        final sb = StringBuffer();
        for (final coll in args.innerList) {
          if (coll is ScString) {
            sb.write(coll.value);
          } else if (coll == ScNil()) {
            continue;
          } else {
            sb.write(coll.printToString(env));
          }
        }
        return ScString(sb.toString());
      } else if (sample is ScList) {
        List<ScExpr> l = [];
        for (final coll in args.innerList) {
          if (coll is ScList) {
            l.addAll(coll.innerList);
          } else if (coll == ScNil()) {
            continue;
          } else {
            throw BadArgumentsException(
                "The `$canonicalName` function can concatenate lists, but all arguments must then be lists; received a ${coll.typeName()}");
          }
        }
        return ScList(l);
      } else if (sample is ScMap) {
        ScMap m = ScMap({});
        for (final coll in args.innerList) {
          if (coll is ScMap) {
            m.addMapMutable(coll);
          } else if (coll == ScNil()) {
            continue;
          } else {
            throw BadArgumentsException(
                "The `$canonicalName` function can concatenate maps, but all arguments must then be maps; received a ${coll.typeName()}");
          }
        }
        return m;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function can concatenate strings, lists, and maps, but received a ${sample.typeName()}");
      }
    }
  }
}

class ScFnExtend extends ScBaseInvocable {
  static final ScFnExtend _instance = ScFnExtend._internal();
  ScFnExtend._internal();
  factory ScFnExtend() => _instance;

  @override
  String get canonicalName => 'extend';

  @override
  Set<List<String>> get arities => {
        [],
        ["collection", "..."]
      };

  @override
  String get help =>
      'Combine multiple maps into one, concatenating values that are collections.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""This function works only with maps, and concatenates values recursively as shown in the examples below.

Compare:

extend {.a [1 2]} {.a [3 4]} => {.a [1 2 3 4]}
concat {.a [1 2]} {.a [3 4]} => {.a [3 4]}
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScList([]);
    } else {
      ScMap m = ScMap({});
      for (final coll in args.innerList) {
        if (coll is ScMap) {
          for (final key in coll.keys) {
            final newValue = coll[key];
            final previousValue = m[key];
            ScExpr finalValue;
            if (newValue is ScList && previousValue is ScList) {
              final concatFn = ScFnConcat();
              finalValue =
                  concatFn.invoke(env, ScList([previousValue, newValue]));
            } else if (newValue is ScMap && previousValue is ScMap) {
              finalValue = invoke(env, ScList([previousValue, newValue]));
            } else {
              finalValue = newValue!;
            }
            m[key] = finalValue;
          }
        } else if (coll == ScNil()) {
          continue;
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function can extend maps, but received a ${coll.typeName()}");
        }
      }
      return m;
    }
  }
}

class ScFnKeys extends ScBaseInvocable {
  static final ScFnKeys _instance = ScFnKeys._internal();
  ScFnKeys._internal();
  factory ScFnKeys() => _instance;

  @override
  String get canonicalName => 'keys';

  @override
  Set<List<String>> get arities => {
        [],
        ["map-or-entity"]
      };

  @override
  String get help => "Returns the keys of this map or entity's data.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      if (env.parentEntity != null) {
        final pe = env.parentEntity!;
        return ScList(pe.data.innerMap.keys.toList());
      } else {
        throw BadArgumentsException(
            "If no arguments passed to `keys`, it expects the parent entity to be set by `cd`ing into an entity.");
      }
    } else {
      final arg = args[0];
      if (arg is ScMap) {
        return ScList(arg.innerMap.keys.toList());
      } else if (arg is ScEntity) {
        return ScList(arg.data.innerMap.keys.toList());
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects a map or entity argument, but received ${arg.typeName()}");
      }
    }
  }
}

class ScFnWhenNil extends ScBaseInvocable {
  static final ScFnWhenNil _instance = ScFnWhenNil._internal();
  ScFnWhenNil._internal();
  factory ScFnWhenNil() => _instance;

  @override
  String get canonicalName => 'when-nil';

  @override
  Set<List<String>> get arities => {
        ["possibly-nil-value", "replacement-value"]
      };

  @override
  String get help =>
      "If argument is `nil`, returns the replacement value provided.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 2) {
      final arg1 = args[0];
      final arg2 = args[1];
      if (arg1 == ScNil()) {
        return arg2;
      } else {
        return arg1;
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects two arguments: a possibly-nil value and a default to return if it is nil.");
    }
  }
}

class ScFnGet extends ScBaseInvocable {
  static final ScFnGet _instance = ScFnGet._internal();
  ScFnGet._internal();
  factory ScFnGet() => _instance;

  @override
  String get canonicalName => 'get';

  @override
  Set<List<String>> get arities => {
        ["collection", "key-or-index"],
        ["collection", "key-or-index", "default-if-not-found"]
      };

  @override
  String get help => 'Retrieve an item from a source at a selector.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length < 2) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects at least two arguments: `get <key> <source> [<default if missing>]`");
    }
    final source = args[0];
    final key = args[1];
    ScString strKey;
    if (key is ScDottedSymbol) {
      strKey = ScString(args[1].toString().substring(1));
    } else {
      strKey = ScString(args[1].toString());
    }
    final missingDefault = args.length > 2 ? args[2] : ScNil();
    if (source is ScEntity) {
      return source.data[key] ?? source.data[strKey] ?? missingDefault;
    } else if (source is ScMap) {
      return source.innerMap[key] ?? source.innerMap[strKey] ?? missingDefault;
    } else if (source is ScList) {
      if (key is ScNumber) {
        final k = key.value;
        if (k is int) {
          return source[k];
        } else {
          throw BadArgumentsException(
              "The index to `get` must be an integer if the collection is a list.");
        }
      } else {
        throw BadArgumentsException(
            "To `get` from a list, you must supply a numeric index.");
      }
    }
    // Not sure where null can be returned above, but this solves it.
    return missingDefault;
  }
}

class ScFnSecond extends ScBaseInvocable {
  static final ScFnSecond _instance = ScFnSecond._internal();
  ScFnSecond._internal();
  factory ScFnSecond() => _instance;

  @override
  String get canonicalName => 'second';

  @override
  Set<List<String>> get arities => {
        ["collection-or-date-time"]
      };

  @override
  String get help =>
      "Returns either the second item in a collection, or the second value of a date-time value.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final target = args[0];
      if (target is ScDateTime) {
        final dateTimeSecondFn = ScFnDateTimeField(ScDateTimeFormat.second);
        return dateTimeSecondFn.invoke(env, ScList([target]));
      } else {
        final getFn = ScFnGet();
        return getFn.invoke(env, ScList([target, ScNumber(1)]));
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnGetIn extends ScBaseInvocable {
  static final ScFnGetIn _instance = ScFnGetIn._internal();
  ScFnGetIn._internal();
  factory ScFnGetIn() => _instance;

  @override
  String get canonicalName => 'get-in';

  @override
  Set<List<String>> get arities => {
        ["collection", "list-of-keys-and/or-indices"],
        ["collection", "list-of-keys-and/or-indices", "default-if-not-found"]
      };

  @override
  String get help => 'Retrieve an item from a source at a selector.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length < 2) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects at least two arguments: `get-in <source> <selector> [<default if missing>]`");
    }
    final source = args[0];
    final selector = args[1];
    if (selector is! ScList) {
      throw BadArgumentsException(
          "The `$canonicalName` function's second argument must be a list of keys to get out of the map, but received a ${selector.typeName()}");
    }
    final missingDefault = args.length > 2 ? args[2] : ScNil();
    if (source is ScEntity) {
      return getIn(source.data, selector, missingDefault);
    } else if (source is ScMap) {
      return getIn(source, selector, missingDefault);
    }
    // Not sure where null can be returned above, but this solves it.
    return missingDefault;
  }
}

class ScFnContains extends ScBaseInvocable {
  static final ScFnContains _instance = ScFnContains._internal();
  ScFnContains._internal();
  factory ScFnContains() => _instance;

  @override
  String get canonicalName => 'contains?';

  @override
  Set<List<String>> get arities => {
        ["collection", "item"]
      };

  @override
  String get help => 'Returns true if the collection contains the given item.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length < 2) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 2 arguments: a collection (or string) and an item (or substring).");
    }
    final source = args[0];
    final key = args[1];
    ScString strKey;
    if (key is ScString) {
      strKey = key;
    } else if (key is ScDottedSymbol) {
      strKey = ScString(key.toString().substring(1));
    } else {
      strKey = ScString(key.toString());
    }
    if (source is ScEntity) {
      return ScBoolean.fromBool(
          source.data.containsKey(key) || source.data.containsKey(strKey));
    } else if (source is ScMap) {
      return ScBoolean.fromBool(
          source.containsKey(key) || source.containsKey(strKey));
    } else if (source is ScList) {
      return ScBoolean.fromBool(
          source.innerList.contains(key) || source.innerList.contains(strKey));
    } else if (source is ScString) {
      return ScBoolean.fromBool(source.value.contains(strKey.value));
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function's first argument must be a collection or string, but received ${source.typeName()}");
    }
  }
}

class ScFnIsSubset extends ScBaseInvocable {
  static final ScFnIsSubset _instance = ScFnIsSubset._internal();
  ScFnIsSubset._internal();
  factory ScFnIsSubset() => _instance;

  @override
  String get canonicalName => 'subset?';

  @override
  Set<List<String>> get arities => {
        ["collection-subset", "collection-superset"]
      };

  @override
  String get help =>
      "Returns true if the first collection is a subset of the second.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 2) {
      final subset = args[0];
      final superset = args[1];
      if (subset is ScList) {
        if (superset is ScList) {
          for (final item in subset.innerList) {
            if (!superset.contains(item)) {
              return ScBoolean.falsitas();
            }
          }
          return ScBoolean.veritas();
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function expects both arguments to be of the same type, received one list and one ${superset.typeName()}");
        }
      } else if (subset is ScString) {
        if (superset is ScString) {
          return ScBoolean.fromBool(superset.value.contains(subset.value));
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function expects both arguments to be of the same type, received one string and one ${superset.typeName()}");
        }
      } else if (subset is ScMap) {
        if (superset is ScMap) {
          for (final key in subset.innerMap.keys) {
            if (!(superset.containsKey(key) && superset[key] == subset[key])) {
              return ScBoolean.falsitas();
            }
          }
          return ScBoolean.veritas();
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function expects both arguments to be of the same type, received one map and one ${superset.typeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function does not support values of type ${subset.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects to receive 2 arguments, but received ${args.length} arguments.");
    }
  }
}

class ScFnCount extends ScBaseInvocable {
  static final ScFnCount _instance = ScFnCount._internal();
  ScFnCount._internal();
  factory ScFnCount() => _instance;

  @override
  String get canonicalName => 'count';

  @override
  Set<List<String>> get arities => {
        ["collection"]
      };

  @override
  String get help =>
      'Returns the length of the collection, i.e., the count of its items.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw BadArgumentsException(
          'The `$canonicalName` function expects one argument: a collection.');
    } else {
      final coll = args.first;
      if (coll is ScList) {
        return ScNumber(coll.length);
      } else if (coll is ScMap) {
        return ScNumber(coll.length);
      } else if (coll is ScString) {
        return ScNumber(coll.value.length);
      } else {
        throw BadArgumentsException(
            'The `$canonicalName` function expects its argument to be a collection, but received a ${coll.typeName()}');
      }
    }
  }
}

class ScFnSort extends ScBaseInvocable {
  static final ScFnSort _instance = ScFnSort._internal();
  ScFnSort._internal();
  factory ScFnSort() => _instance;

  @override
  String get canonicalName => 'sort';

  @override
  Set<List<String>> get arities => {
        ["collection"],
        ["collection", "function"]
      };

  @override
  String get help => 'Sort the collection (maps by their keys).';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""Returns a copy of the original collection, sorted. Maps are sorted by their keys.

Pass an additional function (or dotted symbol) to sort using a custom comparator.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final coll = args[0];
      if (coll is ScList) {
        final copy = List<ScExpr>.from(coll.innerList);
        copy.sort();
        return ScList(copy);
      } else if (coll is ScMap) {
        final copy = Map<ScExpr, ScExpr>.from(coll.innerMap);
        final ksUnsorted = copy.keys;
        final ks = ksUnsorted.toList();
        ks.sort();
        final Map<ScExpr, ScExpr> m = {};
        for (final k in ks) {
          m[k] = copy[k]!;
        }
        return ScMap(m);
      } else if (coll is ScString) {
        throw BadArgumentsException(
            "Sorting a string is not supported at this time.");
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's first argument must be a collection, but received a ${coll.typeName()}");
      }
    } else if (args.length == 2) {
      final coll = args[0];
      final fn = args[1];
      if (fn is ScBaseInvocable) {
        if (coll is ScList) {
          final copy = List<ScExpr>.from(coll.innerList);
          copy.sort((a, b) {
            final valueA = fn.invoke(env, ScList([a]));
            final valueB = fn.invoke(env, ScList([b]));
            return (valueA as Comparable).compareTo(valueB);
          });
          return ScList(copy);
        } else if (coll is ScMap) {
          final copy = Map<ScExpr, ScExpr>.from(coll.innerMap);
          final ksUnsorted = copy.keys;
          final ks = ksUnsorted.toList();
          ks.sort((a, b) {
            final valueA = fn.invoke(env, ScList([a]));
            final valueB = fn.invoke(env, ScList([b]));
            return (valueA as Comparable).compareTo(valueB);
          });
          final Map<ScExpr, ScExpr> m = {};
          for (final k in ks) {
            m[k] = copy[k]!;
          }
          return ScMap(m);
        } else if (coll is ScString) {
          throw BadArgumentsException(
              "Sorting a string is not supported at this time.");
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function's first argument must be a collection, but received a ${coll.typeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's second argument must be a function, but received a ${fn.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          'The `$canonicalName` function expects either 1 or 2 arguments: a collection, and an optional sorting function.');
    }
  }
}

class ScFnSplit extends ScBaseInvocable {
  static final ScFnSplit _instance = ScFnSplit._internal();
  ScFnSplit._internal();
  factory ScFnSplit() => _instance;

  @override
  String get canonicalName => 'split';

  @override
  Set<List<String>> get arities => {
        ["collection"],
        ["collection", "separator"]
      };

  @override
  String get help => 'Split the collection by the given separator.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""

If no separator is given, defaults to splitting by newlines (\n).""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty || args.length > 2) {
      throw BadArgumentsException(
          'The `$canonicalName` function expects one or two arguments: a collection and an optional separator (default is newline), but received ${args.length} arguments.');
    } else {
      final coll = args.first;
      ScString sep;
      if (args.length == 2) {
        final argSep = args[1];
        if (argSep is ScString) {
          sep = argSep;
        } else {
          throw BadArgumentsException(
              'The `$canonicalName` function expects its second argument to be a string, but received a ${argSep.typeName()}');
        }
      } else {
        sep = ScString('\n');
      }

      if (coll is ScString) {
        return coll.split(separator: sep);
      } else {
        throw BadArgumentsException(
            'The `$canonicalName` function currently only supports splitting strings, received a ${coll.typeName()}');
      }
    }
  }
}

class ScFnJoin extends ScBaseInvocable {
  static final ScFnJoin _instance = ScFnJoin._internal();
  ScFnJoin._internal();
  factory ScFnJoin() => _instance;

  @override
  String get canonicalName => 'join';

  @override
  Set<List<String>> get arities => {
        ["collection"],
        ["collection", "separator"]
      };

  @override
  String get help =>
      'Join the collection into a string using the given separator.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""

If no separator is given, defaults to joining with newlines (\n).""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw BadArgumentsException(
          'The `$canonicalName` function expects one or two arguments: a collection and an optional separator (default is newline)');
    } else {
      final coll = args[0];
      ScString sep;
      if (args.length == 2) {
        final argSep = args[1];
        if (argSep is ScString) {
          sep = argSep;
        } else {
          throw BadArgumentsException(
              'The `$canonicalName` function expects its second argument to be a string, but received a ${argSep.typeName()}');
        }
      } else {
        sep = ScString('\n');
      }

      if (coll is ScList) {
        return coll.join(separator: sep);
      } else {
        throw BadArgumentsException(
            'The `$canonicalName` function currently only supports joining lists, received a ${coll.typeName()}');
      }
    }
  }
}

class ScFnFile extends ScBaseInvocable {
  static final ScFnFile _instance = ScFnFile._internal();
  ScFnFile._internal();
  factory ScFnFile() => _instance;

  @override
  String get canonicalName => 'file';

  @override
  Set<List<String>> get arities => {
        [],
        ["file-name"]
      };

  @override
  String get help =>
      'Returns a file object given its relative or absolute path as a string, or a temporary file if called with no arguments.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScFile(newTempFile());
    } else if (args.length == 1) {
      final path = args.first;
      if (path is ScString) {
        final file = File(path.value);
        return ScFile(file);
      } else {
        throw BadArgumentsException(
            'The argument to `file` must be a string, but received a ${path.typeName()}');
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 0 or 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnReadFile extends ScBaseInvocable {
  static final ScFnReadFile _instance = ScFnReadFile._internal();
  ScFnReadFile._internal();
  factory ScFnReadFile() => _instance;

  @override
  String get canonicalName => 'read-file';

  @override
  Set<List<String>> get arities => {
        ["file-or-file-name"]
      };

  @override
  String get help => 'Returns string contents of a file.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final file = args[0];
      if (file is ScFile) {
        return file.readAsStringSync();
      } else if (file is ScString) {
        final fileFile = resolveFile(env, file.value);
        return ScFile(fileFile).readAsStringSync();
      } else {
        throw BadArgumentsException(
            'The `$canonicalName` function expects a file argument, but received a ${file.typeName()}');
      }
    } else {
      throw BadArgumentsException(
          'The `$canonicalName` function expects one argument: the file to read.');
    }
  }
}

class ScFnWriteFile extends ScBaseInvocable {
  static final ScFnWriteFile _instance = ScFnWriteFile._internal();
  ScFnWriteFile._internal();
  factory ScFnWriteFile() => _instance;

  @override
  String get canonicalName => 'write-file';

  @override
  Set<List<String>> get arities => {
        ["file-or-file-name", "value"]
      };

  @override
  String get help => 'Write string contents to a file.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 2) {
      final maybeFile = args[0];
      File file;
      if (maybeFile is ScFile) {
        file = maybeFile.file;
      } else if (maybeFile is ScString) {
        file = resolveFile(env, maybeFile.value);
      } else {
        throw BadArgumentsException(
            'The `$canonicalName` function expects its first argument to be a file, but received a ${maybeFile.typeName()}');
      }
      final content = args[1];
      String contentStr;
      if (content is ScString) {
        contentStr = content.value;
      } else {
        final isAnsiEnabled = env.isAnsiEnabled;
        env.isAnsiEnabled = false;
        contentStr = content.printToString(env);
        env.isAnsiEnabled = isAnsiEnabled;
      }

      file.writeAsStringSync(contentStr);
      return ScNil();
    } else {
      throw BadArgumentsException(
          'The `$canonicalName` function expects two arguments: the file to write and content to write to it.');
    }
  }
}

class ScFnClipboard extends ScBaseInvocable {
  static final ScFnClipboard _instance = ScFnClipboard._internal();
  ScFnClipboard._internal();
  factory ScFnClipboard() => _instance;

  @override
  String get canonicalName => 'clip';

  @override
  Set<List<String>> get arities => {
        ["value"]
      };

  @override
  String get help => "Copy the given string to your system clipboard.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final content = args[0];
      String contentStr;
      if (content is ScString) {
        contentStr = content.value;
      } else {
        final isAnsiEnabled = env.isAnsiEnabled;
        env.isAnsiEnabled = false;
        contentStr = content.printToString(env);
        env.isAnsiEnabled = isAnsiEnabled;
      }
      String executable;
      List<String> executableArgs = [];
      if (Platform.isMacOS) {
        executable = 'pbcopy';
      } else if (Platform.isLinux) {
        executable = 'xclip';
        executableArgs = ['-selection', 'clipboard', '-i'];
      } else if (Platform.isWindows) {
        executable = 'clip';
      } else {
        throw PlatformNotSupported(
            "Only macOS, Linux, and Windows support clipboard access at this time.");
      }
      final proc = waitOn(Process.start(executable, executableArgs));
      proc.stdin.write(contentStr);
      proc.stdin.close();
      env.out.writeln(
          env.style('[INFO] Content copied to system clipboard.', styleInfo));
      return ScString(contentStr);
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function only accepts 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnInterpret extends ScBaseInvocable {
  static final ScFnInterpret _instance = ScFnInterpret._internal();
  ScFnInterpret._internal();
  factory ScFnInterpret() => _instance;

  @override
  String get canonicalName => 'interpret';

  @override
  Set<List<String>> get arities => {
        ["string"]
      };

  @override
  String get help =>
      "Returns the expression resulting from interpreting the given string of code.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final sourceString = args[0];
      if (sourceString is ScString) {
        return env.interpretAll(
            '<string from console>', sourceString.value.split('\n'));
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function only accepts a string argument, but received a ${sourceString.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument: a string of source code to interpret.");
    }
  }
}

class ScFnLoad extends ScBaseInvocable {
  static final ScFnLoad _instance = ScFnLoad._internal();
  ScFnLoad._internal();
  factory ScFnLoad() => _instance;

  @override
  String get canonicalName => 'load';

  @override
  Set<List<String>> get arities => {
        ["file-or-file-name"]
      };

  @override
  String get help => 'Read and evaluate the given source code file.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final sourceFilePath = args[0];
      File sourceFile;
      if (sourceFilePath is ScFile) {
        sourceFile = sourceFilePath.file;
      } else if (sourceFilePath is ScString) {
        sourceFile = resolveFile(env, (args.first as ScString).value);
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects a string argument, but received a ${sourceFilePath.typeName()}");
      }
      final sourceLines = sourceFile.readAsLinesSync();
      return env.interpretAll(sourceFile.absolute.path, sourceLines);
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects one argument: the path of the file to load.");
    }
  }
}

class ScFnOpen extends ScBaseInvocable {
  static final ScFnOpen _instance = ScFnOpen._internal();
  ScFnOpen._internal();
  factory ScFnOpen() => _instance;

  @override
  String get canonicalName => 'open';

  @override
  Set<List<String>> get arities => {
        ["entity-or-map"]
      };

  @override
  String get help =>
      "Open an entity's page in the Shortcut web app, or any map with a \"url\" or \"app_url\" entry.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""Every Shortcut entity has an `app_url` entry that can be opened in a web browser to view the details of that entity.

Caveat: Only Linux and macOS supported, this function shells out to `xdg-open` or `open` respectively. If on another platform, copy the `app_url` directly.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1 && args[0] is ScMap) {
      final m = args[0] as ScMap;
      final appUrl = m[ScString('app_url')];
      final url = m[ScString('url')];
      if (appUrl is ScString) {
        execOpenInBrowser(appUrl.value);
      } else if (url is ScString) {
        execOpenInBrowser(url.value);
      } else {
        throw BadArgumentsException(
            'Could not find a URL at "app_url" or "url" to open in the map passed to the `$canonicalName` function.');
      }
    } else {
      ScEntity entity = env.resolveArgEntity(args, canonicalName);
      final appUrl = entity.data[ScString('app_url')];
      if (appUrl is ScString) {
        execOpenInBrowser(appUrl.value);
      } else {
        throw MissingEntityDataException(
            "The app_url of this ${entity.typeName()} could not be accessed.");
      }
    }
    return ScNil();
  }
}

class ScFnEdit extends ScBaseInvocable {
  static final ScFnEdit _instance = ScFnEdit._internal();
  ScFnEdit._internal();
  factory ScFnEdit() => _instance;

  @override
  String get canonicalName => 'edit';

  @override
  Set<List<String>> get arities => {
        [],
        ["content-or-file"]
      };

  @override
  String get help =>
      'Opens your SHORTCUT_EDITOR or EDITOR and returns the temp file created, or opens your editor with the temp file supplied, or opens your editor with a temp file pre-populated with the value supplied.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return execOpenInEditor(env);
    } else if (args.length == 1) {
      final content = args[0];
      if (content is ScFile) {
        return execOpenInEditor(env, existingFile: content.file);
      } else {
        String contentStr;
        if (content is ScString) {
          contentStr = content.value;
        } else {
          contentStr = content.printToString(env);
        }
        final tempFile = newTempFile();
        tempFile.writeAsStringSync(contentStr);
        return execOpenInEditor(env, existingFile: tempFile);
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function does not take any arguments, but received ${args.length} arguments.");
    }
  }
}

class ScFnColor extends ScBaseInvocable {
  static final ScFnColor _instance = ScFnColor._internal();
  ScFnColor._internal();
  factory ScFnColor() => _instance;

  @override
  String get canonicalName => 'color';

  @override
  Set<List<String>> get arities => {
        ['color-name-or-number']
      };

  @override
  String get help =>
      "Print the color and return a hexadecimal representation of its RGB values.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""

If the color passed in is not recognized, black is printed and what you passed in is returned.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final x = args[0];
      if (x is ScString) {
        String hex = x.value.toUpperCase();
        if (!hex.startsWith('#')) {
          hex = "#$hex";
        }
        env.out.writeln(env.style("$hex ⬛️", hex));
        return ScString(hex);
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects a string argument, but received a ${x.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` expects 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnSearch extends ScBaseInvocable {
  static final ScFnSearch _instance = ScFnSearch._internal();
  ScFnSearch._internal();
  factory ScFnSearch() => _instance;

  @override
  String get canonicalName => 'search';

  @override
  Set<List<String>> get arities => {
        ["api-search-query-string"],
        ["collection", "string"]
      };

  @override
  String get help =>
      'Search through a local list or for stories & epics via the Shortcut API.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""If given a collection as the first argument, this function does a case-insensitive search for the second argument and returns a collection of matching items.

If given a single string value, this function makes an API call to use Shortcut's full-text search functionality, returning a map with a "stories" and "epics" entries for story and epic search results, respectively.

Search operators that Shortcut's API supports:

== Story-specific Search Operators ==
estimate:      is:blocked
has:attachment is:blocker
has:epic       is:story
has:task       type:

== Story & Epic Search Operators ==
completed:   is:done        requester:
created:     is:overdue     skill-set:
due:         is:started     started:
epic:        is:unestimated state:
estimate:    is:unstarted   team:
has:comment  label:         technical-area:
has:deadline moved:         type:
has:owner    owner:         updated:
id:          product-area:
is:archived  project:
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final query = args[0];
      if (query is ScString) {
        ScMap res = waitOn(env.client.search(env, query));
        return res;
      } else {
        throw BadArgumentsException(
            "The argument to `search` must be a search string, but received a ${query.typeName()}");
      }
    } else if (args.length == 2) {
      final coll = args[0];
      final query = args[1];
      String queryStr;
      if (query is ScString) {
        queryStr = query.value;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function when passed 2 arguments expects its second to be a string (for now), but received a ${query.typeName()}");
      }
      final jsonEncoder = JsonEncoder();
      if (coll is ScList) {
        return coll.where((expr) {
          final value = scExprToValue(expr, forJson: true);
          final jsonStr = jsonEncoder.convert(value);
          return ScBoolean.fromBool(
              jsonStr.toLowerCase().contains(queryStr.toLowerCase()));
        });
      } else if (coll is ScMap) {
        return coll.where((k, v) {
          final keyJson = jsonEncoder.convert(
              scExprToValue(k, forJson: true, throwOnIllegalJsonKeys: false));
          final valueJson = jsonEncoder.convert(
              scExprToValue(v, forJson: true, throwOnIllegalJsonKeys: false));
          final jsonStr = '$keyJson $valueJson';
          return ScBoolean.fromBool(
              jsonStr.toLowerCase().contains(queryStr.toLowerCase()));
        });
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function when passed 2 arguments expects its first to be a list, but received a ${coll.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 or 2 arguments: a query/search string, or a collection and a query.");
    }
  }
}

class ScFnFindStories extends ScBaseInvocable {
  static final ScFnFindStories _instance = ScFnFindStories._internal();
  ScFnFindStories._internal();
  factory ScFnFindStories() => _instance;

  @override
  String get canonicalName => 'find-stories';

  @override
  Set<List<String>> get arities => {
        ["find-stories-query-map"]
      };

  @override
  String get help => "Find stories given map of search parameters.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""Parameters that accept a collection employ "OR" semantics, not "AND".
For example, specifying two owner ids will return all stories owned by _either_
of the owners, not just stories they co-own.

archived           estimate             owner_id
completed_at_end   external_id          owner_ids
completed_at_start group_id             project_id
created_at_end     group_ids            project_ids
created_at_start   includes_description requested_by_id
deadline_end       iteration_id         story_type
deadline_start     iteration_ids        updated_at_end
epic_id            label_ids            updated_at_start
epic_ids           label_name           workflow_state_id

workflow_state_types (Enum: "done", "started", "unstarted")

Visit API docs for more details: https://shortcut.com/api/rest/v3#Search-Stories-Old""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final findMap = args[0];
      if (findMap is ScMap) {
        return waitOn(env.client.findStories(
            env, scExprToValue(findMap, forJson: true, onlyEntityIds: true)));
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's first argument must be a map, but recevied a ${findMap.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument: a map of parameters to search by.");
    }
  }
}

class ScFnFetch extends ScBaseInvocable {
  static final ScFnFetch _instance = ScFnFetch._internal();
  ScFnFetch._internal();
  factory ScFnFetch() => _instance;

  @override
  String get canonicalName => 'fetch';

  @override
  Set<List<String>> get arities => {
        [],
        ["entity-or-id"]
      };

  @override
  String get help => 'Fetch an entity via the Shortcut API.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    ScEntity entity =
        env.resolveArgEntity(args, canonicalName, forceFetch: true);
    return entity;
  }
}

class ScFnFetchAll extends ScBaseInvocable {
  static final ScFnFetchAll _instance = ScFnFetchAll._internal();
  ScFnFetchAll._internal();
  factory ScFnFetchAll() => _instance;

  @override
  String get canonicalName => 'fetch-all';

  @override
  Set<List<String>> get arities => {[]};

  @override
  String get help => 'Fetch and cache members, teams, and workflows.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      // NB: Fetch things that change infrequently but will make everything else here faster.
      env.out.writeln(env.style(
          ";; [Please Wait] Caching of all workflows, workflow states, members, and teams for this session. Run `fetch-all` to refresh.",
          'warn'));
      fetchAllTheThings(env);
      return ScNil();
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function takes no arguments. Use `fetch` to fetch an individual entity.");
    }
  }
}

class ScFnUpdate extends ScBaseInvocable {
  static final ScFnUpdate _instance = ScFnUpdate._internal();
  ScFnUpdate._internal();
  factory ScFnUpdate() => _instance;

  @override
  String get canonicalName => '!';

  @override
  Set<List<String>> get arities => {
        ["update-map"],
        ["key", "value"],
        ["entity", "update-map"],
        ["entity", "key", "value"],
      };

  @override
  String get help =>
      'Update the given entity in Shortcut with the given update map.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""
This function supports a couple of calling signatures:

    ! .owner_ids [me]

This expects to find a parent entity with an `"owner_ids"` entry. It calls the Shortcut API to _replace_ (not extend) the owners of this entity with `[me]`, resulting in you completely owning it.

    ! {.name "New name" .description "New description" .owner_ids [me]}

This is similar to the previous example regarding an expected parent entity, but allows you to provide a map with which to update the entity that contains several entries at once.

Both of these signatures support a first argument that is an entity, so that you can update any entity, rather than just the current parent entity you have `cd`ed into.
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isNotEmpty) {
      ScEntity entity = env.resolveArgEntity(args, canonicalName,
          forceParent: (args[0] is ScMap ||
              args[0] is ScString ||
              args[0] is ScDottedSymbol));

      ScMap updateMap;
      final maybeUpdateMap = args[0];
      if (maybeUpdateMap is ScMap) {
        updateMap = maybeUpdateMap;
      } else if (maybeUpdateMap is ScString ||
          maybeUpdateMap is ScDottedSymbol) {
        if (args.length == 1) {
          final value = entity.getField(maybeUpdateMap);
          final tempFile = newTempFile();
          List<String>? fields;
          if (entity is ScStory) {
            fields = ScStory.fieldsForUpdate.toList();
          } else if (entity is ScEpic) {
            fields = ScEpic.fieldsForUpdate.toList();
          } else if (entity is ScIteration) {
            fields = ScIteration.fieldsForUpdate.toList();
          } else if (entity is ScLabel) {
            fields = ScLabel.fieldsForUpdate.toList();
          } else if (entity is ScMilestone) {
            fields = ScMilestone.fieldsForUpdate.toList();
          } else if (entity is ScTask) {
            fields = ScTask.fieldsForUpdate.toList();
          } else if (entity is ScComment) {
            fields = ScComment.fieldsForUpdate.toList();
          } else if (entity is ScEpicComment) {
            fields = ScEpicComment.fieldsForUpdate.toList();
          }

          if (fields == null) {
            throw BadArgumentsException(
                "Using `!` with a ${entity.typeName()} entity is not currently supported.");
          } else {
            fields.sort();
            final formatted = fields.join(', ');
            tempFile.writeAsStringSync(
                ';; Fields: $formatted\n{$maybeUpdateMap $value}');
            execOpenInEditor(env, existingFile: tempFile);
            env.out.writeln(env.style(
                "\n;; [HELP] Once you've saved the file in your editor, run the following to update your Story:\n\n    load *1 | ! ${entity.readableString(env)} _\n",
                styleInfo));
            return ScFile(tempFile);
          }
        } else if (args.length == 2) {
          final updateKey = maybeUpdateMap;
          final updateValue = args[1];
          if (updateValue is ScWorkflowState) {
            updateMap = ScMap({updateKey: updateValue.id});
          } else {
            updateMap = ScMap({updateKey: updateValue});
          }
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function expects either a map or separate key/value pairs to update the entity; received a key, but no value.");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects either a map or separate key/value pairs to update the entity, but received ${maybeUpdateMap.typeName()}");
      }
      return waitOn(entity.update(
          env, scExprToValue(updateMap, forJson: true, onlyEntityIds: true)));
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects either a map or separate string/symbol key value pairs to update the entity, but received no arguments.");
    }
  }
}

class ScFnNextState extends ScBaseInvocable {
  static final ScFnNextState _instance = ScFnNextState._internal();
  ScFnNextState._internal();
  factory ScFnNextState() => _instance;

  @override
  String get canonicalName => 'next-state';

  @override
  Set<List<String>> get arities => {
        [],
        ["entity"]
      };

  @override
  String get help =>
      "Update the given entity (or parent entity, if unspecified) to the next workflow state.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""Tasks, stories, epics, and milestones can be in one of several states. This function updates such an entity to the next logical state.

- Tasks: Can be either done or not, so this moves an undone task to a done state.
- Stories: Stories live within a Workflow and every Workflow has a canonical sequence of states. This moves the given story to the next one within the same Story Workflow.
- Epics: Epics live within workflows that are similar to but different from Story workflows. This moves the given epic to the next one within the same Epic Workflow.
- Milestones: Milestones have a simpler to do/in-progress/done state. This moves the given workflow to the next logical state.

NB: Iterations are not included in this list, because their "state" is based solely on start/end date.
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    ScEntity entity = env.resolveArgEntity(args, canonicalName);

    if (entity is ScStory) {
      final workflow = entity.data[ScString('workflow_id')] as ScWorkflow;
      final workflowStates = workflow.data[ScString('states')] as ScList;
      final currentWorkflowState =
          entity.data[ScString('workflow_state_id')] as ScWorkflowState;
      final ids = workflowStates.mapImmutable((e) => e.id);
      final idx = ids.indexOf(currentWorkflowState.id);
      if (idx == -1) {
        throw Exception("Workflow state not defined within workflow.");
      } else if (idx == workflowStates.length - 1) {
        // At end, warn and move on.
        env.err.writeln(
            ';; [WARN] Already at last workflow state for the workflow ${workflow.printToString(env)}');
        return entity;
      } else {
        final nextWorkflowState = workflowStates[idx + 1] as ScWorkflowState;
        final updatedEntity = waitOn(env.client.updateStory(
            env,
            entity.idString,
            {"workflow_state_id": int.tryParse(nextWorkflowState.idString)}));
        entity.data = updatedEntity.data;
        env.out.write(env.style(";; [INFO] Moved from ", styleInfo));
        env.out.write(currentWorkflowState.inlineSummary(env));
        env.out.write(env.style(" to ", styleInfo));
        env.out.writeln(nextWorkflowState.inlineSummary(env));
        return entity;
      }
    } else if (entity is ScEpic) {
      final epicWorkflow = env.resolveEpicWorkflow();
      final epicWorkflowStates =
          epicWorkflow.data[ScString('epic_states')] as ScList;
      final currentEpicWorkflowState =
          entity.data[ScString('epic_state_id')] as ScEpicWorkflowState;
      final ids = epicWorkflowStates.mapImmutable((e) => e.id);
      final idx = ids.indexOf(currentEpicWorkflowState.id);
      if (idx == -1) {
        throw Exception(
            "Epic workflow state not defined within the epic workflow.");
      } else if (idx == epicWorkflowStates.length - 1) {
        // At end, warn and move on.
        env.err.writeln(
            ';; [WARN] Already at last epic workflow state for the workflow ${epicWorkflow.printToString(env)}');
        return entity;
      } else {
        final nextEpicWorkflowState =
            epicWorkflowStates[idx + 1] as ScEpicWorkflowState;
        final updatedEntity = waitOn(env.client.updateEpic(env, entity.idString,
            {"epic_state_id": int.tryParse(nextEpicWorkflowState.idString)}));
        entity.data = updatedEntity.data;
        env.out.write(env.style(";; [INFO] Moved from ", styleInfo));
        env.out.write(currentEpicWorkflowState.inlineSummary(env));
        env.out.write(env.style(' to ', styleInfo));
        env.out.writeln(
            env.style(nextEpicWorkflowState.inlineSummary(env), styleInfo));
        return entity;
      }
    } else if (entity is ScMilestone) {
      final currentState = (entity.data[ScString('state')] as ScString).value;
      final idx = ScMilestone.states.indexOf(currentState);
      if (idx == -1) {
        throw BadArgumentsException(
            'The milestone is in an unsupported state: "$currentState"');
      } else if (idx == ScMilestone.states.length - 1) {
        env.err.writeln(';; [WARN] Milestone is already done.');
        return entity;
      } else {
        final nextState = ScMilestone.states[idx + 1];
        final updatedEntity = waitOn(env.client
            .updateMilestone(env, entity.idString, {'state': nextState}));
        env.out.write(env.style(';; [INFO] Moved from ', styleInfo));
        env.out.write(currentState);
        env.out.write(env.style(' to ', styleInfo));
        env.out.writeln(nextState);
        entity.data = updatedEntity.data;
        return entity;
      }
    } else if (entity is ScTask) {
      final isComplete = entity.data[ScString('complete')];
      if (isComplete == ScBoolean.falsitas()) {
        final storyId = entity.data[ScString('story_id')] as ScNumber;
        final updateMap = {'complete': true};
        final updatedEntity = waitOn(env.client.updateTask(
            env, storyId.value.toString(), entity.idString, updateMap));
        entity.data = updatedEntity.data;
        return entity;
      } else {
        env.err.writeln(';; [WARN] Task is already complete.');
        return entity;
      }
    } else {
      throw UnimplementedError();
    }
  }
}

class ScFnPreviousState extends ScBaseInvocable {
  static final ScFnPreviousState _instance = ScFnPreviousState._internal();
  ScFnPreviousState._internal();
  factory ScFnPreviousState() => _instance;

  @override
  String get canonicalName => 'previous-state';

  @override
  Set<List<String>> get arities => {
        [],
        ["entity"]
      };

  @override
  String get help =>
      "Update the given entity (or parent entity, if unspecified) to the previous workflow state.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""Tasks, stories, epics, and milestones can be in one of several states. This function updates such an entity to the previous logical state.

- Tasks: Can be either done or not, so this moves a completed task to an incomplete state.
- Stories: Stories live within a Workflow and every Workflow has a canonical sequence of states. This moves the given story to the previous one within the same Story Workflow.
- Epics: Epics live within workflows that are similar to but different from Story workflows. This moves the given epic to the previous one within the same Epic Workflow.
- Milestones: Milestones have a simpler to do/in-progress/done state. This moves the given workflow to the previous logical state.

NB: Iterations are not included in this list, because their "state" is based solely on start/end date.
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    ScEntity entity = env.resolveArgEntity(args, canonicalName);

    if (entity is ScStory) {
      final workflow = entity.data[ScString('workflow_id')] as ScWorkflow;
      final workflowStates = workflow.data[ScString('states')] as ScList;
      final currentWorkflowState =
          entity.data[ScString('workflow_state_id')] as ScWorkflowState;
      final ids = workflowStates.mapImmutable((e) => e.id);
      final idx = ids.indexOf(currentWorkflowState.id);
      if (idx == -1) {
        throw Exception("Workflow state not defined within workflow.");
      } else if (idx == 0) {
        // At beginning, warn and move on.
        env.err.writeln(
            ';; [WARN] Already at first workflow state for the workflow ${workflow.printToString(env)}');
        return entity;
      } else {
        final nextWorkflowState = workflowStates[idx - 1] as ScWorkflowState;
        final updatedEntity = waitOn(env.client.updateStory(
            env,
            entity.idString,
            {"workflow_state_id": int.tryParse(nextWorkflowState.idString)}));
        entity.data = updatedEntity.data;
        env.out.write(env.style(";; [INFO] Moved from ", styleInfo));
        env.out.write(currentWorkflowState.inlineSummary(env));
        env.out.write(env.style(' to ', styleInfo));
        env.out.writeln(nextWorkflowState.inlineSummary(env));
        return entity;
      }
    } else if (entity is ScEpic) {
      final epicWorkflow = env.resolveEpicWorkflow();
      final epicWorkflowStates =
          epicWorkflow.data[ScString('epic_states')] as ScList;
      final currentEpicWorkflowState =
          entity.data[ScString('epic_state_id')] as ScEpicWorkflowState;
      final ids = epicWorkflowStates.mapImmutable((e) => e.id);
      final idx = ids.indexOf(currentEpicWorkflowState.id);
      if (idx == -1) {
        throw Exception(
            "Epic workflow state not defined within the epic workflow.");
      } else if (idx == 0) {
        // At beginning, warn and move on.
        env.err.writeln(
            ';; [WARN] Already at first epic workflow state for the workflow ${epicWorkflow.printToString(env)}');
        return entity;
      } else {
        final nextEpicWorkflowState =
            epicWorkflowStates[idx - 1] as ScEpicWorkflowState;
        final updatedEntity = waitOn(env.client.updateEpic(env, entity.idString,
            {"epic_state_id": int.tryParse(nextEpicWorkflowState.idString)}));
        entity.data = updatedEntity.data;
        env.out.write(env.style(";; [INFO] Moved from ", styleInfo));
        env.out.write(currentEpicWorkflowState.inlineSummary(env));
        env.out.write(env.style(' to ', styleInfo));
        env.out.writeln(nextEpicWorkflowState.inlineSummary(env));
        return entity;
      }
    } else if (entity is ScMilestone) {
      final currentState = (entity.data[ScString('state')] as ScString).value;
      final idx = ScMilestone.states.indexOf(currentState);
      if (idx == -1) {
        throw BadArgumentsException(
            'The milestone is in an unsupported state: "$currentState"');
      } else if (idx == 0) {
        env.err.writeln(
            ';; [WARN] Milestone is already in the first, "to do" state.');
        return entity;
      } else {
        final nextState = ScMilestone.states[idx - 1];
        final updatedEntity = waitOn(env.client
            .updateMilestone(env, entity.idString, {'state': nextState}));
        env.out.write(env.style(';; [INFO] Moved from ', styleInfo));
        env.out.write(currentState);
        env.out.write(env.style(' to ', styleInfo));
        env.out.writeln(nextState);
        entity.data = updatedEntity.data;
        return entity;
      }
    } else if (entity is ScTask) {
      final isComplete = entity.data[ScString('complete')];
      if (isComplete == ScBoolean.veritas()) {
        final storyId = entity.data[ScString('story_id')] as ScNumber;
        final updateMap = {'complete': false};
        final updatedEntity = waitOn(env.client.updateTask(
            env, storyId.value.toString(), entity.idString, updateMap));
        entity.data = updatedEntity.data;
        return entity;
      } else {
        env.err.writeln(';; [WARN] Task is already in an incomplete state.');
        return entity;
      }
    } else {
      throw UnimplementedError();
    }
  }
}

class ScFnCreate extends ScBaseInvocable {
  static final ScFnCreate _instance = ScFnCreate._internal();
  ScFnCreate._internal();
  factory ScFnCreate() => _instance;

  @override
  String get canonicalName => 'new';

  @override
  Set<List<String>> get arities => {
        [],
        ["entity-map"]
      };

  @override
  String get help =>
      'Create the given entity in Shortcut, either interactively (no args) or with the given data map.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""This function takes into account both the current parent entity (if present) and defaults (if defined).""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      env.startInteractionCreateEntity(null);
      return ScNil();
    } else if (args.length == 1) {
      final maybeDataMap = args[0];
      ScEntity? entity;
      if (maybeDataMap is ScMap) {
        ScMap dataMap = maybeDataMap;
        final maybeType =
            dataMap[ScString('type')] ?? dataMap[ScDottedSymbol('type')];
        if (maybeType == null) {
          throw BadArgumentsException(
              'The map passed to `create` must have a a "type" field with one of "story", "epic", "iteration", or "milestone".');
        } else {
          String typeStr;
          if (maybeType is ScString) {
            typeStr = maybeType.value;
          } else if (maybeType is ScDottedSymbol) {
            typeStr = maybeType._name;
          } else {
            throw BadArgumentsException(
                'The map passed to `create` must have a a "type" field with one of "story", "epic", "iteration", or "milestone", but received ${maybeType.toString()}');
          }
          dataMap = dataMap.remove(ScString('type'));
          dataMap = dataMap.remove(ScDottedSymbol('type'));
          switch (typeStr) {
            case 'story':
              if (!dataMap.containsKey(ScString('epic_id'))) {
                if (env.parentEntity is ScEpic) {
                  final epic = env.parentEntity! as ScEpic;
                  dataMap[ScString('epic_id')] = epic.id;
                }
              }
              if (!dataMap.containsKey(ScString('iteration_id'))) {
                if (env.parentEntity is ScIteration) {
                  final iteration = env.parentEntity! as ScIteration;
                  dataMap[ScString('iteration_id')] = iteration.id;
                }
              }
              final defaultFn = ScFnDefault();
              if (!dataMap.containsKey(ScString('group_id'))) {
                if (env.parentEntity is ScTeam) {
                  final team = env.parentEntity!;
                  dataMap[ScString('group_id')] = team.id;
                } else {
                  final defaultTeam =
                      defaultFn.invoke(env, ScList([ScString('group_id')]));
                  if (defaultTeam is ScTeam) {
                    dataMap[ScString('group_id')] = defaultTeam.id;
                  }
                }
              }
              if (!dataMap.containsKey(ScString('workflow_state_id'))) {
                final defaultWorkflowState = defaultFn.invoke(
                    env, ScList([ScString('workflow_state_id')]));
                if (defaultWorkflowState is ScWorkflowState) {
                  dataMap[ScString('workflow_state_id')] =
                      defaultWorkflowState.id;
                } else {
                  throw BadArgumentsException(
                      "You must either specific a \"workflow_state_id\" entry in your create map, or set a default using `default` or `setup`.");
                }
              }

              entity = waitOn(env.client.createStory(env,
                  scExprToValue(dataMap, forJson: true, onlyEntityIds: true)));
              break;
            case 'epic':
              final defaultFn = ScFnDefault();
              if (!dataMap.containsKey(ScString('group_id'))) {
                if (env.parentEntity is ScTeam) {
                  final team = env.parentEntity!;
                  dataMap[ScString('group_id')] = team.id;
                } else {
                  final defaultTeam =
                      defaultFn.invoke(env, ScList([ScString('group_id')]));
                  if (defaultTeam is ScTeam) {
                    dataMap[ScString('group_id')] = defaultTeam.id;
                  }
                }
              }
              if (!dataMap.containsKey(ScString('milestone_id'))) {
                if (env.parentEntity is ScMilestone) {
                  final milestone = env.parentEntity!;
                  dataMap[ScString('milestone_id')] = milestone.id;
                }
              }

              entity = waitOn(env.client.createEpic(env,
                  scExprToValue(dataMap, forJson: true, onlyEntityIds: true)));
              break;
            case 'milestone':
              entity = waitOn(env.client.createMilestone(env,
                  scExprToValue(dataMap, forJson: true, onlyEntityIds: true)));
              break;
            case 'iteration':
              if (!dataMap.containsKey(ScString('group_ids'))) {
                if (env.parentEntity is ScTeam) {
                  final team = env.parentEntity!;
                  dataMap[ScString('group_ids')] = ScList([team]);
                }
              }
              entity = waitOn(env.client.createIteration(env,
                  scExprToValue(dataMap, forJson: true, onlyEntityIds: true)));
              break;
            case 'task':
              final rawStoryId = dataMap[ScString('story_id')] ??
                  dataMap[ScDottedSymbol('story_id')];
              if (rawStoryId == null) {
                throw BadArgumentsException(
                    "To create a task, your map must include a \"story_id\" entry.");
              } else {
                String storyPublicId;
                if (rawStoryId is ScString) {
                  storyPublicId = rawStoryId.value;
                } else if (rawStoryId is ScNumber) {
                  storyPublicId = rawStoryId.toString();
                } else {
                  throw BadArgumentsException(
                      "The \"story_id\" field must be a string or number, but received a ${rawStoryId.typeName()}");
                }
                dataMap = dataMap.remove(ScString('story_id'));
                dataMap = dataMap.remove(ScDottedSymbol('story_id'));
                entity = waitOn(env.client.createTask(
                    env,
                    storyPublicId,
                    scExprToValue(dataMap,
                        forJson: true, onlyEntityIds: true)));
              }
              break;
            case 'comment':
              final rawStoryId = dataMap[ScString('story_id')] ??
                  dataMap[ScDottedSymbol('story_id')];
              if (rawStoryId == null) {
                throw BadArgumentsException(
                    "To create a story comment, you must include a \"story_id\" entry.");
              } else {
                String storyPublicId;
                if (rawStoryId is ScString) {
                  storyPublicId = rawStoryId.value;
                } else if (rawStoryId is ScNumber) {
                  storyPublicId = rawStoryId.toString();
                } else {
                  throw BadArgumentsException(
                      'The "story_id" field must be a string or number, but received a ${rawStoryId.typeName()}');
                }
                dataMap = dataMap.remove(ScString('story_id'));
                dataMap = dataMap.remove(ScDottedSymbol('story_id'));
                entity = waitOn(env.client.createComment(
                    env,
                    storyPublicId,
                    scExprToValue(dataMap,
                        forJson: true, onlyEntityIds: true)));
              }
              break;
            case 'epic comment':
              final rawEpicId = dataMap[ScString('epic_id')] ??
                  dataMap[ScDottedSymbol('epic_id')];
              if (rawEpicId == null) {
                throw BadArgumentsException(
                    "To create an epic comment, you must include a \"epic_id\" entry.");
              } else {
                String epicPublicId;
                if (rawEpicId is ScString) {
                  epicPublicId = rawEpicId.value;
                } else if (rawEpicId is ScNumber) {
                  epicPublicId = rawEpicId.toString();
                } else {
                  throw BadArgumentsException(
                      'The "epic_id" field must be a string or number, but received a ${rawEpicId.typeName()}');
                }
                dataMap = dataMap.remove(ScString('epic_id'));
                dataMap = dataMap.remove(ScDottedSymbol('epic_id'));

                final rawCommentId = dataMap[ScString('comment_id')] ??
                    dataMap[ScString('epic_comment_id')] ??
                    dataMap[ScDottedSymbol('comment_id')] ??
                    dataMap[ScDottedSymbol('epic_comment_id')];
                if (rawCommentId == null) {
                  // Create Epic Comment
                  entity = waitOn(env.client.createEpicComment(
                      env,
                      epicPublicId,
                      scExprToValue(dataMap,
                          forJson: true, onlyEntityIds: true)));
                } else {
                  // Create Epic Comment Comment
                  String commentPublicId;
                  if (rawCommentId is ScString) {
                    commentPublicId = rawCommentId.value;
                  } else if (rawCommentId is ScNumber) {
                    commentPublicId = rawCommentId.toString();
                  } else {
                    throw BadArgumentsException(
                        'The "comment_id" or "epic_comment_id" field must be a string or number, but received a ${rawCommentId.typeName()}');
                  }
                  dataMap = dataMap.remove(ScString('comment_id'));
                  dataMap = dataMap.remove(ScDottedSymbol('comment_id'));
                  dataMap = dataMap.remove(ScString('epic_comment_id'));
                  dataMap = dataMap.remove(ScDottedSymbol('epic_comment_id'));
                  entity = waitOn(env.client.createEpicCommentComment(
                      env,
                      epicPublicId,
                      commentPublicId,
                      scExprToValue(dataMap,
                          forJson: true, onlyEntityIds: true)));
                }
              }
              break;
            default:
              throw UnimplementedError();
          }
        }
      }
      return entity ?? ScNil();
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 0 or 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnCreateStory extends ScBaseInvocable {
  static final ScFnCreateStory _instance = ScFnCreateStory._internal();
  ScFnCreateStory._internal();
  factory ScFnCreateStory() => _instance;

  @override
  String get canonicalName => 'new-story';

  @override
  Set<List<String>> get arities => {
        [],
        ["story-map"]
      };

  @override
  String get help => "Create a Shortcut story given a data map.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      final tempFile = newTempFile();
      final fields = ScStory.fieldsForCreate.toList();
      fields.sort();
      final formatted = fields.join(', ');
      tempFile.writeAsStringSync(';; Fields: $formatted\n{.name "STORY_NAME"}');
      execOpenInEditor(env, existingFile: tempFile);
      env.out.writeln(env.style(
          "\n;; [HELP] Once you've saved the file in your editor, run the following to create your Story:\n\n    load *1 | $canonicalName\n",
          styleInfo));
      return ScFile(tempFile);
    } else if (args.length == 1) {
      final rawDataMap = args[0];
      ScMap dataMap = ScMap({});

      // NB: Support quick story creation, just name (title)
      if (rawDataMap is ScString) {
        dataMap[ScString('name')] = rawDataMap;
      } else if (rawDataMap is ScMap) {
        dataMap = rawDataMap;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects its argument to be a map, but received ${dataMap.typeName()}");
      }

      dataMap[ScString('type')] = ScString('story');
      final createFn = ScFnCreate(); // handles defaults, parentage
      return createFn.invoke(env, ScList([dataMap]));
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument: a data map.");
    }
  }
}

class ScFnCreateComment extends ScBaseInvocable {
  static final ScFnCreateComment _instance = ScFnCreateComment._internal();
  ScFnCreateComment._internal();
  factory ScFnCreateComment() => _instance;

  @override
  String get canonicalName => 'new-comment';

  @override
  Set<List<String>> get arities => {
        [],
        ["comment-map-or-string"],
        ["story-or-epic-or-comment", "comment-map-or-string"],
        ["epic" "comment" "comment-map-or-string"]
      };

  @override
  String get help =>
      'Create a comment for the given story or epic (or parent, if within a story, comment, epic, or epic comment).';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      if (env.parentEntity != null) {
        final pe = env.parentEntity!;
        if (pe is ScStory) {
          final tempFile = newTempFile();
          final fields = ScComment.fieldsForCreate.toList();
          fields.sort();
          final formatted = fields.join(', ');
          tempFile.writeAsStringSync(
              ';; Fields: $formatted\n{.text "COMMENT_TEXT"}');
          execOpenInEditor(env, existingFile: tempFile);
          env.out.writeln(env.style(
              "\n;; [HELP] Once you've saved the file in your editor, run the following to create your Story:\n\n    load *1 | $canonicalName ${pe.idString} _\n",
              styleInfo));
          return ScFile(tempFile);
        } else if (pe is ScComment) {
          final tempFile = newTempFile();
          final fields = ScComment.fieldsForCreate.toList();
          fields.sort();
          final formatted = fields.join(', ');
          tempFile.writeAsStringSync(
              ';; Fields: $formatted\n{.text "COMMENT_TEXT"\n .parent_id ${pe.idString}}');
          execOpenInEditor(env, existingFile: tempFile);
          env.out.writeln(env.style(
              "\n;; [HELP] Once you've saved the file in your editor, run the following to create your Story:\n\n    load *1 | $canonicalName ${pe.storyId.value} _\n",
              styleInfo));
          return ScFile(tempFile);
        } else if (pe is ScEpic) {
          final tempFile = newTempFile();
          final fields = ScEpicComment.fieldsForCreate.toList();
          fields.sort();
          final formatted = fields.join(', ');
          tempFile.writeAsStringSync(
              ';; Fields: $formatted\n{.text "COMMENT_TEXT"}');
          execOpenInEditor(env, existingFile: tempFile);
          env.out.writeln(env.style(
              "\n;; [HELP] Once you've saved the file in your editor, run the following to create your Story:\n\n    load *1 | $canonicalName ${pe.idString} _\n",
              styleInfo));
          return ScFile(tempFile);
        } else if (pe is ScEpicComment) {
          final epicId = pe.epicId;
          final tempFile = newTempFile();
          final fields = ScEpicComment.fieldsForCreate.toList();
          fields.sort();
          final formatted = fields.join(', ');
          tempFile.writeAsStringSync(
              ';; Fields: $formatted\n{.text "COMMENT_TEXT"}');
          execOpenInEditor(env, existingFile: tempFile);
          env.out.writeln(env.style(
              "\n;; [HELP] Once you've saved the file in your editor, run the following to create your Story:\n\n    load *1 | $canonicalName ${epicId.value} ${pe.idString} _\n",
              styleInfo));
          return ScFile(tempFile);
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function expects you to be within a parent story, story comment, epic, or epic comment if no arguments are supplied, but the parent entity is a ${pe.typeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects you to be within a parent story, story comment, epic, or epic comment if no arguments are supplied, but no parent entity found.");
      }
    } else if (args.length == 1) {
      if (env.parentEntity != null) {
        final rawDataMap = args[0];
        ScMap dataMap = ScMap({});
        if (rawDataMap is ScMap) {
          dataMap = rawDataMap;
        } else if (rawDataMap is ScString) {
          dataMap[ScString('text')] = rawDataMap;
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function taking 1 argument expects a map, but received a ${dataMap.typeName()}");
        }

        final pe = env.parentEntity!;
        if (pe is ScStory) {
          dataMap[ScString('type')] = ScString('comment');
          dataMap[ScString('story_id')] = pe.id;
          final createFn = ScFnCreate();
          return createFn.invoke(env, ScList([dataMap]));
        } else if (pe is ScComment) {
          dataMap[ScString('type')] = ScString('comment');
          dataMap[ScString('story_id')] = pe.storyId;
          dataMap[ScString('parent_id')] = pe.id;
          final createFn = ScFnCreate();
          return createFn.invoke(env, ScList([dataMap]));
        } else if (pe is ScEpic) {
          dataMap[ScString('type')] = ScString('epic comment');
          dataMap[ScString('epic_id')] = pe.id;
          final createFn = ScFnCreate();
          return createFn.invoke(env, ScList([dataMap]));
        } else if (pe is ScEpicComment) {
          dataMap[ScString('type')] = ScString('epic comment');
          dataMap[ScString('epic_id')] = pe.epicId;
          dataMap[ScString('epic_comment_id')] = pe.id;
          final createFn = ScFnCreate();
          return createFn.invoke(env, ScList([dataMap]));
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function can leverage a parent entity that is a story, comment, epic, or epic comment, but it does not support a parent entity of type ${pe.typeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects you to be within a parent story or epic if only 1 argument is supplied, but parent entity is null.");
      }
    } else if (args.length == 2) {
      // All but Epic Comment Comment
      ScString? storyId;
      ScString? epicId;
      final entityId = args[0];
      if (entityId is ScStory) {
        storyId = ScString(entityId.idString);
      } else if (entityId is ScEpic) {
        epicId = ScString(entityId.idString);
      } else if (entityId is ScString) {
        final entity = waitOn(fetchId(env, entityId.value));
        if (entity is ScStory) {
          storyId = ScString(entity.idString);
        } else if (entity is ScEpic) {
          epicId = ScString(entity.idString);
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function expects a story or epic (or and ID for one) as its first argument, but received an ${entity.typeName()}");
        }
      } else if (entityId is ScNumber) {
        final entity = waitOn(fetchId(env, entityId.toString()));
        if (entity is ScStory) {
          storyId = ScString(entity.idString);
        } else if (entity is ScEpic) {
          epicId = ScString(entity.idString);
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function expects a story or epic (or and ID for one) as its first argument, but received an ${entity.typeName()}");
        }
      }
      final rawDataMap = args[1];
      ScMap dataMap = ScMap({});

      // NB: Support quick comment creation, just text
      if (rawDataMap is ScString) {
        dataMap[ScString('text')] = rawDataMap;
      } else if (rawDataMap is ScMap) {
        dataMap = rawDataMap;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects its second argument to be a map, but received a ${dataMap.typeName()}");
      }

      if (storyId != null) {
        dataMap[ScString('type')] = ScString('comment');
        dataMap[ScString('story_id')] = storyId;
        final createFn = ScFnCreate(); // handles defaults, parentage
        return createFn.invoke(env, ScList([dataMap]));
      } else if (epicId != null) {
        dataMap[ScString('type')] = ScString('epic comment');
        dataMap[ScString('epic_id')] = epicId;
        final createFn = ScFnCreate(); // handles defaults, parentage
        return createFn.invoke(env, ScList([dataMap]));
      } else {
        throw BadArgumentsException(
            "Only stories and epics can have comments, but `create-comment` received an ID that couldn't be resolved to either.");
      }
    } else if (args.length == 3) {
      // Epic Comment Comment
      final rawEpicId = args[0];
      ScString? epicId;
      if (rawEpicId is ScEpic) {
        epicId = ScString(rawEpicId.idString);
      } else if (rawEpicId is ScString) {
        epicId = rawEpicId;
      } else if (rawEpicId is ScNumber) {
        epicId = ScString(rawEpicId.toString());
      }

      if (epicId == null) {
        throw BadArgumentsException(
            "The `$canonicalName` function with three arguments expects its first argument to be an epic or its ID, but received a ${rawEpicId.typeName()}");
      } else {
        final rawEpicCommentId = args[1];
        ScString? epicCommentId;
        if (rawEpicCommentId is ScEpicComment) {
          epicCommentId = ScString(rawEpicCommentId.idString);
        } else if (rawEpicCommentId is ScString) {
          epicCommentId = rawEpicCommentId;
        } else if (rawEpicCommentId is ScNumber) {
          epicCommentId = ScString(rawEpicCommentId.toString());
        }

        if (epicCommentId == null) {
          throw BadArgumentsException(
              "The `$canonicalName` function with three arguments expects its second argument to be an epic comment or its ID, but received a ${rawEpicCommentId.typeName()}");
        } else {
          final rawDataMap = args[2];
          ScMap dataMap = ScMap({});

          // NB: Support quick comment creation, just text
          if (rawDataMap is ScString) {
            dataMap[ScString('text')] = rawDataMap;
          } else if (rawDataMap is ScMap) {
            dataMap = rawDataMap;
          } else {
            throw BadArgumentsException(
                "The `$canonicalName` function with three arguments expects its third argument to be a map, but received a ${rawDataMap.typeName()}");
          }

          dataMap[ScString('type')] = ScString('epic comment');
          dataMap[ScString('epic_id')] = epicId;
          dataMap[ScString('epic_comment_id')] = epicCommentId;
          final createFn = ScFnCreate(); // handles defaults, parentage
          return createFn.invoke(env, ScList([dataMap]));
        }
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 2 or 3 arguments, but received ${args.length} arguments.");
    }
  }
}

class ScFnCreateEpic extends ScBaseInvocable {
  static final ScFnCreateEpic _instance = ScFnCreateEpic._internal();
  ScFnCreateEpic._internal();
  factory ScFnCreateEpic() => _instance;

  @override
  String get canonicalName => 'new-epic';

  @override
  Set<List<String>> get arities => {
        [],
        ["epic-map"]
      };

  @override
  String get help => "Create a Shortcut epic given a data map.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      final tempFile = newTempFile();
      final fields = ScEpic.fieldsForCreate.toList();
      fields.sort();
      final formatted = fields.join(', ');
      tempFile.writeAsStringSync(';; Fields: $formatted\n{.name "EPIC_NAME"}');
      execOpenInEditor(env, existingFile: tempFile);
      env.out.writeln(env.style(
          "\n;; [HELP] Once you've saved the file in your editor, run the following to create your Epic:\n\n    load *1 | $canonicalName\n",
          styleInfo));
      return ScFile(tempFile);
    } else if (args.length == 1) {
      final rawDataMap = args[0];
      ScMap dataMap = ScMap({});
      if (rawDataMap is ScMap) {
        dataMap = rawDataMap;
      } else if (rawDataMap is ScString) {
        dataMap[ScString('name')] = rawDataMap;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects its argument to be a map, but received ${dataMap.typeName()}");
      }
      final createFn = ScFnCreate();
      dataMap[ScString('type')] = ScString('epic');
      return createFn.invoke(env, ScList([dataMap]));
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 0 or 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnCreateLabel extends ScBaseInvocable {
  static final ScFnCreateLabel _instance = ScFnCreateLabel._internal();
  ScFnCreateLabel._internal();
  factory ScFnCreateLabel() => _instance;

  @override
  String get canonicalName => 'new-label';

  @override
  Set<List<String>> get arities => {
        [],
        ["label-map"],
      };

  @override
  String get help => "Create a Shortcut label given a data map.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      final tempFile = newTempFile();
      final fields = ScLabel.fieldsForCreate.toList();
      fields.sort();
      final formatted = fields.join(', ');
      tempFile.writeAsStringSync(';; Fields: $formatted\n{.name "LABEL_NAME"}');
      execOpenInEditor(env, existingFile: tempFile);
      env.out.writeln(env.style(
          "\n;; [HELP] Once you've saved the file in your editor, run the following to create your Story:\n\n    load *1 | $canonicalName\n",
          styleInfo));
      return ScFile(tempFile);
    } else if (args.length == 1) {
      final rawDataMap = args[0];
      ScMap dataMap = ScMap({});
      if (rawDataMap is ScString) {
        dataMap[ScString('name')] = rawDataMap;
      } else if (rawDataMap is ScMap) {
        dataMap = rawDataMap;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects a string or map argument, but received a ${rawDataMap.typeName()}");
      }
      return waitOn(env.client.createLabel(
          env, scExprToValue(dataMap, forJson: true, onlyEntityIds: true)));
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnCreateMilestone extends ScBaseInvocable {
  static final ScFnCreateMilestone _instance = ScFnCreateMilestone._internal();
  ScFnCreateMilestone._internal();
  factory ScFnCreateMilestone() => _instance;

  @override
  String get canonicalName => 'new-milestone';

  @override
  Set<List<String>> get arities => {
        ["milestone-map"]
      };

  @override
  String get help => "Create a Shortcut milestone given a data map.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      final tempFile = newTempFile();
      final fields = ScMilestone.fieldsForCreate.toList();
      fields.sort();
      final formatted = fields.join(', ');
      tempFile
          .writeAsStringSync(';; Fields: $formatted\n{.name "MILESTONE_NAME"}');
      execOpenInEditor(env, existingFile: tempFile);
      env.out.writeln(env.style(
          "\n;; [HELP] Once you've saved the file in your editor, run the following to create your Milestone:\n\n    load *1 | $canonicalName\n",
          styleInfo));
      return ScFile(tempFile);
    } else if (args.length == 1) {
      final rawDataMap = args[0];
      ScMap dataMap = ScMap({});
      if (rawDataMap is ScMap) {
        dataMap = rawDataMap;
      } else if (rawDataMap is ScString) {
        dataMap[ScString('name')] = rawDataMap;
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects its argument to be a map, but received ${dataMap.typeName()}");
      }
      final createFn = ScFnCreate();
      dataMap[ScString('type')] = ScString('milestone');
      return createFn.invoke(env, ScList([dataMap]));
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 0 or 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnCreateIteration extends ScBaseInvocable {
  static final ScFnCreateIteration _instance = ScFnCreateIteration._internal();
  ScFnCreateIteration._internal();
  factory ScFnCreateIteration() => _instance;

  @override
  String get canonicalName => 'new-iteration';

  @override
  Set<List<String>> get arities => {
        ["iteration-map"]
      };

  @override
  String get help => "Create a Shortcut iteration given a data map.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      final tempFile = newTempFile();
      final fields = ScIteration.fieldsForCreate.toList();
      fields.sort();
      final formatted = fields.join(', ');
      tempFile.writeAsStringSync(
          ';; Fields: $formatted\n{.name "ITERATION_NAME"\n .start_date ""\n .end_date ""}');
      execOpenInEditor(env, existingFile: tempFile);
      env.out.writeln(env.style(
          "\n;; [HELP] Once you've saved the file in your editor, run the following to create your Story:\n\n    load *1 | $canonicalName\n",
          styleInfo));
      return ScFile(tempFile);
    } else if (args.length == 1) {
      final dataMap = args[0];
      if (dataMap is ScMap) {
        final createFn = ScFnCreate();
        dataMap[ScString('type')] = ScString('iteration');
        return createFn.invoke(env, ScList([dataMap]));
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects its argument to be a map, but received ${dataMap.typeName()}");
      }
    } else {
      // TODO This should open editor with default iteration map
      throw UnimplementedError();
    }
  }
}

class ScFnCreateTask extends ScBaseInvocable {
  static final ScFnCreateTask _instance = ScFnCreateTask._internal();
  ScFnCreateTask._internal();
  factory ScFnCreateTask() => _instance;

  @override
  String get canonicalName => 'new-task';

  @override
  Set<List<String>> get arities => {
        ["task-map"],
        ["story", "task-map"]
      };

  @override
  String get help => "Create a Shortcut task given a story ID and data map.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isNotEmpty) {
      ScEntity story = env.resolveArgEntity(args, canonicalName,
          forceParent: (args[0] is ScMap || args[0] is ScString));
      if (args.length == 1) {
        final dataMap = args[0];
        final createFn = ScFnCreate();
        if (dataMap is ScString) {
          final createMap = ScMap({
            ScString('type'): ScString('task'),
            ScString('story_id'): story.id,
            ScString('description'): dataMap
          });
          return createFn.invoke(env, ScList([createMap]));
        } else if (dataMap is ScMap) {
          dataMap[ScString('type')] = ScString('task');
          dataMap[ScString('story_id')] = story.id;
          return createFn.invoke(env, ScList([dataMap]));
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function expects its second argument to be a map, but received ${dataMap.typeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects either an entity and a create map, or just a create map and a parent entity that is a story.");
      }
    } else {
      // TODO This should open up user's editor with default task map.
      throw UnimplementedError();
    }
  }
}

class ScFnMe extends ScBaseInvocable {
  static final ScFnMe _instance = ScFnMe._internal();
  ScFnMe._internal();
  factory ScFnMe() => _instance;

  @override
  String get canonicalName => 'me';

  static ScMember? me;

  @override
  Set<List<String>> get arities => {[]};

  @override
  String get help => 'Fetch the current member based on the API token.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    me ??= waitOn(env.client.getCurrentMember(env));
    return me!;
  }
}

class ScFnMember extends ScBaseInvocable {
  static final ScFnMember _instance = ScFnMember._internal();
  ScFnMember._internal();
  factory ScFnMember() => _instance;

  @override
  String get canonicalName => 'member';

  @override
  Set<List<String>> get arities => {
        ["member-id"]
      };

  @override
  String get help => 'Fetch the member with the given ID.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final memberId = args[0];
      if (memberId is ScString) {
        return waitOn(env.client.getMember(env, memberId.value));
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's argument must be a string, but received a ${memberId.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument, but received ${args.length}.");
    }
  }
}

class ScFnMembers extends ScBaseInvocable {
  static final ScFnMembers _instance = ScFnMembers._internal();
  ScFnMembers._internal();
  factory ScFnMembers() => _instance;

  @override
  String get canonicalName => 'members';

  @override
  Set<List<String>> get arities => {
        [],
        ["team"]
      };

  @override
  String get help => "Returns _all_ members in this workspace.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""If parent entity is a team, this returns only members of the team (equivalent of `ls`).""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length > 1) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 0 or 1 argument, but received ${args.length} arguments.");
    }

    ScTeam? team;
    if (args.isEmpty) {
      if (env.parentEntity is ScTeam) {
        team = env.parentEntity! as ScTeam;
      }
    } else if (args.length == 1) {
      final rawTeam = args[0];
      if (rawTeam is ScTeam) {
        team = rawTeam;
      } else if (rawTeam is ScString) {
        team = ScTeam(rawTeam);
        waitOn(team.fetch(env));
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects its first argument to be a team or its ID, but received a ${rawTeam.typeName()}");
      }
    }
    if (team != null) {
      ScExpr? memberIds = team.data[ScString('member_ids')];
      if (memberIds == null) {
        waitOn(team.fetch(env));
      }
      memberIds = team.data[ScString('member_ids')];
      if (memberIds is ScList) {
        return memberIds;
      } else {
        env.err.writeln(
            ";; [WARNING] Team didn't have expected \"member_ids\" entry, even after fetching.");
        return ScNil();
      }
    } else {
      return waitOn(env.client.getMembers(env));
    }
  }
}

class ScFnWorkflow extends ScBaseInvocable {
  static final ScFnWorkflow _instance = ScFnWorkflow._internal();
  ScFnWorkflow._internal();
  factory ScFnWorkflow() => _instance;

  @override
  String get canonicalName => 'workflow';

  @override
  Set<List<String>> get arities => {
        ["workflow-id"]
      };

  @override
  String get help => "Returns the Shortcut workflow with this ID.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""A workflow defines an ordered sequence of unstarted, in progress, and done states that a story can be in.

A workspace can have multiple workflows defined, but a given story falls only within one workflow.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final workflowId = args[0];
      if (workflowId is ScString) {
        return waitOn(env.client.getWorkflow(env, workflowId.value));
      } else if (workflowId is ScNumber) {
        return waitOn(env.client.getWorkflow(env, workflowId.toString()));
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's first argument must be the workflow's ID, but received a ${workflowId.typeName()}.");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument: the workflow ID.");
    }
  }
}

class ScFnWorkflows extends ScBaseInvocable {
  static final ScFnWorkflows _instance = ScFnWorkflows._internal();
  ScFnWorkflows._internal();
  factory ScFnWorkflows() => _instance;

  @override
  String get canonicalName => 'workflows';

  @override
  Set<List<String>> get arities => {[]};

  @override
  String get help => "Returns all story workflows in this workspace.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""A workflow state must be assigned a story when created, so you can use this function to find all workflows and then pick a workflow state from within one of them.

You can interactively set a default workflow by running the `setup` function.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isNotEmpty) {
      throw BadArgumentsException(
          "The `$canonicalName` function takes no arguments.");
    } else {
      return waitOn(env.client.getWorkflows(env));
    }
  }
}

class ScFnEpicWorkflow extends ScBaseInvocable {
  static final ScFnEpicWorkflow _instance = ScFnEpicWorkflow._internal();
  ScFnEpicWorkflow._internal();
  factory ScFnEpicWorkflow() => _instance;

  @override
  String get canonicalName => 'epic-workflow';

  @override
  Set<List<String>> get arities => {[]};

  @override
  String get help =>
      "Returns the Shortcut epic workflow for the current workspace.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""A Shortcut workspace only has one epic workflow. That workflow has states that can be adjusted.

This function fetches the epic workflow defined for the workspace, along with its states.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return waitOn(env.client.getEpicWorkflow(env));
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function doesn't accept any arguments, but received ${args.length}");
    }
  }
}

class ScFnTeam extends ScBaseInvocable {
  static final ScFnTeam _instance = ScFnTeam._internal();
  ScFnTeam._internal();
  factory ScFnTeam() => _instance;

  @override
  String get canonicalName => 'team';

  @override
  Set<List<String>> get arities => {
        ["team-id"]
      };

  @override
  String get help => "Returns the Shortcut team with this ID.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      // TODO Implement interactive team creation with this arity
      throw UnimplementedError();
    } else if (args.length == 1) {
      final teamId = args[0];
      if (teamId is ScString) {
        return waitOn(env.client.getTeam(env, teamId.value));
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's first argument must be a string of the team's ID, but received a ${teamId.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnTeams extends ScBaseInvocable {
  static final ScFnTeams _instance = ScFnTeams._internal();
  ScFnTeams._internal();
  factory ScFnTeams() => _instance;

  @override
  String get canonicalName => 'teams';

  @override
  Set<List<String>> get arities => {
        [],
        ["entity"]
      };

  @override
  String get help => "Returns teams in this workspace.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      if (env.parentEntity != null) {
        final pe = env.parentEntity;
        if (pe is ScMember) {
          return teamsOfMember(env, pe);
        } else {
          return waitOn(env.client.getTeams(env));
        }
      } else {
        return waitOn(env.client.getTeams(env));
      }
    } else if (args.length == 1) {
      final member = env.resolveArgEntity(args, canonicalName);
      if (member is ScMember) {
        return teamsOfMember(env, member);
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects either 0 arguments or 1 member argument, but received a ${member.typeName()}");
      }
    } else {
      return waitOn(env.client.getTeams(env));
    }
  }
}

class ScFnStory extends ScBaseInvocable {
  static final ScFnStory _instance = ScFnStory._internal();
  ScFnStory._internal();
  factory ScFnStory() => _instance;

  @override
  String get canonicalName => 'story';

  @override
  Set<List<String>> get arities => {
        [],
        ["story-id"]
      };

  @override
  String get help => 'Fetch a story given its identifier.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      env.startInteractionCreateEntity(ScString('story'));
      return ScNil();
    } else {
      var storyId = args[0];
      if (storyId is ScNumber) {
        storyId = ScString(storyId.toString());
      }
      final story = ScStory(storyId as ScString);
      return waitOn(story.fetch(env));
    }
  }
}

class ScFnTask extends ScBaseInvocable {
  static final ScFnTask _instance = ScFnTask._internal();
  ScFnTask._internal();
  factory ScFnTask() => _instance;

  @override
  String get canonicalName => 'task';

  @override
  Set<List<String>> get arities => {
        [],
        ["task-id"],
        ["story", "task-id"]
      };

  @override
  String get help => 'Fetch a task given its identifier.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      env.startInteractionCreateEntity(ScString('task'));
      return ScNil();
    } else if (args.length == 1) {
      if (env.parentEntity is ScStory) {
        final ScStory story = env.parentEntity! as ScStory;
        var taskId = args[0];
        if (taskId is ScNumber) {
          taskId = ScString(taskId.value.toString());
        } else if (taskId is! ScString) {
          throw BadArgumentsException(
              "The `$canonicalName` function expects a task ID that is a number or string, but received a ${taskId.typeName()}");
        }
        // TODO Clean up places like this ^ and this v that can now be simplified by ScExpr id type.
        final task = ScTask(ScString(story.idString), taskId as ScString);
        return waitOn(task.fetch(env));
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects two arguments, or just a task ID and your parent entity to be a story. Instead, it received one argument and the parent is _not_ a story.");
      }
    } else if (args.length == 2) {
      var storyId = args[0];
      var taskId = args[1];
      if (storyId is ScNumber) {
        storyId = ScString(storyId.toString());
      } else if (storyId is ScStory) {
        storyId = storyId.id;
      } else if (storyId is! ScString) {
        throw BadArgumentsException(
            "The story ID must be a number, a string, or the story itself, but received a ${storyId.typeName()}");
      }
      if (taskId is ScNumber) {
        taskId = ScString(taskId.toString());
      } else if (taskId is! ScString) {
        throw BadArgumentsException(
            "The task ID must be a a number or string, but received a ${storyId.typeName()}");
      }
      final task = ScTask(storyId as ScString, taskId as ScString);
      return waitOn(task.fetch(env));
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function does not support ${args.length} arguments.");
    }
  }
}

class ScFnComment extends ScBaseInvocable {
  static final ScFnComment _instance = ScFnComment._internal();
  ScFnComment._internal();
  factory ScFnComment() => _instance;

  @override
  String get canonicalName => 'comment';

  @override
  Set<List<String>> get arities => {
        ["comment-id"],
        ["story", "comment-id"]
      };

  @override
  String get help => 'Fetch a comment given its identifier.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      // TODO Implement interactive comment creation with this arity
      throw UnimplementedError();
    } else if (args.length == 1) {
      if (env.parentEntity is ScStory) {
        final ScStory story = env.parentEntity! as ScStory;
        var commentId = args[0];
        if (commentId is ScNumber) {
          commentId = ScString(commentId.value.toString());
        } else if (commentId is! ScString) {
          throw BadArgumentsException(
              "The `$canonicalName` function expects a comment ID that is a number or string, but received a ${commentId.typeName()}");
        }
        final comment =
            ScComment(ScString(story.idString), commentId as ScString);
        return waitOn(comment.fetch(env));
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects two arguments, or just a comment ID and your parent entity to be a story. Instead, it received one argument and the parent is _not_ a story.");
      }
    } else if (args.length == 2) {
      var storyId = args[0];
      var commentId = args[1];
      if (storyId is ScNumber) {
        storyId = ScString(storyId.toString());
      } else if (storyId is ScStory) {
        storyId = storyId.id;
      } else if (storyId is! ScString) {
        throw BadArgumentsException(
            "The story ID must be a number, a string, or the story itself, but received a ${storyId.typeName()}");
      }
      if (commentId is ScNumber) {
        commentId = ScString(commentId.toString());
      } else if (commentId is! ScString) {
        throw BadArgumentsException(
            "The comment ID must be a a number or string, but received a ${storyId.typeName()}");
      }
      final comment = ScComment(storyId as ScString, commentId as ScString);
      return waitOn(comment.fetch(env));
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function does not support ${args.length} arguments.");
    }
  }
}

class ScFnEpic extends ScBaseInvocable {
  static final ScFnEpic _instance = ScFnEpic._internal();
  ScFnEpic._internal();
  factory ScFnEpic() => _instance;

  @override
  String get canonicalName => 'epic';

  @override
  Set<List<String>> get arities => {
        [],
        ["epic-id"]
      };

  @override
  String get help => 'Fetch an epic given its identifier.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      env.startInteractionCreateEntity(ScString('epic'));
      return ScNil();
    } else {
      var epicId = args[0];
      if (epicId is ScNumber) {
        epicId = ScString(epicId.toString());
      }
      final epic = ScEpic(epicId as ScString);
      return waitOn(epic.fetch(env));
    }
  }
}

class ScFnEpicComment extends ScBaseInvocable {
  static final ScFnEpicComment _instance = ScFnEpicComment._internal();
  ScFnEpicComment._internal();
  factory ScFnEpicComment() => _instance;

  @override
  String get canonicalName => 'epic-comment';

  @override
  Set<List<String>> get arities => {
        ["epic-comment-id"],
        ["epic", "epic-comment-id"]
      };

  @override
  String get help => 'Fetch an epic comment given its identifier.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      // TODO Implement interactive epic comment creation with this arity
      throw UnimplementedError();
    } else if (args.length == 1) {
      if (env.parentEntity is ScEpic) {
        final ScEpic epic = env.parentEntity! as ScEpic;
        var commentId = args[0];
        if (commentId is ScNumber) {
          commentId = ScString(commentId.value.toString());
        } else if (commentId is! ScString) {
          throw BadArgumentsException(
              "The `$canonicalName` function expects a comment ID that is a number or string, but received a ${commentId.typeName()}");
        }
        final epicComment =
            ScEpicComment(ScString(epic.idString), commentId as ScString);
        return waitOn(epicComment.fetch(env));
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects two arguments, or just a comment ID and your parent entity to be a epic. Instead, it received one argument and the parent is _not_ a epic.");
      }
    } else if (args.length == 2) {
      var epicId = args[0];
      var epicCommentId = args[1];
      if (epicId is ScNumber) {
        epicId = ScString(epicId.toString());
      } else if (epicId is ScEpic) {
        epicId = epicId.id;
      } else if (epicId is! ScString) {
        throw BadArgumentsException(
            "The epic ID must be a number, a string, or the epic itself, but received a ${epicId.typeName()}");
      }
      if (epicCommentId is ScNumber) {
        epicCommentId = ScString(epicCommentId.toString());
      } else if (epicCommentId is! ScString) {
        throw BadArgumentsException(
            "The comment ID must be a a number or string, but received a ${epicId.typeName()}");
      }
      final epicComment =
          ScEpicComment(epicId as ScString, epicCommentId as ScString);
      return waitOn(epicComment.fetch(env));
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function does not support ${args.length} arguments.");
    }
  }
}

class ScFnStories extends ScBaseInvocable {
  static final ScFnStories _instance = ScFnStories._internal();
  ScFnStories._internal();
  factory ScFnStories() => _instance;

  @override
  String get canonicalName => 'stories';

  @override
  Set<List<String>> get arities => {
        [],
        ["entity"]
      };

  @override
  String get help =>
      'Fetch epics, either all or based on the current parent entity.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""If no arguments are provided, this function checks the current parent entity:

- If an epic, returns stories within the epic.
- If a milestone, returns stories within epics attached to that milestone.
- If an iteration, returns only stories that are part of the iteration.
- If a team, returns only stories assigned to that team.
- If a member, returns only stories owned by that member.
- Else: returns stories owned by `me` that are either unstarted or in progress.

If an argument is provided, it must be an epic, iteration, team, member, or milestone.

Use the `find-stories` function to use more fine-grained criteria for retrieving stories.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty && env.parentEntity == null) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects a parent entity, or 1 argument that is an epic, iteration, team, member, or milestone.");
    } else {
      ScEntity entity = env.resolveArgEntity(args, canonicalName);
      if (entity is ScEpic) {
        return waitOn(env.client.getStoriesInEpic(env, entity.idString));
      } else if (entity is ScIteration) {
        return waitOn(env.client.getStoriesInIteration(env, entity.idString));
      } else if (entity is ScTeam) {
        return waitOn(env.client.getStoriesInTeam(env, entity.idString));
      } else if (entity is ScMilestone) {
        final epics = epicsInMilestone(env, entity);
        final stories = ScList([]);
        for (final epic in epics.innerList) {
          final e = epic as ScEpic;
          final ss = waitOn(env.client.getStoriesInEpic(env, e.idString));
          stories.innerList.addAll(ss.innerList);
        }
        return stories;
      } else if (entity is ScMember) {
        final findStoriesFn = ScFnFindStories();
        final ScMap findMap = ScMap({
          ScString("owner_id"): entity,
        });
        return findStoriesFn.invoke(env, ScList([findMap]));
      } else {
        // TODO Parent that is ScLabel
        throw BadArgumentsException(
            "The `$canonicalName` function expects an epic, iteration, team, or milestone argument, but received a ${entity.typeName()}");
      }
    }
  }
}

class ScFnEpics extends ScBaseInvocable {
  static final ScFnEpics _instance = ScFnEpics._internal();
  ScFnEpics._internal();
  factory ScFnEpics() => _instance;

  @override
  String get canonicalName => 'epics';

  @override
  Set<List<String>> get arities => {
        [],
        ["entity"]
      };

  @override
  String get help =>
      'Fetch epics, either all or based on the current parent entity.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""If no arguments are provided, this function checks the current parent entity:

- If a milestone, returns only epics attached to that milestone.
- If an iteration, returns only epics for stories that are part of the iteration.
- Else: returns _all_ epics in the current workspace.

Warning: That last eventuality can be an expensive call.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty && env.parentEntity == null) {
      env.err.writeln(env.style('[WARN] Fetching all epics...', styleWarn));
      return waitOn(env.client.getEpics(env));
    } else {
      ScEntity entity = env.resolveArgEntity(args, canonicalName);
      if (entity is ScMilestone) {
        return epicsInMilestone(env, entity);
      } else if (entity is ScIteration) {
        return epicsInIteration(env, entity);
      } else if (entity is ScTeam) {
        return epicsInTeam(env, entity);
      } else if (entity is ScMember) {
        return epicsForStoriesOwnedByMember(env, entity);
      } else {
        // TODO Parent that is ScLabel
        return waitOn(env.client.getEpics(env));
      }
    }
  }
}

class ScFnMilestone extends ScBaseInvocable {
  static final ScFnMilestone _instance = ScFnMilestone._internal();
  ScFnMilestone._internal();
  factory ScFnMilestone() => _instance;

  @override
  String get canonicalName => 'milestone';

  @override
  Set<List<String>> get arities => {
        [],
        ["milestone-id"]
      };

  @override
  String get help => 'Fetch a milestone given its identifier.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      env.startInteractionCreateEntity(ScString('milestone'));
      return ScNil();
    } else {
      var milestoneId = args[0];
      if (milestoneId is ScNumber) {
        milestoneId = ScString(milestoneId.toString());
      }
      final milestone = ScMilestone(milestoneId as ScString);
      return waitOn(milestone.fetch(env));
    }
  }
}

class ScFnMilestones extends ScBaseInvocable {
  static final ScFnMilestones _instance = ScFnMilestones._internal();
  ScFnMilestones._internal();
  factory ScFnMilestones() => _instance;

  @override
  String get canonicalName => 'milestones';

  @override
  Set<List<String>> get arities => {
        [],
        ["entity"]
      };

  @override
  String get help => 'Fetch all milestones in the current workspace.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""The Shortcut API endpoint does not provide any filtering capabilities, so you'll need to filter here at the console.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      if (env.parentEntity is ScIteration) {
        final iteration = env.parentEntity as ScIteration;
        return milestonesInIteration(env, iteration);
      } else if (env.parentEntity is ScTeam) {
        final team = env.parentEntity as ScTeam;
        return milestonesInTeam(env, team);
      } else if (env.parentEntity is ScMember) {
        final member = env.parentEntity as ScMember;
        final epics = epicsForStoriesOwnedByMember(env, member);
        return uniqueMilestonesAcrossEpics(env, epics);
      } else {
        return waitOn(env.client.getMilestones(env));
      }
    } else if (args.length == 1) {
      final entity = args[0];
      if (entity is ScIteration) {
        return milestonesInIteration(env, entity);
      } else if (entity is ScTeam) {
        return milestonesInTeam(env, entity);
      } else if (entity is ScMember) {
        final epics = epicsForStoriesOwnedByMember(env, entity);
        return uniqueMilestonesAcrossEpics(env, epics);
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function doesn't know how to find milestones in a ${entity.typeName()}.");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects 0 or 1 argument, but received ${args.length} arguments.");
    }
  }
}

class ScFnIteration extends ScBaseInvocable {
  static final ScFnIteration _instance = ScFnIteration._internal();
  ScFnIteration._internal();
  factory ScFnIteration() => _instance;

  @override
  String get canonicalName => 'iteration';

  @override
  Set<List<String>> get arities => {
        [],
        ["iteration-id"]
      };

  @override
  String get help => 'Fetch an iteration given its identifier.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      env.startInteractionCreateEntity(ScString('iteration'));
      return ScNil();
    } else {
      var iterationId = args[0];
      if (iterationId is ScNumber) {
        iterationId = ScString(iterationId.toString());
      }
      final iteration = ScIteration(iterationId as ScString);
      return waitOn(iteration.fetch(env));
    }
  }
}

class ScFnIterations extends ScBaseInvocable {
  static final ScFnIterations _instance = ScFnIterations._internal();
  ScFnIterations._internal();
  factory ScFnIterations() => _instance;

  @override
  String get canonicalName => 'iterations';

  @override
  Set<List<String>> get arities => {[]};

  @override
  String get help =>
      'Fetch iterations, either all or based on the current parent entity.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      final iterations = waitOn(env.client.getIterations(env));
      if (env.parentEntity == null) {
        return iterations;
      } else {
        if (env.parentEntity is ScTeam) {
          final team = env.parentEntity as ScTeam;
          return iterationsOfTeam(env, team, prefetchedIterations: iterations);
        } else if (env.parentEntity is ScMember) {
          final member = env.parentEntity as ScMember;
          final teams = member.data[ScString('group_ids')];
          if (teams is ScList) {
            final allIterations = ScList([]);
            for (final team in teams.innerList) {
              ScTeam t;
              if (team is ScString) {
                t = ScTeam(team);
              } else if (team is ScTeam) {
                t = team;
              } else {
                throw BadArgumentsException(
                    "Found a ${team.typeName()} where a string or team was expected.");
              }
              final iterations = iterationsOfTeam(env, t);
              allIterations.innerList.addAll(iterations.innerList);
            }
            return allIterations;
          } else {
            env.err.writeln(env.style(
                '[WARN] You probably need to run `.` to re-fetch your parent entity, no teams found.',
                styleWarn));
            return ScList([]);
          }
        } else {
          return iterations;
        }
      }
    } else if (args.length == 1) {
      final entity = env.resolveArgEntity(args, canonicalName);
      if (entity is ScTeam) {
        return iterationsOfTeam(env, entity);
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects no arguments, or a team, but received a ${entity.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects no arguments or a single team, but received ${args.length} arguments.");
    }
  }
}

class ScFnLabel extends ScBaseInvocable {
  static final ScFnLabel _instance = ScFnLabel._internal();
  ScFnLabel._internal();
  factory ScFnLabel() => _instance;

  @override
  String get canonicalName => 'label';

  @override
  String get help => "Fetch a specific Shortcut label (for stories, epics).";

  @override
  Set<List<String>> get arities => {
        ["label-id"]
      };

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final labelId = args[0];
      ScLabel label;
      if (labelId is ScNumber) {
        label = ScLabel(ScString(labelId.value.toString()));
      } else if (labelId is ScString) {
        label = ScLabel(labelId);
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects a string or number for the label ID, but received a ${labelId.typeName()}");
      }
      return waitOn(label.fetch(env));
    } else {
      // TODO Implement interactive label creation
      throw UnimplementedError();
    }
  }
}

class ScFnLabels extends ScBaseInvocable {
  static final ScFnLabels _instance = ScFnLabels._internal();
  ScFnLabels._internal();
  factory ScFnLabels() => _instance;

  @override
  String get canonicalName => 'labels';

  @override
  String get help => "Fetch all Shortcut labels in your workspace.";

  @override
  Set<List<String>> get arities => {[]};

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return waitOn(env.client.getLabels(env));
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects no arguments, but received ${args.length}.");
    }
  }
}

class ScFnCustomFields extends ScBaseInvocable {
  static final ScFnCustomFields _instance = ScFnCustomFields._internal();
  ScFnCustomFields._internal();
  factory ScFnCustomFields() => _instance;

  @override
  String get canonicalName => 'custom-fields';

  @override
  String get help => "Fetch all Shortcut custom fields in your workspace.";

  @override
  Set<List<String>> get arities => {[]};

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return waitOn(env.client.getCustomFields(env));
    } else {
      throw BadArgumentsException(
          "The `$canonicalName` function expects no arguments, but received ${args.length}.");
    }
  }
}

class ScFnCustomField extends ScBaseInvocable {
  static final ScFnCustomField _instance = ScFnCustomField._internal();
  ScFnCustomField._internal();
  factory ScFnCustomField() => _instance;

  @override
  String get canonicalName => 'custom-field';

  @override
  String get help => "Fetch a specific Shortcut custom field.";

  @override
  Set<List<String>> get arities => {
        ["custom-field-id"]
      };

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final customFieldId = args[0];
      ScCustomField customField;
      if (customFieldId is ScNumber) {
        customField = ScCustomField(ScString(customFieldId.value.toString()));
      } else if (customFieldId is ScString) {
        customField = ScCustomField(customFieldId);
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function expects a string or number for the custom field ID, but received a ${customFieldId.typeName()}");
      }
      return waitOn(customField.fetch(env));
    } else {
      // TODO Implement interactive custom field creation
      throw UnimplementedError();
    }
  }
}

class ScFnMax extends ScBaseInvocable {
  static final ScFnMax _instance = ScFnMax._internal();
  ScFnMax._internal();
  factory ScFnMax() => _instance;

  @override
  String get canonicalName => 'max';

  @override
  Set<List<String>> get arities => {
        ["number-a", "number-b"]
      };

  @override
  String get help => 'Returns the largest argument.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw UnsupportedError(
          "The `$canonicalName` function expects at least one argument.");
    } else {
      final arg = args[0];
      ScList list;
      if (arg is ScList) {
        list = arg;
      } else {
        list = args;
      }
      return list.reduce((acc, value) {
        final a = acc as ScNumber;
        if (value is ScNumber) {
          return value > a ? value : a;
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function only works with numbers, but received a ${value.typeName()}");
        }
      });
    }
  }
}

class ScFnMin extends ScBaseInvocable {
  static final ScFnMin _instance = ScFnMin._internal();
  ScFnMin._internal();
  factory ScFnMin() => _instance;

  @override
  String get canonicalName => 'min';

  @override
  Set<List<String>> get arities => {
        ["number-a", "number-b"]
      };

  @override
  String get help => 'Returns the smallest argument.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw BadArgumentsException(
          "The `$canonicalName` function expects at least one argument.");
    } else {
      final arg = args[0];
      ScList list;
      if (arg is ScList) {
        list = arg;
      } else {
        list = args;
      }
      return list.reduce((acc, value) {
        final a = acc as ScNumber;
        if (value is ScNumber) {
          return value < a ? value : a;
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function only works with numbers, but received a ${value.typeName()}");
        }
      });
    }
  }
}

class ScFnEquals extends ScBaseInvocable {
  static final ScFnEquals _instance = ScFnEquals._internal();
  ScFnEquals._internal();
  factory ScFnEquals() => _instance;

  @override
  String get canonicalName => '=';

  @override
  Set<List<String>> get arities => {
        [],
        ["number"],
        ["number", "..."]
      };

  @override
  String get help => "Returns true if arguments equal one another.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScBoolean.veritas();
    } else {
      ScBoolean allEqual = ScBoolean.veritas();
      final firstArg = args.first;
      for (final arg in args.innerList) {
        if (arg != firstArg) {
          allEqual = ScBoolean.falsitas();
          break;
        }
      }
      return allEqual;
    }
  }
}

class ScFnGreaterThan extends ScBaseInvocable {
  static final ScFnGreaterThan _instance = ScFnGreaterThan._internal();
  ScFnGreaterThan._internal();
  factory ScFnGreaterThan() => _instance;

  @override
  String get canonicalName => '>';

  @override
  Set<List<String>> get arities => {
        [],
        ["number"],
        ["number", "..."]
      };

  @override
  String get help =>
      "Returns true if earlier arguments are greater than later ones.";

  @override
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScBoolean.veritas();
    } else {
      ScBoolean allGreaterThan = ScBoolean.veritas();
      var previousArg = args[0];
      for (final arg in args.skip(1).innerList) {
        if (previousArg is ScNumber) {
          if (arg is ScNumber) {
            return ScBoolean.fromBool(previousArg > arg);
          }
        }
      }
      return allGreaterThan;
    }
  }
}

class ScFnLessThan extends ScBaseInvocable {
  static final ScFnLessThan _instance = ScFnLessThan._internal();
  ScFnLessThan._internal();
  factory ScFnLessThan() => _instance;

  @override
  String get canonicalName => '<';

  @override
  Set<List<String>> get arities => {
        [],
        ["number"],
        ["number", "..."]
      };

  @override
  String get help =>
      "Returns true if earlier arguments are less than later ones.";

  @override
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScBoolean.veritas();
    } else {
      ScBoolean allLessThan = ScBoolean.veritas();
      var previousArg = args[0];
      for (final arg in args.skip(1).innerList) {
        if (previousArg is ScNumber) {
          if (arg is ScNumber) {
            return ScBoolean.fromBool(previousArg < arg);
          }
        }
      }
      return allLessThan;
    }
  }
}

class ScFnGreaterThanOrEqualTo extends ScBaseInvocable {
  static final ScFnGreaterThanOrEqualTo _instance =
      ScFnGreaterThanOrEqualTo._internal();
  ScFnGreaterThanOrEqualTo._internal();
  factory ScFnGreaterThanOrEqualTo() => _instance;

  @override
  String get canonicalName => '>=';

  @override
  Set<List<String>> get arities => {
        [],
        ["number"],
        ["number", "..."]
      };

  @override
  String get help =>
      "Returns true if earlier arguments are greater than or equal to later ones.";

  @override
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScBoolean.veritas();
    } else {
      ScBoolean allGreaterThanOrEqualTo = ScBoolean.veritas();
      var previousArg = args[0];
      for (final arg in args.skip(1).innerList) {
        if (previousArg is ScNumber) {
          if (arg is ScNumber) {
            return ScBoolean.fromBool(previousArg >= arg);
          }
        }
      }
      return allGreaterThanOrEqualTo;
    }
  }
}

class ScFnLessThanOrEqualTo extends ScBaseInvocable {
  static final ScFnLessThanOrEqualTo _instance =
      ScFnLessThanOrEqualTo._internal();
  ScFnLessThanOrEqualTo._internal();
  factory ScFnLessThanOrEqualTo() => _instance;

  @override
  String get canonicalName => "<=";

  @override
  Set<List<String>> get arities => {
        [],
        ["number"],
        ["number", "..."]
      };

  @override
  String get help =>
      "Returns true if earlier arguments are less than or equal to later ones.";

  @override
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScBoolean.veritas();
    } else {
      ScBoolean allLessThanOrEqualTo = ScBoolean.veritas();
      var previousArg = args[0];
      for (final arg in args.skip(1).innerList) {
        if (previousArg is ScNumber) {
          if (arg is ScNumber) {
            return ScBoolean.fromBool(previousArg <= arg);
          }
        }
      }
      return allLessThanOrEqualTo;
    }
  }
}

class ScFnAdd extends ScBaseInvocable {
  static final ScFnAdd _instance = ScFnAdd._internal();
  ScFnAdd._internal();
  factory ScFnAdd() => _instance;

  @override
  String get canonicalName => "+";

  @override
  Set<List<String>> get arities => {
        [],
        ["number"],
        ["number", "..."]
      };

  @override
  String get help => 'Returns the sum of all the arguments.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScNumber(0);
    } else {
      return args.reduce((acc, item) {
        if (item is ScNumber) {
          final addableAcc = acc as ScNumber;
          final addableItem = item;
          return addableAcc.add(addableItem);
        } else {
          throw BadArgumentsException(
              "Addition is only supported for numbers, but received a ${item.typeName()}");
        }
      });
    }
  }
}

class ScFnSubtract extends ScBaseInvocable {
  static final ScFnSubtract _instance = ScFnSubtract._internal();
  ScFnSubtract._internal();
  factory ScFnSubtract() => _instance;

  @override
  String get canonicalName => '-';

  @override
  Set<List<String>> get arities => {
        [],
        ["number"],
        ["number", "..."]
      };

  @override
  String get help =>
      'Returns the difference of all the arguments, left-to-right.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScNumber(0);
    } else {
      return args.reduce((acc, item) {
        if (item is ScNumber) {
          final subtractableAcc = acc as ScNumber;
          final subtractableItem = item;
          return subtractableAcc.subtract(subtractableItem);
        } else {
          throw BadArgumentsException(
              "Subtraction is only supported for numbers, but received a ${item.typeName()}");
        }
      });
    }
  }
}

class ScFnMultiply extends ScBaseInvocable {
  static final ScFnMultiply _instance = ScFnMultiply._internal();
  ScFnMultiply._internal();
  factory ScFnMultiply() => _instance;

  @override
  String get canonicalName => '*';

  @override
  Set<List<String>> get arities => {
        [],
        ["number"],
        ["number", "..."]
      };
  @override
  String get help => 'Returns the product of all the arguments.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScNumber(1);
    } else {
      return args.reduce((acc, item) {
        if (item is ScNumber) {
          final multipliableAcc = acc as ScNumber;
          final multipliableItem = item;
          return multipliableAcc.multiply(multipliableItem);
        } else {
          throw BadArgumentsException(
              "Multiplication is only supported for numbers, but received a ${item.typeName()}");
        }
      });
    }
  }
}

class ScFnDivide extends ScBaseInvocable {
  static final ScFnDivide _instance = ScFnDivide._internal();
  ScFnDivide._internal();
  factory ScFnDivide() => _instance;

  @override
  String get canonicalName => '/';

  @override
  Set<List<String>> get arities => {
        ['divisor'],
        ['dividend', 'divisor']
      };

  @override
  String get help =>
      'Returns the quotient of all the numbers, left-to-right, as a floating-point number (Dart double).';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw BadArgumentsException(
          "The `/` division function requires at least a divisor.");
    } else if (args.length == 1) {
      final divisor = args[0];
      if (divisor is ScNumber) {
        return ScNumber(1).divide(divisor);
      } else {
        throw BadArgumentsException(
            "Division is only supported for numbers, but received a ${divisor.typeName()}");
      }
    } else {
      return args.reduce((acc, item) {
        if (item is ScNumber) {
          final divisibleAcc = acc as ScNumber;
          final divisibleItem = item;
          return divisibleAcc.divide(divisibleItem);
        } else {
          throw BadArgumentsException(
              "Division is only supported for numbers, but received a ${item.typeName()}");
        }
      });
    }
  }
}

class ScFnModulo extends ScBaseInvocable {
  static final ScFnModulo _instance = ScFnModulo._internal();
  ScFnModulo._internal();
  factory ScFnModulo() => _instance;

  @override
  String get canonicalName => 'mod';

  @override
  Set<List<String>> get arities => {
        ["dividend", "divisor"]
      };

  @override
  String get help => 'Returns the modulo of the two numbers.';

  @override
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 2) {
      final a = args[0];
      final b = args[1];
      if (a is ScNumber) {
        if (b is ScNumber) {
          return ScNumber(a.value % b.value);
        } else {
          throw BadArgumentsException(
              "The `$canonicalName` function's second argument must be a number, but received a ${b.typeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `$canonicalName` function's first argument must be a number, but received a ${b.typeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `mod` modulo function requires at least a divisor.");
    }
  }
}

class ScDefinition extends ScExpr {
  final ScSymbol definitionName;
  final ScList definitionBody;
  ScDefinition(this.definitionName, this.definitionBody);

  @override
  ScExpr eval(ScEnv env) {
    final valueInvocation = windUpPipes(env, definitionBody);
    final invokedValue = valueInvocation.eval(env);
    env[definitionName] = invokedValue;
    return invokedValue;
  }
}

class ScInvocation extends ScExpr {
  final ScList exprs;
  ScInvocation(this.exprs);
  ScList get getExprs => ScList(List<ScExpr>.from(exprs.innerList));

  @override
  ScExpr eval(ScEnv env) {
    if (exprs.isEmpty) {
      return ScNil();
    } else {
      final theseExprs = getExprs;
      final preEvalFirstItem = theseExprs.first;
      final evaledItems = theseExprs.mapMutable((e) => e.eval(env));
      if (evaledItems.first is ScBaseInvocable) {
        final invocable = evaledItems.first as ScBaseInvocable;
        return invocable.invoke(env, theseExprs.skip(1));
      } else if (preEvalFirstItem == ScDottedSymbol('.')) {
        // Special case given how shell-like this whole app is.
        if (evaledItems.first == ScNil()) {
          throw NoParentEntity(
              "No parent entity found. You can only use `..` when you've used `cd` to move into a child entity.");
        } else {
          return ScInvocation(ScList([ScSymbol('cd'), ScSymbol('..')]));
        }
      } else {
        throw UninvocableException(evaledItems);
      }
    }
  }

  @override
  void print(ScEnv env) {
    env.out.writeln("<invocation>");
  }
}

extension ListToScExpr on List {
  ScExpr toScExpr() {
    List<ScExpr> lst = [];
    for (final item in this) {
      lst.add(valueToScExpr(item));
    }
    return ScList(lst);
  }
}

extension ScListEquality on List {
  /// Dart collections have no meaningful equality semantics. This changes that.
  bool equals(Object other) {
    if (other is List) {
      if (other.length != length) {
        return false;
      } else {
        var isEqual = true;
        other.asMap().forEach((key, value) {
          if (this[key] != value) {
            isEqual = false;
          }
        });
        return isEqual;
      }
    }
    return false;
  }
}

extension MapToScExpr on Map {
  ScExpr toScExpr() {
    Map<ScExpr, ScExpr> mp = {};
    for (final key in keys) {
      final scKey = valueToScExpr(key);
      final scValue = valueToScExpr(this[key]);
      mp[scKey] = scValue;
    }
    return ScMap(mp);
  }
}

extension ScMapEquality on Map {
  bool equals(Object other) {
    if (other is Map) {
      if (other.length != length) {
        return false;
      } else {
        var isEqual = true;
        other.forEach((key, value) {
          if (this[key] != value) {
            isEqual = false;
          }
        });
        return isEqual;
      }
    }
    return false;
  }
}

class ScList extends ScExpr {
  List<ScExpr> innerList;
  ScList(this.innerList);

  bool get isEmpty => innerList.isEmpty;
  bool get isNotEmpty => innerList.isNotEmpty;

  get first => innerList.first;

  get length => innerList.length;

  @override
  String typeName() {
    return "list";
  }

  void addMutable(ScExpr expr) {
    innerList.add(expr);
  }

  @override
  ScExpr eval(ScEnv env) {
    if (innerList.isEmpty) {
      return this;
    } else {
      final l = List<ScExpr>.from(innerList);
      return ScList(l.map((item) {
        final evaledItem = item.eval(env);
        ScExpr finalItem;
        if (evaledItem is ScDottedSymbol) {
          finalItem = evaledItem;
        } else {
          finalItem = evaledItem;
        }
        return finalItem;
      }).toList());
    }
  }

  @override
  String printToString(ScEnv env) {
    if (isEmpty) return '[]';
    StringBuffer sb = StringBuffer('[\n');
    env.indentIndex += 1;
    final finalIdx = innerList.length - 1;
    int i = 0;
    for (final item in innerList) {
      sb.write(env.stringWithIndent("${item.printToString(env)},"));
      if (i != finalIdx) {
        sb.write('\n');
      }
      i++;
    }
    env.indentIndex -= 1;
    sb.write('\n');
    sb.write(env.stringWithIndent(']'));
    return sb.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is ScList && innerList.equals(other.innerList);

  @override
  int get hashCode => 31 + innerList.hashCode;

  ScExpr operator [](int n) {
    return innerList[n];
  }

  void operator []=(int n, ScExpr expr) {
    innerList[n] = expr;
  }

  ScList mapImmutable(Function(dynamic e) fn) {
    final l = List<ScExpr>.from(innerList);
    return ScList(List<ScExpr>.from(l.map(fn)));
  }

  ScList mapMutable(Function(dynamic e) fn) {
    final newInnerList = List<ScExpr>.from(innerList);
    innerList = List<ScExpr>.from(newInnerList.map(fn));
    return this;
  }

  ScList where(ScBoolean Function(ScExpr expr) fn) {
    final l = List<ScExpr>.from(innerList);
    return ScList(l.where((item) {
      final scBool = fn(item);
      if (scBool == ScBoolean.veritas()) {
        return true;
      } else {
        return false;
      }
    }).toList());
  }

  ScList skipMutable(int i) {
    innerList = List<ScExpr>.from(innerList.sublist(i));
    return this;
  }

  ScList skip(int i) {
    return ScList(innerList.sublist(i));
  }

  ScExpr reduce(ScExpr Function(ScExpr acc, ScExpr item) fn) {
    final copy = List<ScExpr>.from(innerList);
    return copy.reduce(fn);
  }

  static from(ScList otherScList) {
    final copy = List<ScExpr>.from(otherScList.innerList);
    return ScList(copy);
  }

  bool contains(Object? object) {
    return innerList.contains(object);
  }

  int indexOf(ScExpr expr) {
    return innerList.indexOf(expr);
  }

  int lastIndexOf(ScExpr expr) {
    return innerList.lastIndexOf(expr);
  }

  /// Consider if better return value would be [this]
  void insertMutable(int index, ScExpr expr) {
    innerList.insert(index, expr);
  }

  ScString join({required ScString separator}) {
    List<String> strs = [];
    for (final x in innerList) {
      if (x is ScString) {
        strs.add(x.value);
      } else {
        strs.add(x.toString());
      }
    }
    return ScString(strs.join(separator.value));
  }

  ScExpr sublist(int start, int end) {
    final copy = List<ScExpr>.from(innerList);
    return ScList(copy.sublist(start, end));
  }

  ScExpr takeWhile(ScBoolean Function(dynamic expr) fn) {
    final copy = List<ScExpr>.from(innerList);
    return ScList(copy
        .takeWhile((value) => ScBoolean.fromTruthy(fn(value)).toBool())
        .toList());
  }

  ScList skipWhile(ScBoolean Function(dynamic expr) fn) {
    final copy = List<ScExpr>.from(innerList);
    return ScList(copy
        .skipWhile((value) => ScBoolean.fromTruthy(fn(value)).toBool())
        .toList());
  }

  @override
  String toString() {
    return innerList.toString();
  }
}

class ScMap extends ScExpr {
  Map<ScExpr, ScExpr> innerMap;
  ScMap(this.innerMap);

  get keys => innerMap.keys;

  num get length => innerMap.length;

  bool get isEmpty => innerMap.isEmpty;
  bool get isNotEmpty => innerMap.isNotEmpty;

  @override
  String typeName() {
    return "map";
  }

  void removeMutable(ScExpr key) {
    innerMap.remove(key);
  }

  ScMap remove(ScExpr key) {
    final copy = Map<ScExpr, ScExpr>.from(innerMap);
    copy.remove(key);
    return ScMap(copy);
  }

  bool containsKey(ScExpr key) {
    if (key is ScString) {
      final containsStringKey = innerMap.containsKey(key);
      final containsDottedSymbolKey =
          innerMap.containsKey(ScDottedSymbol(key.value));
      return containsStringKey || containsDottedSymbolKey;
    } else {
      return innerMap.containsKey(key);
    }
  }

  @override

  /// Returns an [ScMap] where all keys and values have been evaluated.
  ScExpr eval(ScEnv env) {
    if (innerMap.isEmpty) {
      return this;
    } else {
      Map<ScExpr, ScExpr> m = {};
      innerMap.forEach((key, value) {
        final evaledKey = key.eval(env);
        final evaledValue = value.eval(env);
        ScExpr finalKey;
        if (evaledKey is ScDottedSymbol) {
          finalKey = evaledKey;
        } else {
          finalKey = evaledKey;
        }

        ScExpr finalValue;
        if (evaledValue is ScAnonymousFunction) {
          finalValue = evaledValue;
        } else {
          finalValue = evaledValue;
        }
        m[finalKey] = finalValue;
      });
      return ScMap(m);
    }
  }

  @override

  /// This particular [printToString] implementation handles the runtime types
  /// annotated from other methods in this code base to handle printing [ScMap] instances
  /// with blessed entries.
  String printToString(ScEnv env) {
    if (isEmpty) return '{}';
    StringBuffer sb = StringBuffer('{\n');
    env.indentIndex += 1;
    final finalIdx = innerMap.length - 1;
    int i = 0;
    for (final key in innerMap.keys) {
      if (env.isPrintJson &&
          key is! ScString &&
          key is! ScSymbol &&
          key is! ScDottedSymbol) {
        // NB: Omit entries that cannot be represented as legal JSON.
        continue;
      }
      final keyStr = key.printToString(env);
      final valueStr = innerMap[key]?.printToString(env);
      if (env.isPrintJson) {
        sb.write(env.stringWithIndent("$keyStr: $valueStr,"));
      } else {
        sb.write(env.stringWithIndent("$keyStr $valueStr,"));
      }
      if (i != finalIdx) {
        sb.write('\n');
      }
      i++;
    }
    env.indentIndex -= 1;
    sb.write('\n');
    sb.write(env.stringWithIndent('}'));
    return sb.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is ScMap && innerMap.equals(other.innerMap);

  @override
  int get hashCode => 31 + innerMap.hashCode;

  ScExpr? operator [](ScExpr key) {
    return innerMap[key];
  }

  void operator []=(ScExpr key, ScExpr value) {
    innerMap[key] = value;
  }

  void addAllMutable(Map<String, dynamic> map) {
    for (final key in map.keys) {
      final value = map[key];
      final scKey = ScString(key);
      // Types!
      ScExpr scValue = valueToScExpr(value);
      this[scKey] = scValue;
    }
  }

  void addMapMutable(ScMap map) {
    for (final key in map.keys) {
      final value = map[key];
      this[key] = value!;
    }
  }

  ScMap where(ScBoolean Function(ScExpr key, ScExpr value) fn) {
    final copy = Map<ScExpr, ScExpr>.from(innerMap);
    copy.removeWhere((k, v) {
      final scBool = fn(k, v);
      if (scBool == ScBoolean.veritas()) {
        return false; // don't remove
      } else {
        return true; // remove
      }
    });
    return ScMap(copy);
  }

  @override
  String toJson() {
    JsonEncoder jsonEncoder = JsonEncoder.withIndent('  ');
    return jsonEncoder.convert(scExprToValue(this, forJson: true));
  }

  @override
  String toString() {
    return innerMap.toString();
  }
}

abstract class RemoteCommand {
  Future<ScEntity> fetch(ScEnv env);
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]);
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap);
}

// Shortcut Entities
final typeMap = {
  ScMember: 'Member',
};

/// A Shortcut entity is part of the product's domain model.
abstract class ScEntity extends ScExpr implements RemoteCommand {
  ScEntity(this.id);
  final ScExpr id;
  String get idString {
    // NB: Appease Dart.
    final idValue = id;
    if (idValue is ScNumber) {
      return idValue.value.toString();
    } else if (idValue is ScString) {
      return idValue.value;
    } else {
      return idValue.toString();
    }
  }

  ScMap data = ScMap({});
  ScString? title;

  void setField(ScExpr key, ScExpr value) {
    if (key is ScString) {
      data[key] = value;
    } else if (key is ScDottedSymbol) {
      data[ScString(key._name)] = value;
    } else {
      throw BadArgumentsException(
          "Entities only support setting data field values via string or dotted symbol keys, but received a ${key.typeName()}");
    }
  }

  ScExpr getField(ScExpr key) {
    if (key is ScString) {
      return data[key] ?? ScNil();
    } else if (key is ScDottedSymbol) {
      return data[ScString(key._name)] ?? ScNil();
    } else {
      throw BadArgumentsException(
          "Entities only support data field access via string or dotted symbol keys, but received a ${key.typeName()}");
    }
  }

  /// Designed to be overridden. The value "fetch" is the default because all entities are constructable via that function.
  String get shortFnName => 'fetch';

  static final Set<ScString> importantKeys = {
    ScString('app_url'),
    ScString('archived'),
    ScString('completed_at'),
    ScString('complete'),
    ScString('description'),
    ScString('disabled'),
    ScString('end_date'),
    ScString('entity_type'),
    ScString('epic_id'),
    ScString('estimate'),
    ScString('group_id'),
    ScString('group_ids'),
    ScString('id'),
    ScString('iteration_id'),
    ScString('mention_name'),
    ScString('milestone_id'),
    ScString('name'),
    ScString('requested_by_id'),
    ScString('owner_ids'),
    ScString('profile'),
    ScString('requested_by_id'),
    ScString('start_date'),
    ScString('started_at'),
    ScString('state'),
    ScString('states'),
    ScString('status'),
    ScString('started_at'),
    ScString('story_type'),
    ScString('workflow_state_id'),
  };

  static final Set<ScString> dateTimeKeys = {
    ScString("completed_at_end"),
    ScString("completed_at_override"),
    ScString("completed_at_start"),
    ScString("completed_at"),
    ScString("created_at"),
    ScString("created_at_end"),
    ScString("created_at_start"),
    ScString("deadline"),
    ScString("deadline_end"),
    ScString("deadline_start"),
    ScString("moved_at"),
    ScString("planned_start_date"),
    ScString("started_at_override"),
    ScString("started_at"),
    ScString("updated_at"),
    ScString("updated_at_end"),
    ScString("updated_at_start"),
  };

  static final Set<ScString> epicKeys = {
    ScString('epic_id'),
  };

  static final Set<ScString> milestoneKeys = {
    ScString('milestone_id'),
  };

  static final Set<ScString> iterationKeys = {
    ScString('iteration_id'),
  };

  static final Set<ScString> memberKeys = {
    ScString('author_id'),
    ScString('requested_by_id'),
  };

  static final Set<ScString> membersKeys = {
    ScString('follower_ids'),
    ScString('member_ids'),
    ScString('member_mention_ids'),
    ScString('owner_ids'),
  };

  static final Set<ScString> teamKeys = {
    ScString('group_id'),
  };

  static final Set<ScString> teamsKeys = {
    ScString('group_ids'),
    ScString('group_mention_ids')
  };

  static final Set<ScString> customFieldEnumValuesKeys = {
    ScString('values'),
  };

  static final Set<ScString> workflowKeys = {ScString('workflow_id')};
  static final Set<ScString> workflowsKeys = {ScString('workflow_ids')};

  static final Set<ScString> workflowStateKeys = {
    ScString('workflow_state_id')
  };
  static final Set<ScString> workflowStatesKeys = {
    ScString('workflow_state_ids')
  };

  static final Set<ScString> epicWorkflowStateKeys = {
    ScString('epic_state_id')
  };

  ScEntity addAll(ScEnv env, Map<String, dynamic> map) {
    data.addAllMutable(map);
    final name = map[ScString('name')];
    final description = map[ScString('description')];
    if (name is ScString) {
      title = name;
    } else if (description is ScString) {
      title = description;
    } else {
      // NB: In practice, should be unreachable.
      title = ScString('<No name>');
    }
    final dtFn = ScFnDateTime();
    for (final key in data.keys) {
      // # Deserialization #
      // ## DateTime values
      if (dateTimeKeys.contains(key)) {
        final dateTimeStr = data[key];
        if (dateTimeStr is ScString) {
          data[key] = dtFn.invoke(env, ScList([dateTimeStr]));
        }
      }

      // # Cached Things #
      // ## Members
      if (memberKeys.contains(key)) {
        final id = data[key]!;
        if (id is ScString) {
          data[key] = env.resolveMember(env, id);
        }
      }
      if (membersKeys.contains(key)) {
        final ids = data[key]!;
        if (ids is ScList) {
          List<ScExpr> l = [];
          for (final id in ids.innerList) {
            if (id is ScString) {
              l.add(env.resolveMember(env, id));
            }
          }
          data[key] = ScList(l);
        }
      }

      // ## Teams
      if (teamKeys.contains(key)) {
        final id = data[key]!;
        if (id is ScString) {
          // NB: Prevent cyclic resolution
          if (this is ScMember) {
            data[key] = id;
          } else {
            data[key] = env.resolveTeam(env, id);
          }
        }
      }
      if (teamsKeys.contains(key)) {
        final ids = data[key];
        if (ids is ScList) {
          List<ScExpr> l = [];
          if (this is ScMember) {
            for (final id in ids.innerList) {
              if (id is ScString) {
                l.add(id);
              }
            }
          } else {
            for (final id in ids.innerList) {
              if (id is ScString) {
                l.add(env.resolveTeam(env, id));
              }
            }
          }
          data[key] = ScList(l);
        }
      }

      // ## Custom Fields and their enum values
      if (this is ScCustomField) {
        if (customFieldEnumValuesKeys.contains(key)) {
          final ids = data[key]!;
          if (ids is ScList) {
            List<ScExpr> l = [];
            for (final id in ids.innerList) {
              if (id is ScString) {
                l.add(env.resolveCustomFieldEnumValue(id));
              } else if (id is ScCustomFieldEnumValue) {
                l.add(id);
              } else if (id is ScMap) {
                l.add(ScCustomFieldEnumValue.fromMap(env, scExprToValue(id)));
              }
            }
            data[key] = ScList(l);
          }
        }
      }

      // ## Workflows
      if (workflowKeys.contains(key)) {
        final id = data[key]!;
        if (id is ScString) {
          data[key] = env.resolveWorkflow(id);
        } else if (id is ScNumber) {
          data[key] = env.resolveWorkflow(ScString(id.toString()));
        }
      }
      if (workflowsKeys.contains(key)) {
        final ids = data[key];
        if (ids is ScList) {
          List<ScExpr> l = [];
          for (final id in ids.innerList) {
            if (id is ScString) {
              l.add(env.resolveWorkflow(id));
            } else if (id is ScNumber) {
              l.add(env.resolveWorkflow(ScString(id.toString())));
            }
          }
          data[key] = ScList(l);
        }
      }
      // ## Workflow States
      if (workflowStateKeys.contains(key)) {
        final id = data[key]!;
        if (id is ScString) {
          data[key] = env.resolveWorkflowState(id);
        } else if (id is ScNumber) {
          data[key] = env.resolveWorkflowState(ScString(id.toString()));
        }
      }
      if (workflowStatesKeys.contains(key)) {
        final ids = data[key];
        if (ids is ScList) {
          List<ScExpr> l = [];
          for (final id in ids.innerList) {
            if (id is ScString) {
              l.add(env.resolveWorkflowState(id));
            } else if (id is ScNumber) {
              l.add(env.resolveWorkflowState(ScString(id.toString())));
            }
          }
          data[key] = ScList(l);
        }
      }

      // ## Epic Workflow States
      if (epicWorkflowStateKeys.contains(key)) {
        final id = data[key]!;
        if (id is ScString) {
          data[key] = env.resolveEpicWorkflowState(id);
        } else if (id is ScNumber) {
          data[key] = env.resolveEpicWorkflowState(ScString(id.toString()));
        }
      }
    }
    return this;
  }

  /// Intended to be overridden to show meaningful, entity-context-specific summaries.
  ScExpr printSummary(ScEnv env) {
    final ks = List<ScExpr>.from(ScEntity.importantKeys);
    ks.sort();
    printTable(env, ks, data);
    return ScNil();
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      if (data.isEmpty) {
        // NB: For now, just printing id's. Fetch would be costly and risks cyclic resolution, which is handled already elsewhere.
        return id.printToString(env);
      } else {
        if (this is ScMember) {
          final dm = Map<ScExpr, ScExpr>.from(data.innerMap);
          final teams = dm[ScString('group_ids')] as ScList;
          teams.mapMutable((e) {
            if (e is ScTeam) {
              return e.id;
            } else {
              return e;
            }
          });
          dm[ScString('group_ids')] = teams;
          return ScMap(dm).printToString(env);
        } else {
          return data.printToString(env);
        }
      }
    } else {
      final sb = StringBuffer('');
      sb.writeln("${typeName().capitalize()} $id");
      env.indentIndex += 1;
      sb.write(env.indentString());
      sb.write(data.printToString(env));
      env.indentIndex -= 1;
      return sb.toString();
    }
  }

  String inlineSummary(ScEnv env) {
    final t = calculateTitle();
    final readable = readableString(env);
    return t + ' ' + readable;
  }

  @override
  String typeName() {
    return 'entity';
  }

  @override
  bool operator ==(Object other) {
    final thisType = runtimeType;
    final otherType = other.runtimeType;
    if (other is ScEntity) {
      return thisType == otherType && id == other.id;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => 31 + id.hashCode;

  @override
  // NB: This is used to create the JSON string sent to Shortcut's API. See [printToString] for how _printing_ a JSON-compatible representation is accomplished for end-user use.
  String toJson() {
    JsonEncoder jsonEncoder = JsonEncoder.withIndent('  ');
    return jsonEncoder.convert(data);
  }

  /// Returns a string representation of this [ScEntity] that is readable and evaluate-able by PL
  String readableString(ScEnv env) {
    final lp = lParen(env);
    final rp = rParen(env);

    String fnName;
    if (shortFnName.isEmpty) {
      fnName = env.style('id', this);
    } else {
      fnName = env.style(shortFnName, this);
    }
    return "$lp$fnName $idString$rp";
  }

  String calculateTitle() {
    ScString calculatedTitle;
    if (this is ScTask) {
      final desc = data[ScString('description')];
      if (desc is ScString) {
        calculatedTitle = desc;
      } else if (title != null) {
        calculatedTitle = title!;
      } else {
        calculatedTitle = ScString('<No description found>');
      }
    } else if (this is ScMember) {
      final profile = data[ScString('profile')];
      if (profile is ScMap) {
        final name = profile[ScString('name')];
        if (name is ScString) {
          calculatedTitle = name;
        } else if (title != null) {
          calculatedTitle = title!;
        } else {
          calculatedTitle = ScString('<No member data: run fetch>');
        }
      } else {
        calculatedTitle = ScString('<No member data: run fetch>');
      }
    } else if (this is ScCustomFieldEnumValue) {
      final value = data[ScString('value')];
      if (value is ScString) {
        calculatedTitle = ScString(value.value);
      } else {
        calculatedTitle =
            ScString('<No custom field enum value data: run fetch>');
      }
    } else {
      final name = data[ScString('name')];
      if (name is ScString) {
        calculatedTitle = name;
      } else if (title != null) {
        calculatedTitle = title!;
      } else {
        calculatedTitle = ScString('<No name: run fetch>');
      }
    }
    return calculatedTitle.value;
  }
}

class ScMember extends ScEntity {
  ScMember(ScString id) : super(id);

  @override
  String get shortFnName => 'mb';

  @override
  String typeName() {
    return 'member';
  }

  factory ScMember.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScMember(ScString(data['id'].toString())).addAll(env, data)
        as ScMember;
  }

  @override
  Future<ScMember> fetch(ScEnv env) async {
    final member = await env.client.getMember(env, idString);
    data = member.data;
    return this;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    final findStoriesFn = ScFnFindStories();
    final findMap = ScMap({
      ScString('owner_id'): ScString(idString),
    });
    return findStoriesFn.invoke(env, ScList([findMap])) as ScList;
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) {
    throw OperationNotSupported(
        "You cannot update a Shortcut member via its API.");
  }

  ScString? get mentionName {
    final profile = data[ScString('profile')];
    if (profile is ScMap) {
      final mentionName = profile[ScString('mention_name')];
      if (mentionName is ScString) {
        return mentionName;
      }
    }
    return null;
  }

  @override
  String readableString(ScEnv env) {
    final lp = lParen(env);
    final rp = rParen(env);
    final fnName = env.style(shortFnName, this);
    return "$lp$fnName $id$rp";
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final role = data[ScString('role')];
      final profile = data[ScString('profile')];
      String name;
      String mentionName;
      if (profile != null) {
        final p = profile as ScMap;
        name = (p[ScString('name')] as ScString).value;
        mentionName = (p[ScString('mention_name')] as ScString).value;
      } else {
        final n =
            data[ScString('name')] ?? title ?? ScString('<No name: run fetch>');
        name = (n as ScString).value;
        final m = data[ScString('mention_name')] ??
            ScString('<No mention name: run fetch>');
        mentionName = (m as ScString).value;
      }
      final shortName = truncate(name, env.displayWidth);

      final cmt = comment(env);

      var prefix = '';
      if (role is ScString) {
        String roleStr = role.value.capitalize();
        switch (roleStr) {
          case 'Admin':
            roleStr = env.style("[$roleStr]", styleRoleAdmin);
            break;
          case 'Member':
            roleStr = env.style("[$roleStr]", styleRoleMember);
            break;
          case 'Observer':
            roleStr = env.style("[$roleStr]", styleRoleObserver);
            break;
          case 'Owner':
            roleStr = env.style("[$roleStr]", styleRoleOwner);
            break;
        }
        prefix = roleStr;
      }
      final memberMentionName = env.style("[@$mentionName]", this);
      prefix = prefix + memberMentionName;
      // prefix = prefix.padRight(39); // some alignment better than none; was 48
      final memberName = env.style(shortName, styleTitle);
      final readable = readableString(env);
      final memberStr = "$readable $cmt $prefix $memberName";
      return memberStr;
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    final lblName = 'Name ';
    final lblId = 'Id ';
    final lblMentionName = 'Mention Name ';
    final lblTeams = 'Teams ';
    final labelWidth =
        maxPaddedLabelWidth([lblName, lblId, lblMentionName, lblTeams]);

    if (!data.containsKey(ScString('profile'))) {
      waitOn(fetch(env));
    }
    final sb = StringBuffer('\n');

    final isArchived = data[ScString('disabled')];
    if (isArchived == ScBoolean.veritas()) {
      sb.writeln(env.style('   !! DISABLED !!', styleError));
    }

    final profile = data[ScString('profile')];
    if (profile is ScMap) {
      final name = profile[ScString('name')];
      if (name is ScString) {
        sb.write(env.style(lblName.padLeft(labelWidth), this));
        sb.writeln(name.value);
      }

      final id = data[ScString('id')];
      if (id is ScString) {
        sb.write(env.style(lblId.padLeft(labelWidth), this));
        sb.writeln(id.value);
      }

      final mentionName = profile[ScString('mention_name')];
      if (mentionName is ScString) {
        sb.write(env.style(lblMentionName.padLeft(labelWidth), this));
        sb.writeln("@${mentionName.value}");
      }
    }

    final teams = data[ScString('group_ids')] as ScList;
    if (teams.isNotEmpty) {
      sb.write(env.style(lblTeams.padLeft(labelWidth), this));
      if (teams.length == 1) {
        final team = teams[0];
        if (team is ScTeam) {
          sb.writeln(team.inlineSummary(env));
        } else if (team is ScString) {
          sb.writeln(env.resolveTeam(env, team).inlineSummary(env));
        }
      } else {
        var isFirst = true;
        for (final team in teams.innerList) {
          ScTeam? teamEntity;
          if (team is ScTeam) {
            teamEntity = team;
          } else if (team is ScString) {
            teamEntity = env.resolveTeam(env, team);
          }

          if (teamEntity != null) {
            if (isFirst) {
              isFirst = false;
              sb.writeln(teamEntity.inlineSummary(env));
            } else {
              sb.writeln(
                  '${"".padLeft(labelWidth)}${teamEntity.inlineSummary(env)}');
            }
          }
        }
      }
    }

    env.out.write(sb.toString());
    return ScNil();
  }

  @override
  String inlineSummary(ScEnv env) {
    final sb = StringBuffer();

    sb.write(calculateTitle());

    final profile = data[ScString('profile')];
    if (profile is ScMap) {
      final mentionName = profile[ScString('mention_name')];
      if (mentionName is ScString) {
        sb.write(env.style(" @${mentionName.value}", styleMemberMention));
      }
    }

    final lp = lParen(env);
    final rp = rParen(env);
    final memberFnName = env.style('mb', this);
    sb.write(" $lp$memberFnName $id$rp");

    return sb.toString();
  }
}

class ScTeam extends ScEntity {
  ScTeam(ScString id) : super(id);

  @override
  String get shortFnName => 'tm';

  factory ScTeam.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScTeam(ScString(data['id'].toString())).addAll(env, data) as ScTeam;
  }

  @override
  String typeName() {
    return 'team';
  }

  ScString? get mentionName {
    final mentionName = data[ScString('mention_name')];
    if (mentionName is ScString) {
      return mentionName;
    }
    return null;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final team = await env.client.getTeam(env, idString);
    data = team.data;
    return this;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    return data[ScString('member_ids')] as ScList;
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final team = await env.client.updateTeam(env, idString, updateMap);
    data = team.data;
    return this;
  }

  @override
  String readableString(ScEnv env) {
    final lp = lParen(env);
    final rp = rParen(env);
    final fnName = env.style(shortFnName, this);
    return "$lp$fnName $id$rp";
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final name = dataFieldOr<ScString?>(data, 'name', title) ??
          ScString("<No name: run fetch>");
      final mentionName = dataFieldOr<ScString>(
              data, 'mention_name', ScString("<No mention name: run fetch>")) ??
          ScString("<No mention name>");
      final shortName = truncate(name.value, env.displayWidth);
      final teamMentionName =
          env.style("[@${mentionName.value}]", styleTeamMention);
      final teamName = env.style(shortName, styleTitle);
      final cmt = comment(env);

      final readable = readableString(env);

      String numMembersStr = '';
      final memberIds = data[ScString('member_ids')];
      if (memberIds is ScList) {
        numMembersStr = env.style("[${memberIds.length}M]", styleMemberMention);
      }
      String prefix = numMembersStr + teamMentionName;
      // prefix = prefix.padRight(39); // some alignment better than none; was 48
      final teamStr = "$readable $cmt $prefix $teamName";
      return teamStr;
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    final lblTeam = 'Team ';
    final lblId = 'Id ';
    final lblMentionName = 'Mention Name ';
    final labelWidth = maxPaddedLabelWidth([lblTeam, lblId, lblMentionName]);
    if (!data.containsKey(ScString('description'))) {
      waitOn(fetch(env));
    }
    final sb = StringBuffer('\n');

    final isArchived = data[ScString('archived')];
    if (isArchived == ScBoolean.veritas()) {
      sb.writeln(env.style('   !! ARCHIVED !!', styleError));
    }

    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    sb.write(env.style(lblTeam.padLeft(labelWidth), this));
    sb.writeln(env.style(name.value, styleTitle, styles: [styleUnderline]));

    final id = data[ScString('id')];
    if (id is ScString) {
      sb.write(env.style(lblId.padLeft(labelWidth), this));
      sb.writeln(id);
    }

    final mentionName = data[ScString('mention_name')];
    if (mentionName is ScString) {
      sb.write(env.style(lblMentionName.padLeft(labelWidth), this));
      sb.writeln("@${mentionName.value}");
    }

    env.out.write(sb.toString());
    return ScNil();
  }

  @override
  String inlineSummary(ScEnv env) {
    final sb = StringBuffer();
    sb.write(calculateTitle());

    final mentionName = data[ScString('mention_name')];
    if (mentionName is ScString) {
      sb.write(env.style(" @${mentionName.value}", styleTeamMention));
    }

    final lp = lParen(env);
    final rp = rParen(env);
    final teamFnName = env.style('tm', this);
    sb.write(" $lp$teamFnName $id$rp");

    return sb.toString();
  }
}

class ScMilestone extends ScEntity {
  ScMilestone(ScString id) : super(id);

  @override
  String get shortFnName => 'mi';

  static final states = ["to do", "in progress", "done"];

  static final Set<String> fieldsForCreate = {
    'categories',
    'completed_at_override',
    'description',
    'name',
    'started_at_override',
    'state',
  };

  static final Set<String> fieldsForUpdate = {
    'after_id',
    'archived',
    'before_id',
    'categories',
    'completed_at_override',
    'description',
    'name',
    'started_at_override',
    'state',
  };

  @override
  String typeName() {
    return 'milestone';
  }

  factory ScMilestone.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScMilestone(ScString(data['id'].toString())).addAll(env, data)
        as ScMilestone;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    return env.client.getEpicsInMilestone(env, idString);
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final milestone =
        await env.client.updateMilestone(env, idString, updateMap);
    data = milestone.data;
    return this;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final milestone = await env.client.getMilestone(env, idString);
    data = milestone.data;
    return this;
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final name = dataFieldOr<ScString?>(data, 'name', title) ??
          ScString("<No name: run fetch>");
      final shortName = truncate(name.value, env.displayWidth);
      final cmt = comment(env);
      final milestoneName = env.style(shortName, styleTitle);
      final milestoneFnName = env.style('mi', this);
      final milestoneId = idString;
      final milestoneState = data[ScString('state')];
      String milestoneStateStr = '';
      if (milestoneState is ScString) {
        final state = milestoneState.value;
        switch (state) {
          case 'to do':
            milestoneStateStr = env.style('[U]', styleUnstarted);
            break;
          case 'in progress':
            milestoneStateStr = env.style('[S]', styleStarted);
            break;
          case 'done':
            milestoneStateStr = env.style('[D]', styleDone);
            break;
        }
      }

      final prefix = milestoneStateStr;
      final lp = lParen(env);
      final rp = rParen(env);
      final readable = "$lp$milestoneFnName $milestoneId$rp";
      // .padRight(39); // adjusted for ANSI codes
      final milestoneStr = "$readable $cmt $prefix $milestoneName";
      return milestoneStr;
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    final lblMilestone = 'Milestone ';
    final lblId = 'Id ';
    final lblStarted = 'Started ';
    final lblCompleted = 'Completed ';
    final lblState = 'State ';
    final labelWidth = maxPaddedLabelWidth(
        [lblMilestone, lblId, lblStarted, lblCompleted, lblState]);

    if (!data.containsKey(ScString('description'))) {
      waitOn(fetch(env));
    }
    final sb = StringBuffer('\n');
    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    sb.write(env.style(lblMilestone.padLeft(labelWidth), this));
    sb.writeln(env.style(name.value, styleTitle, styles: [styleUnderline]));

    final milestoneId = idString;
    sb.write(env.style(lblId.padLeft(labelWidth), this));
    sb.writeln(milestoneId);

    final startedAt = data[ScString('started_at')];
    if (startedAt is ScString) {
      sb.write(env.style(lblStarted.padLeft(labelWidth), this));
      sb.writeln(startedAt.value);
    } else if (startedAt == ScNil()) {
      sb.write(env.style(lblStarted.padLeft(labelWidth), this));
      sb.writeln('N/A');
    }

    final completedAt = data[ScString('completed_at')];
    if (completedAt is ScString) {
      sb.write(env.style(lblCompleted.padLeft(labelWidth), this));
      sb.writeln(completedAt.value);
    } else if (completedAt == ScNil()) {
      sb.write(env.style(lblCompleted.padLeft(labelWidth), this));
      sb.writeln('N/A');
    }

    final state = data[ScString('state')];
    if (state is ScString) {
      sb.write(env.style(lblState.padLeft(labelWidth), this));
      sb.writeln(state.value);
    }

    env.out.write(sb.toString());
    return ScNil();
  }
}

class ScEpic extends ScEntity {
  ScEpic(ScString id) : super(id);

  @override
  String get shortFnName => 'ep';

  @override
  String typeName() {
    return 'epic';
  }

  static final Set<String> fieldsForCreate = {
    'completed_at_override',
    'created_at',
    'deadline',
    'description',
    'epic_state_id',
    'external_id',
    'follower_ids',
    'group_id',
    'labels',
    'milestone_id',
    'name',
    'owner_ids',
    'planned_start_date',
    'requested_by_id',
    'started_at_override',
    'state',
    'updated_at',
  };

  static final Set<String> fieldsForUpdate = {
    'after_id',
    'archived',
    'before_id',
    'completed_at_override',
    'deadline',
    'description',
    'epic_state_id',
    'follower_ids',
    'group_id',
    'labels',
    'milestone_id',
    'name',
    'owner_ids',
    'planned_start_date',
    'requested_by_id',
    'started_at_override',
    'state',
  };

  ScString? get milestoneId {
    final i = data[ScString('milestone_id')];
    if (i is ScMilestone) {
      return ScString(i.idString);
    } else if (i is ScNumber) {
      return ScString(i.value.toString());
    } else if (i is ScString) {
      return i;
    }
    return null;
  }

  factory ScEpic.fromMap(ScEnv env, Map<String, dynamic> data) {
    var epicCommentsData = data['comments'] ?? [];
    ScList epicComments = ScList([]);
    if (epicCommentsData.isNotEmpty) {
      epicComments = ScList(List<ScExpr>.from(epicCommentsData.map(
          (commentMap) => ScEpicComment.fromMap(
              env, ScString(data['id'].toString()), commentMap,
              commentLevel: 0))));
    }
    data.remove('comments');
    final epic =
        ScEpic(ScString(data['id'].toString())).addAll(env, data) as ScEpic;
    epic.data[ScString('comments')] = epicComments;
    return epic;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) {
    return env.client.getStoriesInEpic(env, idString);
  }

  @override
  Future<ScEpic> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final epic = await env.client.updateEpic(env, idString, updateMap);
    data = epic.data;
    return this;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final epic = await env.client.getEpic(env, idString);
    data = epic.data;
    return this;
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final isArchived =
          ScBoolean.fromTruthy(data[ScString('archived')] ?? ScNil());
      final name = dataFieldOr<ScString?>(data, 'name', title) ??
          ScString("<No name: run fetch>");
      final shortName = truncate(name.value, env.displayWidth);
      final cmt = comment(env);
      final epicName = env.style(shortName, styleTitle);
      final epicFnName = env.style('ep', this);
      final epicId = idString;
      final epicState = data[ScString('state')];
      String epicStateStr = '';
      if (epicState is ScString) {
        final state = epicState.value;
        switch (state) {
          case 'to do':
            epicStateStr = env.style('[U]', styleUnstarted);
            break;
          case 'in progress':
            epicStateStr = env.style('[S]', styleStarted);
            break;
          case 'done':
            epicStateStr = env.style('[D]', styleDone);
            break;
        }
      }

      final stats = data[ScString('stats')];
      String pointsStr = '';
      String storiesStr = '';
      if (stats is ScMap) {
        final numStories = stats[ScString('num_stories_total')];
        final numStoriesDone = stats[ScString('num_stories_done')];
        if (numStories is ScNumber) {
          if (numStoriesDone is ScNumber) {
            final numStoriesDoneStr = numStoriesDone.toString();
            final numStoriesStr = numStories.toString();
            storiesStr =
                env.style("[$numStoriesDoneStr/${numStoriesStr}S]", styleStory);
          }
        }

        final numPoints = stats[ScString('num_points')];
        final numPointsDone = stats[ScString('num_points_done')];
        if (numPoints is ScNumber) {
          if (numPointsDone is ScNumber) {
            final numPointsDoneStr = numPointsDone.toString();
            final numPointsStr = numPoints.toString();
            pointsStr =
                env.style("[$numPointsDoneStr/${numPointsStr}P]", styleInfo);
          }
        }
      }

      String archivedStr = '';
      if (isArchived.toBool()) {
        archivedStr = env.style(' [ARCHIVED]', styleError);
      }

      final prefix = "$epicStateStr$storiesStr$pointsStr$archivedStr";
      final lp = lParen(env);
      final rp = rParen(env);
      final readable = "$lp$epicFnName $epicId$rp";
      final epicStr = "$readable $cmt $prefix $epicName";
      if (isArchived.toBool()) {
        return env.style(epicStr, styleSubdued);
      } else {
        return epicStr;
      }
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    final lblEpic = 'Epic ';
    final lblId = 'Id ';
    final lblState = 'State ';
    final lblOwnedBy = 'Owned by ';
    final lblTeam = 'Team ';
    final lblMilestone = 'Milestone ';
    final lblStories = 'Stories ';
    final lblPoints = 'Points ';
    final lblComments = 'Comments ';
    final labelWidth = maxPaddedLabelWidth([
      lblEpic,
      lblId,
      lblState,
      lblOwnedBy,
      lblTeam,
      lblMilestone,
      lblStories,
      lblPoints,
      lblComments,
    ]);
    if (!data.containsKey(ScString('description'))) {
      waitOn(fetch(env));
    }
    final sb = StringBuffer('\n');

    final isArchived = data[ScString('archived')];
    if (isArchived == ScBoolean.veritas()) {
      sb.writeln(env.style('   !! ARCHIVED !!', styleError));
    }
    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    sb.write(env.style(lblEpic.padLeft(labelWidth), this));
    sb.writeln(env.style(name.value, styleTitle, styles: [styleUnderline]));

    final epicId = idString;
    sb.write(env.style(lblId.padLeft(labelWidth), this));
    sb.writeln(epicId);

    final state = data[ScString('epic_state_id')];
    if (state is ScEpicWorkflowState) {
      sb.write(env.style(lblState.padLeft(labelWidth), this));
      sb.write(state.inlineSummary(env));
    }
    sb.writeln();

    final owners = data[ScString('owner_ids')] as ScList;
    sb.write(env.style(lblOwnedBy.padLeft(labelWidth), this));
    if (owners.isEmpty) {
      sb.writeln('<No one>');
    } else {
      if (owners.length == 1) {
        final owner = owners[0];
        if (owner is ScMember) {
          sb.writeln(owner.inlineSummary(env));
        }
      } else {
        var isFirst = true;
        for (final owner in owners.innerList) {
          if (owner is ScMember) {
            if (isFirst) {
              isFirst = false;
              sb.writeln(owner.inlineSummary(env));
            } else {
              sb.writeln(
                  '${"".padLeft(labelWidth)}${owner.inlineSummary(env)}');
            }
          }
        }
      }
    }

    final team = data[ScString('group_id')];
    if (team is ScTeam) {
      sb.write(env.style(lblTeam.padLeft(labelWidth), this));
      sb.write(team.inlineSummary(env));
      sb.writeln();
    }

    final milestoneId = data[ScString('milestone_id')];
    ScMilestone? milestone;
    if (milestoneId is ScNumber) {
      milestone = ScMilestone(ScString(milestoneId.toString()));
      waitOn(milestone.fetch(env));
    } else if (milestoneId is ScMilestone) {
      milestone = milestoneId;
    }
    if (milestone != null) {
      sb.write(env.style(lblMilestone.padLeft(labelWidth), this));
      sb.write(milestone.inlineSummary(env));
      sb.writeln();
    }

    final stats = data[ScString('stats')];
    if (stats is ScMap) {
      final numStories = stats[ScString('num_stories_total')];
      final numStoriesDone = stats[ScString('num_stories_done')];
      if (numStories is ScNumber) {
        if (numStoriesDone is ScNumber) {
          // final numStoriesDoneStr = numStoriesDone.toString().padLeft(2);
          final numStoriesDoneStr = numStoriesDone.toString();
          // final numStoriesStr = numStories.toString().padRight(2);
          final numStoriesStr = numStories.toString();
          sb.write(env.style(lblStories.padLeft(labelWidth), this));
          sb.write("$numStoriesDoneStr/$numStoriesStr stories done");
          sb.writeln();
        }
      }

      final numPoints = stats[ScString('num_points')];
      final numPointsDone = stats[ScString('num_points_done')];
      if (numPoints is ScNumber) {
        if (numPointsDone is ScNumber) {
          sb.write(env.style(lblPoints.padLeft(labelWidth), this));
          sb.write("$numPointsDone/$numPoints points done");
          sb.writeln();
        }
      }
    }

    final comments = data[ScString('comments')];
    if (comments is ScList) {
      if (comments.isNotEmpty) {
        int numComments = 0;
        ScDateTime? latestCommentDt;
        for (final comment in comments.innerList) {
          if (comment is ScEpicComment) {
            numComments++;
            final commentCreatedAt = comment.data[ScString('created_at')];
            if (commentCreatedAt is ScDateTime) {
              if (latestCommentDt == null) {
                latestCommentDt = commentCreatedAt;
              } else {
                if (latestCommentDt.value.isBefore(commentCreatedAt.value)) {
                  latestCommentDt = commentCreatedAt;
                }
              }
            }
          }
        }
        sb.write(env.style(lblComments.padLeft(labelWidth), this));
        if (numComments == 1) {
          sb.write("$numComments comment");
        } else {
          sb.write("$numComments comments");
        }
        if (latestCommentDt != null) {
          sb.write(
              ", latest ${ScFnDateTimeField.weekdays[latestCommentDt.value.weekday]!.value} $latestCommentDt");
        }
        sb.writeln();
      }
    }

    env.out.write(sb.toString());
    return ScNil();
  }
}

class ScStory extends ScEntity {
  ScStory(ScString id) : super(id);

  @override
  String get shortFnName => 'st';

  static final Set<String> fieldsForCreate = {
    'archived',
    'comments',
    'completed_at_override',
    'created_at',
    'custom_fields',
    'deadline',
    'description',
    'epic_id',
    'estimate',
    'external_id',
    'external_links',
    'file_ids',
    'follower_ids',
    'group_id',
    'iteration_id',
    'labels',
    'linked_file_ids',
    'name',
    'owner_ids',
    'project_id',
    'requested_by_id',
    'started_at_override',
    'story_links',
    'story_template_id',
    'story_type',
    'tasks',
    'updated_at',
    'workflow_state_id',
  };

  static final Set<String> fieldsForUpdate = {
    'after_id',
    'archived',
    'before_id',
    'branch_ids',
    'commit_ids',
    'completed_at_override',
    'custom_fields',
    'deadline',
    'description',
    'epic_id',
    'estimate',
    'external_links',
    'file_ids',
    'follower_ids',
    'group_id',
    'iteration_id',
    'labels',
    'linked_file_ids',
    'move_to',
    'name',
    'owner_ids',
    'project_id',
    'pull_request_ids',
    'requested_by_id',
    'started_at_override',
    'story_type',
    'workflow_state_id',
  };

  @override
  String typeName() {
    return 'story';
  }

  ScString? get epicId {
    final i = data[ScString('epic_id')];
    if (i is ScEpic) {
      return ScString(i.idString);
    } else if (i is ScNumber) {
      return ScString(i.value.toString());
    } else if (i is ScString) {
      return i;
    }
    return null;
  }

  factory ScStory.fromMap(ScEnv env, Map<String, dynamic> data) {
    var tasksData = data['tasks'] ?? [];
    ScList tasks = ScList([]);
    if (tasksData.isNotEmpty) {
      tasks = ScList(List<ScExpr>.from(tasksData.map((taskMap) =>
          ScTask.fromMap(env, ScString(data['id'].toString()), taskMap))));
    }
    data.remove('tasks');

    var commentsData = data['comments'] ?? [];
    ScList comments = ScList([]);
    if (commentsData.isNotEmpty) {
      comments = ScList(List<ScExpr>.from(commentsData.map((commentMap) =>
          ScComment.fromMap(
              env, ScString(data['id'].toString()), commentMap))));
    }
    data.remove('comments');

    final story =
        ScStory(ScString(data['id'].toString())).addAll(env, data) as ScStory;
    story.data[ScString('tasks')] = tasks;
    story.data[ScString('comments')] = comments;

    return story;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) {
    return env.client.getTasksInStory(env, idString);
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final story = await env.client.updateStory(env, idString, updateMap);
    data = story.data;
    return this;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    if (env.workflowStatesById.isEmpty) {
      final fetchAllFn = ScFnFetchAll();
      fetchAllFn.invoke(env, ScList([]));
    }
    final story = await env.client.getStory(env, idString);
    data = story.data;
    return this;
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final isArchived =
          ScBoolean.fromTruthy(data[ScString('archived')] ?? ScNil());
      final name = dataFieldOr<ScString?>(data, 'name', title) ??
          ScString("<No name: run fetch>");
      final shortName = truncate(name.value, env.displayWidth);

      final state = data[ScString('workflow_state_id')];
      String storyStateType = '';
      if (state is ScWorkflowState) {
        final stateType = state.data[ScString('type')];
        if (stateType is ScString) {
          switch (stateType.value) {
            case 'unstarted':
              storyStateType = env.style('[U]', styleUnstarted);
              break;
            case 'started':
              storyStateType = env.style('[S]', styleStarted);
              break;
            case 'done':
              storyStateType = env.style('[D]', styleDone);
              break;
          }
        }
      }

      final type = data[ScString('story_type')];
      String storyType = '';
      if (type is ScString) {
        String? color;
        var ts = type.value;
        switch (ts) {
          case 'bug':
            color = styleBug;
            break;
          case 'chore':
            color = styleChore;
            break;
          case 'feature':
            color = styleFeature;
            break;
        }
        final typeAbbrev = ts[0].toUpperCase();
        storyType = env.style("[$typeAbbrev]", color ?? styleSubdued);
      }

      final estimate = data[ScString('estimate')];
      var estimateStr = '';
      if (estimate != null) {
        estimateStr = env.style('[_]', styleDone);
        if (estimate is ScNumber) {
          estimateStr = env.style("[${estimate.value}]", styleDone);
        }
      }

      String archivedStr = '';
      if (isArchived.toBool()) {
        archivedStr = env.style(' [ARCHIVED]', styleError);
      }

      final prefix = "$storyStateType$estimateStr$storyType$archivedStr";
      final storyName = env.style(shortName, styleTitle);
      final storyFnName = env.style('st', this);
      final storyId = idString;
      final lp = lParen(env);
      final rp = rParen(env);
      final cmt = comment(env);
      final readable = "$lp$storyFnName $storyId$rp";
      //.padRight(39); // adjusted for ANSI codes
      final storyStr = "$readable $cmt $prefix $storyName";
      if (isArchived.toBool()) {
        return env.style(storyStr, styleSubdued);
      } else {
        return storyStr;
      }
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    if (!data.containsKey(ScString('description'))) {
      // This is either a StorySlim from the API, or a story stub from parentEntity
      waitOn(fetch(env));
    }

    // NB: Label width calculated after story type determined.

    final sb = StringBuffer('\n');
    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    final isArchived = data[ScString('archived')];
    if (isArchived == ScBoolean.veritas()) {
      sb.writeln(env.style('   !! ARCHIVED !!', styleError));
    }
    final storyType = data[ScString('story_type')];
    var storyLabel = 'Story';
    if (storyType is ScString) {
      storyLabel = storyType.value.capitalize();
    }

    final lblStoryType = '$storyLabel ';
    final lblId = 'Id ';
    final lblState = 'State ';
    final lblEpic = 'Epic ';
    final lblIteration = 'Iteration ';
    final lblOwnedBy = 'Owned by ';
    final lblTeam = 'Team ';
    final lblEstimate = 'Estimate ';
    final lblDeadline = 'Deadline ';
    final lblLabels = 'Labels ';
    final lblComments = 'Comments ';
    final lblTasks = 'Tasks ';
    final labelWidth = maxPaddedLabelWidth([
      lblStoryType,
      lblId,
      lblState,
      lblEpic,
      lblIteration,
      lblOwnedBy,
      lblTeam,
      lblEstimate,
      lblDeadline,
      lblLabels,
      lblComments,
      lblTasks,
    ]);

    sb.write(env.style(lblStoryType.padLeft(labelWidth), this));
    sb.writeln(env.style(name.value, styleTitle, styles: [styleUnderline]));

    final storyId = idString;
    sb.write(env.style(lblId.padLeft(labelWidth), this));
    sb.writeln(storyId);

    final state = data[ScString('workflow_state_id')];
    if (state is ScWorkflowState) {
      final stateName = state.data[ScString('name')];
      if (stateName is ScString) {
        final type = state.data[ScString('type')];
        if (type is ScString) {
          final ts = type.value;
          String color = styleUnstarted;
          switch (ts) {
            case 'unstarted':
              color = styleUnstarted;
              break;
            case 'started':
              color = styleStarted;
              break;
            case 'done':
              color = styleDone;
              break;
          }
          sb.write(env.style(lblState.padLeft(labelWidth), this));
          sb.write(env.style(stateName.value, color));
          sb.write(" ${state.readableString(env)}");
        }
      }
    }
    sb.writeln();

    final epic = data[ScString('epic_id')];
    if (epic != ScNil()) {
      sb.write(env.style(lblEpic.padLeft(labelWidth), this));
      if (epic is ScEpic) {
        sb.write(epic.inlineSummary(env));
      } else if (epic is ScNumber) {
        final epicEntity = ScEpic(ScString(epic.value.toString()));
        waitOn(epicEntity.fetch(env));
        sb.write(epicEntity.inlineSummary(env));
      }
      sb.writeln();
    }

    final iteration = data[ScString('iteration_id')];
    if (iteration != ScNil()) {
      sb.write(env.style(lblIteration.padLeft(labelWidth), this));
      if (iteration is ScIteration) {
        sb.write(iteration.inlineSummary(env));
      } else if (iteration is ScNumber) {
        final iterationEntity =
            ScIteration(ScString(iteration.value.toString()));
        waitOn(iterationEntity.fetch(env));
        sb.write(iterationEntity.inlineSummary(env));
      }
      sb.writeln();
    }

    final owners = data[ScString('owner_ids')] as ScList;
    if (owners.isNotEmpty) {
      sb.write(env.style(lblOwnedBy.padLeft(labelWidth), this));
      if (owners.length == 1) {
        final owner = owners[0];
        if (owner is ScMember) {
          sb.writeln(owner.inlineSummary(env));
        }
      } else {
        var isFirst = true;
        for (final owner in owners.innerList) {
          if (owner is ScMember) {
            if (isFirst) {
              isFirst = false;
              sb.writeln(owner.inlineSummary(env));
            } else {
              sb.writeln(
                  '${"".padLeft(labelWidth)}${owner.inlineSummary(env)}');
            }
          }
        }
      }
    }

    final team = data[ScString('group_id')];
    if (team != ScNil()) {
      sb.write(env.style(lblTeam.padLeft(labelWidth), this));
      if (team is ScTeam) {
        sb.write(team.inlineSummary(env));
      } else if (team is ScString) {
        final teamEntity = ScTeam(ScString(team.value));
        waitOn(teamEntity.fetch(env));
        sb.write(teamEntity.inlineSummary(env));
      }
      sb.writeln();
    }

    final estimate = data[ScString('estimate')];
    if (estimate is ScNumber) {
      sb.write(env.style(lblEstimate.padLeft(labelWidth), this));
      if (estimate == ScNumber(1)) {
        sb.write("$estimate point");
      } else {
        sb.write("$estimate points");
      }
      sb.writeln();
    }

    final deadline = data[ScString('deadline')];
    if (deadline is ScString) {
      sb.write(env.style(lblDeadline.padLeft(labelWidth), this));
      sb.write(deadline);
      sb.writeln();
    }

    final labels = data[ScString('labels')];
    if (labels is ScList && labels.isNotEmpty) {
      sb.write(env.style(lblLabels.padLeft(labelWidth), this));
      for (var i = 0; i < labels.length; i++) {
        final label = labels[i];
        if (label is ScMap) {
          final name = label[ScString('name')];
          if (name is ScString) {
            final color = label[ScString('color')];
            if (color is ScString) {
              final colorHex = color.value.substring(1); // has leading #
              final rgb = ColorUtils.hex2rgb(colorHex);
              sb.write(chalk.rgb(rgb[0], rgb[1], rgb[2])("⚫"));
            }
            sb.write(name.value);
          }
          if (i + 1 != labels.length) {
            sb.write(', ');
          }
        }
      }
      sb.writeln();
    }

    final comments = data[ScString('comments')];
    if (comments is ScList) {
      if (comments.isNotEmpty) {
        int numComments = 0;
        ScDateTime? latestCommentDt;
        for (final comment in comments.innerList) {
          if (comment is ScComment) {
            numComments++;
            final commentCreatedAt = comment.data[ScString('created_at')];
            if (commentCreatedAt is ScDateTime) {
              if (latestCommentDt == null) {
                latestCommentDt = commentCreatedAt;
              } else {
                if (latestCommentDt.value.isBefore(commentCreatedAt.value)) {
                  latestCommentDt = commentCreatedAt;
                }
              }
            }
          }
        }
        sb.write(env.style(lblComments.padLeft(labelWidth), this));
        if (numComments == 1) {
          sb.write("$numComments comment");
        } else {
          sb.write("$numComments comments");
        }
        if (latestCommentDt != null) {
          sb.write(
              ", latest ${ScFnDateTimeField.weekdays[latestCommentDt.value.weekday]!.value} $latestCommentDt");
        }
        sb.writeln();
      }
    }

    final tasks = data[ScString('tasks')];
    if (tasks != null) {
      final ts = tasks as ScList;
      var numComplete = 0;
      for (final task in ts.innerList) {
        final t = task as ScTask;
        final isComplete = t.data[ScString('complete')];
        if (isComplete == ScBoolean.veritas()) {
          numComplete++;
        }
      }
      if (ts.length > 0) {
        sb.write(env.style(lblTasks.padLeft(labelWidth), this));
        sb.writeln('$numComplete/${ts.length} complete:');
        for (final task in ts.innerList) {
          final t = task as ScTask;
          final isComplete = t.data[ScString('complete')];
          var prefix = '';
          if (isComplete is ScBoolean) {
            if (isComplete == ScBoolean.veritas()) {
              prefix = env.style("[DONE] ", styleDone);
            } else if (isComplete == ScBoolean.falsitas()) {
              prefix = env.style("[TODO] ", styleUnstarted);
            }
          }
          sb.writeln("${''.padLeft(labelWidth)}$prefix${t.inlineSummary(env)}");
        }
      }
    }

    env.out.write(sb.toString());
    return ScNil();
  }
}

class ScTask extends ScEntity {
  ScTask(this.storyId, ScString taskId) : super(taskId);
  final ScString storyId;

  @override
  String get shortFnName => 'tk';

  @override
  String typeName() {
    return 'task';
  }

  static Set<String> fieldsForCreate = {
    'complete',
    'created_at',
    'description',
    'external_id',
    'owner_ids',
    'updated_at',
  };

  static Set<String> fieldsForUpdate = {
    'after_id',
    'before_id',
    'complete',
    'description',
    'owner_ids',
  };

  factory ScTask.fromMap(
      ScEnv env, ScString storyId, Map<String, dynamic> data) {
    return ScTask(storyId, ScString(data['id'].toString())).addAll(env, data)
        as ScTask;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) {
    throw UnimplementedError();
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final task =
        await env.client.updateTask(env, storyId.value, idString, updateMap);
    data = task.data;
    return this;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final task = await env.client.getTask(env, storyId.value, idString);
    data = task.data;
    return this;
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final description = dataFieldOr<ScString?>(data, 'description', title) ??
          ScString("<No description: run fetch>");
      final shortDescription = truncate(description.value, env.displayWidth);
      final complete =
          dataFieldOr<ScBoolean>(data, 'complete', ScBoolean.falsitas());
      String? status;
      if (complete == ScBoolean.veritas()) {
        status = env.style("[DONE]", styleDone);
      } else if (complete == ScBoolean.falsitas()) {
        status = env.style("[TODO]", styleUnstarted);
      }

      final sb = StringBuffer();
      sb.write(readableString(env));

      final cmt = comment(env);
      sb.write(' $cmt');

      if (status != null) {
        sb.write(' $status');
      }

      sb.write(' ' + env.style(shortDescription, styleTitle));

      return sb.toString();
    }
  }

  @override
  String readableString(ScEnv env) {
    final lp = lParen(env);
    final rp = rParen(env);

    final fnName = env.style(shortFnName, this);
    return "$lp$fnName ${storyId.value} $idString$rp";
  }
}

class ScComment extends ScEntity {
  ScComment(this.storyId, ScString commentId) : super(commentId);
  final ScString storyId;

  @override
  String get shortFnName => 'cm';

  @override
  String typeName() {
    return 'comment';
  }

  static final Set<String> fieldsForCreate = {
    'author_id',
    'created_at',
    'external_id',
    'parent_id',
    'text',
    'updated_at',
  };

  static final Set<String> fieldsForUpdate = {
    'text',
  };

  ScString? get parentId {
    final i = data[ScString('parent_id')];
    if (i is ScComment) {
      return ScString(i.idString);
    } else if (i is ScNumber) {
      return ScString(i.value.toString());
    } else if (i is ScString) {
      return i;
    }
    return null;
  }

  factory ScComment.fromMap(
      ScEnv env, ScString storyId, Map<String, dynamic> data) {
    return ScComment(storyId, ScString(data['id'].toString())).addAll(env, data)
        as ScComment;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) {
    throw OperationNotSupported(
        "Comments have nothing meaningful to list. Try `${ScFnDetails().canonicalName}` for a subset or `${ScFnData().canonicalName}` if you want to see everything about your task.");
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final comment =
        await env.client.updateComment(env, storyId.value, idString, updateMap);
    data = comment.data;
    return this;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final comment = await env.client.getComment(env, storyId.value, idString);
    data = comment.data;
    return this;
  }

  @override
  String readableString(ScEnv env) {
    final lp = lParen(env);
    final rp = rParen(env);

    final fnName = env.style(shortFnName, this);
    return "$lp$fnName ${storyId.value} $idString$rp";
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final sb = StringBuffer();
      final text = dataFieldOr<ScString?>(data, 'text', title) ??
          ScString("<No text: run fetch>");
      final cmt = comment(env);
      // final shortDescription = truncate(text.value, env.displayWidth);

      final parentId = data[ScString('parent_id')];

      final readable = readableString(env);
      if (parentId != ScNil()) {
        sb.write("  $readable");
      } else {
        sb.write(readable);
      }
      sb.write(" $cmt");

      final author = data[ScString('author_id')];
      if (author is ScMember) {
        sb.write(env.style(
            " @${author.mentionName?.value ?? '<No mention name: run fetch>'}",
            styleMemberMention));
      }

      final createdAt = data[ScString('created_at')];
      if (createdAt is ScDateTime) {
        final dateTime = createdAt.value;
        final local = dateTime.toLocal();
        sb.write(env.style(" ${local.toString()}", styleDateTime));
      }

      var indent = '';
      if (parentId != ScNil()) {
        indent = '  ';
      }
      final formattedText = wrap(text.value, 100, "  $indent$cmt ");
      sb.writeln("\n$formattedText");
      return sb.toString();
    }
  }
}

class ScEpicComment extends ScEntity {
  ScEpicComment(this.epicId, ScString commentId) : super(commentId);
  final ScString epicId;
  ScString? parentId;
  int level = 0;

  @override
  String get shortFnName => 'ec';

  @override
  String typeName() {
    return 'epic comment';
  }

  static final Set<String> fieldsForCreate = {
    'author_id',
    'created_at',
    'external_id',
    'text',
    'updated_at',
  };

  static final Set<String> fieldsForUpdate = {
    'text',
  };

  factory ScEpicComment.fromMap(
      ScEnv env, ScString epicId, Map<String, dynamic> data,
      {commentLevel = 0, ScString? parentId}) {
    var epicCommentsData = data['comments'] ?? [];
    ScList epicComments = ScList([]);
    if (epicCommentsData.isNotEmpty) {
      epicComments = ScList(List<ScExpr>.from(epicCommentsData.map(
          (commentMap) => ScEpicComment.fromMap(env, epicId, commentMap,
              commentLevel: commentLevel + 1,
              parentId: ScString(data['id'].toString())))));
    }
    data.remove('comments');
    final epicComment = ScEpicComment(epicId, ScString(data['id'].toString()))
        .addAll(env, data) as ScEpicComment;
    epicComment.level = commentLevel;
    epicComment.data[ScString('comments')] = epicComments;
    if (parentId != null) {
      epicComment.parentId = parentId;
    }
    return epicComment;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) {
    throw OperationNotSupported(
        "Epic comments have nothing meaningful to list. Try `${ScFnDetails().canonicalName}` for a subset or `${ScFnData().canonicalName}` if you want to see everything about your task.");
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final comment = await env.client
        .updateEpicComment(env, epicId.value, idString, updateMap);
    data = comment.data;
    return this;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final comment =
        await env.client.getEpicComment(env, epicId.value, idString);
    data = comment.data;
    return this;
  }

  @override
  String readableString(ScEnv env) {
    final lp = lParen(env);
    final rp = rParen(env);

    final fnName = env.style(shortFnName, this);
    return "$lp$fnName ${epicId.value} $idString$rp";
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final sb = StringBuffer();
      final text = dataFieldOr<ScString?>(data, 'text', title) ??
          ScString("<No text: run fetch>");
      final cmt = comment(env);
      // final shortDescription = truncate(text.value, env.displayWidth);

      final readable = readableString(env);
      if (level == 0) {
        sb.write(readable);
      } else {
        // Because this is called recursively from this method, we have to add
        // the default indentation that level 0 gets from being an ScList value.
        sb.write("  ${'  ' * level}$readable");
      }

      sb.write(" $cmt");

      final author = data[ScString('author_id')];
      if (author is ScMember) {
        sb.write(env.style(
            " @${author.mentionName?.value ?? '<No mention name: run fetch>'}",
            styleMemberMention));
      }

      final createdAt = data[ScString('created_at')];
      if (createdAt is ScDateTime) {
        final dateTime = createdAt.value;
        final local = dateTime.toLocal();
        sb.write(env.style(" ${local.toString()}", styleDateTime));
      }

      final formattedText = wrap(text.value, 100, "  ${'  ' * level}$cmt ");
      sb.writeln("\n$formattedText");

      final epicComments = data[ScString('comments')];
      if (epicComments is ScList) {
        if (epicComments.isNotEmpty) {
          for (final epicComment in epicComments.innerList) {
            if (epicComment is ScEpicComment) {
              sb.writeln(epicComment.printToString(env));
            }
          }
        }
      }
      return sb.toString();
    }
  }
}

class ScIteration extends ScEntity {
  ScIteration(ScString id) : super(id);

  @override
  String get shortFnName => 'it';

  @override
  String typeName() {
    return 'iteration';
  }

  static final Set<String> fieldsForCreate = {
    'description',
    'end_date',
    'follower_ids',
    'group_ids',
    'labels',
    'name',
    'start_date',
  };
  static final Set<String> fieldsForUpdate = {
    'description',
    'end_date',
    'follower_ids',
    'group_ids',
    'labels',
    'name',
    'start_date',
  };

  factory ScIteration.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScIteration(ScString(data['id'].toString())).addAll(env, data)
        as ScIteration;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) {
    return env.client.getStoriesInIteration(env, idString);
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final iteration =
        await env.client.updateIteration(env, idString, updateMap);
    data = iteration.data;
    return this;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final iteration = await env.client.getIteration(env, idString);
    data = iteration.data;
    return this;
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final name = dataFieldOr<ScString?>(data, 'name', title) ??
          ScString("<No name: run fetch>");
      final shortName = truncate(name.value, env.displayWidth);
      final iterationName = env.style(shortName, styleTitle);
      final iterationId = idString;
      final iterationFnName = env.style('it', this);

      final iterationStatus = data[ScString('status')];
      String iterationStatusStr = '';
      if (iterationStatus is ScString) {
        final state = iterationStatus.value;
        switch (state) {
          case 'unstarted':
            iterationStatusStr = env.style('[U]', styleUnstarted);
            break;
          case 'started':
            iterationStatusStr = env.style('[S]', styleStarted);
            break;
          case 'done':
            iterationStatusStr = env.style('[D]', styleDone);
            break;
        }
      }

      final stats = data[ScString('stats')];
      String pointsStr = '';
      String storiesStr = '';
      if (stats is ScMap) {
        final numStoriesUnstarted = stats[ScString('num_stories_unstarted')];
        final numStoriesStarted = stats[ScString('num_stories_started')];
        final numStoriesDone = stats[ScString('num_stories_done')];
        if (numStoriesUnstarted is ScNumber &&
            numStoriesStarted is ScNumber &&
            numStoriesDone is ScNumber) {
          // final numStoriesDoneStr = numStoriesDone.toString().padLeft(2);
          final numStoriesDoneStr = numStoriesDone.toString();
          final numStories =
              numStoriesUnstarted.add(numStoriesStarted).add(numStoriesDone);
          // final numStoriesStr = numStories.toString().padRight(2);
          final numStoriesStr = numStories.toString();
          storiesStr =
              env.style("[$numStoriesDoneStr/${numStoriesStr}S]", styleStory);
        }

        final numPoints = stats[ScString('num_points')];
        final numPointsDone = stats[ScString('num_points_done')];
        if (numPoints is ScNumber) {
          if (numPointsDone is ScNumber) {
            // final numPointsDoneStr = numPointsDone.toString().padLeft(2);
            final numPointsDoneStr = numPointsDone.toString();
            // final numPointsStr = numPoints.toString().padRight(2);
            final numPointsStr = numPoints.toString();
            pointsStr =
                env.style("[$numPointsDoneStr/${numPointsStr}P]", styleNumber);
          }
        }
      }

      final prefix = '$iterationStatusStr$storiesStr$pointsStr';
      final lp = lParen(env);
      final rp = rParen(env);
      final cmt = comment(env);
      final readable = "$lp$iterationFnName $iterationId$rp";
      // .padRight(39); // adjusted for ANSI codes
      final iterationStr = "$readable $cmt $prefix $iterationName";
      return iterationStr;
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    if (!data.containsKey(ScString('description'))) {
      waitOn(fetch(env));
    }

    final lblIteration = 'Iteration ';
    final lblId = 'Id ';
    final lblTeams = 'Teams ';
    final lblStart = 'Start ';
    final lblEnd = 'End ';
    final lblStatus = 'Status ';
    final lblPoints = 'Points ';
    final labelWidth = maxPaddedLabelWidth([
      lblIteration,
      lblId,
      lblTeams,
      lblStart,
      lblEnd,
      lblStatus,
      lblPoints,
    ]);

    final sb = StringBuffer('\n');
    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    sb.write(env.style(lblIteration.padLeft(labelWidth), this));
    sb.writeln(env.style(name.value, styleTitle, styles: [styleUnderline]));

    final epicId = idString;
    sb.write(env.style(lblId.padLeft(labelWidth), this));
    sb.writeln(epicId);

    final teams = data[ScString('group_ids')] as ScList;
    if (teams.isNotEmpty) {
      sb.write(env.style(lblTeams.padLeft(labelWidth), this));
      if (teams.length == 1) {
        final team = teams[0];
        if (team is ScTeam) {
          sb.writeln(team.inlineSummary(env));
        }
      } else {
        var isFirst = true;
        for (final team in teams.innerList) {
          if (team is ScTeam) {
            if (isFirst) {
              isFirst = false;
              sb.writeln(team.inlineSummary(env));
            } else {
              sb.writeln('${"".padLeft(labelWidth)}${team.inlineSummary(env)}');
            }
          }
        }
      }
    }

    final startDate = data[ScString('start_date')];
    if (startDate is ScString) {
      sb.write(env.style(lblStart.padLeft(labelWidth), this));
      sb.writeln(startDate.value);
    }

    final endDate = data[ScString('end_date')];
    if (endDate is ScString) {
      sb.write(env.style(lblEnd.padLeft(labelWidth), this));
      sb.writeln(endDate.value);
    }

    final status = data[ScString('status')];
    if (status is ScString) {
      sb.write(env.style(lblStatus.padLeft(labelWidth), this));
      sb.writeln(status.value);
    }

    final stats = data[ScString('stats')];
    if (stats is ScMap) {
      final numPoints = stats[ScString('num_points')];
      final numPointsDone = stats[ScString('num_points_done')];
      if (numPoints is ScNumber) {
        if (numPointsDone is ScNumber) {
          sb.write(env.style(lblPoints.padLeft(labelWidth), this));
          sb.write("$numPointsDone/$numPoints points done");
        }
      }
    }
    sb.writeln();

    env.out.write(sb.toString());
    return ScNil();
  }
}

class ScLabel extends ScEntity {
  ScLabel(ScString id) : super(id);

  @override
  String typeName() {
    return 'label';
  }

  @override
  String get shortFnName => 'lb';

  static final Set<String> fieldsForCreate = {
    'color',
    'description',
    'external_id',
    'name',
  };

  static final Set<String> fieldsForUpdate = {
    'archived',
    'color',
    'description',
    'name',
  };

  factory ScLabel.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScLabel(ScString(data['id'].toString())).addAll(env, data)
        as ScLabel;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final label = await env.client.getLabel(env, idString);
    data = label.data;
    return this;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) {
    return env.client.getStoriesWithLabel(env, idString);
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final label = await env.client.updateLabel(env, idString, updateMap);
    data = label.data;
    return this;
  }

  @override
  String printToString(ScEnv env) {
    final sb = StringBuffer();
    sb.write(readableString(env));

    final cmt = comment(env);
    sb.write(' $cmt');

    final color = data[ScString('color')];
    if (color is ScString) {
      final colorHex = color.value.substring(1); // has leading #
      final rgb = ColorUtils.hex2rgb(colorHex);
      sb.write(chalk.rgb(rgb[0], rgb[1], rgb[2])(" ⚫"));
    } else {
      sb.write(' ');
    }
    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    sb.write(env.style(name.value, styleTitle));

    return sb.toString();
  }

  @override
  ScExpr printSummary(ScEnv env) {
    if (!data.containsKey(ScString('description'))) {
      waitOn(fetch(env));
    }

    final lblLabel = 'Label ';
    final lblId = 'Id ';
    final lblColor = 'Color ';
    final lblDescription = 'Description ';
    final labelWidth = maxPaddedLabelWidth([
      lblLabel,
      lblId,
      lblColor,
      lblDescription,
    ]);

    final sb = StringBuffer('\n');

    final name = data[ScString('name')];
    if (name is ScString) {
      sb.write(env.style(lblLabel.padLeft(labelWidth), this));
      sb.write(name.value);
      sb.writeln();
    }

    sb.write(env.style(lblId.padLeft(labelWidth), this));
    if (id is ScString) {
      final i = id as ScString;
      sb.write(i.value);
    } else {
      sb.write(id.toString());
    }
    sb.writeln();

    final color = data[ScString('color')];
    if (color is ScString) {
      sb.write(env.style(lblColor.padLeft(labelWidth), this));

      final colorHex = color.value.substring(1); // has leading #
      final rgb = ColorUtils.hex2rgb(colorHex);
      sb.write(chalk.rgb(rgb[0], rgb[1], rgb[2])("⚫"));
      sb.write(' ${color.value}');
      sb.writeln();
    }

    env.out.write(sb.toString());

    return ScNil();
  }
}

class ScWorkflow extends ScEntity {
  ScWorkflow(ScString id) : super(id);

  @override
  String get shortFnName => 'wf';

  factory ScWorkflow.fromMap(ScEnv env, Map<String, dynamic> data) {
    final statesData = data['states'] as List;
    ScList states = ScList([]);
    if (statesData.isNotEmpty) {
      states = ScList(statesData
          .map((stateMap) => ScWorkflowState.fromMap(env, stateMap))
          .toList());
    }
    data.remove('states');
    final workflow = ScWorkflow(ScString(data['id'].toString()))
        .addAll(env, data) as ScWorkflow;
    workflow.data[ScString('states')] = states;
    return workflow;
  }

  @override
  String typeName() {
    return 'workflow';
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final workflow = await env.client.getWorkflow(env, idString);
    data = workflow.data;
    return this;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    final states = data[ScString('states')];
    if (states is ScList) {
      return Future<ScList>.value(states);
    } else {
      return ScList([]);
    }
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) {
    throw OperationNotSupported(
        "You cannot update a workflow via the Shortcut API.");
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final name = dataFieldOr<ScString?>(data, 'name', title) ??
          ScString("<No name: run fetch>");
      final shortName = truncate(name.value, env.displayWidth);

      final sb = StringBuffer();

      sb.write(readableString(env));

      final cmt = comment(env);
      sb.write(' $cmt ');
      sb.write(env.style(shortName, styleTitle));
      final states = data[ScString('states')];
      if (states is ScList) {
        final numStates = states.length;
        sb.write(env.style(' [$numStates states]', styleWorkflowState));
      }
      return sb.toString();
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    final lblWorkflow = 'Workflow ';
    final lblId = 'Id ';
    final lblDefaultState = 'Default State ';
    final lblStates = 'States ';
    int labelWidth = maxPaddedLabelWidth([lblWorkflow, lblId, lblStates]);

    if (!data.containsKey(ScString('description'))) {
      waitOn(fetch(env));
    }
    final sb = StringBuffer('\n');

    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    sb.write(env.style(lblWorkflow.padLeft(labelWidth), this));
    sb.writeln(env.style(name.value, styleTitle, styles: [styleUnderline]));

    final workflowId = idString;
    sb.write(env.style(lblId.padLeft(labelWidth), this));
    sb.writeln(workflowId);

    sb.write(env.style(lblDefaultState.padLeft(labelWidth), this));
    final defaultWorkflowStateId =
        data[ScString('default_state_id')] as ScNumber;
    final epicStates = data[ScString('states')] as ScList;
    for (final epicState in epicStates.innerList) {
      final es = epicState as ScEpicWorkflowState;
      if (int.tryParse(es.idString) == defaultWorkflowStateId.value) {
        sb.writeln(es.inlineSummary(env));
        break;
      }
    }

    final states = data[ScString('states')] as ScList;
    sb.write(env.style(lblStates.padLeft(labelWidth), this));
    var isFirst = true;
    for (final state in states.innerList) {
      if (state is ScWorkflowState) {
        final type = state.data[ScString('type')];
        String typeStr = '';
        if (type is ScString) {
          final ts = type.value;
          String color = styleUnstarted;
          switch (ts) {
            case 'unstarted':
              color = styleUnstarted;
              break;
            case 'started':
              color = styleStarted;
              break;
            case 'done':
              color = styleDone;
              break;
          }
          typeStr = env.style('[${ts.substring(0, 1).toUpperCase()}]', color);
        }

        if (isFirst) {
          isFirst = false;
          sb.writeln("$typeStr ${state.inlineSummary(env)}");
        } else {
          sb.writeln(
              '${"".padLeft(labelWidth)}$typeStr ${state.inlineSummary(env)}');
        }
      }
    }

    env.out.write(sb.toString());
    return ScNil();
  }
}

class ScWorkflowState extends ScEntity {
  ScWorkflowState(ScString id) : super(id);

  @override
  String get shortFnName => '';

  factory ScWorkflowState.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScWorkflowState(ScString(data['id'].toString())).addAll(env, data)
        as ScWorkflowState;
  }

  @override
  String typeName() {
    return 'workflow state';
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    env.err.writeln(env.style(
        ";; [WARN] To fetch a workflow state, fetch its workflow instead.",
        styleWarn));
    return this;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    throw UnimplementedError();
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) {
    throw OperationNotSupported(
        "You cannot update a workflow state via the Shortcut API.");
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final name = dataFieldOr<ScString?>(data, 'name', title) ??
          ScString("<No name: run fetch>");
      final shortName = truncate(name.value, env.displayWidth);
      final type = data[ScString('type')];
      String typeStr = '';
      if (type is ScString) {
        final ts = type.value;
        String color = styleUnstarted;
        switch (ts) {
          case 'unstarted':
            color = styleUnstarted;
            break;
          case 'started':
            color = styleStarted;
            break;
          case 'done':
            color = styleDone;
            break;
        }
        typeStr = env.style('[${ts.substring(0, 1).toUpperCase()}]', color);
      }

      final sb = StringBuffer();
      sb.write(readableString(env));

      final cmt = comment(env);
      sb.write(' $cmt');
      sb.write(env.style(' [Workflow State]', this));
      if (typeStr.isNotEmpty) {
        sb.write(typeStr);
      }
      sb.write(env.style(' $shortName', styleTitle));

      return sb.toString();
    }
  }
}

class ScEpicWorkflow extends ScEntity {
  ScEpicWorkflow(ScString id) : super(id);

  @override
  String get shortFnName => 'ew';

  factory ScEpicWorkflow.fromMap(ScEnv env, Map<String, dynamic> data) {
    final statesData = data['epic_states'] as List;
    ScList states = ScList([]);
    if (statesData.isNotEmpty) {
      states = ScList(statesData
          .map((stateMap) => ScEpicWorkflowState.fromMap(env, stateMap))
          .toList());
    }
    data.remove('states');
    final epicWorkflow = ScEpicWorkflow(ScString(data['id'].toString()))
        .addAll(env, data) as ScEpicWorkflow;
    epicWorkflow.data[ScString('epic_states')] = states;
    return epicWorkflow;
  }

  @override
  String typeName() {
    return 'epic workflow';
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final epicWorkflow = await env.client.getEpicWorkflow(env);
    data = epicWorkflow.data;
    return this;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    final states = data[ScString('epic_states')];
    if (states is ScList) {
      return Future<ScList>.value(states);
    } else {
      return ScList([]);
    }
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) {
    throw OperationNotSupported(
        "You cannot update the epic workflow via the Shortcut API.");
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final name = 'Workspace-wide Epic Workflow';
      final shortName = truncate(name, env.displayWidth);

      final sb = StringBuffer();

      sb.write(readableString(env));

      final cmt = comment(env);
      sb.write(' $cmt ');
      sb.write(env.style(shortName, styleTitle));
      final states = data[ScString('epic_states')];
      if (states is ScList) {
        final numStates = states.length;
        sb.write(env.style(' [$numStates states]', styleEpicWorkflowState));
      }
      return sb.toString();
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    final lblWorkflow = 'Epic Workflow ';
    final lblId = 'Id ';
    final lblDefaultState = 'Default State ';
    final lblStates = 'States ';
    int labelWidth =
        maxPaddedLabelWidth([lblWorkflow, lblId, lblDefaultState, lblStates]);

    if (!data.containsKey(ScString('description'))) {
      waitOn(fetch(env));
    }
    final sb = StringBuffer('\n');

    final name = 'Workspace-wide Epic Workflow';
    sb.write(env.style(lblWorkflow.padLeft(labelWidth), this));
    sb.writeln(env.style(name, styleTitle, styles: [styleUnderline]));

    final workflowId = idString;
    sb.write(env.style(lblId.padLeft(labelWidth), this));
    sb.writeln(workflowId);

    sb.write(env.style(lblDefaultState.padLeft(labelWidth), this));
    final defaultEpicWorkflowStateId =
        data[ScString('default_epic_state_id')] as ScNumber;
    final epicStates = data[ScString('epic_states')] as ScList;
    for (final epicState in epicStates.innerList) {
      final es = epicState as ScEpicWorkflowState;
      if (int.tryParse(es.idString) == defaultEpicWorkflowStateId.value) {
        sb.writeln(es.inlineSummary(env));
        break;
      }
    }

    final states = data[ScString('epic_states')] as ScList;
    sb.write(env.style(lblStates.padLeft(labelWidth), this));
    var isFirst = true;
    for (final state in states.innerList) {
      if (state is ScEpicWorkflowState) {
        final type = state.data[ScString('type')];
        String typeStr = '';
        if (type is ScString) {
          final ts = type.value;
          String color = styleUnstarted;
          switch (ts) {
            case 'unstarted':
              color = styleUnstarted;
              break;
            case 'started':
              color = styleStarted;
              break;
            case 'done':
              color = styleDone;
              break;
          }
          typeStr = env.style('[${ts.substring(0, 1).toUpperCase()}]', color);
        }

        if (isFirst) {
          isFirst = false;
          sb.writeln("$typeStr ${state.inlineSummary(env)}");
        } else {
          sb.writeln(
              '${"".padLeft(labelWidth)}$typeStr ${state.inlineSummary(env)}');
        }
      }
    }

    env.out.write(sb.toString());
    return ScNil();
  }
}

class ScEpicWorkflowState extends ScEntity {
  ScEpicWorkflowState(ScString id) : super(id);

  @override
  String get shortFnName => '';

  factory ScEpicWorkflowState.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScEpicWorkflowState(ScString(data['id'].toString()))
        .addAll(env, data) as ScEpicWorkflowState;
  }

  @override
  String typeName() {
    return 'epic workflow state';
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    env.err.writeln(env.style(
        ";; [WARN] To fetch an epic workflow state, fetch its workflow instead.",
        styleWarn));
    return this;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    env.err.writeln(env.style(
        "[WARN] Epic workflow states have nothing meaningful to list. Try `${ScFnDetails().canonicalName}` for a subset or `${ScFnData().canonicalName}` if you want to see everything about your task.",
        styleWarn));
    return ScList([]);
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) {
    throw OperationNotSupported(
        "You cannot update an epic workflow state via the Shortcut API.");
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final name = dataFieldOr<ScString?>(data, 'name', title) ??
          ScString("<No name: run fetch>");
      final shortName = truncate(name.value, env.displayWidth);
      final type = data[ScString('type')];
      String typeStr = '';
      if (type is ScString) {
        final ts = type.value;
        String color = styleUnstarted;
        switch (ts) {
          case 'unstarted':
            color = styleUnstarted;
            break;
          case 'started':
            color = styleStarted;
            break;
          case 'done':
            color = styleDone;
            break;
        }
        typeStr = env.style('[${ts.substring(0, 1).toUpperCase()}]', color);
      }

      final sb = StringBuffer();
      sb.write(readableString(env));

      final cmt = comment(env);
      sb.write(' $cmt');
      sb.write(env.style(' [Epic Workflow State]', this));
      if (typeStr.isNotEmpty) {
        sb.write(typeStr);
      }
      sb.write(env.style(' $shortName', styleTitle));

      return sb.toString();
    }
  }
}

class ScCustomField extends ScEntity {
  ScCustomField(ScString id) : super(id);

  @override
  String get shortFnName => 'cf';

  factory ScCustomField.fromMap(ScEnv env, Map<String, dynamic> data) {
    final customField = ScCustomField(ScString(data['id'].toString()))
        .addAll(env, data) as ScCustomField;
    return customField;
  }

  @override
  String typeName() {
    return 'custom field';
  }

  ScString? get canonicalName {
    final canonicalName = data[ScString('canonical_name')];
    if (canonicalName is ScString) {
      return canonicalName;
    }
    return null;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final customField = await env.client.getCustomField(env, idString);
    data = customField.data;
    return this;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    final values = data[ScString('values')];
    if (values is ScList) {
      return Future<ScList>.value(values);
    } else {
      return ScList([]);
    }
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final customField =
        await env.client.updateCustomField(env, idString, updateMap);
    data = customField.data;
    return this;
  }

  @override
  String readableString(ScEnv env) {
    final lp = lParen(env);
    final rp = rParen(env);
    final fnName = env.style(shortFnName, this);
    return "$lp$fnName $id$rp";
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final name = dataFieldOr<ScString?>(data, 'name', title) ??
          ScString("<No name: run fetch>");
      final shortName = truncate(name.value, env.displayWidth);

      final sb = StringBuffer();

      sb.write(readableString(env));

      final cmt = comment(env);
      sb.write(' $cmt ');
      sb.write(env.style(shortName, styleTitle));
      final states = data[ScString('states')];
      if (states is ScList) {
        final numStates = states.length;
        sb.write(env.style(' [$numStates states]', styleWorkflowState));
      }
      return sb.toString();
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    final lblName = 'Field Name ';
    final lblId = 'Id ';
    final lblEnabled = 'Enabled? ';
    final lblFieldType = 'Field Type ';
    final lblValues = 'Values ';
    int labelWidth = maxPaddedLabelWidth([
      lblName,
      lblId,
      lblEnabled,
      lblFieldType,
      lblValues,
    ]);

    if (!data.containsKey(ScString('name'))) {
      waitOn(fetch(env));
    }

    final sb = StringBuffer('\n');

    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    final canonicalName = data[ScString('canonical_name')];
    sb.write(env.style(lblName.padLeft(labelWidth), this));
    sb.write(env.style(name.value, styleTitle, styles: [styleUnderline]));
    if (canonicalName is ScString) {
      sb.write(env.style(" (${canonicalName.value})", styleTitle,
          styles: [styleUnderline]));
    }
    sb.writeln();

    sb.write(env.style(lblId.padLeft(labelWidth), this));
    sb.writeln(id);

    final isEnabled = data[ScString('enabled')];
    if (isEnabled is ScBoolean) {
      sb.write(env.style(lblEnabled.padLeft(labelWidth), this));
      if (isEnabled == ScBoolean.veritas()) {
        sb.writeln(env.style('Yes', styleBoolean));
      } else {
        sb.writeln(env.style('No', styleBoolean));
      }
    }

    final values = data[ScString('values')] as ScList;
    sb.write(env.style(lblValues.padLeft(labelWidth), this));
    var isFirst = true;
    for (final value in values.innerList) {
      if (value is ScCustomFieldEnumValue) {
        if (isFirst) {
          isFirst = false;
          sb.writeln(value.inlineSummary(env));
        } else {
          sb.writeln('${"".padLeft(labelWidth)}${value.inlineSummary(env)}');
        }
      }
    }

    env.out.write(sb.toString());
    return ScNil();
  }
}

class ScCustomFieldEnumValue extends ScEntity {
  ScCustomFieldEnumValue(ScString id) : super(id);

  @override
  String get shortFnName => '';

  factory ScCustomFieldEnumValue.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScCustomFieldEnumValue(ScString(data['id'].toString()))
        .addAll(env, data) as ScCustomFieldEnumValue;
  }

  @override
  String typeName() {
    return 'custom field enum value';
  }

  @override
  String readableString(ScEnv env) {
    final lp = lParen(env);
    final rp = rParen(env);
    return "${lp}id $id$rp";
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    env.err.writeln(env.style(
        ";; [WARN] To fetch a custom field enum value, fetch the custom field itself instead.",
        styleWarn));
    return this;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    throw UnimplementedError();
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) {
    throw OperationNotSupported(
        "You cannot update a custom field enum value via the Shortcut API.");
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      final value = dataFieldOr<ScString?>(data, 'value', title) ??
          ScString("<No value: run fetch>");

      final sb = StringBuffer();
      sb.write(readableString(env));

      final cmt = comment(env);
      sb.write(' $cmt');
      sb.write(env.style(' [Custom Field Enum Value]', this));
      sb.write(env.style(' ${value.value}', styleTitle));

      return sb.toString();
    }
  }
}

/// Functions

Future<void> fetchParentAsync(ScEnv env, ScEntity parentEntity) {
  env.out.writeln(env.style(
      ";; [INFO] Fetching your parent entity from the last session...",
      styleInfo));
  return parentEntity.fetch(env).then((value) {
    env.out.writeln(env.style(";; [INFO] Parent entity fetched.", styleInfo));
  });
}

ScExpr fetchAndSetParentEntity(ScEnv env, ScString? entityId) {
  if (entityId != null) {
    final fetchFn = ScFnFetch();
    final entity = fetchFn.invoke(env, ScList([entityId])) as ScEntity;
    setParentEntity(env, entity);
    return entity;
  } else {
    return setParentEntityRoot(env);
  }
}

ScNil setParentEntityRoot(ScEnv env) {
  env.parentEntity = null;
  env.parentEntityHistoryCursor = 0;
  return ScNil();
}

void fetchAllTheThings(ScEnv env) {
  env.cacheWorkflows(waitOn(env.client.getWorkflows(env)));
  env.cacheMembers(waitOn(env.client.getMembers(env)));
  env.cacheTeams(waitOn(env.client.getTeams(env)));
  env.cacheEpicWorkflow(waitOn(env.client.getEpicWorkflow(env)));
  env.cacheCustomFields(waitOn(env.client.getCustomFields(env)));
  env.writeCachesToDisk();
  bindAllTheThings(env);
}

void bindAllTheThings(ScEnv env) {
  for (final memberId in env.membersById.keys) {
    final member = env.membersById[memberId] as ScMember;
    final mentionName = member.mentionName;
    if (mentionName is ScString) {
      final isDisabled = member.data[ScString('disabled')];
      if (isDisabled != ScBoolean.veritas()) {
        final sym = ScSymbol("member-${mentionName.value}");
        env.bindings[sym] = member;
      }
    }
  }

  for (final teamId in env.teamsById.keys) {
    final team = env.teamsById[teamId] as ScTeam;
    final mentionName = team.mentionName;
    if (mentionName is ScString) {
      final isArchived = team.data[ScString('archived')];
      if (isArchived != ScBoolean.veritas()) {
        final sym = ScSymbol("team-${mentionName.value}");
        env.bindings[sym] = team;
      }
    }
  }

  for (final customFieldId in env.customFieldsById.keys) {
    final customField = env.customFieldsById[customFieldId] as ScCustomField;
    final canonicalName = customField.canonicalName;
    if (canonicalName is ScString) {
      final isEnabled = customField.data[ScString('enabled')];
      if (isEnabled != ScBoolean.falsitas()) {
        final sym = ScSymbol("field-${canonicalName.value}");
        env.bindings[sym] = customField;
        // Bindings for each custom field enum value as well, since those are
        // how users set the custom field value on a Story.
        final customFieldEnumValues = customField.data[ScString('values')];
        if (customFieldEnumValues is ScList) {
          for (final customFieldEnumValue in customFieldEnumValues.innerList) {
            if (customFieldEnumValue is ScCustomFieldEnumValue) {
              final valueName = customFieldEnumValue.data[ScString('value')];
              if (valueName is ScString) {
                final legalValueName = mungeToLegalSymbolName(valueName.value);
                final sym =
                    ScSymbol("field-${canonicalName.value}--$legalValueName");
                env.bindings[sym] = customFieldEnumValue;
              }
            }
          }
        }
      }
    }
  }

  for (final workflowId in env.workflowsById.keys) {
    final workflow = env.workflowsById[workflowId] as ScWorkflow;
    final workflowName = workflow.data[ScString('name')];
    if (workflowName is ScString) {
      // Names aren't unique; appending ID if there's a conflict.
      final legalName = mungeToLegalSymbolName(workflowName.value);
      final sym = ScSymbol("workflow-$legalName");
      if (env.bindings[sym] is ScWorkflow) {
        final uniqueSym = ScSymbol("workflow-$legalName-$workflowId");
        env.bindings[uniqueSym] = workflow;
      } else {
        env.bindings[sym] = workflow;
      }
    }
  }

  final defaultFn = ScFnDefault();
  final defaultWorkflow = defaultFn.invoke(env, ScList([ScString('workflow')]));
  if (defaultWorkflow is ScWorkflow) {
    final states = defaultWorkflow.data[ScString('states')];
    if (states is ScList) {
      for (final state in states.innerList) {
        if (state is ScWorkflowState) {
          final stateName = state.data[ScString('name')];
          if (stateName is ScString) {
            final legalName = mungeToLegalSymbolName(stateName.value);
            final sym = ScSymbol('state-$legalName');
            if (env.bindings[sym] is ScWorkflowState) {
              final uniqueSym = ScSymbol('state-$legalName-${state.idString}');
              env.bindings[uniqueSym] = state;
            } else {
              env.bindings[sym] = state;
            }
          }
        }
      }
    }
  }

  if (env.epicWorkflow is ScEpicWorkflow) {
    final epicWorkflowStates =
        (env.epicWorkflow as ScEpicWorkflow).data[ScString('epic_states')];
    if (epicWorkflowStates is ScList) {
      for (final epicWorkflowState in epicWorkflowStates.innerList) {
        if (epicWorkflowState is ScEpicWorkflowState) {
          final name = epicWorkflowState.data[ScString('name')];
          if (name is ScString) {
            final legalName = mungeToLegalSymbolName(name.value);
            final sym = ScSymbol("epic-state-$legalName");
            if (env.bindings[sym] is ScEpicWorkflowState) {
              final uniqueSym = ScSymbol(
                  "epic-state-$legalName-${epicWorkflowState.idString}");
              env.bindings[uniqueSym] = epicWorkflowState;
            } else {
              env.bindings[sym] = epicWorkflowState;
            }
          }
        }
      }
    }
  }
}

/// Calculates number of weeks for a given year as per https://en.wikipedia.org/wiki/ISO_week_date#Weeks_per_year
/// Copied from: https://stackoverflow.com/a/54129275
int numOfWeeks(int year) {
  DateTime dec28 = DateTime(year, 12, 28);
  int dayOfDec28 = int.parse(DateFormat("D").format(dec28));
  return ((dayOfDec28 - dec28.weekday + 10) / 7).floor();
}

/// Calculates week number from a date-time as per https://en.wikipedia.org/wiki/ISO_week_date#Calculation
/// Copied from: https://stackoverflow.com/a/54129275
int calculateWeekOfYear(DateTime dt) {
  int dayOfYear = int.parse(DateFormat("D").format(dt));
  int woy = ((dayOfYear - dt.weekday + 10) / 7).floor();
  if (woy < 1) {
    woy = numOfWeeks(dt.year - 1);
  } else if (woy > numOfWeeks(dt.year)) {
    woy = 1;
  }
  return woy;
}

String mungeToLegalSymbolName(String s) {
  return s.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-').toLowerCase();
}

ScNumber dateTimeDifference(ScDateTime dtA, ScDateTime dtB, ScDateTimeUnit unit,
    {mustNegate = false}) {
  final dateTimeA = dtA.value;
  final dateTimeB = dtB.value;
  final dur = dateTimeA.difference(dateTimeB);
  int amount;
  switch (unit) {
    case ScDateTimeUnit.microseconds:
      amount = dur.inMicroseconds;
      break;
    case ScDateTimeUnit.milliseconds:
      amount = dur.inMilliseconds;
      break;
    case ScDateTimeUnit.seconds:
      amount = dur.inSeconds;
      break;
    case ScDateTimeUnit.minutes:
      amount = dur.inMinutes;
      break;
    case ScDateTimeUnit.hours:
      amount = dur.inHours;
      break;
    case ScDateTimeUnit.days:
      amount = dur.inDays;
      break;
    case ScDateTimeUnit.weeks:
      amount = (dur.inDays / 7).floor();
      break;
  }
  if (mustNegate) {
    return ScNumber(-amount);
  } else {
    return ScNumber(amount);
  }
}

ScDateTime addAllToDateTime(ScDateTime dt, ScDateTimeUnit unit, ScList args,
    {mustNegate = false}) {
  args.insertMutable(0, dt);
  return args.reduce((dt, amount) {
    final dateTime = (dt as ScDateTime).value;
    if (amount is ScNumber) {
      final value = amount.value;
      if (value is int) {
        Duration dur;
        switch (unit) {
          case ScDateTimeUnit.microseconds:
            dur = Duration(microseconds: value);
            break;
          case ScDateTimeUnit.milliseconds:
            dur = Duration(milliseconds: value);
            break;
          case ScDateTimeUnit.seconds:
            dur = Duration(seconds: value);
            break;
          case ScDateTimeUnit.minutes:
            dur = Duration(minutes: value);
            break;
          case ScDateTimeUnit.hours:
            dur = Duration(hours: value);
            break;
          case ScDateTimeUnit.days:
            dur = Duration(days: value);
            break;
          case ScDateTimeUnit.weeks:
            dur = Duration(days: value * 7);
            break;
        }
        if (mustNegate) {
          return ScDateTime(dateTime.subtract(dur));
        } else {
          return ScDateTime(dateTime.add(dur));
        }
      } else {
        throw BadArgumentsException(
            "Only integer values may be used to add durations to a date-time value, received a ${value.runtimeType}");
      }
    } else {
      throw BadArgumentsException(
          "A value of type ${amount.typeName()} cannot be used as a duration to add to a date-time value.");
    }
  }) as ScDateTime;
}

String formatPrompt(ScEnv env) {
  if (env.parentEntity != null) {
    final pe = env.parentEntity!;
    final sb = StringBuffer();
    sb.writeln();
    sb.write(env.style('sc ', stylePrompt));
    sb.write(pe.readableString(env));
    sb.write(env.style('> ', stylePrompt));
    return sb.toString();
  } else {
    return env.style('\nsc> ', stylePrompt);
  }
}

String lParen(ScEnv env) {
  return env.style('(', styleSubdued);
}

String rParen(ScEnv env) {
  return env.style(')', styleSubdued);
}

String lSquare(ScEnv env) {
  return env.style('[', styleSubdued);
}

String rSquare(ScEnv env) {
  return env.style(']', styleSubdued);
}

String comment(ScEnv env) {
  return env.style(';', styleSubdued);
}

/// A function and not a method so its available from the [ScEnv] factory constructor.
void setParentEntity(ScEnv env, ScEntity entity, {bool isHistory = true}) {
  final previousParentEntity = env.parentEntity;
  env.parentEntity = entity;
  ScEntity? previousParentInHistory;
  if (env.parentEntityHistory.isEmpty) {
    previousParentInHistory = null;
  } else {
    previousParentInHistory = env.parentEntityHistory[0];
  }
  var addIt = true;
  if (previousParentInHistory is ScEntity) {
    if (previousParentInHistory.id == entity.id) {
      addIt = false;
    }
  }
  if (addIt && isHistory) {
    if (env.parentEntityHistory.isEmpty) {
      env.parentEntityHistory.add(entity);
    } else {
      env.parentEntityHistory.insert(0, entity);
    }
  }
  if (env.parentEntityHistory.length > 100) {
    env.parentEntityHistory = env.parentEntityHistory.sublist(0, 100);
  }
  if (previousParentEntity is ScEntity) {
    env[ScSymbol('__sc_previous-parent-entity')] = previousParentEntity;
  }
  env.writeToDisk();
}

ScEntity? entityFromEnvJson(Map<String, dynamic> json) {
  ScEntity? entity;
  final entityTypeString = json['entityType'];
  if (entityTypeString == null) {
    entity = null;
  }
  final entityId = json['entityId'] as String?;
  if (entityId == null) {
    entity = null;
  } else {
    final title = json['entityTitle'];
    switch (entityTypeString) {
      case 'comment':
        final storyId = json['entityContainerId'];
        if (storyId != null) {
          entity =
              ScEpicComment(ScString(storyId.toString()), ScString(entityId));
          entity.title = ScString(title);
        } else {
          entity = null;
        }
        break;
      case 'epic':
        entity = ScEpic(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'epic comment':
        final epicId = json['entityContainerId'];
        if (epicId != null) {
          entity =
              ScEpicComment(ScString(epicId.toString()), ScString(entityId));
          entity.title = ScString(title);
        } else {
          entity = null;
        }
        break;
      case 'epic workflow':
        entity = ScEpicWorkflow(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'iteration':
        entity = ScIteration(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'label':
        entity = ScLabel(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'milestone':
        entity = ScMilestone(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'member':
        entity = ScMember(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'story':
        entity = ScStory(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'task':
        final storyId = json['entityContainerId'];
        if (storyId != null) {
          entity = ScTask(ScString(storyId.toString()), ScString(entityId));
          entity.title = ScString(title);
        } else {
          entity = null;
        }
        break;
      case 'team':
        entity = ScTeam(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'workflow':
        entity = ScWorkflow(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'custom field':
        entity = ScCustomField(ScString(entityId));
        entity.title = ScString(title);
        break;
    }
  }
  return entity;
}

ScList teamsOfMember(ScEnv env, ScMember member) {
  final teams = member.data[ScString('group_ids')];
  final l = ScList([]);
  if (teams is ScList) {
    for (final team in teams.innerList) {
      if (team is ScTeam) {
        l.addMutable(team);
      } else if (team is ScString) {
        l.addMutable(env.resolveTeam(env, team));
      }
    }
  }
  return l;
}

ScList epicsInMilestone(ScEnv env, ScMilestone milestone) {
  final milestonePublicId = milestone.idString;
  final epicsInMilestone =
      waitOn(env.client.getEpicsInMilestone(env, milestonePublicId));
  return epicsInMilestone;
}

ScList epicsInIteration(ScEnv env, ScIteration iteration) {
  final iterationStories =
      waitOn(env.client.getStoriesInIteration(env, iteration.idString));
  return uniqueEpicsAcrossStories(env, iterationStories);
}

ScList epicsInTeam(ScEnv env, ScTeam team) {
  final storiesInTeam = waitOn(env.client.getStoriesInTeam(env, team.idString));
  return uniqueEpicsAcrossStories(env, storiesInTeam);
}

ScList epicsForStoriesOwnedByMember(ScEnv env, ScMember member) {
  final findStoriesFn = ScFnFindStories();
  final findMap = ScMap({
    ScString('owner_id'): member.id,
  });
  final storiesForMember =
      findStoriesFn.invoke(env, ScList([findMap])) as ScList;
  return uniqueEpicsAcrossStories(env, storiesForMember);
}

ScList uniqueEpicsAcrossStories(ScEnv env, ScList stories) {
  final Set<ScString> epicIds = {};
  for (final story in stories.innerList) {
    final s = story as ScStory;
    final epic = s.data[ScString('epic_id')];
    if (epic is ScEpic) {
      // TODO Clean up ids as ScExprs
      epicIds.add(ScString(epic.idString));
    } else if (epic is ScNumber) {
      epicIds.add(ScString(epic.value.toString()));
    }
  }
  final List<ScEpic> epics = [];
  // NB: Now a set of unique ids, iterate once more and fetch.
  for (final epicId in epicIds) {
    epics.add(waitOn(env.client.getEpic(env, epicId.value)));
  }
  return ScList(epics);
}

ScList uniqueMilestonesAcrossEpics(ScEnv env, ScList epics) {
  final Set<ScString> milestoneIds = {};
  for (final epic in epics.innerList) {
    final e = epic as ScEpic;
    final milestone = e.data[ScString('milestone_id')];
    if (milestone is ScMilestone) {
      // TODO Clean up ids as ScExprs
      milestoneIds.add(ScString(milestone.idString));
    } else if (milestone is ScNumber) {
      milestoneIds.add(ScString(milestone.value.toString()));
    }
  }
  final List<ScMilestone> milestones = [];
  for (final milestoneId in milestoneIds) {
    milestones.add(waitOn(env.client.getMilestone(env, milestoneId.value)));
  }
  return ScList(milestones);
}

ScList milestonesInIteration(ScEnv env, ScIteration iteration) {
  final epics = epicsInIteration(env, iteration);
  return uniqueMilestonesAcrossEpics(env, epics);
}

ScList milestonesInTeam(ScEnv env, ScTeam team) {
  final epics = epicsInTeam(env, team);
  final milestones = ScList([]);
  for (final epic in epics.innerList) {
    final ep = epic as ScEpic;
    final milestoneId = ep.data[ScString('milestone_id')];
    if (milestoneId != null && milestoneId != ScNil()) {
      ScMilestone? milestone;
      if (milestoneId is ScNumber) {
        milestone = ScMilestone(ScString(milestoneId.value.toString()));
      } else if (milestoneId is ScMilestone) {
        milestone = milestoneId;
      }
      if (milestone != null && !milestones.contains(milestone)) {
        milestones.addMutable(waitOn(milestone.fetch(env)));
      }
    }
  }
  return milestones;
}

ScList iterationsOfTeam(ScEnv env, ScTeam team,
    {ScList? prefetchedIterations}) {
  ScList iterations;
  if (prefetchedIterations is ScList) {
    iterations = prefetchedIterations;
  } else {
    iterations = waitOn(env.client.getIterations(env));
  }

  final filteredIterations = iterations.where((expr) {
    final iteration = expr as ScIteration;
    final iterationTeams = iteration.data[ScString('group_ids')];
    if (iterationTeams is ScList) {
      final iterationTeamIds = iterationTeams.mapMutable((e) => e.id);
      return ScBoolean.fromBool(iterationTeamIds.contains(team.id));
    } else {
      return ScBoolean.falsitas();
    }
  });

  return filteredIterations;
}

ScExpr getIn(ScExpr m, ScList rawSelector, ScExpr missingDefault) {
  // Defensive copy
  final selector = ScList(List<ScExpr>.from(rawSelector.innerList));
  if (selector.isEmpty || identical(m, missingDefault)) {
    return m;
  } else {
    final k = selector.first;
    ScString strK;
    if (k is ScDottedSymbol) {
      strK = ScString(k.toString().substring(1));
    } else {
      strK = ScString(k.toString());
    }
    if (m is ScMap) {
      if (m.containsKey(k) || m.containsKey(strK)) {
        final value = m[k] ?? m[strK]!;
        if (value is ScEntity) {
          return getIn(value.data, selector.skip(1), missingDefault);
        } else {
          return getIn(value, selector.skip(1), missingDefault);
        }
      } else {
        return getIn(missingDefault, selector, missingDefault);
      }
    } else {
      throw BadArgumentsException(
          "Don't know how to `get-in` a $k from a value of type ${m.typeName()}");
    }
  }
}

ScExpr details(ScEntity entity) {
  final copy = Map<ScExpr, ScExpr>.from(entity.data.innerMap);
  copy.removeWhere((key, _) {
    return !ScEntity.importantKeys.contains(key);
  });
  return ScMap(copy);
}

int maxPaddedLabelWidth(List<String> lbls) {
  int labelWidth = 0;
  for (final lbl in lbls) {
    if (lbl.length > labelWidth) {
      labelWidth = lbl.length;
    }
  }
  return labelWidth + 1;
}

void printTable(ScEnv env, List<ScExpr> ks, ScMap data) {
  int maxLength = 0;
  for (final k in ks) {
    int kLength;
    if (k is ScString) {
      kLength = k.value.length;
    } else if (k is ScSymbol) {
      kLength = k._name.length;
    } else if (k is ScDottedSymbol) {
      kLength = k._name.length;
    } else {
      kLength = k.toString().length;
    }
    if (kLength > maxLength) {
      maxLength = kLength;
    }
  }
  final sb = StringBuffer();
  for (final k in ks) {
    final value = data[k];
    if (value != null) {
      String keyStr;
      if (k is ScString) {
        keyStr = k.value;
      } else if (k is ScSymbol) {
        keyStr = k._name;
      } else if (k is ScDottedSymbol) {
        keyStr = k._name;
      } else {
        keyStr = k.toString();
      }
      keyStr = keyStr.padLeft(maxLength);
      String valueStr;
      if (value == ScNil()) {
        valueStr = "N/A";
      } else {
        valueStr = value.printToString(env);
      }
      sb.write(env.style(keyStr, stylePrompt));
      sb.writeln(" $valueStr");
    }
  }
  env.out.write(sb.toString());
}

/// Convert a Dart value to an equivalent instance of [ScExpr].
ScExpr valueToScExpr(dynamic value) {
  if (value is ScExpr) return value;
  if (value is String) return value.toScExpr();
  if (value is num) return value.toScExpr();
  if (value is bool) return ScBoolean.fromBool(value);
  if (value is List) return value.toScExpr();
  if (value is Map) return value.toScExpr();

  if (value != null) {
    stderr.writeln(
        "Couldn't convert $value of type ${value.runtimeType} to an ScExpr");
  }

  return ScNil();
}

/// Convert an [ScExpr] to an equivalent Dart value.
dynamic scExprToValue(ScExpr expr,
    {currentDepth = 0,
    forJson = false,
    onlyEntityIds = false,
    throwOnIllegalJsonKeys = true}) {
  if (expr is ScList) {
    return unwrapScList(expr,
        currentDepth: currentDepth + 1,
        forJson: forJson,
        onlyEntityIds: onlyEntityIds);
  } else if (expr is ScMap) {
    return unwrapScMap(
      expr,
      currentDepth: currentDepth + 1,
      forJson: forJson,
      onlyEntityIds: onlyEntityIds,
      throwOnIllegalJsonKeys: throwOnIllegalJsonKeys,
    );
  } else if (expr is ScEntity) {
    // These should always be persisted as-is, not independenty fetch-able.
    if (expr is ScWorkflowState || expr is ScCustomFieldEnumValue) {
      return unwrapScMap(
        expr.data,
        currentDepth: currentDepth + 1,
        forJson: forJson,
        onlyEntityIds: onlyEntityIds,
        throwOnIllegalJsonKeys: throwOnIllegalJsonKeys,
      );
    }
    if (onlyEntityIds) {
      return expr.idString;
    } else if (currentDepth > 2) {
      // NB: Given Shortcut's data model, we are likely in an cycle like Member -> Teams -> Members -> Teams
      return expr.idString;
    } else {
      return unwrapScMap(
        expr.data,
        currentDepth: currentDepth + 1,
        forJson: forJson,
        onlyEntityIds: onlyEntityIds,
        throwOnIllegalJsonKeys: throwOnIllegalJsonKeys,
      );
    }
  } else if (expr is ScString) {
    return expr.value;
  } else if (expr is ScSymbol) {
    return expr._name;
  } else if (expr is ScDottedSymbol) {
    return expr._name;
  } else if (expr is ScNumber) {
    return expr.value;
  } else if (expr is ScDateTime) {
    if (forJson) {
      return expr.value.toString().replaceFirst(' ', 'T');
    } else {
      // TODO Make DateTime and JSON encoding work nicely
      return expr.value.toString();
    }
  } else if (expr is ScBoolean) {
    return expr.toBool();
  } else if (expr == ScNil()) {
    return null;
  } else {
    return expr.toString();
  }
}

List<dynamic> unwrapScList(ScList list,
    {forJson = false, onlyEntityIds = false, currentDepth = 0}) {
  List<dynamic> l = [];
  for (final expr in list.innerList) {
    l.add(scExprToValue(expr,
        currentDepth: currentDepth,
        forJson: forJson,
        onlyEntityIds: onlyEntityIds));
  }
  return l;
}

Map<String, dynamic> unwrapScMap(ScMap map,
    {bool forJson = false,
    bool onlyEntityIds = false,
    currentDepth = 0,
    throwOnIllegalJsonKeys = true}) {
  Map<String, dynamic> m = {};
  for (final key in map.innerMap.keys) {
    final k = scExprToValue(key,
        currentDepth: currentDepth,
        forJson: forJson,
        onlyEntityIds: onlyEntityIds);
    bool includeEntry = true;
    if (forJson && k is! String) {
      if (throwOnIllegalJsonKeys) {
        throw BadArgumentsException(
            "The map targeting JSON must contain only symbol or string keys, but found the key $key of type ${key.typeName()}");
      } else {
        includeEntry = false;
      }
    }
    if (includeEntry) {
      var expr = map[key]!;
      m[k] = scExprToValue(expr,
          currentDepth: currentDepth,
          forJson: forJson,
          onlyEntityIds: onlyEntityIds);
    }
  }
  return m;
}

T? dataFieldOr<T>(ScMap data, String dataKey, T alternative) {
  final rawFieldValue = data[ScString(dataKey)];
  T? fieldValue;
  if (data.containsKey(ScString(dataKey))) {
    if (rawFieldValue == null) {
      fieldValue = null;
    } else {
      fieldValue = rawFieldValue as T;
    }
  } else {
    fieldValue = alternative;
  }
  return fieldValue;
}

final anonymousArgPattern = RegExp(r'^(%[0-9]+.*|%)$');

bool isAnonymousArg(ScSymbol sym) {
  return sym == ScSymbol('%') || anonymousArgPattern.hasMatch(sym._name);
}

int nthOfArg(ScSymbol arg) {
  if (arg == ScSymbol('%')) {
    return 0;
  } else {
    final nthArgChar = arg._name[1];
    final nth = int.tryParse(nthArgChar)! - 1;
    return nth;
  }
}

String truncate(String s, int displayWidth) {
  String returnValue;
  final len = s.length;
  final newLen = min((displayWidth * 0.6).toInt() - 3, len);
  returnValue = s.substring(0, newLen);
  if (newLen < len) {
    returnValue += '...';
  }
  return returnValue;
}

String wrap(String s, int displayWidth, String prefix) {
  final sb = StringBuffer();
  List<int> currentLine = [];
  final newline = '\n'.codeUnitAt(0);
  var col = 0;
  for (final rune in s.runes) {
    col++;
    currentLine.add(rune);
    if (col % displayWidth == 0) {
      final line = String.fromCharCodes(currentLine);
      final spaceIdx = line.lastIndexOf(' ');
      if (spaceIdx == -1) {
        sb.writeln("$prefix$line");
        currentLine = [];
        col = 0;
        continue;
      } else if (spaceIdx != displayWidth - 1) {
        final unread = line.substring(spaceIdx + 1);
        sb.writeln("$prefix${line.substring(0, spaceIdx)}");
        currentLine = unread.runes.toList();
        col = currentLine.length;
        continue;
      } else {
        sb.writeln("$prefix$line");
        currentLine = [];
        col = 0;
        continue;
      }
    } else if (rune == newline) {
      sb.write("$prefix${String.fromCharCodes(currentLine)}");
      currentLine = [];
      col = 0;
    }
  }
  sb.write("$prefix${String.fromCharCodes(currentLine)}");
  return sb.toString();
}

Map<String, dynamic> jsonRoundTrip(Map<String, dynamic> map) {
  final jsonMap = jsonEncode(
    map,
    toEncodable: handleJsonNonEncodable,
  );
  return jsonDecode(jsonMap);
}

/// Shortcut public IDs are guaranteed to be unique _across entity types_, so
/// we don't have to be specific up front about what entity we're asking for
/// if we're smart.
Future<ScEntity> fetchId(ScEnv env, String entityPublicId) async {
  try {
    return await env.client.getStory(env, entityPublicId);
  } catch (_) {
    try {
      return await env.client.getEpic(env, entityPublicId);
    } catch (_) {
      try {
        return await env.client.getMilestone(env, entityPublicId);
      } catch (_) {
        try {
          return await env.client.getIteration(env, entityPublicId);
        } catch (_) {
          try {
            return await env.client.getTeam(env, entityPublicId);
          } catch (_) {
            try {
              return await env.client.getMember(env, entityPublicId);
            } catch (_) {
              try {
                return await env.client.getLabel(env, entityPublicId);
              } catch (_) {
                try {
                  return await env.client.getCustomField(env, entityPublicId);
                } catch (_) {
                  try {
                    return await env.client.getWorkflow(env, entityPublicId);
                  } catch (_) {
                    try {
                      final epicWorkflow =
                          await env.client.getEpicWorkflow(env);
                      if (epicWorkflow.idString == entityPublicId) {
                        return epicWorkflow;
                      } else {
                        throw EntityNotFoundException(
                            "No entity with public ID $entityPublicId could be found.\nTask fetching requires both story and task IDs; use `cd` or `ls` with a story to fetch its tasks.");
                      }
                    } catch (_) {
                      throw EntityNotFoundException(
                          "No entity with public ID $entityPublicId could be found.\nTask fetching requires both story and task IDs; use `cd` or `ls` with a story to fetch its tasks.");
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

execOpenInBrowser(String url) async {
  if (Platform.isMacOS) {
    unawaited(Process.run('open', [url]));
  } else if (Platform.isLinux) {
    unawaited(Process.run('xdg-open', [url]));
  } else {
    throw UnsupportedError(
        "Your operating system is not supported.\nPlease open $url manually.");
  }
}

ScFile execOpenInEditor(ScEnv env, {File? existingFile}) {
  String editor;
  final shortcutEditor = Platform.environment['SHORTCUT_EDITOR'];
  final defaultEditor = Platform.environment['EDITOR'];
  if (shortcutEditor != null) {
    editor = shortcutEditor;
  } else if (defaultEditor != null) {
    editor = defaultEditor;
  } else {
    editor = 'vi';
  }

  File tempFile;
  if (existingFile != null) {
    tempFile = existingFile;
  } else {
    tempFile = newTempFile();
  }

  startAndPrintPid(env, editor, [tempFile.absolute.path]);
  return ScFile(tempFile);
}

File newTempFile() {
  return File(Directory.systemTemp.absolute.path +
      'sc_' +
      DateTime.now().millisecondsSinceEpoch.toString());
}

void startAndPrintPid(ScEnv env, String program, List<String> args) {
  final proc = waitOn(Process.start(program, args));
  env.out.writeln(env.style(
      ";; [INFO] Editor opened with process ID ${proc.pid}", styleInfo));
}

File resolveFile(ScEnv env, String filePath) {
  String fp = filePath;
  if (fp.contains('~')) {
    String? home = Platform.environment['HOME'];
    if (home == null) {
      throw BadArgumentsException(
          "Tried to read a file at path $filePath but your HOME folder is not defined in your environment.");
    } else {
      home = home.replaceFirst(RegExp(r'/+$'), '');
      fp = fp.replaceFirst('~', home);
    }
  }

  var sourceFile = File(fp);
  if (!sourceFile.existsSync()) {
    sourceFile = File(env.baseConfigDirPath + '/' + fp);
    if (!sourceFile.existsSync()) {
      throw FileNotFound(filePath, env.baseConfigDirPath);
    }
  }
  return sourceFile;
}

/// Enumerations

enum MyEntityTypes { stories, tasks, epics, milestones, iterations }

enum ScDateTimeUnit {
  microseconds,
  milliseconds,
  seconds,
  minutes,
  hours,
  days,
  weeks,
}

enum ScDateTimeFormat {
  year,
  month,
  weekOfYear,
  dateOfMonth,
  dayOfWeek,
  hour,
  minute,
  second,
  millisecond,
  microsecond,
}

/// Shortcut's API expects [get], [put], [post], [delete] for API requests.
enum HttpVerb { get, put, post, delete }

/// When interacting at the REPL, these are designed to capture user answers.
enum ReplAnswer { yes, no, yesToAll, noToAll }

/// States of REPL interactivity.
enum ScInteractivityState {
  normal,

  getEntityType,
  getTaskStoryId, // Specifically for tasks, that need the parent story ID to work
  getEntityDescription,
  getEntityName,
  startCreateEntity,
  finishCreateEntity,

  startSetup,
  getDefaultWorkflowId,
  getDefaultWorkflowStateId,
  getDefaultTeamId,
  finishSetup,
}

/// Exceptions

abstract class ExceptionWithMessage implements Exception {
  String? message;
  ExceptionWithMessage(this.message);
}

class ScAssertionError extends ExceptionWithMessage {
  ScAssertionError(String message) : super(message);
}

class InterpretationException extends ExceptionWithMessage {
  InterpretationException(String message) : super(message);
}

class BadArgumentsException extends ExceptionWithMessage {
  BadArgumentsException(String message) : super(message);
}

class OperationNotSupported extends ExceptionWithMessage {
  OperationNotSupported(String message) : super(message);
}

class PlatformNotSupported extends ExceptionWithMessage {
  PlatformNotSupported(String message) : super(message);
}

class MissingEntityDataException extends ExceptionWithMessage {
  MissingEntityDataException(String message) : super(message);
}

class NoParentEntity extends ExceptionWithMessage {
  NoParentEntity(String message) : super(message);
}

class UndefinedSymbolException extends ExceptionWithMessage {
  final ScSymbol symbol;
  UndefinedSymbolException(this.symbol, String message) : super(message);
}

class UninvocableException extends ExceptionWithMessage {
  final ScList args;
  UninvocableException(this.args)
      : super(
            "Tried to invoke a ${args.first.typeName()} that isn't invocable.");
}

class FileNotFound extends ExceptionWithMessage {
  FileNotFound(String filePath, String configDirPath)
      : super(
            "Source file '$filePath' not found relative to current working directory or in $configDirPath config directory.");
}

class PrematureEndOfProgram extends ExceptionWithMessage {
  PrematureEndOfProgram(String message) : super(message);
}

class BadRequestException extends ExceptionWithMessage {
  final HttpClientRequest request;
  final HttpClientResponse response;
  BadRequestException(String message, this.request, this.response)
      : super(message);
}

class BadResponseException extends ExceptionWithMessage {
  final HttpClientRequest request;
  final HttpClientResponse response;
  BadResponseException(String message, this.request, this.response)
      : super(message);
}

class EntityNotFoundException extends ExceptionWithMessage {
  EntityNotFoundException(String? message) : super(message);
}

class UnrecognizedResponseException {
  final HttpClientRequest request;
  final HttpClientResponse response;
  UnrecognizedResponseException(this.request, this.response);
}
