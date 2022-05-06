import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:io/ansi.dart';
import 'package:sc_cli/cli_repl.dart';
import 'package:sc_cli/sc_cli.dart';

import 'package:hotreloader/hotreloader.dart';
import 'package:sc_cli/src/options.dart';
import 'package:sc_cli/src/sc_api.dart';
import 'package:sc_cli/src/sc_config.dart';

/// Closure to make [options] available to the isolate fn. Dev-facing because it activates hot code reloading.
Function startDevReplServerIsolateFn(Options options) {
  return (SendPort sendPort) async {
    HotReloader? reloader;
    try {
      reloader = await HotReloader.create(
          onBeforeReload: (ctx) => ctx.isolate.name == 'replServerIsolate',
          onAfterReload: (ctx) {
            print(wrapWith("\n🛠  Code reloaded 🎉", [yellow]));
          });
    } catch (_) {
      stderr.writeln(
          "Hot code reloading not available. Rerun with --enable-vm-service if desired.");
    }

    final client = ScLiveClient(getShortcutHost(), getShortcutApiToken());
    final env = ScEnv.readFromDisk(
        client: client,
        out: stdout,
        err: stderr,
        isReplMode: true,
        isAnsiEnabled: options.isAnsiEnabled ?? true);
    env.loadPrelude();
    maybeLoadFiles(env, options);
    unawaited(loadCaches(env));
    final repl = Repl(
        prompt: '\nsc> ',
        continuation: '>>> ',
        validator: replValidator,
        env: env);
    await for (final x in repl.runAsync()) {
      handleRepl(env, repl, sendPort, x);
    }
    if (reloader != null) {
      await reloader.reloadCode();
    }
  };
}
