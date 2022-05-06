// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'options.dart';

// **************************************************************************
// CliGenerator
// **************************************************************************

Options _$parseOptionsResult(ArgResults result) => Options(
      result['help'] as bool,
      result['repl'] as bool,
    )
      ..program = result['eval'] as String?
      ..loadFiles = result['load'] as List<String>
      ..isAnsiEnabled = result['ansi-color'] as bool?;

ArgParser _$populateOptionsParser(ArgParser parser) => parser
  ..addFlag(
    'help',
    abbr: 'h',
    help: 'Prints usage information.',
    negatable: false,
  )
  ..addOption(
    'eval',
    abbr: 'e',
    help: 'Evaluate a one-off Shortcut program and exit.',
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
  )
  ..addFlag(
    'ansi-color',
    abbr: 'a',
    help: 'Whether or not to use ANSI codes for colored output.',
    defaultsTo: null,
  );

final _$parserForOptions = _$populateOptionsParser(ArgParser());

Options parseOptions(List<String> args) {
  final result = _$parserForOptions.parse(args);
  return _$parseOptionsResult(result);
}
