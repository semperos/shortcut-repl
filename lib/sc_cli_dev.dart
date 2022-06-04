import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:io/ansi.dart';
import 'package:sc_cli/cli_repl.dart';
import 'package:sc_cli/sc_cli.dart';

import 'package:hotreloader/hotreloader.dart';
import 'package:sc_cli/src/options.dart';
import 'package:sc_cli/src/sc.dart';
import 'package:sc_cli/src/sc_api.dart' show ScLiveClient;
import 'package:sc_cli/src/sc_config.dart';
import 'package:sc_cli/src/sc_style.dart';

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
        continuation: '>>> ',
        validator: replValidator(env),
        env: env);
    env.out.writeln(env.style(
        "\n;; [INFO] Loading caches from disk, some data may appear missing until finished...",
        styleWarn));
    unawaited(loadCaches(env, repl));
    await for (final x in repl.runAsync()) {
      handleRepl(env, repl, sendPort, x);
    }
    if (reloader != null) {
      await reloader.reloadCode();
    }
  };
}
