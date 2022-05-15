// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'options.dart';

// **************************************************************************
// CliGenerator
// **************************************************************************

Options _$parseOptionsResult(ArgResults result) => Options(
      result['help'] as bool,
      result['repl'] as bool,
      result['json'] as bool,
    )
      ..isAnsiEnabled = result['ansi-color'] as bool?
      ..baseConfigDir = result['config-directory'] as String?
      ..program = result['eval'] as String?
      ..loadFiles = result['load'] as List<String>;

ArgParser _$populateOptionsParser(ArgParser parser) => parser
  ..addFlag(
    'ansi-color',
    abbr: 'a',
    help: 'Whether or not to use ANSI codes for colored output.',
    defaultsTo: null,
  )
  ..addOption(
    'config-directory',
    abbr: 'c',
    help:
        'Base directory to store configuration and caches. Defaults to ~/.config/shortcut-cli. Override here or with SHORTCUT_CONFIG_DIR environment variable.',
  )
  ..addOption(
    'eval',
    abbr: 'e',
    help: 'Evaluate a one-off Shortcut program and exit.',
  )
  ..addFlag(
    'help',
    abbr: 'h',
    help: 'Prints usage information.',
    negatable: false,
  )
  ..addFlag(
    'json',
    abbr: 'j',
    help: 'Print output in JSON format.',
    negatable: false,
  )
  ..addMultiOption(
    'load',
    abbr: 'l',
    help: 'Load one or more source files at startup.',
  )
  ..addFlag(
    'repl',
    abbr: 'r',
    help: 'Start a Shortcut REPL.',
    negatable: false,
  );

final _$parserForOptions = _$populateOptionsParser(ArgParser());

Options parseOptions(List<String> args) {
  final result = _$parserForOptions.parse(args);
  return _$parseOptionsResult(result);
}
