import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:io/ansi.dart';
import 'package:petitparser/petitparser.dart';
import 'package:sc_cli/sc_static.dart';
import 'package:sc_cli/src/sc_async.dart';
import 'package:sc_cli/src/sc_config.dart';
import 'package:sc_cli/src/sc_lang.dart';

class ScEnv {
  ScInteractivityState interactivityState;

  ScMap membersById = ScMap({});
  ScMap teamsById = ScMap({});
  ScMap workflowsById = ScMap({});
  ScMap workflowStatesById = ScMap({});
  ScEpicWorkflow? epicWorkflow;
  late final String baseConfigDirPath;

  ScEnv(this.client)
      : isReplMode = false,
        isAnsiEnabled = true,
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

  int resolutionDepth = 0;

  ReplAnswer lastAnswer = ReplAnswer.no;
  bool isExpectingBindingAnswer = false;
  ScSymbol? symbolBeingDefined;
  bool bindNextValue = false;

  /// Is the environment a REPL or script being evaluated non-interactively?
  final bool isReplMode;

  /// Should strings be printed using ANSI color codes?
  bool isAnsiEnabled;

  bool isPrintJson;

  /// Client to Shortcut API
  final ScClient client;

  /// The [parentEntity] represents the Shortcut entity that is the current parent/container.
  ScEntity? parentEntity;
  late List<ScEntity> parentEntityHistory;
  int parentEntityHistoryCursor = 0;

  /// IDEA Have the functions here mapped to their _classes_ so that debug mode can re-construct them with each evaluation for better code reloading support.
  /// The default bindings of this [ScEnv] give identifiers values in code.
  static Map<ScSymbol, dynamic> defaultBindings = {
    ScSymbol('*1'): ScNil(),
    ScSymbol('*2'): ScNil(),
    ScSymbol('*3'): ScNil(),

    ScSymbol('true'): ScBoolean.veritas(),
    ScSymbol('false'): ScBoolean.falsitas(),
    ScSymbol('if'): ScFnIf(),

    ScSymbol('nil'): ScNil(),

    ScSymbol('invoke'): ScFnInvoke(),
    ScSymbol('apply'): ScFnApply(),
    ScSymbol('identity'): ScFnIdentity(),
    ScSymbol('just'): ScFnIdentity(),
    ScSymbol('return'): ScFnIdentity(),
    ScSymbol('value'): ScFnIdentity(), // esp. for fn as value
    ScSymbol('type'): ScFnType(),
    ScSymbol('undef'): ScFnUndef(),

    ScSymbol('for-each'): ScFnForEach(),
    ScSymbol('map'): ScFnForEach(),
    ScSymbol('reduce'): ScFnReduce(),
    ScSymbol('concat'): ScFnConcat(),
    ScSymbol('extend'): ScFnExtend(),
    ScSymbol('keys'): ScFnKeys(),

    // REPL Helpers

    ScSymbol('help'): ScFnHelp(),
    ScSymbol('?'): ScFnHelp(),
    ScSymbol('print'): ScFnPrint(''),
    ScSymbol('println'): ScFnPrint('\n'),

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

    ScSymbol('select'): ScFnSelect(),
    ScSymbol('where'): ScFnWhere(),
    ScSymbol('filter'): ScFnWhere(),
    ScSymbol('limit'): ScFnLimit(),
    ScSymbol('take'): ScFnLimit(),
    ScSymbol('skip'): ScFnSkip(),
    ScSymbol('drop'): ScFnSkip(),
    ScSymbol('search'): ScFnSearch(),
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

    ScSymbol('file'): ScFnFile(),
    ScSymbol('read-file'): ScFnReadFile(),
    ScSymbol('interpret'): ScFnInterpret(),
    ScSymbol('load'): ScFnLoad(),
    ScSymbol('open'): ScFnOpen(),

    ScSymbol('default'): ScFnDefault(),
    ScSymbol('defaults'): ScFnDefaults(),
    ScSymbol('setup'): ScFnSetup(),

    ScSymbol('cd'): ScFnCd(),
    ScSymbol('ls'): ScFnLs(),
    ScSymbol('cwd'): ScFnCwd(),
    ScSymbol('pwd'): ScFnPwd(),
    ScSymbol('data'): ScFnData(),
    ScSymbol('details'): ScFnDetails(),
    ScSymbol('summary'): ScFnSummary(),
    ScSymbol('fetch'): ScFnFetch(),
    ScSymbol('fetch-all'): ScFnFetchAll(),
    ScSymbol('create'): ScFnCreate(),
    ScSymbol('create-story'): ScFnCreateStory(),
    ScSymbol('create-epic'): ScFnCreateEpic(),
    ScSymbol('create-milestone'): ScFnCreateMilestone(),
    ScSymbol('create-iteration'): ScFnCreateIteration(),
    ScSymbol('create-task'): ScFnCreateTask(),
    ScSymbol('new'): ScFnCreate(),
    ScSymbol('new-story'): ScFnCreateStory(),
    ScSymbol('new-epic'): ScFnCreateEpic(),
    ScSymbol('new-milestone'): ScFnCreateMilestone(),
    ScSymbol('new-iteration'): ScFnCreateIteration(),
    ScSymbol('new-task'): ScFnCreateTask(),
    ScSymbol('!'): ScFnUpdate(),
    ScSymbol('update!'): ScFnUpdate(),
    // ScSymbol('!'): ScFnUpdateParentEntity(),
    ScSymbol('mv!'): ScFnMv(),
    // ScSymbol('unstarted'): ScFnUnstarted(),
    // ScSymbol('in-progress'): ScFnInProgress(),
    // ScSymbol('done'): ScFnDone(),
    ScSymbol('next-state'): ScFnNextState(),
    ScSymbol('prev-state'): ScFnPreviousState(),
    ScSymbol('previous-state'): ScFnPreviousState(),
    ScSymbol('story'): ScFnStory(),
    ScSymbol('stories'): ScFnStories(),
    ScSymbol('task'): ScFnTask(),
    ScSymbol('epic'): ScFnEpic(),
    ScSymbol('epics'): ScFnEpics(),
    ScSymbol('milestone'): ScFnMilestone(),
    ScSymbol('milestones'): ScFnMilestones(),
    ScSymbol('iteration'): ScFnIteration(),
    ScSymbol('iterations'): ScFnIterations(),
    ScSymbol('member'): ScFnMember(),
    ScSymbol('members'): ScFnMembers(),
    ScSymbol('team'): ScFnTeam(),
    ScSymbol('teams'): ScFnTeams(),
    ScSymbol('workflow'): ScFnWorkflow(),
    ScSymbol('workflows'): ScFnWorkflows(),
    ScSymbol('epic-workflow'): ScFnEpicWorkflow(),
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
    isPrintJson = false,
    required IOSink out,
    required IOSink err,
    required String baseConfigDirPath,
  }) {
    final envFile = getEnvFile(baseConfigDirPath);
    String contents = envFile.readAsStringSync();
    if (contents.isEmpty) {
      contents = '{}';
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
    env.isPrintJson = isPrintJson;
    env = ScEnv.extendEnvfromMap(env, json);
    return env;
  }

  /// Used in tests.
  factory ScEnv.fromMap(ScClient client, Map<String, dynamic> data) {
    final env = ScEnv(client);
    return ScEnv.extendEnvfromMap(env, data);
  }

  static ScEnv extendEnvfromMap(ScEnv env, Map<String, dynamic> data) {
    ScEntity? parentEntity;
    final p = data['parent'] as Map<String, dynamic>?;
    if (p == null) {
      parentEntity = null;
    } else {
      parentEntity = entityFromEnvJson(p);
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

    return env;
  }

  ScExpr interpretProgram(String sourceName, List<String> sourceLines) {
    ScExpr returnValue = ScNil();
    final multiLineExprString = StringBuffer();
    for (var i = 0; i < sourceLines.length; i++) {
      final line = sourceLines[i];
      final trimmed = line.trim();
      if (multiLineExprString.isNotEmpty) {
        // Continue building up multi-line program.
        multiLineExprString.write("$trimmed ");
        final currentProgram = multiLineExprString.toString();
        if (scParser.accept(currentProgram)) {
          try {
            returnValue = interpretExprString(currentProgram);
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
        returnValue = interpretExprString('$line\nnil');
      } else if (!scParser.accept(trimmed)) {
        // Allow multi-line programs
        multiLineExprString.write("$trimmed ");
        final currentExprString = multiLineExprString.toString();
        // Single-line parenthetical program
        if (scParser.accept(currentExprString)) {
          try {
            returnValue = interpretExprString(currentExprString);
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
          returnValue = interpretExprString(line);
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

  ScExpr interpretExprString(String exprString) {
    final expr = scEval(this, readExprString(exprString));
    if (isReplMode) {
      final star2 = this[ScSymbol('*2')];
      final star1 = this[ScSymbol('*1')];
      if (star2 != ScNil() && star2 != null) this[ScSymbol('*3')] = star2;
      if (star1 != ScNil() && star1 != null) this[ScSymbol('*2')] = star1;
      this[ScSymbol('*1')] = expr;
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
    final prelude = '''
def first       value %(get % 0)
def second      value %(get % 1)
def third       value %(get % 2)
def fourth      value %(get % 3)
def fifth       value %(get % 4)
def sixth       value %(get % 5)
def seventh     value %(get % 6)
def eighth      value %(get % 7)
def ninth       value %(get % 8)
def tenth       value %(get % 9)
def not         value (fn [x] (if x %(value false) %(value true)))
def or          value (fn [this that] ((fn [this-res] (if this-res %(value this-res) that)) (this)))
def when        value (fn [condition then-branch] (if condition then-branch %(identity nil)))
def first-where value (fn [coll where-clause] (first (where coll where-clause)))
def mapcat      value (fn [coll f] (apply (map coll f) concat))
def states      value (fn [entity] (ls (.workflow_id (fetch entity))))
''';
    interpretProgram("<built-in prelude source>", prelude.split('\n'));
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

  String? styleWith(String s, Iterable<AnsiCode> codes) {
    if (isAnsiEnabled) {
      return wrapWith(s, codes);
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
        'entityType': pe.informalTypeName(),
        'entityId': pe.id.value,
        'entityTitle': title,
      };
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
      String title;
      if (entity is ScTask) {
        final desc = entity.data[ScString('description')];
        if (desc is ScString) {
          title = desc.value;
        } else if (entity.title != null) {
          title = entity.title!.value;
        } else {
          title = '<No description found>';
        }
      } else {
        final name = entity.data[ScString('name')];
        if (name is ScString) {
          title = name.value;
        } else if (entity.title != null) {
          title = entity.title!.value;
        } else {
          title = '<No name: fetch the entity>';
        }
      }
      pH.add({
        'entityType': entity.informalTypeName(),
        'entityId': entity.id.value,
        'entityTitle': title,
      });
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
      final workflowsFile = getCacheWorkflowsFile(baseConfigDirPath);
      final epicWorkflowFile = getCacheEpicWorkflowFile(baseConfigDirPath);

      final membersStr = await membersFile.readAsString();
      final teamsStr = await teamsFile.readAsString();
      final workflowsStr = await workflowsFile.readAsString();
      final epicWorkflowStr = await epicWorkflowFile.readAsString();

      final membersMap = jsonDecode(membersStr) as Map;
      final teamsMap = jsonDecode(teamsStr) as Map;
      final workflowsMap = jsonDecode(workflowsStr) as Map;
      final epicWorkflowMap =
          jsonDecode(epicWorkflowStr) as Map<String, dynamic>;

      // These are stored as JSON objects based on their cache
      final membersMaps = membersMap.values;
      final teamsMaps = teamsMap.values;
      final workflowsMaps = workflowsMap.values;

      final members =
          ScList(membersMaps.map((e) => ScMember.fromMap(this, e)).toList());
      final teams =
          ScList(teamsMaps.map((e) => ScTeam.fromMap(this, e)).toList());
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
      if (env.resolutionDepth > 2) {
        env.resolutionDepth = 0;
        return member;
      } else {
        env.resolutionDepth++;
        member.fetch(this);
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
      if (env.resolutionDepth > 2) {
        env.resolutionDepth = 0;
        return team;
      } else {
        env.resolutionDepth++;
        team.fetch(this);
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

  ScWorkflow resolveWorkflow(ScString workflowId) {
    final maybeCachedWorkflow = workflowsById[workflowId];
    if (maybeCachedWorkflow != null) {
      return maybeCachedWorkflow as ScWorkflow;
    } else {
      final workflow = ScWorkflow(workflowId);
      workflow.fetch(this);
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
            "If calling the `$fnName` function's with no arguments, a parent entity must be active (`cd` into one).");
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
            "The `$fnName` function's $nthArg argument must be an entity or its ID, but received a ${maybeEntity.informalTypeName()}");
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
  String informalTypeName();
}

class ScExpr extends AbstractScExpr {
  /// ScExprs evaluate to themselves by default.
  @override
  ScExpr eval(ScEnv env) {
    return this;
  }

  /// ScExprs print their default Dart [toString] by default.
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
  String informalTypeName() {
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

extension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
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
  String informalTypeName() {
    return 'nil';
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
    return env.styleWith(super.printToString(env), [red])!;
  }

  @override
  String informalTypeName() {
    return 'boolean';
  }
}

class ScNumber extends ScExpr
    implements
        Comparable,
        ScAddable,
        ScSubtractable,
        ScMultipliable,
        ScDivisible {
  ScNumber(this.value);
  final num value;

  @override
  String toString() {
    return value.toString();
  }

  @override
  String printToString(ScEnv env) {
    return env.styleWith(super.printToString(env), [green])!;
  }

  @override
  String informalTypeName() {
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
      throw UnsupportedError(
          "You cannot sort a number with a ${other.informalTypeName()}");
    } else {
      throw UnsupportedError(
          "You cannot sort a number with a ${other.runtimeType}");
    }
  }

  @override
  ScExpr add(ScAddable other) {
    if (other is! ScNumber) {
      // TODO User-facing type mismatch messaging
      throw UnsupportedError('ScNumber can only be added to ScNumber');
    } else {
      return ScNumber(value + other.value);
    }
  }

  @override
  ScExpr subtract(ScSubtractable other) {
    if (other is! ScNumber) {
      throw UnsupportedError('ScNumber can only be subtracted from ScNumber');
    } else {
      return ScNumber(value - other.value);
    }
  }

  @override
  ScExpr multiply(ScMultipliable other) {
    if (other is! ScNumber) {
      throw UnsupportedError('ScNumber can only be multipled with ScNumber');
    } else {
      return ScNumber(value * other.value);
    }
  }

  @override
  ScExpr divide(ScDivisible other) {
    if (other is! ScNumber) {
      throw UnsupportedError('ScNumber can only be divided by ScNumber');
    } else {
      return ScNumber(value / other.value);
    }
  }
}

abstract class ScAddable {
  ScExpr add(ScAddable other);
}

abstract class ScSubtractable {
  ScExpr subtract(ScSubtractable other);
}

abstract class ScMultipliable {
  ScExpr multiply(ScMultipliable other);
}

abstract class ScDivisible {
  ScExpr divide(ScDivisible other);
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
    return env.styleWith(toString(), [yellow])!;
  }

  @override
  String informalTypeName() {
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
          "You cannot sort a string with a ${other.informalTypeName()}");
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
    return env.styleWith(str, [magenta])!;
  }

  @override
  String informalTypeName() {
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
          "You cannot sort a symbol with a ${other.informalTypeName()}");
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

  /// Returns the string representation of the symbolic name.
  @override
  String toString() => ".$_name";

  @override
  String printToString(ScEnv env) {
    String str = super.printToString(env);
    if (env.isPrintJson) {
      str = '"$_name"';
    }
    return env.styleWith(str, [magenta])!;
  }

  @override
  String informalTypeName() {
    return 'dotted symbol';
  }

  @override
  ScExpr eval(ScEnv env) {
    // Parsing treats .. as a ScDottedSymbol but I want to use it as a ScSymbol
    if (_name == '.') {
      return env[ScSymbol('..')]!;
    } else {
      return this;
    }
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
        args.insert(1, this);
        final getFn = ScFnGet();
        return getFn.invoke(env, args);
      } else {
        if (env.parentEntity != null) {
          // NB: Arg is a "default if not found" value when pulling out of the parent entity
          final getFn = ScFnGet();
          return getFn.invoke(env, ScList([env.parentEntity!, this, arg]));
        } else {
          throw BadArgumentsException(
              "If you pass only 1 argument to a dotted symbol, it must either be a map/entity you expect to contain your symbol, or you must be in a parent entity and the argument is considered the default-if-not-found value. Your parent entity is `nil` and you passed this dotted symbol an argument of type ${arg.informalTypeName()}");
        }
      }
    } else if (args.length == 2) {
      // NB: Assumes arg 2 is a "default if not found" which [ScFnGet] supports.
      args.insert(1, this);
      final getFn = ScFnGet();
      return getFn.invoke(env, args);
    } else {
      throw BadArgumentsException(
          "Dotted symbols expect either no arguments, 1 map/entity argument, or 1 map/entity argument and a default-if-not-found value.");
    }
  }
}

class ScFile extends ScExpr {
  final File file;
  ScFile(this.file);

  @override
  String toString() {
    return '<file: ${file.path}>';
  }

  @override
  String informalTypeName() {
    return 'file';
  }

  ScString readAsStringSync({Encoding encoding = utf8}) {
    return ScString(file.readAsStringSync(encoding: encoding));
  }
}

// ScFns

abstract class ScBaseInvocable extends ScExpr {
  // ScBaseInvocable(this.name);
  // final String name;

  @override
  String informalTypeName() {
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

class ScFunction extends ScBaseInvocable {
  ScFunction(String name, this.env, this.params, this.bodyExprs) : super();
  final ScEnv env;
  final ScList params;
  final ScList bodyExprs;

  ScList get getExprs => ScList(List<ScExpr>.from(bodyExprs.innerList));

  @override
  String informalTypeName() {
    return 'function';
  }

  @override
  String get help => "This is a standalone function; no help found.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""Standalone function definitions do not support storing help information at this time.

A future extension to the language either for help or arbitrary metadata may be added.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != params.length) {
      // NB: Support fns leveraging implicit env.parentEntity
      if (1 == (params.length - args.length)) {
        if (env.parentEntity != null) {
          args.insert(0, env.parentEntity!);
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
      env.addFnBindings(params, args);
      final theseExprs = getExprs;
      final evaledItems = theseExprs.mapMutable((e) => e.eval(env));
      if (evaledItems.first is ScBaseInvocable) {
        final invocable = evaledItems.first as ScBaseInvocable;
        final returnValue = invocable.invoke(env, theseExprs.skip(1));
        env.removeFnBindings(params, args);
        return returnValue;
      } else {
        return evaledItems[evaledItems.length - 1];
      }
    }
  }
}

class ScAnonymousFunction extends ScBaseInvocable {
  ScAnonymousFunction(String name, this.env, this.numArgs, this.exprs)
      : super();
  final ScEnv env;
  final int numArgs;
  final ScList exprs;

  ScList get getExprs => ScList(List<ScExpr>.from(exprs.innerList));

  @override
  String informalTypeName() {
    return 'anonymous function';
  }

  @override
  String get help =>
      "No help found: Anonymous function definitions do not support help.";

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
          args.insert(0, env.parentEntity!);
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
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length > 1) {
      throw BadArgumentsException(
          "identity expects 1 arg, found ${args.length} args.");
    } else {
      return args.first;
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
  @override
  // TODO: implement help
  String get help => "Return the type of this value.";

  @override
  // TODO: implement helpFull
  String get helpFull =>
      r"""The language provided by this program is a rudimentary Lisp. The "type" of a value is informational; you cannot program with the types, so they are returned as strings.

  The data types are:

  - number
  - string
  - list
  - map
  - function
  - entity

  The "entity" type has the following sub-types:

  - story
  - task
  - epic
  - milestone
  - iteration
  - workflow
  - workflow state
  - epic workflow
  - epic workflow state

  While the Shortcut API and data model support other entities, they are not represented as first-class entities in this tool at this time. Consult the JSON structure of Shortcut API endpoints that include them for further information.
  """;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      return ScString(args[0].informalTypeName());
    } else {
      throw BadArgumentsException(
          "The `type` function expects one argument, but received ${args.length}");
    }
  }
}

class ScFnUndef extends ScBaseInvocable {
  @override
  String get help =>
      "Remove the symbol with the given string or dotted symbol name from the environment's bindings.";

  @override
  // TODO: implement helpFull
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
            "The `undef` function expects either a string or dotted symbol, but received a ${toUnbind.informalTypeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `undef` function expects only 1 argument, but received ${args.length}");
    }
    return ScNil();
  }
}

class ScFnIf extends ScBaseInvocable {
  static final ScFnIf _instance = ScFnIf._internal();
  ScFnIf._internal();
  factory ScFnIf() => _instance;

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
          "The `if` function expects 3 arguments: a truthy value, a 'then' function, and an 'else' function.");
    } else {
      final ScExpr truthy = args.first;
      final ScExpr thenInv = args[1];
      final ScExpr elseInv = args[2];
      if (thenInv is! ScBaseInvocable) {
        throw BadArgumentsException(
            "The `if` function expects its second argument to be a function, but received a ${thenInv.informalTypeName()}");
      }
      if (elseInv is! ScBaseInvocable) {
        throw BadArgumentsException(
            "The `if` function expects its third argument to be a function, but received a ${thenInv.informalTypeName()}");
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

class ScFnSelect extends ScBaseInvocable {
  static final ScFnSelect _instance = ScFnSelect._internal();
  ScFnSelect._internal();
  factory ScFnSelect() => _instance;

  @override
  String get help =>
      "Return a map that only has the specified entries of this map.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""The first argument must be a map or an entity. A sub-map is returned consisting only of the keys specified by the rest of the arguments to this function.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    ScExpr? sourceMap;
    ScExpr? selector;
    if (args.length == 2) {
      sourceMap = args[0];
      selector = args[1];
    } else if (args.length == 1) {
      selector = args[0];
      if (env.parentEntity != null) {
        final pe = env.parentEntity!;
        sourceMap = pe;
      } else {
        throw BadArgumentsException(
            "The `select` function expects either an explicit map or entity as its first argument, or that you have `cd`ed into an entity. Neither is the case.");
      }
    }

    if (sourceMap == null) {
      throw BadArgumentsException(
          "The `select` function expects either an explicit map or entity as its first argument, or that you have `cd`ed into an entity. Neither is the case.");
    } else if (selector == null) {
      throw BadArgumentsException(
          "The `select` function's second argument must be a list of keys to select.");
    } else if (selector is! ScList) {
      throw BadArgumentsException(
          "The `select` function's second argument must be a list of keys to select.");
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
            "The `select` function expects a map/entity and a list of keys to select out of it.");
      }
    }
  }
}

class ScFnWhere extends ScBaseInvocable {
  static final ScFnWhere _instance = ScFnWhere._internal();
  ScFnWhere._internal();
  factory ScFnWhere() => _instance;

  @override
  String get help =>
      'Return items from a collection that match the given map spec or function.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""The `where` or `filter` function is a tool for finding items in collections.

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
          "The `where` function expects two arguments: a query and a map of where clauses.");
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
                "The `where` function using a map spec requires that each item in your list be a map, but found ${expr.informalTypeName()}");
          }
        });
      } else {
        throw BadArgumentsException(
            "The `where` function's second argument must be a function when passing a list as the first argument.");
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
            "The `where` function's second argument must be a function when passing a map as the first argument.");
      }
    } else {
      throw BadArgumentsException(
          "The `where` function's first argument must be either a list or map, but received ${coll.informalTypeName()}");
    }
  }
}

class ScFnLimit extends ScBaseInvocable {
  static final ScFnLimit _instance = ScFnLimit._internal();
  ScFnLimit._internal();
  factory ScFnLimit() => _instance;

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
          "The `limit` or `take` function expects two arguments: a collection and a limit of how many items to return.");
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
            return coll.sublistImmutable(0, theNum);
          }
        } else {
          throw BadArgumentsException(
              "The `limit` or `take` function's second argument must be an integer.");
        }
      } else {
        throw BadArgumentsException(
            "The `limit` or `take` function's second argument must be an integer.");
      }
    } else {
      throw BadArgumentsException(
          "The `limit` or `take` function's first argument must be either a list, but received ${coll.informalTypeName()}");
    }
  }
}

class ScFnSkip extends ScBaseInvocable {
  static final ScFnSkip _instance = ScFnSkip._internal();
  ScFnSkip._internal();
  factory ScFnSkip() => _instance;

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
          "The `skip` or `drop` function expects two arguments: a collection and a number of items to skip.");
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
            return coll.sublistImmutable(theNum, coll.length);
          }
        } else {
          throw BadArgumentsException(
              "The `skip` or `drop` function's second argument must be an integer.");
        }
      } else {
        throw BadArgumentsException(
            "The `skip` or `drop` function's second argument must be an integer.");
      }
    } else {
      throw BadArgumentsException(
          "The `skip` or `drop` function's first argument must be either a list, but received ${coll.informalTypeName()}");
    }
  }
}

class ScFnHelp extends ScBaseInvocable {
  static final ScFnHelp _instance = ScFnHelp._internal();
  ScFnHelp._internal();
  factory ScFnHelp() => _instance;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      // TODO Make this more a table of contents/concepts
      env.out.writeln('Available commands:');
      ScMap m = ScMap({});
      ScEnv.defaultBindings.forEach((key, value) {
        if (value is ScBaseInvocable) {
          m[key] = ScString(value.help);
        } else if (value is ScExpr) {
          m[key] = ScString("a ${value.informalTypeName()} value");
        }
      });
      final ks = m.keys.toList();
      ks.sort();
      printTable(env, ks, m);
    } else {
      final query = args[0];
      if (query is ScBaseInvocable) {
        env.out.writeln(env.styleWith(query.helpFull, [yellow]));
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

class ScFnDefaults extends ScBaseInvocable {
  @override
  String get help => "Display all workspace-level defaults set using sc.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

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
      // printTable(env, defaults.innerList, m);
      return m;
    } else {
      throw BadArgumentsException(
          "The `defaults` function expects 0 arguments, but received ${args.length}");
    }
  }
}

class ScFnDefault extends ScBaseInvocable {
  static final ScFnDefault _instance = ScFnDefault._internal();
  ScFnDefault._internal();
  factory ScFnDefault() => _instance;

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
            "The `default` function's first argument must be a string or dotted symbol of one of ${identifiers.join(', ')}");
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
            "The `default` function's first argument must be a string or dotted symbol of one of ${identifiers.join(', ')}");
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
            "The `default` function's first argument must be a string or dotted symbol of one of ${identifiers.join(', ')}");
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
            "The `default` function's first argument must be a string or dotted symbol of one of ${identifiers.join(', ')}");
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

Note: These defaults are only meaningful for the quick, interactive entity creation functions. If you use the `create-*` or `new-*` functions and supply a full map as the body of the request, you have complete control over the entity's workflow state and team.
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      env.interactivityState = ScInteractivityState.startSetup;
      return ScNil();
    } else {
      throw BadArgumentsException("The `setup` function expects no arguments.");
    }
  }
}

class ScFnCd extends ScBaseInvocable {
  static final ScFnCd _instance = ScFnCd._internal();
  ScFnCd._internal();
  factory ScFnCd() => _instance;

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
      env[ScSymbol('.')] = ScNil();
      env.parentEntityHistoryCursor = 0;
      return ScNil();
    } else if (args.length == 1) {
      final newParentEntity = args.first;
      final oldParentEntity = env.parentEntity;
      env.parentEntityHistoryCursor = 0;
      if (newParentEntity is ScEntity) {
        setParentEntity(env, newParentEntity);
        // Feature: Keep the env.json up-to-date with most recent parent entity.
        return newParentEntity;
      } else if (newParentEntity is ScNumber || newParentEntity is ScString) {
        ScString id;
        if (newParentEntity is ScNumber) {
          id = ScString(newParentEntity.value.toString());
        } else {
          id = newParentEntity;
        }
        if (oldParentEntity is ScStory) {
          try {
            final task = waitOn(
                env.client.getTask(env, oldParentEntity.id.value, id.value));
            env.parentEntity = task;
            env[ScSymbol('.')] = task;
            env[ScSymbol('__sc_previous-parent-entity')] = oldParentEntity;
            // NB: Don't! env.writeToDisk() or put in parentEntityHistory. It's not usable on re-boot unless we store storyId as well.
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
            'The argument to `cd` must be a Shortcut entity or ID.');
      }
    } else {
      throw BadArgumentsException(
          'The `cd` function expects an entity to move into.');
    }
  }
}

class ScFnHistory extends ScBaseInvocable {
  @override
  String get help =>
      "Return history of parent entities you have `cd`ed into, in reverse order so latest are at the bottom. Max 100 entries.";

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
          "The `history` function takes no arguments, but received ${args.length}");
    } else {
      return ScList(env.parentEntityHistory.reversed.toList());
    }
  }
}

class ScFnBackward extends ScBaseInvocable {
  @override
  String get help =>
      "Change your parent entity to the previous one in your history.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

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
        env.err.writeln(
            "[INFO] No previous parent found in history; you've reached the beginning of time.");
        return ScNil();
      }
    } else {
      throw BadArgumentsException(
          "The `backward` function expects no arguments, but received ${args.length}");
    }
  }
}

class ScFnForward extends ScBaseInvocable {
  @override
  String get help =>
      "Change your parent entity to the next one in your history.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      if (env.parentEntityHistoryCursor == 0) {
        env.err.writeln(
            "[INFO] No subsequent parent found in history; you're back to the latest.");
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
          "The `forward` function expects no arguments, but received ${args.length}");
    }
  }
}

class ScFnLs extends ScBaseInvocable {
  @override
  String get help => 'List items within a context.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    ScEntity entity = env.resolveArgEntity(args, 'ls');
    return waitOn(entity.ls(env));
  }
}

class ScFnCwd extends ScBaseInvocable {
  static String cwdHelp =
      '[Help] `cd` into a Shortcut entity or entity ID to use `cwd`, `pwd`, and `.`';

  @override
  String get help =>
      'Return the working "directory"—the current parent entity we have `cd`ed into.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      if (env.parentEntity != null) {
        final pe = env.parentEntity!;
        if (pe.data.isEmpty) {
          waitOn(pe.fetch(env));
        }
        return pe;
      } else {
        env.out.writeln(env.styleWith(cwdHelp, [green]));
        return ScNil();
      }
    } else {
      throw BadArgumentsException(
          "The `cwd` function doesn't take any arguments.");
    }
  }
}

class ScFnPwd extends ScBaseInvocable {
  @override
  String get help =>
      'Print the working "directory"—the current parent entity we have `cd`ed into.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      if (env.parentEntity != null) {
        final pe = env.parentEntity!;
        if (env.membersById.isEmpty || pe.data.isEmpty) {
          waitOn(pe.fetch(env));
        }
        pe.printSummary(env);
        return ScNil();
      } else {
        env.out.writeln(env.styleWith(ScFnCwd.cwdHelp, [green]));
        return ScNil();
      }
    } else {
      throw BadArgumentsException(
          "The `pwd` function doesn't take any arguments.");
    }
  }
}

class ScFnMv extends ScBaseInvocable {
  @override
  String get help =>
      "Move a Shortcut entity from one container to another (e.g., a story to a new epic).";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != 2) {
      throw BadArgumentsException(
          "The `mv` function expects 2 arguments: a child entity and a new parent entity to move it to.");
    } else {
      ScEntity childEntity = env.resolveArgEntity(args, 'mv');
      ScEntity parentEntity =
          env.resolveArgEntity(args, 'mv', nthArg: 'second');

      // Mv logic
      if (childEntity is ScStory) {
        if (parentEntity is ScEpic) {
          return waitOn(env.client.updateStory(
              env, childEntity.id.value, {'epic_id': parentEntity.id.value}));
        } else if (parentEntity is ScIteration) {
          return waitOn(env.client.updateStory(env, childEntity.id.value,
              {'iteration_id': parentEntity.id.value}));
        } else if (parentEntity is ScTeam) {
          return waitOn(env.client.updateStory(
              env, childEntity.id.value, {'group_id': parentEntity.id.value}));
        } else {
          throw BadArgumentsException(
              "A story can only be moved to an epic, iteration, or team, but you tried to move it to a ${parentEntity.informalTypeName()}");
        }
      } else if (childEntity is ScEpic) {
        if (parentEntity is ScMilestone) {
          return waitOn(env.client.updateEpic(env, childEntity.id.value,
              {'milestone_id': parentEntity.id.value}));
        } else if (parentEntity is ScTeam) {
          return waitOn(env.client.updateEpic(
              env, childEntity.id.value, {'group_id': parentEntity.id.value}));
        } else {
          throw BadArgumentsException(
              "An epic can only be moved to a milestone or team, but you tried to move it to a ${parentEntity.informalTypeName()}");
        }
      } else {
        throw BadArgumentsException(
            "You tried to mv a ${childEntity.informalTypeName()} to a ${parentEntity.informalTypeName()}, but that is unsupported.");
      }
    }
  }
}

class ScFnData extends ScBaseInvocable {
  @override
  String get help => "Return the entity's complete, raw data.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

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
          "The `data` function expects either a single entity as argument, or you can invoke it with no arguments if you've already `cd`ed into an entity.");
    } else {
      final ScExpr entity = args.first;
      if (entity is ScEntity) {
        return entity.data;
      } else {
        throw BadArgumentsException(
            "If provided, the argument to `data` must be an entity, but received ${entity.informalTypeName()}");
      }
    }
  }
}

class ScFnDetails extends ScBaseInvocable {
  @override
  String get help => "Return the entity's most important details as a map.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

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
          "The `details` function expects either a single entity as argument, or you can invoke it with no arguments if you've already `cd`ed into an entity.");
    } else {
      final ScExpr entity = args.first;
      if (entity is ScEntity) {
        return details(entity);
      } else {
        throw BadArgumentsException(
            "If provided, the argument to `details` must be an entity, but received ${entity.informalTypeName()}");
      }
    }
  }
}

class ScFnSummary extends ScBaseInvocable {
  @override
  String get help => "Return a summary of the Shortcut entity's state.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    ScEntity entity = env.resolveArgEntity(args, 'summary');
    if (entity.data.isEmpty) waitOn(entity.fetch(env));
    return entity.printSummary(env);
  }
}

class ScFnInvoke extends ScBaseInvocable {
  static final ScFnInvoke _instance = ScFnInvoke._internal();
  ScFnInvoke._internal();
  factory ScFnInvoke() => _instance;

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

It's actually tough to discover a position where functions _aren't_ invoked (hint: see the examples for the `identity` function).

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
          "The `invoke` function expects its first argument to be a function, but received a ${invocable.informalTypeName()}");
    }
  }
}

class ScFnApply extends ScBaseInvocable {
  static final ScFnApply _instance = ScFnApply._internal();
  ScFnApply._internal();
  factory ScFnApply() => _instance;

  @override
  String get help => "Apply the given function to the list of arguments.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

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
              "The `apply` function expects its second argument to be a function, but received a ${invocable.informalTypeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `apply` function expects its first argument to be a list, but received a ${itsArgs.informalTypeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `apply` function expects 2 arguments: a list of args and an function to invoke with them.");
    }
  }
}

class ScFnForEach extends ScBaseInvocable {
  static final ScFnForEach _instance = ScFnForEach._internal();
  ScFnForEach._internal();
  factory ScFnForEach() => _instance;

  @override
  String get help => "Execute a function for each item in a list.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != 2) {
      throw BadArgumentsException(
          "The `for-each` function expects 2 arguments: a list and a function.");
    } else {
      final list = args[0];
      final invocable = args[1];
      if (list is! ScList) {
        throw BadArgumentsException(
            "The first argument to `for-each` must be a list, but received ${list.informalTypeName()}");
      }
      if (invocable is! ScBaseInvocable) {
        throw BadArgumentsException(
            "The second argument to `for-each` must be a function, but received ${invocable.informalTypeName()}");
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
  String get help =>
      "Reduce a list of things down to a single value. Takes a list, an optional starting accumulator, and a function of (acc, item).";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length < 2 || args.length > 3) {
      throw BadArgumentsException(
          "The `reduce` function expects 2 or 3 arguments: a list, an optional starting accumulator, and a function of (acc, item).");
    } else {
      var list = args[0];
      if (list is ScList) {
        ScExpr acc;
        ScBaseInvocable invocable;
        if (args.length == 2) {
          acc = list.first;
          final maybeInvocable = args[1];
          if (maybeInvocable is! ScBaseInvocable) {
            throw BadArgumentsException(
                "When passing two arguments to `reduce`, the second argument must be a function, but received ${maybeInvocable.informalTypeName()}");
          }
          list = list.skip(1);
          invocable = maybeInvocable;
        } else {
          acc = args[1];
          final maybeInvocable = args[2];
          if (maybeInvocable is! ScBaseInvocable) {
            throw BadArgumentsException(
                "When passing three arguments to `reduce`, the third argument must be a function, but received ${maybeInvocable.informalTypeName()}");
          }
          invocable = maybeInvocable;
        }
        for (final item in list.innerList) {
          acc = invocable.invoke(env, ScList([acc, item]));
        }
        return acc;
      } else {
        throw BadArgumentsException(
            "The first argument to `reduce` must be a list, but received ${list.informalTypeName()}");
      }
    }
  }
}

class ScFnConcat extends ScBaseInvocable {
  static final ScFnConcat _instance = ScFnConcat._internal();
  ScFnConcat._internal();
  factory ScFnConcat() => _instance;

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
          } else {
            throw BadArgumentsException(
                "The `concat` function can concatenate strings, but all arguments must then be strings; received a ${coll.informalTypeName()}");
          }
        }
        return ScString(sb.toString());
      } else if (sample is ScList) {
        List<ScExpr> l = [];
        for (final coll in args.innerList) {
          if (coll is ScList) {
            l.addAll(coll.innerList);
          } else {
            throw BadArgumentsException(
                "The `concat` function can concatenate lists, but all arguments must then be lists; received a ${coll.informalTypeName()}");
          }
        }
        return ScList(l);
      } else if (sample is ScMap) {
        ScMap m = ScMap({});
        for (final coll in args.innerList) {
          if (coll is ScMap) {
            m.addMap(coll);
          } else {
            throw BadArgumentsException(
                "The `concat` function can concatenate maps, but all arguments must then be maps; received a ${coll.informalTypeName()}");
          }
        }
        return m;
      } else {
        throw BadArgumentsException(
            "The `concat` function can concatenate strings, lists, and maps, but received a ${sample.informalTypeName()}");
      }
    }
  }
}

class ScFnExtend extends ScBaseInvocable {
  static final ScFnExtend _instance = ScFnExtend._internal();
  ScFnExtend._internal();
  factory ScFnExtend() => _instance;

  @override
  String get help =>
      'Combine multiple maps into one, concatenating values that are collections.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""The `concat` function naively concatenates its arguments. The `extend` function works (1) exclusively with maps, and (2) _extends_ map values via concatenation, recursively.

Compare:

extend {.a [1 2]} {.a [3 4]} => {.a [1 2 3 4]}
concat {.a [1 2]} {.a [3 4]} => {.a [3 4]}
""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScList([]);
    } else {
      final sample = args[0];
      if (sample is ScMap) {
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
          } else {
            throw BadArgumentsException(
                "The `extend` function can extend maps, but received a ${coll.informalTypeName()}");
          }
        }
        return m;
      } else {
        throw BadArgumentsException(
            "The `extend` function can extend maps, but received a ${sample.informalTypeName()}");
      }
    }
  }
}

class ScFnKeys extends ScBaseInvocable {
  static final ScFnKeys _instance = ScFnKeys._internal();
  ScFnKeys._internal();
  factory ScFnKeys() => _instance;

  @override
  String get help => "Return the keys of this map or entity's data.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != 1) {
      throw BadArgumentsException(
          "The `keys` function expects 1 argument: a map or entity.");
    } else {
      final arg = args[0];
      if (arg is ScMap) {
        return ScList(arg.innerMap.keys.toList());
      } else if (arg is ScEntity) {
        return ScList(arg.data.innerMap.keys.toList());
      } else {
        throw BadArgumentsException(
            "The `keys` function expects a map or entity argument, but received ${arg.informalTypeName()}");
      }
    }
  }
}

class ScFnWhenNil extends ScBaseInvocable {
  static final ScFnWhenNil _instance = ScFnWhenNil._internal();
  ScFnWhenNil._internal();
  factory ScFnWhenNil() => _instance;

  @override
  String get help =>
      "If argument is nil, returns the default value provided instead.";

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
          "The `when-nil` function expects two arguments: a possibly-nil value and a default to return if it is nil.");
    }
  }
}

class ScFnGet extends ScBaseInvocable {
  static final ScFnGet _instance = ScFnGet._internal();
  ScFnGet._internal();
  factory ScFnGet() => _instance;

  @override
  String get help => 'Retrieve an item from a source at a selector.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length < 2) {
      throw BadArgumentsException(
          "The `get` function expects at least two arguments: `get <key> <source> [<default if missing>]`");
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

class ScFnGetIn extends ScBaseInvocable {
  static final ScFnGetIn _instance = ScFnGetIn._internal();
  ScFnGetIn._internal();
  factory ScFnGetIn() => _instance;

  @override
  String get help => 'Retrieve an item from a source at a selector.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length < 2) {
      throw BadArgumentsException(
          "The `get-in` function expects at least two arguments: `get-in <source> <selector> [<default if missing>]`");
    }
    final source = args[0];
    final selector = args[1];
    if (selector is! ScList) {
      throw BadArgumentsException(
          "The `get-in` function's second argument must be a list of keys to get out of the map, but received a ${selector.informalTypeName()}");
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
  String get help => 'Returns true if the collection contains the given item.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length < 2) {
      throw BadArgumentsException(
          "The `contains?` function expects 2 arguments: a collection (or string) and an item (or substring).");
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
          "The `contains?` function's first argument must be a collection or string, but received ${source.informalTypeName()}");
    }
  }
}

class ScFnCount extends ScBaseInvocable {
  static final ScFnCount _instance = ScFnCount._internal();
  ScFnCount._internal();
  factory ScFnCount() => _instance;

  @override
  String get help => 'The length of the collection, the count of its items.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw BadArgumentsException(
          'The `count` or `length` function expects one argument: a collection.');
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
            'The `count` or `length` function expects its argument to be a collection, but received a ${coll.informalTypeName()}');
      }
    }
  }
}

class ScFnSort extends ScBaseInvocable {
  static final ScFnSort _instance = ScFnSort._internal();
  ScFnSort._internal();
  factory ScFnSort() => _instance;

  @override
  String get help => 'Sort the collection (maps by their keys).';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""Return a copy of the original collection, sorted. Maps are sorted by their keys.

If you need to sort by a derivative value of each item, try `sort-by`.""";

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
            "The `sort` function's first argument must be a collection, but received a ${coll.informalTypeName()}");
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
              "The `sort` function's first argument must be a collection, but received a ${coll.informalTypeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `sort` function's second argument must be a function, but received a ${fn.informalTypeName()}");
      }
    } else {
      throw BadArgumentsException(
          'The `sort` function expects either 1 or 2 arguments: a collection, and an optional sorting function.');
    }
  }
}

class ScFnSplit extends ScBaseInvocable {
  static final ScFnSplit _instance = ScFnSplit._internal();
  ScFnSplit._internal();
  factory ScFnSplit() => _instance;

  @override
  String get help => 'Split the collection by the given separator.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw BadArgumentsException(
          'The `split` function expects one or two arguments: a collection and an optional separator (default is newline)');
    } else {
      final coll = args.first;
      ScString sep;
      if (args.length == 2) {
        final argSep = args[1];
        if (argSep is ScString) {
          sep = argSep;
        } else {
          throw BadArgumentsException(
              'The `split` function expects its second argument to be a string, but received a ${argSep.informalTypeName()}');
        }
      } else {
        sep = ScString('\n');
      }

      if (coll is ScString) {
        return coll.split(separator: sep);
      } else {
        throw BadArgumentsException(
            'The `split` function currently only supports splitting strings, received a ${coll.informalTypeName()}');
      }
    }
  }
}

class ScFnJoin extends ScBaseInvocable {
  static final ScFnJoin _instance = ScFnJoin._internal();
  ScFnJoin._internal();
  factory ScFnJoin() => _instance;

  @override
  String get help =>
      'Join the collection into a string using the given separator.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw BadArgumentsException(
          'The `join` function expects one or two arguments: a collection and an optional separator (default is newline)');
    } else {
      final coll = args.first;
      ScString sep;
      if (args.length == 2) {
        final argSep = args[1];
        if (argSep is ScString) {
          sep = argSep;
        } else {
          throw BadArgumentsException(
              'The `join` function expects its second argument to be a string, but received a ${argSep.informalTypeName()}');
        }
      } else {
        sep = ScString('\n');
      }

      if (coll is ScList) {
        return coll.join(separator: sep);
      } else {
        throw BadArgumentsException(
            'The `join` function currently only supports joining lists, received a ${coll.informalTypeName()}');
      }
    }
  }
}

class ScFnFile extends ScBaseInvocable {
  static final ScFnFile _instance = ScFnFile._internal();
  ScFnFile._internal();
  factory ScFnFile() => _instance;

  @override
  String get help =>
      'Returns a file object given its relative or absolute path as a string.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw BadArgumentsException(
          'The `file` function expects one argument: a string of the file\'s path.');
    } else {
      final path = args.first;
      if (path is ScString) {
        final file = File(path.value);
        return ScFile(file);
      } else {
        throw BadArgumentsException(
            'The argument to `file` must be a string, but received a ${path.informalTypeName()}');
      }
    }
  }
}

class ScFnReadFile extends ScBaseInvocable {
  static final ScFnReadFile _instance = ScFnReadFile._internal();
  ScFnReadFile._internal();
  factory ScFnReadFile() => _instance;

  @override
  String get help => 'Return string contents of a file.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty || args.length > 1) {
      throw BadArgumentsException(
          'The `read-file` function expects one argument: the file to read.');
    } else {
      final file = args.first;
      if (file is ScFile) {
        return file.readAsStringSync();
      } else {
        throw BadArgumentsException(
            'The `read-file` function expects a file argument, but received a ${file.informalTypeName()}');
      }
    }
  }
}

class ScFnInterpret extends ScBaseInvocable {
  @override
  String get help =>
      "Return the expression resulting from interpreting the given string of code.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final sourceString = args[0];
      if (sourceString is ScString) {
        return env.interpretProgram(
            '<string from console>', sourceString.value.split('\n'));
      } else {
        throw BadArgumentsException(
            "The `interpret` function only accepts a string argument, but received a ${sourceString.informalTypeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `interpret` function expects 1 argument: a string of source code to interpret.");
    }
  }
}

class ScFnLoad extends ScBaseInvocable {
  static final ScFnLoad _instance = ScFnLoad._internal();
  ScFnLoad._internal();
  factory ScFnLoad() => _instance;

  @override
  String get help => 'Read and evaluate the given source code file.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != 1) {
      throw BadArgumentsException(
          "The `load` function expects one argument: the path of the file to load.");
    } else {
      final sourceFilePath = (args.first as ScString).value;
      var sourceFile = File(sourceFilePath);
      if (!sourceFile.existsSync()) {
        sourceFile = File(env.baseConfigDirPath + '/' + sourceFilePath);
        if (!sourceFile.existsSync()) {
          throw SourceFileNotFound(sourceFilePath, env.baseConfigDirPath);
        }
      }

      final sourceLines = sourceFile.readAsLinesSync();
      return env.interpretProgram(sourceFile.absolute.path, sourceLines);
    }
  }
}

class ScFnOpen extends ScBaseInvocable {
  static final ScFnOpen _instance = ScFnOpen._internal();
  ScFnOpen._internal();
  factory ScFnOpen() => _instance;

  @override
  String get help => "Open an entity's page in the Shortcut web app.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""Every Shortcut entity has an `app_url` entry that can be opened in a web browser to view the details of that entity.

Caveat: Only Linux and macOS supported, this function shells out to `xdg-open` or `open` respectively. If on another platform, copy the `app_url` directly.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    ScEntity entity = env.resolveArgEntity(args, 'open');
    final appUrl = entity.data[ScString('app_url')];
    if (appUrl is ScString) {
      openInBrowser(appUrl.value);
    } else {
      throw MissingEntityDataException(
          "The app_url of this ${entity.informalTypeName()} could not be accessed.");
    }
    return ScNil();
  }
}

class ScFnSearch extends ScBaseInvocable {
  static final ScFnSearch _instance = ScFnSearch._internal();
  ScFnSearch._internal();
  factory ScFnSearch() => _instance;

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
type: estimate: has:attachment has:task has:epic
is:blocked is:blocker is:story

== Story & Epic Search Operators ==
id: team: project: state: type: epic: estimate: label: owner: requester:
has:comment has:deadline has:owner
is:unestimated is:overdue is:archived
is:unstarted is:started is:done
updated: created: started: completed: moved: due:
technical-area: skill-set: product-area:""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final query = args[0];
      if (query is ScString) {
        ScMap res = waitOn(env.client.search(env, query));
        return res;
      } else {
        throw BadArgumentsException(
            "The argument to `search` must be a search string, but received a ${query.informalTypeName()}");
      }
    } else if (args.length == 2) {
      final coll = args[0];
      final query = args[1];
      String queryStr;
      if (query is ScString) {
        queryStr = query.value;
      } else {
        throw BadArgumentsException(
            "The `search` function when passed 2 arguments expects its second to be a string (for now), but received a ${query.informalTypeName()}");
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
          final keyJson = jsonEncoder.convert(scExprToValue(k));
          final valueJson = jsonEncoder.convert(scExprToValue(v));
          final jsonStr = '$keyJson $valueJson';
          return ScBoolean.fromBool(
              jsonStr.toLowerCase().contains(queryStr.toLowerCase()));
        });
      } else {
        throw BadArgumentsException(
            "The `search` function when passed 2 arguments expects its first to be a list, but received a ${coll.informalTypeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `search` function expects 1 or 2 arguments: a query/search string, or a collection and a query.");
    }
  }
}

class ScFnFindStories extends ScBaseInvocable {
  static final ScFnFindStories _instance = ScFnFindStories._internal();
  ScFnFindStories._internal();
  factory ScFnFindStories() => _instance;

  @override
  String get help => "Find stories given specific parameters.";

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
            "The `find-stories` function's first argument must be a map, but recevied a ${findMap.informalTypeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `find-stories` function expects 1 argument: a map of parameters to search by.");
    }
  }
}

class ScFnFetch extends ScBaseInvocable {
  static final ScFnFetch _instance = ScFnFetch._internal();
  ScFnFetch._internal();
  factory ScFnFetch() => _instance;

  @override
  String get help => 'Fetch an entity via the Shortcut API.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    ScEntity entity = env.resolveArgEntity(args, 'fetch', forceFetch: true);
    return entity;
  }
}

class ScFnFetchAll extends ScBaseInvocable {
  static final ScFnFetchAll _instance = ScFnFetchAll._internal();
  ScFnFetchAll._internal();
  factory ScFnFetchAll() => _instance;

  @override
  String get help => 'Fetch and cache members, teams, and workflows.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      // NB: Fetch things that change infrequently but will make everything else here faster.
      env.out.writeln(
          "[Please Wait] Caching of all workflows, workflow states, members, and teams for this session. Run `fetch-all` to refresh.");
      env.cacheWorkflows(waitOn(env.client.getWorkflows(env)));
      env.cacheMembers(waitOn(env.client.getMembers(env)));
      env.cacheTeams(waitOn(env.client.getTeams(env)));
      env.cacheEpicWorkflow(waitOn(env.client.getEpicWorkflow(env)));
      env.writeCachesToDisk();
      return ScNil();
    } else {
      throw BadArgumentsException(
          "The `fetch-all` function takes no arguments. Use `fetch` to fetch an individual entity.");
    }
  }
}

class ScFnUpdate extends ScBaseInvocable {
  static final ScFnUpdate _instance = ScFnUpdate._internal();
  ScFnUpdate._internal();
  factory ScFnUpdate() => _instance;

  @override
  String get help =>
      'Update the given entity in Shortcut with the given update map.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isNotEmpty) {
      ScEntity entity = env.resolveArgEntity(args, 'update!',
          forceParent: (args[0] is ScMap ||
              args[0] is ScString ||
              args[0] is ScDottedSymbol));

      ScMap updateMap;
      final maybeUpdateMap = args[0];
      if (maybeUpdateMap is ScMap) {
        updateMap = maybeUpdateMap;
      } else if (maybeUpdateMap is ScString ||
          maybeUpdateMap is ScDottedSymbol) {
        if (args.length == 2) {
          final updateKey = maybeUpdateMap;
          final updateValue = args[1];
          updateMap = ScMap({updateKey: updateValue});
        } else {
          throw BadArgumentsException(
              "The `update!` function expects either a map or separate string/symbol key value pairs to update the entity; received a key, but no value.");
        }
      } else {
        throw BadArgumentsException(
            "The `update!` function expects either a map or separate string/symbol key value pairs to update the entity, but received ${maybeUpdateMap.informalTypeName()}");
      }
      return waitOn(entity.update(
          env, scExprToValue(updateMap, forJson: true, onlyEntityIds: true)));
    } else {
      throw BadArgumentsException(
          "The `update!` function expects either a map or separate string/symbol key value pairs to update the entity, but received no arguments.");
    }
  }
}

class ScFnNextState extends ScBaseInvocable {
  static final ScFnNextState _instance = ScFnNextState._internal();
  ScFnNextState._internal();
  factory ScFnNextState() => _instance;

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
    ScEntity entity = env.resolveArgEntity(args, 'next-state');

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
            '[WARN] Already at last workflow state for the workflow ${workflow.printToString(env)}');
        return entity;
      } else {
        final nextWorkflowState = workflowStates[idx + 1] as ScWorkflowState;
        final updatedEntity = waitOn(env.client.updateStory(
            env,
            entity.id.value,
            {"workflow_state_id": int.tryParse(nextWorkflowState.id.value)}));
        entity.data = updatedEntity.data;
        env.out.writeln(
            "[INFO] Moved from ${currentWorkflowState.printToString(env)} to ${nextWorkflowState.printToString(env)}");
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
            '[WARN] Already at last epic workflow state for the workflow ${epicWorkflow.printToString(env)}');
        return entity;
      } else {
        final nextEpicWorkflowState =
            epicWorkflowStates[idx + 1] as ScEpicWorkflowState;
        final updatedEntity = waitOn(env.client.updateEpic(env, entity.id.value,
            {"epic_state_id": int.tryParse(nextEpicWorkflowState.id.value)}));
        entity.data = updatedEntity.data;
        env.out.writeln(
            "[INFO] Moved from ${currentEpicWorkflowState.printToString(env)} to ${nextEpicWorkflowState.printToString(env)}");
        return entity;
      }
    } else if (entity is ScMilestone) {
      final currentState = (entity.data[ScString('state')] as ScString).value;
      final idx = ScMilestone.states.indexOf(currentState);
      if (idx == -1) {
        throw BadArgumentsException(
            'The milestone is in an unsupported state: "$currentState"');
      } else if (idx == ScMilestone.states.length - 1) {
        env.err.writeln('[WARN] Milestone is already done.');
        return entity;
      } else {
        final nextState = ScMilestone.states[idx + 1];
        final updatedEntity = waitOn(env.client
            .updateMilestone(env, entity.id.value, {'state': nextState}));
        env.out.writeln('[INFO] Moved from "$currentState" to "$nextState"');
        entity.data = updatedEntity.data;
        return entity;
      }
    } else if (entity is ScTask) {
      final isComplete = entity.data[ScString('complete')];
      if (isComplete == ScBoolean.falsitas()) {
        final storyId = entity.data[ScString('story_id')] as ScNumber;
        final taskId = entity.id;
        final updateMap = {'complete': true};
        final updatedEntity = waitOn(env.client.updateTask(
            env, storyId.value.toString(), taskId.value, updateMap));
        entity.data = updatedEntity.data;
        return entity;
      } else {
        env.err.writeln('[WARN] Task is already complete.');
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
    ScEntity entity = env.resolveArgEntity(args, 'previous');

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
            '[WARN] Already at first workflow state for the workflow ${workflow.printToString(env)}');
        return entity;
      } else {
        final nextWorkflowState = workflowStates[idx - 1] as ScWorkflowState;
        final updatedEntity = waitOn(env.client.updateStory(
            env,
            entity.id.value,
            {"workflow_state_id": int.tryParse(nextWorkflowState.id.value)}));
        entity.data = updatedEntity.data;
        env.out.writeln(
            "[INFO] Moved from ${currentWorkflowState.printToString(env)} to ${nextWorkflowState.printToString(env)}");
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
            '[WARN] Already at first epic workflow state for the workflow ${epicWorkflow.printToString(env)}');
        return entity;
      } else {
        final nextEpicWorkflowState =
            epicWorkflowStates[idx - 1] as ScEpicWorkflowState;
        final updatedEntity = waitOn(env.client.updateEpic(env, entity.id.value,
            {"epic_state_id": int.tryParse(nextEpicWorkflowState.id.value)}));
        entity.data = updatedEntity.data;
        env.out.writeln(
            "[INFO] Moved from ${currentEpicWorkflowState.printToString(env)} to ${nextEpicWorkflowState.printToString(env)}");
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
            '[WARN] Milestone is already in the first, "to do" state.');
        return entity;
      } else {
        final nextState = ScMilestone.states[idx - 1];
        final updatedEntity = waitOn(env.client
            .updateMilestone(env, entity.id.value, {'state': nextState}));
        env.out.writeln('[INFO] Moved from "$currentState" to "$nextState"');
        entity.data = updatedEntity.data;
        return entity;
      }
    } else if (entity is ScTask) {
      final isComplete = entity.data[ScString('complete')];
      if (isComplete == ScBoolean.veritas()) {
        final storyId = entity.data[ScString('story_id')] as ScNumber;
        final taskId = entity.id;
        final updateMap = {'complete': false};
        final updatedEntity = waitOn(env.client.updateTask(
            env, storyId.value.toString(), taskId.value, updateMap));
        entity.data = updatedEntity.data;
        return entity;
      } else {
        env.err.writeln('[WARN] Task is already in an incomplete state.');
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
    } else {
      final maybeDataMap = args[0];
      ScEntity? entity;
      if (maybeDataMap is ScMap) {
        final ScMap dataMap = maybeDataMap;
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
          dataMap.remove(ScString('type'));
          dataMap.remove(ScDottedSymbol('type'));
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

              entity = waitOn(env.client.createEpic(env,
                  scExprToValue(dataMap, forJson: true, onlyEntityIds: true)));
              break;
            case 'milestone':
              final defaultFn = ScFnDefault();
              if (!dataMap.containsKey(ScString('group_id'))) {
                final defaultTeam =
                    defaultFn.invoke(env, ScList([ScString('group_id')]));
                if (defaultTeam is ScTeam) {
                  dataMap[ScString('group_id')] = defaultTeam.id;
                }
              }

              entity = waitOn(env.client.createMilestone(env,
                  scExprToValue(dataMap, forJson: true, onlyEntityIds: true)));
              break;
            case 'iteration':
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
                      "The \"story_id\" field must be a string or number, but received a ${rawStoryId.informalTypeName()}");
                }
                dataMap.remove(ScString('story_id'));
                dataMap.remove(ScDottedSymbol('story_id'));
                entity = waitOn(env.client.createTask(
                    env,
                    storyPublicId,
                    scExprToValue(dataMap,
                        forJson: true, onlyEntityIds: true)));
              }
              break;
            default:
              throw UnimplementedError();
          }
        }
      }
      return entity ?? ScNil();
    }
  }
}

class ScFnCreateStory extends ScBaseInvocable {
  static final ScFnCreateStory _instance = ScFnCreateStory._internal();
  ScFnCreateStory._internal();
  factory ScFnCreateStory() => _instance;

  @override
  String get help => "Create a Shortcut story given a data map.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final rawDataMap = args[0];
      ScMap dataMap = ScMap({});

      // NB: Support quick story creation, just name (title)
      if (rawDataMap is ScString) {
        dataMap[ScString('name')] = rawDataMap;
      } else if (rawDataMap is ScMap) {
        dataMap = rawDataMap;
      } else {
        throw BadArgumentsException(
            "The `create-story` function expects its argument to be a map, but received ${dataMap.informalTypeName()}");
      }

      dataMap[ScString('type')] = ScString('story');
      final createFn = ScFnCreate(); // handles defaults, parentage
      return createFn.invoke(env, ScList([dataMap]));
    } else {
      throw BadArgumentsException(
          "The `create-story` function expects 1 argument: a data map.");
    }
  }
}

class ScFnCreateEpic extends ScBaseInvocable {
  static final ScFnCreateEpic _instance = ScFnCreateEpic._internal();
  ScFnCreateEpic._internal();
  factory ScFnCreateEpic() => _instance;

  @override
  String get help => "Create a Shortcut epic given a data map.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final dataMap = args[0];
      if (dataMap is ScMap) {
        final createFn = ScFnCreate();
        dataMap[ScString('type')] = ScString('epic');
        return createFn.invoke(env, ScList([dataMap]));
      } else {
        throw BadArgumentsException(
            "The `create-epic` function expects its argument to be a map, but received ${dataMap.informalTypeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `create-epic` function expects 1 argument: a data map.");
    }
  }
}

class ScFnCreateMilestone extends ScBaseInvocable {
  static final ScFnCreateMilestone _instance = ScFnCreateMilestone._internal();
  ScFnCreateMilestone._internal();
  factory ScFnCreateMilestone() => _instance;

  @override
  String get help => "Create a Shortcut milestone given a data map.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final dataMap = args[0];
      if (dataMap is ScMap) {
        final createFn = ScFnCreate();
        dataMap[ScString('type')] = ScString('milestone');
        return createFn.invoke(env, ScList([dataMap]));
      } else {
        throw BadArgumentsException(
            "The `create-milestone` function expects its argument to be a map, but received ${dataMap.informalTypeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `create-milestone` function expects 1 argument: a data map.");
    }
  }
}

class ScFnCreateIteration extends ScBaseInvocable {
  static final ScFnCreateIteration _instance = ScFnCreateIteration._internal();
  ScFnCreateIteration._internal();
  factory ScFnCreateIteration() => _instance;

  @override
  String get help => "Create a Shortcut iteration given a data map.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length == 1) {
      final dataMap = args[0];
      if (dataMap is ScMap) {
        final createFn = ScFnCreate();
        dataMap[ScString('type')] = ScString('iteration');
        return createFn.invoke(env, ScList([dataMap]));
      } else {
        throw BadArgumentsException(
            "The `create-iteration` function expects its argument to be a map, but received ${dataMap.informalTypeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `create-iteration` function expects 1 argument: a data map.");
    }
  }
}

class ScFnCreateTask extends ScBaseInvocable {
  static final ScFnCreateTask _instance = ScFnCreateTask._internal();
  ScFnCreateTask._internal();
  factory ScFnCreateTask() => _instance;

  @override
  String get help => "Create a Shortcut task given a story ID and data map.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isNotEmpty) {
      ScEntity story = env.resolveArgEntity(args, 'create-task',
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
              "The `create-task` function expects its second argument to be a map, but received ${dataMap.informalTypeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `create-task` function expects either an entity and a create map, or just a create map and a parent entity that is a story.");
      }
    } else {
      throw BadArgumentsException(
          "The `create-task` function expects either an entity and a create map, or just a create map and a parent entity that is a story. Received no arguments.");
    }
  }
}

class ScFnMe extends ScBaseInvocable {
  static final ScFnMe _instance = ScFnMe._internal();
  ScFnMe._internal();
  factory ScFnMe() => _instance;

  static ScMember? me;

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
  String get help => 'Fetch the current member based on the API token.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != 1) {
      throw BadArgumentsException(
          "The `member` function expects 1 argument: the member ID.");
    } else {
      final memberId = args[0];
      if (memberId is ScString) {
        return waitOn(env.client.getMember(env, memberId.value));
      } else {
        throw BadArgumentsException(
            "The `member` function's argument must be a string, but received a ${memberId.informalTypeName()}");
      }
    }
  }
}

class ScFnMembers extends ScBaseInvocable {
  static final ScFnMembers _instance = ScFnMembers._internal();
  ScFnMembers._internal();
  factory ScFnMembers() => _instance;

  @override
  String get help => "Return _all_ members in this workspace.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""If parent entity is a team, this returns only members of the team (equivalent of `ls`).""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isNotEmpty) {
      throw BadArgumentsException("The `members` function takes no arguments.");
    } else {
      if (env.parentEntity is ScTeam) {
        return env.parentEntity!.data[ScString('member_ids')] as ScList;
      }
      return waitOn(env.client.getMembers(env));
    }
  }
}

class ScFnWorkflow extends ScBaseInvocable {
  static final ScFnWorkflow _instance = ScFnWorkflow._internal();
  ScFnWorkflow._internal();
  factory ScFnWorkflow() => _instance;

  @override
  String get help => "Return the Shortcut workflow with this ID.";

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""A workflow defines an ordered sequence of unstarted, in progress, and done states that a story can be in.

A workspace can have multiple workflows defined, but a given story falls only within one workflow.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != 1) {
      throw BadArgumentsException(
          "The `workflow` function expects 1 argument: the workflow ID.");
    } else {
      final workflowId = args[0];
      if (workflowId is ScString) {
        return waitOn(env.client.getWorkflow(env, workflowId.value));
      } else if (workflowId is ScNumber) {
        return waitOn(env.client.getWorkflow(env, workflowId.toString()));
      } else {
        throw BadArgumentsException(
            "The `workflow` function's first argument must be the workflow's ID, but received a ${workflowId.informalTypeName()}.");
      }
    }
  }
}

class ScFnWorkflows extends ScBaseInvocable {
  static final ScFnWorkflows _instance = ScFnWorkflows._internal();
  ScFnWorkflows._internal();
  factory ScFnWorkflows() => _instance;

  @override
  String get help => "Return all story workflows in this workspace.";

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
          "The `workflows` function takes no arguments.");
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
  String get help =>
      "Return the Shortcut epic workflow for the current workspace.";

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
          "The `epic-workflow` function doesn't accept any arguments, but received ${args.length}");
    }
  }
}

class ScFnTeam extends ScBaseInvocable {
  static final ScFnTeam _instance = ScFnTeam._internal();
  ScFnTeam._internal();
  factory ScFnTeam() => _instance;

  @override
  String get help => "Return the Shortcut team with this ID.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.length != 1) {
      throw BadArgumentsException(
          "The `team` function expects 1 argument: the team ID.");
    } else {
      final teamId = args[0];
      if (teamId is ScString) {
        return waitOn(env.client.getTeam(env, teamId.value));
      } else {
        throw BadArgumentsException(
            "The `team` function's first argument must be a string of the team's ID, but received a ${teamId.informalTypeName()}");
      }
    }
  }
}

class ScFnTeams extends ScBaseInvocable {
  static final ScFnTeams _instance = ScFnTeams._internal();
  ScFnTeams._internal();
  factory ScFnTeams() => _instance;

  @override
  String get help => "Return teams in this workspace.";

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isNotEmpty) {
      throw BadArgumentsException("The `teams` function takes no arguments.");
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
              "The `task` function expects a task ID that is a number or string, but received a ${taskId.informalTypeName()}");
        }
        final task = ScTask(story.id, taskId as ScString);
        return waitOn(task.fetch(env));
      } else {
        throw BadArgumentsException(
            "The `task` function expects two arguments, or just a task ID and your parent entity to be a story. Instead, it received one argument and the parent is _not_ a story.");
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
            "The story ID must be a number, a string, or the story itself, but received a ${storyId.informalTypeName()}");
      }
      if (taskId is ScNumber) {
        taskId = ScString(taskId.toString());
      } else if (taskId is! ScString) {
        throw BadArgumentsException(
            "The task ID must be a a number or string, but received a ${storyId.informalTypeName()}");
      }
      final task = ScTask(storyId as ScString, taskId as ScString);
      return waitOn(task.fetch(env));
    } else {
      throw BadArgumentsException(
          "The `task` function does not support ${args.length} arguments.");
    }
  }
}

class ScFnEpic extends ScBaseInvocable {
  static final ScFnEpic _instance = ScFnEpic._internal();
  ScFnEpic._internal();
  factory ScFnEpic() => _instance;

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

class ScFnStories extends ScBaseInvocable {
  @override
  String get help =>
      'Fetch epics, either all or based on the current parent entity.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""If no arguments are provided, the `stories` function checks the current parent entity:

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
          "The `stories` function expects a parent entity, or 1 argument that is an epic, iteration, team, member, or milestone.");
    } else {
      ScEntity entity = env.resolveArgEntity(args, 'epics');
      if (entity is ScEpic) {
        return waitOn(env.client.getStoriesInEpic(env, entity.id.value));
      } else if (entity is ScIteration) {
        return waitOn(env.client.getStoriesInIteration(env, entity.id.value));
      } else if (entity is ScTeam) {
        return waitOn(env.client.getStoriesInTeam(env, entity.id.value));
      } else if (entity is ScMilestone) {
        final epics = epicsInMilestone(env, entity);
        final stories = ScList([]);
        for (final epic in epics.innerList) {
          final e = epic as ScEpic;
          final ss = waitOn(env.client.getStoriesInEpic(env, e.id.value));
          stories.innerList.addAll(ss.innerList);
        }
        return stories;
      } else if (entity is ScMember) {
        final findStoriesFn = ScFnFindStories();
        final ScMap findMap = ScMap({
          ScString("owner_ids"): ScList([entity]),
        });
        return findStoriesFn.invoke(env, ScList([findMap]));
      } else {
        throw BadArgumentsException(
            "The `stories` function expects an epic, iteration, team, or milestone argument, but received a ${entity.informalTypeName()}");
      }
    }
  }
}

class ScFnEpics extends ScBaseInvocable {
  static final ScFnEpics _instance = ScFnEpics._internal();
  ScFnEpics._internal();
  factory ScFnEpics() => _instance;

  @override
  String get help =>
      'Fetch epics, either all or based on the current parent entity.';

  @override
  String get helpFull =>
      help +
      '\n\n' +
      r"""If no arguments are provided, the `epics` function checks the current parent entity:

- If a milestone, returns only epics attached to that milestone.
- If an iteration, returns only epics for stories that are part of the iteration.
- Else: returns _all_ epics in the current workspace.

Warning: That last eventuality can be an expensive call.""";

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    ScEntity entity = env.resolveArgEntity(args, 'epics');
    if (entity is ScMilestone) {
      return epicsInMilestone(env, entity);
    } else if (entity is ScIteration) {
      return epicsInIteration(env, entity);
    } else if (entity is ScTeam) {
      return epicsInTeam(env, entity);
    } else {
      return waitOn(env.client.getEpics(env));
    }
  }
}

class ScFnMilestone extends ScBaseInvocable {
  static final ScFnMilestone _instance = ScFnMilestone._internal();
  ScFnMilestone._internal();
  factory ScFnMilestone() => _instance;

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
      } else {
        final milestones = waitOn(env.client.getMilestones(env));
        return milestones;
      }
    } else {
      throw BadArgumentsException(
          "The `milestones` function does not take any arguments, but received ${args.length}");
    }
  }
}

class ScFnIteration extends ScBaseInvocable {
  static final ScFnIteration _instance = ScFnIteration._internal();
  ScFnIteration._internal();
  factory ScFnIteration() => _instance;

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
        } else {
          return iterations;
        }
      }
    } else if (args.length == 1) {
      final entity = env.resolveArgEntity(args, 'iterations');
      if (entity is ScTeam) {
        return iterationsOfTeam(env, entity);
      } else {
        throw BadArgumentsException(
            "The `iterations` function expects no arguments, or a team, but received a ${entity.informalTypeName()}");
      }
    } else {
      throw BadArgumentsException(
          "The `iterations` function expects no arguments or a single team, but received ${args.length} arguments.");
    }
  }
}

class ScFnMax extends ScBaseInvocable {
  static final ScFnMax _instance = ScFnMax._internal();
  ScFnMax._internal();
  factory ScFnMax() => _instance;

  @override
  String get help => 'Returns the largest argument.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw UnsupportedError("The max function expects at least one argument.");
    } else if (args.length == 1) {
      final arg = args[0];
      if (arg is ScList) {
        return arg.reduce((acc, value) {
          return value > acc ? value : acc;
        });
      } else {
        return arg;
      }
    } else {
      return args.reduce((acc, value) {
        return value > acc ? value : acc;
      });
    }
  }
}

class ScFnMin extends ScBaseInvocable {
  static final ScFnMin _instance = ScFnMin._internal();
  ScFnMin._internal();
  factory ScFnMin() => _instance;

  @override
  String get help => 'Returns the smallest argument.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw BadArgumentsException(
          "The `min` function expects at least one argument.");
    } else if (args.length == 1) {
      final arg = args[0];
      if (arg is ScList) {
        return arg.reduce((acc, value) {
          return value < acc ? value : acc;
        });
      } else {
        return arg;
      }
    } else {
      return args.reduce((acc, value) {
        return value < acc ? value : acc;
      });
    }
  }
}

class ScFnEquals extends ScBaseInvocable {
  static final ScFnEquals _instance = ScFnEquals._internal();
  ScFnEquals._internal();
  factory ScFnEquals() => _instance;

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
  String get help => 'Adds values together.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScNumber(0);
    } else {
      return args.reduce((acc, item) {
        final addableAcc = acc as ScAddable;
        final addableItem = item as ScAddable;
        return addableAcc.add(addableItem);
      });
    }
  }
}

class ScFnSubtract extends ScBaseInvocable {
  static final ScFnSubtract _instance = ScFnSubtract._internal();
  ScFnSubtract._internal();
  factory ScFnSubtract() => _instance;

  @override
  String get help => 'Subtracts later arguments from earlier ones.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScNumber(0);
    } else {
      return args.reduce((acc, item) {
        final subtractableAcc = acc as ScSubtractable;
        final subtractableItem = item as ScSubtractable;
        return subtractableAcc.subtract(subtractableItem);
      });
    }
  }
}

class ScFnMultiply extends ScBaseInvocable {
  static final ScFnMultiply _instance = ScFnMultiply._internal();
  ScFnMultiply._internal();
  factory ScFnMultiply() => _instance;

  @override
  String get help => 'Multiplies its arguments.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      return ScNumber(1);
    } else {
      return args.reduce((acc, item) {
        final multipliableAcc = acc as ScMultipliable;
        final multipliableItem = item as ScMultipliable;
        return multipliableAcc.multiply(multipliableItem);
      });
    }
  }
}

class ScFnDivide extends ScBaseInvocable {
  static final ScFnDivide _instance = ScFnDivide._internal();
  ScFnDivide._internal();
  factory ScFnDivide() => _instance;

  @override
  String get help => 'Divides earlier arguments by later ones.';

  @override
  // TODO: implement helpFull
  String get helpFull => help;

  @override
  ScExpr invoke(ScEnv env, ScList args) {
    if (args.isEmpty) {
      throw BadArgumentsException(
          "The `/` division function requires at least a divisor.");
    } else if (args.length == 1) {
      final divisor = args[0] as ScDivisible;
      return ScNumber(1).divide(divisor);
    } else {
      return args.reduce((acc, item) {
        final divisibleAcc = acc as ScDivisible;
        final divisibleItem = item as ScDivisible;
        return divisibleAcc.divide(divisibleItem);
      });
    }
  }
}

class ScFnModulo extends ScBaseInvocable {
  static final ScFnModulo _instance = ScFnModulo._internal();
  ScFnModulo._internal();
  factory ScFnModulo() => _instance;

  @override
  String get help => 'Return the modulo of the two numbers.';

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
              "The `mod` function's second argument must be a number, but received a ${b.informalTypeName()}");
        }
      } else {
        throw BadArgumentsException(
            "The `mod` function's first argument must be a number, but received a ${b.informalTypeName()}");
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
  String informalTypeName() {
    return "list";
  }

  void add(ScExpr expr) {
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
        } else if (evaledItem is ScBaseInvocable) {
          finalItem = evaledItem.invoke(env, ScList([]));
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

  /// Mutable skip
  ScList skip(int i) {
    // innerList = List<ScExpr>.from(innerList.skip(i));
    innerList = List<ScExpr>.from(innerList.sublist(i));
    return this;
  }

  ScExpr reduce(ScExpr Function(dynamic acc, dynamic item) fn) {
    return innerList.reduce(fn);
  }

  static from(ScList otherScList) {
    final newInnerList = List<ScExpr>.from(otherScList.innerList);
    return ScList(newInnerList);
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
  void insert(int index, ScExpr expr) {
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

  /// Mutable sublist
  ScExpr sublist(int start, int end) {
    return ScList(innerList.sublist(start, end));
  }

  ScExpr sublistImmutable(int start, int end) {
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
}

class ScMap extends ScExpr {
  Map<ScExpr, ScExpr> innerMap;
  ScMap(this.innerMap);

  get keys => innerMap.keys;

  num get length => innerMap.length;

  bool get isEmpty => innerMap.isEmpty;
  bool get isNotEmpty => innerMap.isNotEmpty;

  @override
  String informalTypeName() {
    return "map";
  }

  void remove(ScExpr key) {
    innerMap.remove(key);
  }

  bool containsKey(ScExpr key) => innerMap.containsKey(key);

  @override

  /// Return an [ScMap] where all keys and values have been evaluated.
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
        } else if (evaledKey is ScBaseInvocable) {
          finalKey = evaledKey.invoke(env, ScList([]));
        } else {
          finalKey = evaledKey;
        }

        ScExpr finalValue;
        if (evaledValue is ScAnonymousFunction) {
          finalValue = evaledValue;
        } else if (evaledValue is ScBaseInvocable) {
          finalValue = evaledValue.invoke(env, ScList([]));
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

  void addAll(Map<String, dynamic> map) {
    for (final key in map.keys) {
      final value = map[key];
      final scKey = ScString(key);
      // Types!
      ScExpr scValue = valueToScExpr(value);
      this[scKey] = scValue;
    }
  }

  void addMap(ScMap map) {
    for (final key in map.keys) {
      final value = map[key];
      this[key] = value!;
    }
  }

  ScExpr where(ScBoolean Function(ScExpr key, ScExpr value) fn) {
    // Why does dart have removeWhere but not where for Map?
    innerMap.removeWhere((k, v) {
      final scBool = fn(k, v);
      if (scBool == ScBoolean.veritas()) {
        return false; // don't remove
      } else {
        return true; // remove
      }
    });
    return this;
  }

  @override
  String toJson() {
    JsonEncoder jsonEncoder = JsonEncoder.withIndent('  ');
    return jsonEncoder.convert(scExprToValue(this, forJson: true));
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
  final ScString id;
  ScMap data = ScMap({});
  ScString? title;

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
    ScString('id'),
    ScString('iteration_id'),
    ScString('mention_name'),
    ScString('milestone_id'),
    ScString('name'),
    ScString('requested_by_id'),
    ScString('owner_ids'),
    ScString('profile'),
    ScString('start_date'),
    ScString('started_at'),
    ScString('state'),
    ScString('states'),
    ScString('status'),
    ScString('started_at'),
    ScString('story_type'),
    ScString('workflow_state_id'),
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
    data.addAll(map);
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
    for (final key in data.keys) {
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
          data[key] = env.resolveTeam(env, id);
        }
      }
      if (teamsKeys.contains(key)) {
        final ids = data[key];
        if (ids is ScList) {
          List<ScExpr> l = [];
          for (final id in ids.innerList) {
            if (id is ScString) {
              l.add(env.resolveTeam(env, id));
            }
          }
          data[key] = ScList(l);
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
        // TODO Consider whether the same is necessary for ScTeam
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
      sb.writeln("${informalTypeName().capitalize()} $id");
      env.indentIndex += 1;
      sb.write(env.indentString());
      sb.write(data.printToString(env));
      env.indentIndex -= 1;
      return sb.toString();
    }
  }

  @override
  String informalTypeName() {
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
}

class ScMember extends ScEntity {
  ScMember(ScString id) : super(id);

  static final entityColor = green;

  @override
  String informalTypeName() {
    return 'member';
  }

  factory ScMember.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScMember(ScString(data['id'].toString())).addAll(env, data)
        as ScMember;
  }

  @override
  Future<ScMember> fetch(ScEnv env) async {
    final member = await env.client.getMember(env, id.value);
    data = member.data;
    return this;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    return ScList([this]);
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) {
    throw OperationNotSupported(
        "You cannot update a Shortcut member via its API.");
  }

  @override
  String printToString(ScEnv env) {
    if (data.isEmpty) {
      waitOn(fetch(env));
    }
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
        name = (data[ScString('name')] as ScString).value;
        mentionName = (data[ScString('mention_name')] as ScString).value;
      }
      final shortName = truncate(name, env.displayWidth);
      var prefix = env.styleWith('[User]', [green]);
      if (role != null) {
        final r = role as ScString;
        prefix = env.styleWith('[${r.value.capitalize()}]', [entityColor])!;
      }
      final memberMentionName =
          env.styleWith("[@$mentionName]", [entityColor])!;
      final memberName = env.styleWith(shortName, [yellow])!;
      final memberId = env.styleWith("[$id]", [entityColor])!;
      return "$prefix$memberMentionName $memberName $memberId";
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
      sb.writeln(env.styleWith('   !! DISABLED !!', [red]));
    }

    final profile = data[ScString('profile')];
    if (profile is ScMap) {
      final name = profile[ScString('name')];
      if (name is ScString) {
        sb.write(env.styleWith(lblName.padLeft(labelWidth), [entityColor]));
        sb.writeln(name.value);
      }

      final id = data[ScString('id')];
      if (id is ScString) {
        sb.write(env.styleWith(lblId.padLeft(labelWidth), [entityColor]));
        sb.writeln(id.value);
      }

      final mentionName = profile[ScString('mention_name')];
      if (mentionName is ScString) {
        sb.write(
            env.styleWith(lblMentionName.padLeft(labelWidth), [entityColor]));
        sb.writeln("@${mentionName.value}");
      }
    }

    final teams = data[ScString('group_ids')] as ScList;
    if (teams.isNotEmpty) {
      sb.write(env.styleWith(lblTeams.padLeft(labelWidth), [entityColor]));
      if (teams.length == 1) {
        final team = teams[0] as ScTeam;
        sb.writeln(team.printToString(env));
      } else {
        var isFirst = true;
        for (final owner in teams.innerList) {
          if (isFirst) {
            isFirst = false;
            sb.writeln(owner.printToString(env));
          } else {
            sb.writeln('${"".padLeft(labelWidth)}${owner.printToString(env)}');
          }
        }
      }
    }

    env.out.writeln(sb.toString());
    return ScNil();
  }
}

class ScTeam extends ScEntity {
  ScTeam(ScString id) : super(id);

  static final entityColor = lightRed;

  factory ScTeam.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScTeam(ScString(data['id'].toString())).addAll(env, data) as ScTeam;
  }

  @override
  String informalTypeName() {
    return 'team';
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final team = await env.client.getTeam(env, id.value);
    data = team.data;
    return this;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    // TODO Use this for stories within team as parent
    // return env.client.getStoriesInTeam(env, id.value);
    return data[ScString('member_ids')] as ScList;
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) {
    // TODO: implement update for ScTeam
    throw UnimplementedError();
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
      final prefix = env.styleWith('[Team]', [entityColor]);
      final teamMentionName =
          env.styleWith("[@${mentionName.value}]", [green])!;
      final teamName = env.styleWith(shortName, [yellow])!;
      final teamId = env.styleWith("[$id]", [entityColor])!;
      return "$prefix$teamMentionName $teamName $teamId";
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
      sb.writeln(env.styleWith('   !! ARCHIVED !!', [red]));
    }

    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    sb.write(env.styleWith(lblTeam.padLeft(labelWidth), [entityColor]));
    sb.writeln(env.styleWith(name.value, [yellow, styleUnderlined]));

    final id = data[ScString('id')];
    if (id is ScString) {
      sb.write(env.styleWith(lblId.padLeft(labelWidth), [entityColor]));
      sb.writeln(id);
    }

    final mentionName = data[ScString('mention_name')];
    if (mentionName is ScString) {
      sb.write(
          env.styleWith(lblMentionName.padLeft(labelWidth), [entityColor]));
      sb.writeln("@${mentionName.value}");
    }

    env.out.writeln(sb.toString());
    return ScNil();
  }
}

class ScMilestone extends ScEntity {
  ScMilestone(ScString id) : super(id);

  static final entityColor = red;
  static final states = ["to do", "in progress", "done"];

  @override
  String informalTypeName() {
    return 'milestone';
  }

  factory ScMilestone.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScMilestone(ScString(data['id'].toString())).addAll(env, data)
        as ScMilestone;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    return env.client.getEpicsInMilestone(env, id.value);
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final milestone =
        await env.client.updateMilestone(env, id.value, updateMap);
    data = milestone.data;
    return this;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final milestone = await env.client.getMilestone(env, id.value);
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
      final prefix = env.styleWith('[Milestone]', [red]);
      final milestoneName = env.styleWith(shortName, [yellow])!;
      final milestoneId = env.styleWith("[${id.value}]", [red])!;
      return "$prefix $milestoneName $milestoneId";
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    // TODO calculate
    final labelWidth = 12;
    if (!data.containsKey(ScString('description'))) {
      waitOn(fetch(env));
    }
    final sb = StringBuffer('\n');
    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    sb.write(env.styleWith('Milestone '.padLeft(labelWidth), [entityColor]));
    sb.writeln(env.styleWith(name.value, [yellow, styleUnderlined]));

    final milestoneId = id.value;
    sb.write(env.styleWith('Id '.padLeft(labelWidth), [entityColor]));
    sb.writeln(milestoneId);

    final startedAt = data[ScString('started_at')];
    if (startedAt is ScString) {
      sb.write(env.styleWith('Started '.padLeft(labelWidth), [entityColor]));
      sb.writeln(startedAt.value);
    } else if (startedAt == ScNil()) {
      sb.write(env.styleWith('Started '.padLeft(labelWidth), [entityColor]));
      sb.writeln('N/A');
    }

    final completedAt = data[ScString('completed_at')];
    if (completedAt is ScString) {
      sb.write(env.styleWith('Completed '.padLeft(labelWidth), [entityColor]));
      sb.writeln(completedAt.value);
    } else if (completedAt == ScNil()) {
      sb.write(env.styleWith('Completed '.padLeft(labelWidth), [entityColor]));
      sb.writeln('N/A');
    }

    final state = data[ScString('state')];
    if (state is ScString) {
      sb.write(env.styleWith('State '.padLeft(labelWidth), [entityColor]));
      sb.writeln(state.value);
    }

    env.out.writeln(sb.toString());
    return ScNil();
  }
}

class ScEpic extends ScEntity {
  ScEpic(ScString id) : super(id);

  static final entityColor = green;

  @override
  String informalTypeName() {
    return 'epic';
  }

  factory ScEpic.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScEpic(ScString(data['id'].toString())).addAll(env, data) as ScEpic;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) {
    return env.client.getStoriesInEpic(env, id.value);
  }

  @override
  Future<ScEpic> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final epic = await env.client.updateEpic(env, id.value, updateMap);
    data = epic.data;
    return this;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final epic = await env.client.getEpic(env, id.value);
    data = epic.data;
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
      final prefix = env.styleWith('[Epic]', [entityColor]);
      final epicName = env.styleWith(shortName, [yellow])!;
      final epicId = env.styleWith("[${id.value}]", [entityColor])!;
      return "$prefix $epicName $epicId";
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    // TODO calculate
    final labelWidth = 12;
    if (!data.containsKey(ScString('description'))) {
      waitOn(fetch(env));
    }
    final sb = StringBuffer('\n');

    final isArchived = data[ScString('archived')];
    if (isArchived == ScBoolean.veritas()) {
      sb.writeln(env.styleWith('   !! ARCHIVED !!', [red]));
    }
    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    sb.write(env.styleWith('Epic '.padLeft(labelWidth), [entityColor]));
    sb.writeln(env.styleWith(name.value, [yellow, styleUnderlined]));

    final epicId = id.value;
    sb.write(env.styleWith('Id '.padLeft(labelWidth), [entityColor]));
    sb.writeln(epicId);

    final state = data[ScString('epic_state_id')];
    if (state is ScEpicWorkflowState) {
      sb.write(env.styleWith('State '.padLeft(labelWidth), [entityColor]));
      sb.write(state.printToString(env));
    }
    sb.writeln();

    final owners = data[ScString('owner_ids')] as ScList;
    sb.write(env.styleWith('Owned by '.padLeft(labelWidth), [entityColor]));
    if (owners.isEmpty) {
      sb.writeln('<No one>');
    } else {
      if (owners.length == 1) {
        final owner = owners[0] as ScMember;
        sb.writeln(owner.printToString(env));
      } else {
        var isFirst = true;
        for (final owner in owners.innerList) {
          if (isFirst) {
            isFirst = false;
            sb.writeln(owner.printToString(env));
          } else {
            sb.writeln('${"".padLeft(labelWidth)}${owner.printToString(env)}');
          }
        }
      }
    }

    final team = data[ScString('group_id')];
    if (team is ScTeam) {
      sb.write(env.styleWith('Team '.padLeft(labelWidth), [entityColor]));
      sb.write(team.printToString(env));
      sb.writeln();
    }

    final stats = data[ScString('stats')];
    if (stats is ScMap) {
      final numPoints = stats[ScString('num_points')];
      final numPointsDone = stats[ScString('num_points_done')];
      if (numPoints is ScNumber) {
        if (numPointsDone is ScNumber) {
          sb.write(env.styleWith('Points '.padLeft(labelWidth), [entityColor]));
          sb.write("$numPointsDone/$numPoints points done");
        }
      }
      sb.writeln();
    }

    env.out.writeln(sb.toString());
    return ScNil();
  }
}

class ScStory extends ScEntity {
  ScStory(ScString id) : super(id);

  static final entityColor = magenta;

  @override
  String informalTypeName() {
    return 'story';
  }

  factory ScStory.fromMap(ScEnv env, Map<String, dynamic> data) {
    var tasksData = data['tasks'] ?? [];
    ScList tasks = ScList([]);
    if (tasksData.isNotEmpty) {
      tasks = ScList(List<ScExpr>.from(tasksData.map((taskMap) =>
          ScTask.fromMap(env, ScString(data['id'].toString()), taskMap))));
    }
    data.remove('tasks');
    final story =
        ScStory(ScString(data['id'].toString())).addAll(env, data) as ScStory;
    story.data[ScString('tasks')] = tasks;
    return story;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) {
    return env.client.getTasksInStory(env, id.value);
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final story = await env.client.updateStory(env, id.value, updateMap);
    data = story.data;
    return this;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    if (env.workflowStatesById.isEmpty) {
      final fetchAllFn = ScFnFetchAll();
      fetchAllFn.invoke(env, ScList([]));
    }
    final story = await env.client.getStory(env, id.value);
    data = story.data;
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

      final state = data[ScString('workflow_state_id')];
      String storyStateType = '';
      if (state is ScWorkflowState) {
        final stateType = (state.data[ScString('type')] as ScString).value;
        var color = entityColor;
        switch (stateType) {
          case 'unstarted':
            color = lightRed;
            break;
          case 'started':
            color = lightMagenta;
            break;
          case 'done':
            color = lightGreen;
            break;
        }
        final stateTypeAbbrev = stateType[0].toUpperCase();
        storyStateType = env.styleWith('[$stateTypeAbbrev]', [color])!;
      }

      final type = data[ScString('story_type')];
      String storyType = '';
      if (type is ScString) {
        var color = entityColor;
        var ts = type.value;
        switch (ts) {
          case 'bug':
            color = lightRed;
            break;
          case 'chore':
            color = lightGray;
            break;
          case 'feature':
            color = lightYellow;
            break;
        }
        final typeAbbrev = ts[0].toUpperCase();
        storyType = env.styleWith('[$typeAbbrev]', [color])!;
      }

      final prefix =
          env.styleWith('[Story]', [entityColor])! + storyType + storyStateType;
      final storyName = env.styleWith(shortName, [yellow])!;
      final storyId = env.styleWith("[${id.value}]", [entityColor])!;
      return "$prefix $storyName $storyId";
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    // TODO Calculate dynamically based on widest label
    final labelWidth = 12;
    if (!data.containsKey(ScString('description'))) {
      // This is either a StorySlim from the API, or a story stub from parentEntity
      waitOn(fetch(env));
    }
    final sb = StringBuffer('\n');
    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    final isArchived = data[ScString('archived')];
    if (isArchived == ScBoolean.veritas()) {
      sb.writeln(env.styleWith('   !! ARCHIVED !!', [red]));
    }
    final storyType = data[ScString('story_type')];
    var storyLabel = 'Story';
    if (storyType is ScString) {
      storyLabel = storyType.value.capitalize();
    }
    sb.write(env.styleWith('$storyLabel '.padLeft(labelWidth), [entityColor]));
    sb.writeln(env.styleWith(name.value, [yellow, styleUnderlined]));

    final storyId = id.value;
    sb.write(env.styleWith('Id '.padLeft(labelWidth), [entityColor]));
    sb.writeln(storyId);

    final state = data[ScString('workflow_state_id')];
    if (state is ScWorkflowState) {
      sb.write(env.styleWith('State '.padLeft(labelWidth), [entityColor]));
      sb.write(state.printToString(env));
    }
    sb.writeln();

    final epic = data[ScString('epic_id')];
    if (epic != ScNil()) {
      sb.write(env.styleWith('Epic '.padLeft(labelWidth), [entityColor]));
      if (epic is ScEpic) {
        sb.write(epic.printToString(env));
      } else if (epic is ScNumber) {
        final epicEntity = ScEpic(ScString(epic.value.toString()));
        waitOn(epicEntity.fetch(env));
        sb.write(epicEntity.printToString(env));
      }
      sb.writeln();
    }

    final iteration = data[ScString('iteration_id')];
    if (iteration != ScNil()) {
      sb.write(env.styleWith('Iteration '.padLeft(labelWidth), [entityColor]));
      if (iteration is ScIteration) {
        sb.write(iteration.printToString(env));
      } else if (iteration is ScNumber) {
        final iterationEntity =
            ScIteration(ScString(iteration.value.toString()));
        waitOn(iterationEntity.fetch(env));
        sb.write(iterationEntity.printToString(env));
      }
      sb.writeln();
    }

    final owners = data[ScString('owner_ids')] as ScList;
    if (owners.isNotEmpty) {
      sb.write(env.styleWith('Owned by '.padLeft(labelWidth), [entityColor]));
      if (owners.length == 1) {
        final owner = owners[0] as ScMember;
        sb.writeln(owner.printToString(env));
      } else {
        var isFirst = true;
        for (final owner in owners.innerList) {
          if (isFirst) {
            isFirst = false;
            sb.writeln(owner.printToString(env));
          } else {
            sb.writeln('${"".padLeft(labelWidth)}${owner.printToString(env)}');
          }
        }
      }
    }

    final team = data[ScString('group_id')];
    if (team != ScNil()) {
      sb.write(env.styleWith('Team '.padLeft(labelWidth), [entityColor]));
      if (team is ScTeam) {
        sb.write(team.printToString(env));
      } else if (team is ScString) {
        final teamEntity = ScTeam(ScString(team.value));
        waitOn(teamEntity.fetch(env));
        sb.write(teamEntity.printToString(env));
      }
      sb.writeln();
    }

    final estimate = data[ScString('estimate')];
    if (estimate is ScNumber) {
      sb.write(env.styleWith('Estimate '.padLeft(labelWidth), [entityColor]));
      if (estimate == ScNumber(1)) {
        sb.write("$estimate point");
      } else {
        sb.write("$estimate points");
      }
      sb.writeln();
    }

    final deadline = data[ScString('deadline')];
    if (deadline is ScString) {
      sb.write(env.styleWith('Deadline '.padLeft(labelWidth), [entityColor]));
      sb.write(deadline);
      sb.writeln();
    }

    final labels = data[ScString('labels')];
    if (labels is ScList && labels.isNotEmpty) {
      sb.write(env.styleWith('Labels '.padLeft(labelWidth), [entityColor]));
      for (var i = 0; i < labels.length; i++) {
        final label = labels[i];
        if (label is ScMap) {
          final name = label[ScString('name')];
          if (name is ScString) {
            sb.write(name);
          }
          if (i + 1 != labels.length) {
            sb.write(', ');
          }
        }
      }
      sb.writeln();
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
        sb.write(env.styleWith('Tasks '.padLeft(labelWidth), [entityColor]));
        sb.writeln('$numComplete/${ts.length} complete:');
        for (final task in ts.innerList) {
          final t = task as ScTask;
          sb.writeln("            ${t.printToString(env)}");
        }
      }
    }

    env.out.writeln(sb.toString());
    return ScNil();
  }
}

class ScTask extends ScEntity {
  ScTask(this.storyId, ScString taskId) : super(taskId);
  final ScString storyId;

  @override
  String informalTypeName() {
    return 'task';
  }

  factory ScTask.fromMap(
      ScEnv env, ScString storyId, Map<String, dynamic> data) {
    return ScTask(storyId, ScString(data['id'].toString())).addAll(env, data)
        as ScTask;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) {
    throw OperationNotSupported(
        "The `ls` function doesn't have a meaningful purpose for tasks. Try `details` for a subset or `data` if you want to see everything about your task.");
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final task =
        await env.client.updateTask(env, storyId.value, id.value, updateMap);
    data = task.data;
    return this;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final task = await env.client.getTask(env, storyId.value, id.value);
    data = task.data;
    return this;
  }

  @override
  String printToString(ScEnv env) {
    if (env.isPrintJson) {
      return super.printToString(env);
    } else {
      // TODO Consider config of which fields users want printed
      // TODO Consider prefab minimal, medium, full printings
      final description = dataFieldOr<ScString?>(data, 'description', title) ??
          ScString("<No description: run fetch>");
      final shortDescription = truncate(description.value, env.displayWidth);
      final complete =
          dataFieldOr<ScBoolean>(data, 'complete', ScBoolean.falsitas());
      String status;
      if (complete == ScBoolean.veritas()) {
        status = env.styleWith("[DONE]", [green])!;
      } else {
        status = env.styleWith("[TODO]", [red, styleUnderlined])!;
      }
      final prefix = env.styleWith('[Task]', [lightMagenta]);
      final taskDescription = env.styleWith(shortDescription, [yellow])!;
      final taskId = env.styleWith("[${id.value}]", [lightMagenta])!;
      return "$prefix$status $taskDescription $taskId";
    }
  }
}

class ScIteration extends ScEntity {
  ScIteration(ScString id) : super(id);

  static final entityColor = cyan;

  @override
  String informalTypeName() {
    return 'iteration';
  }

  factory ScIteration.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScIteration(ScString(data['id'].toString())).addAll(env, data)
        as ScIteration;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) {
    return env.client.getStoriesInIteration(env, id.value);
  }

  @override
  Future<ScEntity> update(ScEnv env, Map<String, dynamic> updateMap) async {
    final iteration =
        await env.client.updateIteration(env, id.value, updateMap);
    data = iteration.data;
    return this;
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final iteration = await env.client.getIteration(env, id.value);
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
      final prefix = env.styleWith('[Iteration]', [entityColor]);
      final iterationName = env.styleWith(shortName, [yellow])!;
      final iterationId = env.styleWith("[${id.value}]", [entityColor])!;
      return "$prefix $iterationName $iterationId";
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    // TODO calculate
    final labelWidth = 12;
    if (!data.containsKey(ScString('description'))) {
      waitOn(fetch(env));
    }
    final sb = StringBuffer('\n');
    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    sb.write(env.styleWith('Iteration '.padLeft(labelWidth), [entityColor]));
    sb.writeln(env.styleWith(name.value, [yellow, styleUnderlined]));

    final epicId = id.value;
    sb.write(env.styleWith('Id '.padLeft(labelWidth), [entityColor]));
    sb.writeln(epicId);

    final teams = data[ScString('group_ids')] as ScList;
    if (teams.isNotEmpty) {
      sb.write(env.styleWith('Teams '.padLeft(labelWidth), [entityColor]));
      if (teams.length == 1) {
        final team = teams[0] as ScTeam;
        sb.writeln(team.printToString(env));
      } else {
        var isFirst = true;
        for (final owner in teams.innerList) {
          if (isFirst) {
            isFirst = false;
            sb.writeln(owner.printToString(env));
          } else {
            sb.writeln('${"".padLeft(labelWidth)}${owner.printToString(env)}');
          }
        }
      }
    }

    final startDate = data[ScString('start_date')];
    if (startDate is ScString) {
      sb.write(env.styleWith('Start '.padLeft(labelWidth), [entityColor]));
      sb.writeln(startDate.value);
    }

    final endDate = data[ScString('end_date')];
    if (endDate is ScString) {
      sb.write(env.styleWith('End '.padLeft(labelWidth), [entityColor]));
      sb.writeln(endDate.value);
    }

    final status = data[ScString('status')];
    if (status is ScString) {
      sb.write(env.styleWith('Status '.padLeft(labelWidth), [entityColor]));
      sb.writeln(status.value);
    }

    final stats = data[ScString('stats')];
    if (stats is ScMap) {
      final numPoints = stats[ScString('num_points')];
      final numPointsDone = stats[ScString('num_points_done')];
      if (numPoints is ScNumber) {
        if (numPointsDone is ScNumber) {
          sb.write(env.styleWith('Points '.padLeft(labelWidth), [entityColor]));
          sb.write("$numPointsDone/$numPoints points done");
        }
      }
    }
    sb.writeln();

    env.out.writeln(sb.toString());
    return ScNil();
  }
}

class ScWorkflow extends ScEntity {
  ScWorkflow(ScString id) : super(id);

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

  static final entityColor = lightCyan;

  @override
  String informalTypeName() {
    return 'workflow';
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    final workflow = await env.client.getWorkflow(env, id.value);
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
      final prefix = env.styleWith('[Workflow]', [lightCyan]);
      final workflowName = env.styleWith(shortName, [yellow])!;
      final workflowId = env.styleWith("[${id.value}]", [lightCyan])!;
      return "$prefix $workflowName $workflowId";
    }
  }

  @override
  ScExpr printSummary(ScEnv env) {
    final lblWorkflow = 'Workflow ';
    final lblId = 'Id ';
    final lblStates = 'States ';
    int labelWidth = maxPaddedLabelWidth([lblWorkflow, lblId, lblStates]);

    if (!data.containsKey(ScString('description'))) {
      waitOn(fetch(env));
    }
    final sb = StringBuffer('\n');

    final name = dataFieldOr<ScString?>(data, 'name', title) ??
        ScString("<No name: run fetch>");
    sb.write(env.styleWith(lblWorkflow.padLeft(labelWidth), [entityColor]));
    sb.writeln(env.styleWith(name.value, [yellow, styleUnderlined]));

    final workflowId = id.value;
    sb.write(env.styleWith(lblId.padLeft(labelWidth), [entityColor]));
    sb.writeln(workflowId);

    final states = data[ScString('states')] as ScList;
    sb.write(env.styleWith(lblStates.padLeft(labelWidth), [entityColor]));
    var isFirst = true;
    for (final state in states.innerList) {
      if (isFirst) {
        isFirst = false;
        sb.writeln(state.printToString(env));
      } else {
        sb.writeln('${"".padLeft(labelWidth)}${state.printToString(env)}');
      }
    }

    env.out.writeln(sb.toString());
    return ScNil();
  }
}

class ScWorkflowState extends ScEntity {
  ScWorkflowState(ScString id) : super(id);

  static final entityColor = lightCyan;

  factory ScWorkflowState.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScWorkflowState(ScString(data['id'].toString())).addAll(env, data)
        as ScWorkflowState;
  }

  @override
  String informalTypeName() {
    return 'workflow state';
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    env.err.writeln("To fetch a workflow state, fetch its workflow instead.");
    return this;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    env.err
        .writeln("The `ls` function is not supported within workflow states.");
    return ScList([]);
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
        var color = entityColor;
        switch (ts) {
          case 'unstarted':
            color = lightRed;
            break;
          case 'started':
            color = lightMagenta;
            break;
          case 'done':
            color = lightGreen;
            break;
        }
        typeStr = env.styleWith('[$ts]', [color])!;
      }
      final prefix = env.styleWith('[Workflow State]', [entityColor]);
      final workflowStateName = env.styleWith(shortName, [yellow])!;
      final workflowStateId = env.styleWith("[${id.value}]", [entityColor])!;
      return "$prefix$typeStr $workflowStateName $workflowStateId";
    }
  }
}

class ScEpicWorkflow extends ScEntity {
  ScEpicWorkflow(ScString id) : super(id);

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

  static final entityColor = lightCyan;

  @override
  String informalTypeName() {
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
      final prefix = env.styleWith('[Epic Workflow]', [entityColor]);
      final epicWorkflowName = env.styleWith(shortName, [yellow])!;
      final epicWorkflowId = env.styleWith("[${id.value}]", [entityColor])!;
      return "$prefix $epicWorkflowName $epicWorkflowId";
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
    sb.write(env.styleWith(lblWorkflow.padLeft(labelWidth), [entityColor]));
    sb.writeln(env.styleWith(name, [yellow, styleUnderlined]));

    final workflowId = id.value;
    sb.write(env.styleWith(lblId.padLeft(labelWidth), [entityColor]));
    sb.writeln(workflowId);

    sb.write(env.styleWith(lblDefaultState.padLeft(labelWidth), [entityColor]));
    final defaultEpicWorkflowStateId =
        data[ScString('default_epic_state_id')] as ScNumber;
    final epicStates = data[ScString('epic_states')] as ScList;
    for (final epicState in epicStates.innerList) {
      final es = epicState as ScEpicWorkflowState;
      if (int.tryParse(es.id.value) == defaultEpicWorkflowStateId.value) {
        sb.writeln(es.printToString(env));
        break;
      }
    }

    final states = data[ScString('epic_states')] as ScList;
    sb.write(env.styleWith(lblStates.padLeft(labelWidth), [entityColor]));
    var isFirst = true;
    for (final state in states.innerList) {
      if (isFirst) {
        isFirst = false;
        sb.writeln(state.printToString(env));
      } else {
        sb.writeln('${"".padLeft(labelWidth)}${state.printToString(env)}');
      }
    }

    env.out.writeln(sb.toString());
    return ScNil();
  }
}

class ScEpicWorkflowState extends ScEntity {
  ScEpicWorkflowState(ScString id) : super(id);

  static final entityColor = lightCyan;

  factory ScEpicWorkflowState.fromMap(ScEnv env, Map<String, dynamic> data) {
    return ScEpicWorkflowState(ScString(data['id'].toString()))
        .addAll(env, data) as ScEpicWorkflowState;
  }

  @override
  String informalTypeName() {
    return 'epic workflow state';
  }

  @override
  Future<ScEntity> fetch(ScEnv env) async {
    env.err.writeln(
        "To fetch an epic workflow state, fetch its workflow instead.");
    return this;
  }

  @override
  Future<ScList> ls(ScEnv env, [Iterable<ScExpr>? args]) async {
    env.err.writeln(
        "The `ls` function is not supported within epic workflow states.");
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
        var color = entityColor;
        switch (ts) {
          case 'unstarted':
            color = lightRed;
            break;
          case 'started':
            color = lightMagenta;
            break;
          case 'done':
            color = lightGreen;
            break;
        }
        typeStr = env.styleWith('[$ts]', [color])!;
      }
      final prefix = env.styleWith('[Epic Workflow State]', [entityColor]);
      final workflowStateName = env.styleWith(shortName, [yellow])!;
      final workflowStateId = env.styleWith("[${id.value}]", [entityColor])!;
      return "$prefix$typeStr $workflowStateName $workflowStateId";
    }
  }
}

abstract class ScApiContract {
  // # CRUD

  // ## Stories
  Future<ScStory> createStory(ScEnv env, Map<String, dynamic> storyData);
  Future<ScStory> getStory(ScEnv env, String storyPublicId);
  Future<ScStory> updateStory(
      ScEnv env, String storyPublicId, Map<String, dynamic> updateMap);
  // bool archiveStory(String storyPublicId);
  // bool deleteStory(String storyPublicId);

  // ## Tasks
  Future<ScTask> createTask(
      ScEnv env, String storyPublicId, Map<String, dynamic> taskData);
  Future<ScTask> getTask(ScEnv env, String storyPublicId, String taskPublicId);
  Future<ScTask> updateTask(ScEnv env, String storyPublicId,
      String taskPublicId, Map<String, dynamic> updateMap);
  // bool deleteTask(String storyPublicId, String taskPublicId);

  // ## Epics
  Future<ScEpic> createEpic(ScEnv env, Map<String, dynamic> epicData);
  Future<ScEpic> getEpic(ScEnv env, String epicPublicId);
  Future<ScList> getEpics(ScEnv env);
  Future<ScEpic> updateEpic(
      ScEnv env, String epicPublicId, Map<String, dynamic> updateMap);
  // bool archiveEpic(String epicPublicId);
  // bool deleteEpic(String epicPublicId);

  // ## Members
  Future<ScMember> getCurrentMember(ScEnv env);
  Future<ScMember> getMember(ScEnv env, String memberPublicId);
  Future<ScList> getMembers(ScEnv env);

  // ## Teams, a.k.a. Groups
  Future<ScTeam> getTeam(ScEnv env, String teamPublicId);
  Future<ScList> getTeams(ScEnv env);

  // ## Workflows
  Future<ScWorkflow> getWorkflow(ScEnv env, String workflowPublicId);
  Future<ScList> getWorkflows(ScEnv env);

  // ## Epic Workflows
  // NB: There is only one per workspace.
  Future<ScEpicWorkflow> getEpicWorkflow(ScEnv env);

  // ## Milestones
  Future<ScMilestone> createMilestone(
      ScEnv env, Map<String, dynamic> milestoneData);
  Future<ScMilestone> getMilestone(ScEnv env, String milestonePublicId);
  Future<ScList> getMilestones(ScEnv env);
  Future<ScMilestone> updateMilestone(
      ScEnv env, String milestonePublicId, Map<String, dynamic> updateMap);
  // NB: Milestones don't support archival
  // bool archiveMilestone(String milestonePublicId);
  // bool deleteMilestone(String milestonePublicId);

  // ## Iterations
  Future<ScIteration> createIteration(
      ScEnv env, Map<String, dynamic> iterationData);
  Future<ScIteration> getIteration(ScEnv env, String iterationPublicId);
  Future<ScList> getIterations(ScEnv env);
  Future<ScIteration> updateIteration(
      ScEnv env, String iterationPublicId, Map<String, dynamic> updateMap);
  // bool archiveIteration(String iterationPublicId);
  // bool deleteIteration(String iterationPublicId);

  // # Listings
  Future<ScList> getEpicsInMilestone(ScEnv env, String milestonePublicId);
  Future<ScList> getStoriesInEpic(ScEnv env, String epicPublicId);
  Future<ScList> getStoriesInIteration(ScEnv env, String iterationPublicId);
  Future<ScList> getStoriesInTeam(ScEnv env, String teamPublicId);
  // Future<List<ScComment>> getCommentsInStory(String storyPublicId);
  Future<ScList> getTasksInStory(ScEnv env, String storyPublicId);

  // Search
  Future<ScMap> search(ScEnv env, ScString queryString);
  Future<ScList> findStories(ScEnv env, Map<String, dynamic> findMap);
}

const arrayValuesKey = '__sc_array-values';

abstract class ScClient implements ScApiContract {
  /// HTTP client used for requests to Shortcut's API
  final HttpClient client = HttpClient();

  ScClient(this.host, this.apiToken);

  /// Shortcut API token used to communicate via its RESTful API.
  final String? apiToken;

  final String host;
}

class ScLiveClient extends ScClient {
  ScLiveClient(String host, String? apiToken) : super(host, apiToken);

  File? recordedCallsFile;
  bool shouldRecordCalls = false;

  @override
  Future<ScEpic> getEpic(ScEnv env, String epicPublicId) async {
    final taba = await authedCall(env, "/epics/$epicPublicId");
    return taba.epic(env);
  }

  @override
  Future<ScList> getEpics(ScEnv env) async {
    final taba = await authedCall(env, "/epics");
    return taba.epics(env);
  }

  @override
  Future<ScEpic> updateEpic(
      ScEnv env, String epicPublicId, Map<String, dynamic> updateMap) async {
    final taba = await authedCall(env, "/epics/$epicPublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.epic(env);
  }

  @override
  Future<ScIteration> getIteration(ScEnv env, String iterationPublicId) async {
    final taba = await authedCall(env, "/iterations/$iterationPublicId");
    return taba.iteration(env);
  }

  @override
  Future<ScMilestone> getMilestone(ScEnv env, String milestonePublicId) async {
    final taba = await authedCall(env, "/milestones/$milestonePublicId");
    return taba.milestone(env);
  }

  @override
  Future<ScStory> getStory(ScEnv env, String storyPublicId) async {
    final taba = await authedCall(env, "/stories/$storyPublicId");
    return taba.story(env);
  }

  @override
  Future<ScList> getEpicsInMilestone(
      ScEnv env, String milestonePublicId) async {
    final taba = await authedCall(env, "/milestones/$milestonePublicId/epics");
    return taba.epics(env);
  }

  @override
  Future<ScEpic> createEpic(ScEnv env, Map<String, dynamic> epicData) async {
    final taba = await authedCall(env, "/epics",
        httpVerb: HttpVerb.post, body: epicData);
    return taba.epic(env);
  }

  @override
  Future<ScIteration> createIteration(
      ScEnv env, Map<String, dynamic> iterationData) async {
    final taba = await authedCall(env, "/iterations",
        httpVerb: HttpVerb.post, body: iterationData);
    return taba.iteration(env);
  }

  @override
  Future<ScMilestone> createMilestone(
      ScEnv env, Map<String, dynamic> milestoneData) async {
    final taba = await authedCall(env, "/milestones",
        httpVerb: HttpVerb.post, body: milestoneData);
    return taba.milestone(env);
  }

  @override
  Future<ScStory> createStory(ScEnv env, Map<String, dynamic> storyData) async {
    final taba = await authedCall(env, "/stories",
        httpVerb: HttpVerb.post, body: storyData);
    return taba.story(env);
  }

  @override
  Future<ScList> getStoriesInEpic(ScEnv env, String epicPublicId) async {
    final taba = await authedCall(env, "/epics/$epicPublicId/stories");
    return taba.stories(env);
  }

  @override
  Future<ScList> getStoriesInIteration(
      ScEnv env, String iterationPublicId) async {
    final taba =
        await authedCall(env, "/iterations/$iterationPublicId/stories");
    return taba.stories(env);
  }

  @override
  Future<ScIteration> updateIteration(ScEnv env, String iterationPublicId,
      Map<String, dynamic> updateMap) async {
    final taba = await authedCall(env, "/iterations/$iterationPublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.iteration(env);
  }

  @override
  Future<ScMilestone> updateMilestone(ScEnv env, String milestonePublicId,
      Map<String, dynamic> updateMap) async {
    final taba = await authedCall(env, "/milestones/$milestonePublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.milestone(env);
  }

  @override
  Future<ScStory> updateStory(
      ScEnv env, String storyPublicId, Map<String, dynamic> updateMap) async {
    final taba = await authedCall(env, "/stories/$storyPublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.story(env);
  }

  @override
  Future<ScMember> getCurrentMember(ScEnv env) async {
    final tabaShallow = await authedCall(env, '/member');
    final shallowMember = tabaShallow.currentMember(env);
    return await getMember(env, shallowMember.id.value);
  }

  @override
  Future<ScMap> search(ScEnv env, ScString queryString) async {
    final taba = await authedCall(env, '/search',
        body: {'query': queryString.value}, httpVerb: HttpVerb.get);
    return taba.search(env);
  }

  @override
  Future<ScList> getTasksInStory(ScEnv env, String storyPublicId) async {
    final story = await getStory(env, storyPublicId);
    final tasksList = story.data[ScString('tasks')];
    if (tasksList == null || (tasksList as ScList).isEmpty) {
      return ScList([]);
    } else {
      return tasksList;
    }
  }

  @override
  Future<ScTask> createTask(
      ScEnv env, String storyPublicId, Map<String, dynamic> taskData) async {
    final taba = await authedCall(env, "/stories/$storyPublicId/tasks",
        httpVerb: HttpVerb.post, body: taskData);
    return taba.task(env, storyPublicId);
  }

  @override
  Future<ScTask> getTask(
      ScEnv env, String storyPublicId, String taskPublicId) async {
    final taba =
        await authedCall(env, "/stories/$storyPublicId/tasks/$taskPublicId");
    return taba.task(env, storyPublicId);
  }

  @override
  Future<ScTask> updateTask(ScEnv env, String storyPublicId,
      String taskPublicId, Map<String, dynamic> updateMap) async {
    final taba = await authedCall(
        env, "/stories/$storyPublicId/tasks/$taskPublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.task(env, storyPublicId);
  }

  @override
  Future<ScList> getWorkflows(ScEnv env) async {
    final taba = await authedCall(env, "/workflows");
    return taba.workflows(env);
  }

  @override
  Future<ScTeam> getTeam(ScEnv env, String teamPublicId) async {
    final taba = await authedCall(env, "/groups/$teamPublicId");
    return taba.team(env, teamPublicId);
  }

  @override
  Future<ScList> getTeams(ScEnv env) async {
    final taba = await authedCall(env, "/groups");
    return taba.teams(env);
  }

  @override
  Future<ScWorkflow> getWorkflow(ScEnv env, String workflowPublicId) async {
    final taba = await authedCall(env, "/workflows/$workflowPublicId");
    return taba.workflow(env, workflowPublicId);
  }

  @override
  Future<ScEpicWorkflow> getEpicWorkflow(ScEnv env) async {
    final taba = await authedCall(env, "/epic-workflow");
    return taba.epicWorkflow(env);
  }

  @override
  Future<ScList> getMembers(ScEnv env) async {
    final taba = await authedCall(env, "/members");
    return taba.members(env);
  }

  @override
  Future<ScMember> getMember(ScEnv env, String memberPublicId) async {
    final taba = await authedCall(env, "/members/$memberPublicId");
    return taba.member(env);
  }

  @override
  Future<ScList> getStoriesInTeam(ScEnv env, String teamPublicId) async {
    final taba = await authedCall(env, "/groups/$teamPublicId/stories");
    return taba.stories(env);
  }

  @override
  Future<ScList> getIterations(ScEnv env) async {
    final taba = await authedCall(env, "/iterations");
    return taba.iterations(env);
  }

  @override
  Future<ScList> findStories(ScEnv env, Map<String, dynamic> findMap) async {
    final taba = await authedCall(env, "/stories/search",
        httpVerb: HttpVerb.post, body: findMap);
    return taba.stories(env);
  }

  @override
  Future<ScList> getMilestones(ScEnv env) async {
    final taba = await authedCall(env, "/milestones");
    return taba.milestones(env);
  }

  Future<ThereAndBackAgain> authedCall(ScEnv env, String path,
      {HttpVerb httpVerb = HttpVerb.get, Map<String, dynamic>? body}) async {
    if (recordedCallsFile == null) {
      shouldRecordCalls = checkShouldRecordCalls();
      recordedCallsFile ??= File([
        getDefaultBaseConfigDirPath(),
        'recorded-calls.jsonl'
      ].join(Platform.pathSeparator));
    }
    final uri =
        Uri(scheme: scheme, host: getShortcutHost(), path: "$basePath$path");
    HttpClientRequest request =
        await client.openUrl(methodFromVerb(httpVerb), uri);
    request
      ..headers.set('Shortcut-Token', "$apiToken")
      ..headers.contentType = ContentType.json;

    if (httpVerb == HttpVerb.post || httpVerb == HttpVerb.put || body != null) {
      final bodyJson = jsonEncode(
        body,
        toEncodable: handleJsonNonEncodable,
      );
      request
        ..headers.contentLength = bodyJson.length
        ..write(bodyJson);
    }

    final requestDt = DateTime.now();
    HttpClientResponse response = await request.close();
    final responseDt = DateTime.now();

    Map<String, dynamic> bodyData = {};
    if (response.statusCode.toString().startsWith('2')) {
      final bodyString = await response.transform(utf8.decoder).join();
      final jsonData = jsonDecode(bodyString);
      if (jsonData is List) {
        bodyData[arrayValuesKey] = jsonData;
      } else if (jsonData is Map) {
        bodyData = jsonData as Map<String, dynamic>;
      } else {
        throw UnrecognizedResponseException(request, response);
      }
    } else {
      final responseContents = StringBuffer();

      await for (var data in response.transform(utf8.decoder)) {
        responseContents.write(data);
      }

      if (response.statusCode == 404) {
        throw EntityNotFoundException("Entity not found at $path");
      } else if (response.statusCode == 400) {
        throw BadRequestException(
            "HTTP 400 Bad Request: The request wasn't quite right. See details below.\n${responseContents.toString()}",
            request,
            response);
      } else if (response.statusCode == 401) {
        throw BadRequestException(
            "HTTP 401 Not Authorized: Make sure you have SHORTCUT_API_TOKEN defined in your environment correctly.",
            request,
            response);
      } else if (response.statusCode == 422) {
        throw BadRequestException(
            "HTTP 422 Unprocessable: The request wasn't quite right. See details below.\n${responseContents.toString()}",
            request,
            response);
      } else {
        stderr.writeln("HTTP Request: ${request.method} ${request.uri}");
        stderr.writeln(
            "HTTP Response: ${response.statusCode} Something went especially wrong. See details below.\n${responseContents.toString()}");
        throw BadResponseException(
            "HTTP Response: ${response.statusCode} Something went especially wrong. See details below.\n${responseContents.toString()}",
            request,
            response);
      }
    }

    final requestMap = request.toMap(requestDt);
    Map<String, dynamic> responseMap =
        response.toMap(requestDt, responseDt, bodyData);
    final taba = ThereAndBackAgain(requestMap, responseMap);
    if (shouldRecordCalls) {
      final json = jsonEncode(taba);
      await recordedCallsFile?.writeAsString("$json\n", mode: FileMode.append);
    }
    return taba;
  }
}

extension on HttpClientRequest {
  Map<String, dynamic> toMap(DateTime when) {
    return {'uri': uri.toString(), 'timestamp': when.toIso8601String()};
  }
}

extension on HttpClientResponse {
  /// To account for REST endpoints that return JSON arrays vs. objects, this
  /// [toMap] expects the caller to supply the parsed [bodyData].
  Map<String, dynamic> toMap(
      DateTime requestDt, DateTime responseDt, Map<String, dynamic> bodyData) {
    return {
      'body': bodyData,
      'duration': responseDt.difference(requestDt).inMilliseconds,
      'statusCode': statusCode,
      'timestamp': responseDt.toIso8601String(),
    };
  }
}

Object? handleJsonNonEncodable(Object? nonEncodable) {
  if (nonEncodable is DateTime) {
    return nonEncodable.toIso8601String();
  }
  return null;
}

String methodFromVerb(HttpVerb httpVerb) {
  switch (httpVerb) {
    case HttpVerb.get:
      return 'GET';
    case HttpVerb.put:
      return 'PUT';
    case HttpVerb.post:
      return 'POST';
    case HttpVerb.delete:
      return 'DELETE';
  }
}

class ThereAndBackAgain {
  ThereAndBackAgain(this.request, this.response);
  final Map<String, dynamic> request;
  final Map<String, dynamic> response;

  static ThereAndBackAgain fromJson(String tabaJson) {
    final jsonData = jsonDecode(tabaJson);
    final requestData = jsonData['request'];
    final responseData = jsonData['response'];
    return ThereAndBackAgain(requestData, responseData);
  }

  Map<String, dynamic> toJsonMap() {
    return {
      'request': request,
      'response': response,
      'timestamp': response['timestamp'],
      'duration': response['duration'],
      'version': recordedCallsVersion,
    };
  }

  List<dynamic> arrayBody() {
    return response['body'][arrayValuesKey];
  }

  Map<String, dynamic> objectBody() {
    return response['body'];
  }

  ScEpic epic(ScEnv env) {
    Map<String, dynamic> epic = objectBody();
    return ScEpic.fromMap(env, epic);
  }

  ScList epics(ScEnv env) {
    List<dynamic> epics = arrayBody();
    return ScList(epics.map((e) => ScEpic.fromMap(env, e)).toList());
  }

  ScStory story(ScEnv env) {
    Map<String, dynamic> story = objectBody();
    return ScStory.fromMap(env, story);
  }

  ScList stories(ScEnv env) {
    List<dynamic> stories = arrayBody();
    return ScList(stories.map((e) => ScStory.fromMap(env, e)).toList());
  }

  ScTask task(ScEnv env, String storyPublicId) {
    Map<String, dynamic> task = objectBody();
    return ScTask.fromMap(env, ScString(storyPublicId), task);
  }

  ScMilestone milestone(ScEnv env) {
    Map<String, dynamic> milestone = objectBody();
    return ScMilestone.fromMap(env, milestone);
  }

  ScList milestones(ScEnv env) {
    List<dynamic> milestones = arrayBody();
    return ScList(milestones.map((e) => ScMilestone.fromMap(env, e)).toList());
  }

  ScIteration iteration(ScEnv env) {
    Map<String, dynamic> iteration = objectBody();
    return ScIteration.fromMap(env, iteration);
  }

  ScList iterations(ScEnv env) {
    List<dynamic> iterations = arrayBody();
    return ScList(iterations.map((e) => ScIteration.fromMap(env, e)).toList());
  }

  ScMember currentMember(ScEnv env) {
    Map<String, dynamic> member = objectBody();
    return ScMember.fromMap(env, member);
  }

  ScWorkflow workflow(ScEnv env, String workflowPublicId) {
    Map<String, dynamic> workflow = objectBody();
    return ScWorkflow.fromMap(env, workflow);
  }

  ScEpicWorkflow epicWorkflow(ScEnv env) {
    Map<String, dynamic> epicWorkflow = objectBody();
    return ScEpicWorkflow.fromMap(env, epicWorkflow);
  }

  ScList workflows(ScEnv env) {
    List<dynamic> workflows = arrayBody();
    return ScList(workflows.map((e) => ScWorkflow.fromMap(env, e)).toList());
  }

  ScTeam team(ScEnv env, String teamPublicId) {
    Map<String, dynamic> team = objectBody();
    return ScTeam.fromMap(env, team);
  }

  ScList teams(ScEnv env) {
    List<dynamic> teams = arrayBody();
    return ScList(teams.map((e) => ScTeam.fromMap(env, e)).toList());
  }

  ScMember member(ScEnv env) {
    Map<String, dynamic> member = objectBody();
    return ScMember.fromMap(env, member);
  }

  ScList members(ScEnv env) {
    List<dynamic> members = arrayBody();
    return ScList(members.map((e) => ScMember.fromMap(env, e)).toList());
  }

  ScMap search(ScEnv env) {
    final searchResults = objectBody();
    final storyResults = searchResults['stories'] as Map<String, dynamic>;
    final epicResults = searchResults['epics'] as Map<String, dynamic>;
    final storiesData = storyResults['data'] as List;
    final epicsData = epicResults['data'] as List;
    final stories = storiesData.map((data) => ScStory.fromMap(env, data));
    final epics = epicsData.map((data) => ScEpic.fromMap(env, data));
    return ScMap({
      ScString('stories'): ScList(stories.toList()),
      ScString('epics'): ScList(epics.toList()),
    });
  }
}

/// Functions

/// A function and not a method so its available from the [ScEnv] factory constructor.
void setParentEntity(ScEnv env, ScEntity entity, {bool isHistory = true}) {
  final previousParentEntity = env.parentEntity;
  env.parentEntity = entity;
  env[ScSymbol('.')] = entity;
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
    // err.writeln(
    //     "Your ${getEnvFile().path} is malformed at the \"parent\" key.");
    entity = null;
  }
  final entityId = json['entityId'] as String?;
  if (entityId == null) {
    // err.writeln(
    //     "Your ${getEnvFile().path} is malformed at the \"parent\" key.");
    entity = null;
  } else {
    final title = json['entityTitle'];
    switch (entityTypeString) {
      case 'story':
        entity = ScStory(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'epic':
        entity = ScEpic(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'iteration':
        entity = ScIteration(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'milestone':
        entity = ScMilestone(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'team':
        entity = ScTeam(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'member':
        entity = ScMember(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'workflow':
        entity = ScWorkflow(ScString(entityId));
        entity.title = ScString(title);
        break;
      case 'epic workflow':
        entity = ScEpicWorkflow(ScString(entityId));
        entity.title = ScString(title);
    }
  }
  return entity;
}

ScList epicsInMilestone(ScEnv env, ScMilestone milestone) {
  final milestonePublicId = milestone.id.value;
  final epicsInMilestone =
      waitOn(env.client.getEpicsInMilestone(env, milestonePublicId));
  return epicsInMilestone;
}

ScList epicsInIteration(ScEnv env, ScIteration iteration) {
  final iterationStories =
      waitOn(env.client.getStoriesInIteration(env, iteration.id.value));
  return uniqueEpicsAcrossStories(env, iterationStories);
}

ScList epicsInTeam(ScEnv env, ScTeam team) {
  final storiesInTeam = waitOn(env.client.getStoriesInTeam(env, team.id.value));
  return uniqueEpicsAcrossStories(env, storiesInTeam);
}

ScList uniqueEpicsAcrossStories(ScEnv env, ScList stories) {
  final Set<ScString> epicIds = {};
  for (final story in stories.innerList) {
    final s = story as ScStory;
    final epic = s.data[ScString('epic_id')];
    if (epic is ScEpic) {
      epicIds.add(epic.id);
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

ScList milestonesInIteration(ScEnv env, ScIteration iteration) {
  final epics = epicsInIteration(env, iteration);
  final Set<ScString> milestoneIds = {};
  for (final epic in epics.innerList) {
    final e = epic as ScEpic;
    final milestone = e.data[ScString('milestone_id')];
    if (milestone is ScMilestone) {
      milestoneIds.add(milestone.id);
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
          "Don't know how to `get-in` a $k from a value of type ${m.informalTypeName()}");
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
      sb.write(env.styleWith(keyStr, [magenta]));
      sb.writeln(" $valueStr");
    }
  }
  env.out.writeln(sb.toString());
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
    {currentDepth = 0, forJson = false, onlyEntityIds = false}) {
  if (expr is ScList) {
    return unwrapScList(expr,
        currentDepth: currentDepth + 1,
        forJson: forJson,
        onlyEntityIds: onlyEntityIds);
  } else if (expr is ScMap) {
    // currentDepth++;
    return unwrapScMap(expr,
        currentDepth: currentDepth + 1,
        forJson: forJson,
        onlyEntityIds: onlyEntityIds);
  } else if (expr is ScEntity) {
    // ScWorkflowState should always be persisted as-is, not independenty fetch-able.
    if (expr is ScWorkflowState) {
      return unwrapScMap(
        expr.data,
        currentDepth: currentDepth + 1,
        forJson: forJson,
        onlyEntityIds: onlyEntityIds,
      );
    }
    if (onlyEntityIds) {
      return expr.id.value;
    } else if (currentDepth > 2) {
      // NB: Given Shortcut's data model, we are likely in an cycle like Member -> Teams -> Members -> Teams
      return expr.id.value;
    } else {
      // currentDepth++;
      return unwrapScMap(expr.data,
          currentDepth: currentDepth + 1,
          forJson: forJson,
          onlyEntityIds: onlyEntityIds);
    }
  } else if (expr is ScString) {
    return expr.value;
  } else if (expr is ScSymbol) {
    return expr._name;
  } else if (expr is ScDottedSymbol) {
    return expr._name;
  } else if (expr is ScNumber) {
    return expr.value;
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
    {bool forJson = false, bool onlyEntityIds = false, currentDepth = 0}) {
  Map<String, dynamic> m = {};
  for (final key in map.innerMap.keys) {
    final k = scExprToValue(key,
        currentDepth: currentDepth,
        forJson: forJson,
        onlyEntityIds: onlyEntityIds);
    if (forJson && k is! String) {
      throw BadArgumentsException(
          "The map targeting JSON must contain only symbol or string keys, but found the key $key of type ${key.informalTypeName()}");
    }
    var expr = map[key]!;
    m[k] = scExprToValue(expr,
        currentDepth: currentDepth,
        forJson: forJson,
        onlyEntityIds: onlyEntityIds);
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
                return await env.client.getWorkflow(env, entityPublicId);
              } catch (_) {
                try {
                  final epicWorkflow = await env.client.getEpicWorkflow(env);
                  if (epicWorkflow.id.value == entityPublicId) {
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

openInBrowser(String url) async {
  if (Platform.isMacOS) {
    Process.run('open', [url]);
  } else if (Platform.isLinux) {
    Process.run('xdg-open', [url]);
  } else {
    throw UnsupportedError(
        "Your operating system is not supported.\nPlease open $url manually.");
  }
}

/// Enumerations

enum MyEntityTypes { stories, tasks, epics, milestones, iterations }

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

class InterpretationException extends ExceptionWithMessage {
  InterpretationException(String message) : super(message);
}

class BadArgumentsException extends ExceptionWithMessage {
  BadArgumentsException(String message) : super(message);
}

class OperationNotSupported extends ExceptionWithMessage {
  OperationNotSupported(String message) : super(message);
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
            "Tried to invoke a ${args.first.informalTypeName()} that isn't invocable.");
}

class SourceFileNotFound extends ExceptionWithMessage {
  SourceFileNotFound(String filePath, String configDirPath)
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
