import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:petitparser/matcher.dart';
import 'package:sc_cli/cli_repl.dart';

import 'package:sc_cli/src/options.dart';
import 'package:sc_cli/src/repl_adapter/vm.dart';
import 'package:sc_cli/src/sc.dart';
import 'package:sc_cli/src/sc_api.dart' show ScLiveClient;
import 'package:sc_cli/src/sc_config.dart';
import 'package:sc_cli/src/sc_lang.dart';
import 'package:sc_cli/src/sc_style.dart';

mainEntryPoint(List<String> args, Function(Options options) isolateFn) async {
  final options = parseOptions(args);

  if (options.help) {
    printUsage();
    exit(0);
  } else if (options.isReplMode) {
    startRepl(options, isolateFn);
    // NB: Don't exit, let server+client run.
  } else if (options.program != null) {
    interpretProgram(options);
    exit(0);
  } else {
    printUsage();
    exit(1);
  }
}

void printUsage() {
  print("""
A command line utility for interacting with Shortcut.

Usage: sc [<args>]

Arguments:
${parser.usage}
""");
}

void interpretProgram(Options options) {
  final program = options.program!; // null checked by caller
  final client = ScLiveClient(
      getShortcutApiHost(), getShortcutApiToken(), getShortcutAppCookie());
  final baseConfigDirPath =
      options.baseConfigDir ?? getDefaultBaseConfigDirPath();
  final env = ScEnv.readFromDisk(
      baseConfigDirPath: baseConfigDirPath,
      client: client,
      out: stdout,
      err: stderr,
      isReplMode: false,
      isPrintJson: options.isPrintJson,
      isAnsiEnabled: options.isAnsiEnabled ?? false,
      isAccessibleColors: options.isAccessibleColors);
  maybeLoadFiles(env, options);
  final expr = env.interpret(program);
  final str = expr.printToString(env);
  stdout.writeln(str);
}

bool Function(String str) replValidator(ScEnv env) {
  return (String str) {
    final trimmed = str.trim();
    return trimmed.isEmpty || env.scParser.accept(trimmed);
  };
}

void startRepl(Options options, Function(Options options) isolateFn) async {
  startReplClient(await startReplServer(options, isolateFn));
}

Future<Isolate> startReplClient(Isolate serverIsolate) async {
  return await Isolate.spawn(
      startReplClientIsolate, ReceivePort('replClientReceiverPort').sendPort,
      paused: false, debugName: 'replClientIsolate');
}

void startReplClientIsolate(SendPort sendPort) {}

Future<Isolate> startReplServer(
    Options options, Function(Options options) isolateFn) async {
  final receiverPort = ReceivePort('replServerReceiverPort');

  void Function(SendPort) spawnFn =
      isolateFn(options) as void Function(SendPort);
  final isolate = await Isolate.spawn(spawnFn, receiverPort.sendPort,
      paused: false, debugName: 'replServerIsolate');
  receiverPort.listen((_data) {
    // stdout.writeln("DATA: $data");
  });
  return isolate;
}

/// Closure to make [options] available to the isolate fn.
Function startProdReplServerIsolateFn(Options options) {
  return (SendPort sendPort) async {
    final client = ScLiveClient(
        getShortcutApiHost(), getShortcutApiToken(), getShortcutAppCookie());
    final baseConfigDirPath =
        options.baseConfigDir ?? getDefaultBaseConfigDirPath();
    final env = ScEnv.readFromDisk(
        baseConfigDirPath: baseConfigDirPath,
        client: client,
        out: stdout,
        err: stderr,
        isReplMode: true,
        isPrintJson: options.isPrintJson,
        isAnsiEnabled: options.isAnsiEnabled ?? true,
        isAccessibleColors: options.isAccessibleColors);
    maybeLoadFiles(env, options);
    final repl = Repl(
        prompt: formatPrompt(env),
        continuation: ',,,   ',
        validator: replValidator(env),
        env: env);
    env.out.writeln(env.style(
        "\n;; [INFO] Loading caches from disk, some data may appear missing until finished...",
        styleInfo));
    unawaited(loadCaches(env, repl));

    // Interrupt Handling
    int numInterrupts = 0;
    DateTime timeLastInterrupt = DateTime.now();
    ProcessSignal.sigint.watch().listen((signal) {
      final now = DateTime.now();
      final duration = now.difference(timeLastInterrupt);
      if (duration.inMilliseconds > 5000) {
        numInterrupts = 0;
      }

      numInterrupts++;
      timeLastInterrupt = DateTime.now();
      if (numInterrupts == 1) {
        repl.prompt = formatPrompt(env);
        repl.clearBuffer();
        env.out.write(env.style(r'''


💡 Press Ctrl-c twice to exit.
✅️ Press ENTER to get a fresh prompt.

== Console Help ==

TAB autocompletes at cursor.

Ctrl-a moves cursor to start of line.    Ctrl-e moves cursor to end of line.
Ctrl-b moves cursor back one character.  Ctrl-f moves cursor forward one character.
Ctrl-k kills text after cursor.          Ctrl-l clears the screen.
Ctrl-w kills previous word.
''', styleWarn));
      } else if (numInterrupts >= 2) {
        leave(env);
      }
    });
    await for (final x in repl.runAsync()) {
      handleRepl(env, repl, sendPort, x);
    }
  };
}

void leave(ScEnv env) {
  env.err.writeln(env.style('\nUntil next time! 👋', stylePrompt));
  exit(0);
}

void handleRepl(ScEnv env, Repl repl, SendPort sendPort, String x) {
  var trimmed = x.trim();
  trimmed = trimmed.replaceFirst(promptPattern, '');
  if (trimmed.isEmpty) return;
  final lowered = trimmed.toLowerCase();
  if (lowered == 'exit' || lowered == 'quit') {
    leave(env);
  } else {
    try {
      // BEFORE EVAL
      ScExpr expr = ScNil();
      Set<ScInteractivityState> skipEvalStates = {
        ScInteractivityState.getEntityType,
        ScInteractivityState.getTaskStoryId,
        ScInteractivityState.getEntityName,
        ScInteractivityState.getEntityDescription,
        ScInteractivityState.getDefaultWorkflowId,
        ScInteractivityState.getDefaultWorkflowStateId,
        ScInteractivityState.getDefaultTeamId
      };
      if (skipEvalStates.contains(env.interactivityState) ||
          env.isExpectingBindingAnswer) {
        expr = ScString(trimmed);
      } else {
        // EVAL
        expr = env.interpret(trimmed); // read + eval
      }
      // AFTER EVAL
      // == Interactive Setup ==
      if (env.interactivityState == ScInteractivityState.startSetup) {
        env.interactivityState = ScInteractivityState.getDefaultWorkflowId;
        env.out.writeln("Fetching your workspace's workflows...");
        scPrint(env, env.interpret('workflows | map %(select % "id" "name")'));
        repl.prompt = env.style('\nDefault Workflow ID: ', stylePrompt);
      } else if (env.interactivityState ==
          ScInteractivityState.getDefaultWorkflowId) {
        env.interactivityState = ScInteractivityState.getDefaultWorkflowStateId;
        env[ScSymbol('__sc_default-workflow-id')] =
            ScNumber(int.tryParse((expr as ScString).value)!);
        env.out.writeln("Fetching that workflow's workflow states...");
        scPrint(
            env,
            env.interpret(
                '${env[ScSymbol("__sc_default-workflow-id")]} | workflow | .states | map %(select % "id" "name") '));
        repl.prompt = env.style('\nDefault Workflow State Id: ', stylePrompt);
      } else if (env.interactivityState ==
          ScInteractivityState.getDefaultWorkflowStateId) {
        env.interactivityState = ScInteractivityState.getDefaultTeamId;
        env[ScSymbol('__sc_default-workflow-state-id')] =
            ScNumber(int.tryParse((expr as ScString).value)!);
        env.out.writeln("Fetching your workspace's teams...");
        scPrint(env, env.interpret('teams'));
        repl.prompt = env.style('\nDefault Team ID: ', stylePrompt);
      } else if (env.interactivityState ==
          ScInteractivityState.getDefaultTeamId) {
        env.interactivityState = ScInteractivityState.finishSetup;
        env[ScSymbol('__sc_default-team-id')] = expr;
        env.writeToDisk();
        env.out.writeln(env.style("Defaults set!", styleInfo));
        repl.prompt = formatPrompt(env);
        // == Interactive Entity Creation ==
      } else if (env.interactivityState ==
              ScInteractivityState.startCreateEntity &&
          env[ScSymbol('__sc_entity-type')] == null) {
        env.interactivityState = ScInteractivityState.getEntityType;
        repl.prompt = env.style(
            "Create a story, epic, milestone, iteration, or task? ",
            stylePrompt);
      } else if (env.interactivityState == ScInteractivityState.getEntityType ||
          (env.interactivityState == ScInteractivityState.startCreateEntity &&
              env[ScSymbol('__sc_entity-type')] != null)) {
        ScString entityType;
        if (expr == ScNil()) {
          final preType = env[ScSymbol('__sc_entity-type')];
          if (preType == null) {
            throw BadArgumentsException(
                "You must specify one of story, epic, milestone, iteration, or task. Please try again.");
          } else {
            entityType = preType as ScString;
          }
        } else {
          entityType = expr as ScString;
        }
        if (!(entityType == ScString('story') ||
            entityType == ScString('epic') ||
            entityType == ScString('milestone') ||
            entityType == ScString('iteration') ||
            entityType == ScString('task'))) {
          throw BadArgumentsException(
              "You must specify one of story, epic, milestone, iteration, or task. Please try again.");
        }
        if (entityType == ScString('story')) {
          if (env[ScSymbol('__sc_default-workflow-state-id')] == null) {
            throw BadArgumentsException(
                "Please run `setup` first to establish a default story workflow state.");
          }
        }
        env[ScSymbol('__sc_entity-type')] = entityType;
        if (entityType == ScString('task')) {
          final pe = env.parentEntity;
          if (pe is ScStory) {
            // NB: Assumption is this `create` call is meant to be scoped to the cwd of the Story
            env.interactivityState = ScInteractivityState.getEntityDescription;
            env[ScSymbol('__sc_task-story-id')] = pe.id;
            repl.prompt = env.style('Description: ', stylePrompt);
          } else {
            env.interactivityState = ScInteractivityState.getTaskStoryId;
            repl.prompt = env.style("Task's Story ID: ", stylePrompt);
          }
        } else {
          env.interactivityState = ScInteractivityState.getEntityName;
          repl.prompt = env.style('Title: ', stylePrompt);
        }
      } else if (env.interactivityState ==
          ScInteractivityState.getTaskStoryId) {
        env[ScSymbol('__sc_task-story-id')] = expr;
        env.interactivityState = ScInteractivityState.getEntityDescription;
        repl.prompt = env.style('Description: ', stylePrompt);
      } else if (env.interactivityState == ScInteractivityState.getEntityName &&
          env[ScSymbol('__sc_entity-type')] != ScString('task')) {
        env.interactivityState = ScInteractivityState.getEntityDescription;
        env[ScSymbol('__sc_entity-name')] = expr;
        repl.prompt = env.style('Description: ', stylePrompt);
      } else if (env.interactivityState ==
          ScInteractivityState.getEntityDescription) {
        env.interactivityState = ScInteractivityState.finishCreateEntity;
        final entityType = env[ScSymbol('__sc_entity-type')];
        final entityName = env[ScSymbol('__sc_entity-name')];
        final entityDescription = expr;
        final Map<String, dynamic> createMap = {};
        if (entityName is ScString) {
          createMap['name'] = entityName.value;
        }
        createMap['description'] = (entityDescription as ScString).value;
        if (entityType == ScString('story')) {
          createMap['workflow_state_id'] =
              (env[ScSymbol('__sc_default-workflow-state-id')] as ScNumber)
                  .value;
        }
        // NB: Tasks have a description, not a name.
        if (env[ScSymbol('__sc_entity-type')] == ScString('task')) {
          createMap.remove('name');
        }
        switch ((entityType as ScString).value) {
          case 'story':
            final createStoryFn = ScFnCreateStory();
            final storyExpr =
                createStoryFn.invoke(env, ScList([valueToScExpr(createMap)]));
            scPrint(env, storyExpr);
            break;
          case 'epic':
            final createEpicFn = ScFnCreateEpic();
            final epicExpr =
                createEpicFn.invoke(env, ScList([valueToScExpr(createMap)]));
            scPrint(env, epicExpr);
            break;
          case 'milestone':
            final createMilestoneFn = ScFnCreateMilestone();
            final milestoneExpr = createMilestoneFn.invoke(
                env, ScList([valueToScExpr(createMap)]));
            scPrint(env, milestoneExpr);
            break;
          case 'iteration': // TODO start_date and end_date are required. Print two-month calendar.
            final createIterationFn = ScFnCreateIteration();
            final iterationExpr = createIterationFn.invoke(
                env, ScList([valueToScExpr(createMap)]));
            scPrint(env, iterationExpr);
            break;
          case 'task':
            final storyId = env[ScSymbol('__sc_task-story-id')];
            final exprCreateMap = valueToScExpr(createMap) as ScMap;
            exprCreateMap[ScString('type')] = ScString('task');
            exprCreateMap[ScString('story_id')] = storyId!;
            final createFn = ScFnCreate();
            final taskExpr = createFn.invoke(env, ScList([exprCreateMap]));
            scPrint(env, taskExpr);
            break;
          default:
            throw UnimplementedError();
        }
        repl.prompt = formatPrompt(env);
      } else if (env.isExpectingBindingAnswer && expr is ScString) {
        final answer = expr.value.toLowerCase();
        if (answer == 'y' || answer == 'yes') {
          env.bindNextValue = true;
          env.isExpectingBindingAnswer = false;
          env.out.write(env.style(
              'Great! The next thing you evaluate will be bound to ',
              styleInfo));
          env.out
              .write(env.style(env.symbolBeingDefined.toString(), styleTitle));
          repl.prompt = '\ndef ${env.symbolBeingDefined.toString()} ';
        } else {
          env.bindNextValue = false;
          env.isExpectingBindingAnswer = false;
          env.out.write(env.style('Ok, maybe next time!', styleInfo));
          repl.prompt = formatPrompt(env);
        }
      } else if (env.symbolBeingDefined != null && env.bindNextValue) {
        final sym = env.symbolBeingDefined!;
        env[sym] = expr;
        env.bindNextValue = false;
        env.out.write(env.style('✅ The symbol ', styleInfo));
        env.out.write(env.style(env.symbolBeingDefined.toString(), styleTitle));
        env.out.write(env.style(
            ' is now bound to that ${expr.typeName()} value.', styleInfo));
        env.symbolBeingDefined = null;
        repl.prompt = formatPrompt(env);
      } else {
        scPrint(env, expr);
        repl.prompt = formatPrompt(env);
      }
      env.writeHistory();
    } catch (e, stacktrace) {
      if (e is UndefinedSymbolException) {
        env.isExpectingBindingAnswer = true;
        env.interactiveStartBinding(e.symbol);
        stderr.write(env.style(
            "${e.symbol}\n${'^' * e.symbol.toString().length} This symbol isn't defined.\n",
            styleWarn));
        repl.prompt =
            env.style("\nDo you want to define it? (y/n) > ", stylePrompt);
      } else {
        String? recoveryMessage;
        if (e is ExceptionWithMessage) {
          recoveryMessage = e.message;
        } else if (e is UnimplementedError) {
          recoveryMessage =
              "What you just tried hasn't been implemented, but please file a bug report if you think it should be!";
        } else if (e is AsyncError) {
          final underlyingError = e.error;
          if (underlyingError is ExceptionWithMessage) {
            recoveryMessage = underlyingError.message;
          } else if (underlyingError is UnimplementedError) {
            recoveryMessage =
                "What you just tried hasn't been implemented, but please file a bug report if you think it should be!";
          }
        }
        if (recoveryMessage != null) {
          if (e is ScAssertionError) {
            stderr.write(
                env.style("Assertion Failed: $recoveryMessage", styleError));
          } else {
            stderr.write(env.style("[!] $recoveryMessage", styleError));
          }
        } else {
          stderr.write("🔥 Something Broke 🔥\n$e\n$stacktrace");
        }
      }
    }
  }
  sendPort.send({'msg': trimmed});
}

void maybeLoadFiles(ScEnv env, Options options) {
  if (options.loadFiles != null) {
    final loadFn = ScFnLoad();
    try {
      for (final filePath in options.loadFiles!) {
        loadFn.invoke(env, ScList([ScString(filePath)]));
      }
    } catch (e) {
      if (e is FileNotFound) {
        stderr.writeln("[ERROR] ${e.message}");
      } else {
        rethrow;
      }
    }
  }
}

/// Load caches from disk. Done in an unawaited() call to allow the REPL
/// to start up more quickly but still have these loaded (hopefully) before
/// the user starts issuing commands that need to resolve workflows, workflow
/// states, members, or teams.
Future loadCaches(ScEnv env, Repl repl) async {
  try {
    if (File(cacheMembersFilePath).existsSync()) {
      await env.loadCachesFromDisk();
      env.out.write(
          env.style("\n;; [INFO] Finished loading caches.\n", styleInfo));
      bindAllTheThings(env);
      repl.rewriteBuffer();
    }
  } catch (e) {
    env.err.writeln(env.style(
        ";; [WARN] Failed to load caches. Delete the cache*.json files under your config direction (default is ~/.config/shortcut-cli/) and try again.",
        styleError));
    env.err.writeln('Error: $e');
    exit(1);
  }
}
