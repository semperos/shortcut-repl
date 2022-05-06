import 'dart:math';

import 'package:io/ansi.dart';

/// Taken from https://pub.dev/packages/io/example
void previewAnsi(String name, List<AnsiCode> values, bool forScript) {
  print('');
  final longest = values.map((ac) => ac.name.length).reduce(max);

  print(wrapWith('** $name **', [styleBold, styleUnderlined]));
  for (var code in values) {
    final header =
        '${code.name.padRight(longest)} ${code.code.toString().padLeft(3)}';

    print("$header: ${code.wrap('Sample', forScript: forScript)}");
  }
}
