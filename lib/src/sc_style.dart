import 'dart:math';

import 'package:chalkdart/chalk.dart';
import 'package:io/ansi.dart';
import 'package:sc_cli/src/sc.dart' show ScExpr;

/// Taken from https://pub.dev/packages/io/example
void previewAnsiCode(String name, List<AnsiCode> values, bool forScript) {
  print('');
  final longest = values.map((ac) => ac.name.length).reduce(max);

  print(wrapWith('** $name **', [styleBold, styleUnderlined]));
  for (var code in values) {
    final header =
        '${code.name.padRight(longest)} ${code.code.toString().padLeft(3)}';

    print("$header: ${code.wrap('Sample', forScript: forScript)}");
  }
}

String styleString(Map<String, String> palette, String paletteKey, String s,
    {List<String>? styles}) {
  String hex;
  if (s.startsWith('#')) {
    hex = s;
  } else {
    hex = palette[paletteKey] ?? palette['__fallback']!;
  }
  return applyStringStyles(styles, chalk.hex(hex)(s));
}

String styleStringForScExpr(Map<String, String> palette, ScExpr expr, String s,
    {List<String>? styles}) {
  final typeName = expr.typeName();
  return styleString(palette, typeName, s, styles: styles);
}

String applyStringStyles(List<String>? styles, String s) {
  if (styles != null) {
    String finalString = s;
    for (final style in styles) {
      switch (style) {
        case 'dim':
          finalString = chalk.dim(finalString);
          break;
        case 'bold':
          finalString = chalk.bold(finalString);
          break;
        case 'underline':
          finalString = chalk.underline(finalString);
          break;
      }
    }
    return finalString;
  } else {
    return s;
  }
}

final styleBoolean = 'boolean';
final styleBug = 'bug';
final styleChore = 'chore';
final styleCustomField = 'custom field';
final styleCustomFieldEnumValue = 'custom field enum value';
final styleDateTime = 'date-time';
final styleDone = 'done';
final styleEpicWorkflowState = 'epic workflow state';
final styleError = 'error';
final styleFeature = 'feature';
final styleInfo = 'info';
final styleMemberMention = 'member';
final styleNil = 'nil';
final styleNumber = 'number';
final stylePrompt = 'prompt';
final styleRoleAdmin = 'role__admin';
final styleRoleMember = 'role__member';
final styleRoleObserver = 'role__observer';
final styleRoleOwner = 'role__owner';
final styleStarted = 'started';
final styleStory = 'story';
final styleSubdued = 'subdued';
final styleTeamMention = 'team';
final styleTitle = 'title';
final styleUnderline = 'underline';
final styleUnstarted = 'unstarted';
final styleWarn = 'warn';
final styleWorkflowState = 'workflow state';

final defaultDarkPalette = {
  'boolean': '#d96e7b',
  'bug': '#e75569',
  'chore': '#3895c9',
  'comment': '#8c8d8c',
  'custom field': '#df8632',
  'custom field enum value': '#3895c9',
  'date-time': '#97c6e8',
  'done': '#71b259',
  'dotted symbol': '#ad87f3',
  'epic comment': '#8c8d8c',
  'epic workflow state': '#97c6e8',
  'epic workflow': '#97c6e8',
  'epic': '#71b259',
  'error': '#e75569',
  '__fallback': '#8c8d8c',
  'feature': '#e6d566',
  'file': '#d96e7b',
  // 'iteration': '#58b1e4',
  'iteration': '#3895c9',
  'info': '#71b259',
  'label': '#ad9865',
  'member': '#8bb771',
  'milestone': '#df8632',
  'nil': '#8c8d8c',
  'number': '#71b259',
  // 'prompt': '#ad87f3',
  'prompt': '#58b1e4',
  'role__admin': '#e6d566',
  'role__member': '#3a95c9',
  'role__observer': '#8c8d8c',
  'role__owner': '#e75569',
  'started': '#ad87f3',
  'story': '#ad87f3', // active links #6414db
  'string': '#e6d566',
  'subdued': '#575858',
  'symbol': '#ad87f3',
  'task': '#3a95c9',
  'team': '#d96e7b',
  'title': '#97c6e8',
  // 'title': '#e6d566',
  // 'title': '#ccba45',
  'unstarted': '#e75569',
  'warn': '#e6d566',
  'workflow state': '#97c6e8',
  'workflow': '#97c6e8',
};

// From https://lospec.com/palette-list/colorblind-16
final colorBlindDarkPalette = {
  'boolean': '#b66dff',
  'comment': '#676767',
  'date-time': '#97c6e8',
  'done': '#22cf22',
  'dotted symbol': '#b66dff',
  'epic comment': '#676767',
  'epic workflow state': '#006ddb',
  'epic workflow': '#006ddb',
  'epic': '#22cf22',
  'error': '#920000',
  '__fallback': '#676767',
  'file': '#ff6db6',
  'iteration': '#006ddb',
  'info': '#22cf22',
  'label': '#ad9865',
  'member': '#22cf22',
  'milestone': '#db6d00',
  'nil': '#676767',
  'number': '#22cf22',
  'prompt': '#006ddb',
  'role__admin': '#ffdf4d',
  'role__member': '#3a95c9',
  'role__observer': '#676767',
  'role__owner': '#920000',
  'started': '#b66dff',
  'story': '#b66dff',
  'string': '#ffdf4d',
  'subdued': '#676767',
  'symbol': '#b66dff',
  'task': '#009999',
  'team': '#ff6db6',
  'title': '#ffffff',
  'unstarted': '#920000',
  'warn': '#ffdf4d',
  'workflow state': '#006ddb',
  'workflow': '#006ddb',

  // "#000000",
  // "#252525",
  // "#676767",
  // "#ffffff",
  // "#171723",
  // "#004949",
  // "#009999",
  // "#22cf22",
  // "#490092",
  // "#006ddb",
  // "#b66dff",
  // "#ff6db6",
  // "#920000",
  // "#8f4e00",
  // "#db6d00",
  // "#ffdf4d",
};


// final defaultLightPalette = {
//   'comment': '#8c8d8c',
//   'done': '#56993d',
//   'epic workflow state': '#444444',
//   'epic workflow': '#444444',
//   'epic': '#56993d',
//   '__fallback': '#444444',
//   'iteration': '#61a3cf',
//   'label': '#c3a73f',
//   'member': '#658ee7',
//   'milestone': '#df8632',
//   'prompt': '#ad87f3',
//   'started': '#5c1bd2',
//   'story': '#5c1bd2',
//   'subdued': '#575858',
//   'task': '#ad87f3',
//   'team': '#224bb3',
//   'title': '#50ab54',
//   'unstarted': '#931f17',
//   'workflow state': '#444444',
//   'workflow': '#444444',
// };

// final colorblindLightColors = {};
