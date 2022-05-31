// Copyright (c) 2018, Jennifer Thakar.
// All rights reserved.

// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the project nor the names of its contributors may be
//       used to endorse or promote products derived from this software without
//       specific prior written permission.

// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:io/ansi.dart';

import '../../cli_repl.dart';
import 'codes.dart';

final RegExp promptPattern = RegExp(r'^(sc[^>]*>\s*)+');

class ReplAdapter {
  Repl repl;

  ReplAdapter(this.repl);

  Iterable<String> run() sync* {
    try {
      // Try to set up for interactive session
      stdin.echoMode = false;
      stdin.lineMode = false;
      // Write to persistent history file.
    } on StdinException {
      // If it can't, print both input and prompts (useful for testing)
      yield* linesToStatements(inputLines());
      return;
    }
    while (true) {
      try {
        var result = readStatement();
        if (result == null) {
          print("");
          break;
        }
        yield result;
      } on Exception catch (e) {
        print(e);
      }
    }
    exit();
  }

  Iterable<String> inputLines() sync* {
    while (true) {
      try {
        String? line = stdin.readLineSync();
        if (line == null) break;
        yield line;
      } on StdinException {
        break;
      }
    }
  }

  Stream<String> runAsync() {
    bool interactive = true;
    try {
      stdin.echoMode = false;
      stdin.lineMode = false;
    } on StdinException {
      interactive = false;
    }

    late StreamController<String> controller;
    controller = StreamController(
        onListen: () async {
          try {
            var charQueue =
                this.charQueue = StreamQueue<int>(stdin.expand((data) => data));
            while (true) {
              if (!interactive && !(await charQueue.hasNext)) {
                this.charQueue = null;
                controller.close();
                return;
              }

              var result = await _readStatementAsync(charQueue);
              if (result == null) {
                print("");
                break;
              }
              controller.add(result);
            }
          } catch (error, stackTrace) {
            controller.addError(error, stackTrace);
            await exit();
            controller.close();
          }
        },
        onCancel: exit,
        sync: true);

    return controller.stream;
  }

  FutureOr<void> exit() {
    try {
      stdin.lineMode = true;
      stdin.echoMode = true;
    } on StdinException {}

    var future = charQueue?.cancel(immediate: true);
    charQueue = null;
    return future;
  }

  Iterable<String> linesToStatements(Iterable<String> lines) sync* {
    String previous = "";
    for (var line in lines) {
      write(previous == "" ? repl.prompt : repl.continuation);
      previous += line;
      stdout.writeln(line);
      if (repl.validator(previous)) {
        yield previous;
        previous = "";
      } else {
        previous += '\n';
      }
    }
  }

  StreamQueue<int>? charQueue;

  List<int> buffer = [];
  int cursor = 0;

  setCursor(int c) {
    if (c < 0) {
      c = 0;
    } else if (c > buffer.length) {
      c = buffer.length;
    }
    moveCursor(c - cursor);
    cursor = c;
  }

  write(String text) {
    stdout.write(text);
  }

  writeChar(int char) {
    stdout.writeCharCode(char);
  }

  int historyIndex = -1;
  String currentSaved = "";

  String previousLines = "";
  bool inContinuation = false;

  String? readStatement() {
    startReadStatement();
    while (true) {
      int char = stdin.readByteSync();
      if (char == eof && buffer.isEmpty) return null;
      if (char == escape) {
        var char = stdin.readByteSync();
        if (char == c('[') || char == c('O')) {
          var ansi = stdin.readByteSync();
          if (!handleAnsi(ansi)) {
            write('^[');
            input(char);
            input(ansi);
          }
          continue;
        }
        write('^[');
      }
      var result = processCharacter(char);
      if (result != null) return result;
    }
  }

  Future<String?> _readStatementAsync(StreamQueue<int> charQueue) async {
    startReadStatement();
    while (true) {
      int char = await charQueue.next;
      if (char == eof && buffer.isEmpty) return null;
      if (char == escape) {
        char = await charQueue.next;
        if (char == c('[') || char == c('O')) {
          var ansi = await charQueue.next;
          if (!handleAnsi(ansi)) {
            write('^[');
            input(char);
            input(ansi);
          }
          continue;
        }
        write('^[');
      }
      var result = processCharacter(char);
      if (result != null) return result;
    }
  }

  void startReadStatement() {
    write(repl.prompt);
    buffer.clear();
    cursor = 0;
    historyIndex = -1;
    currentSaved = "";
    inContinuation = false;
    previousLines = "";
  }

  List<int> yanked = [];

  String? processCharacter(int char) {
    switch (char) {
      case eof:
        if (cursor != buffer.length) delete(1);
        break;
      case clear:
        clearScreen();
        break;
      case backspace:
        if (cursor > 0) {
          setCursor(cursor - 1);
          delete(1);
        }
        break;
      case ctrlW:
        int searchCursor = cursor - 1;
        while (true) {
          if (searchCursor == -1) {
            break;
          } else {
            final codePoint = buffer[searchCursor];
            if (codePoint == space ||
                codePoint == c('.') ||
                codePoint == c('-') ||
                codePoint == c('_') ||
                codePoint == c('{') ||
                codePoint == c('}') ||
                codePoint == c('(') ||
                codePoint == c(')') ||
                codePoint == c('[') ||
                codePoint == c(']') ||
                codePoint == c('"')) {
              // Handle multiple ctrlW and swallow one space + next whole word
              if (searchCursor != cursor - 1) {
                break;
              }
            }
          }
          searchCursor--;
        }
        if (cursor == 0 && searchCursor == -1) {
          break;
        } else {
          final numToDelete = cursor - searchCursor;
          setCursor(searchCursor + 1);
          delete(numToDelete - 1);
        }
        break;
      case killToEnd:
        yanked = delete(buffer.length - cursor);
        break;
      case killToStart:
        int oldCursor = cursor;
        setCursor(0);
        yanked = delete(oldCursor);
        break;
      case yank:
        yanked.forEach(input);
        break;
      case startOfLine:
        setCursor(0);
        break;
      case endOfLine:
        setCursor(buffer.length);
        break;
      case forward:
        setCursor(cursor + 1);
        break;
      case backward:
        setCursor(cursor - 1);
        break;
      case tab:
        List<int> autoCompleteCodePoints = [];
        int searchCursor = cursor - 1;
        while (true) {
          if (searchCursor == -1) {
            break;
          } else {
            final codePoint = buffer[searchCursor];
            if (codePoint == space ||
                codePoint == c('{') ||
                codePoint == c('}') ||
                codePoint == c('(') ||
                codePoint == c(')') ||
                codePoint == c('[') ||
                codePoint == c(']')) {
              break;
            } else {
              autoCompleteCodePoints.add(codePoint);
            }
          }
          searchCursor--;
        }
        if (autoCompleteCodePoints.isNotEmpty) {
          final autoCompletePrefix =
              String.fromCharCodes(autoCompleteCodePoints.reversed);
          final autoCompletions =
              repl.env.autoCompletionsFrom(autoCompletePrefix);
          if (autoCompletions.isNotEmpty) {
            if (autoCompletions.length == 1) {
              // If one result, write its suffix directly into buffer.
              clearToEnd();
              var autoCompletion = autoCompletions.first;
              if (autoCompletePrefix.startsWith('.')) {
                autoCompletion =
                    autoCompletion.substring(autoCompletePrefix.length - 1);
              } else {
                autoCompletion =
                    autoCompletion.substring(autoCompletePrefix.length);
              }
              for (final byte in utf8.encode(autoCompletion)) {
                input(byte);
              }
            } else {
              // Show autocomplete results
              String sharedFurtherPrefix =
                  calculateSharedPrefix(autoCompletePrefix, autoCompletions);
              if (sharedFurtherPrefix.isNotEmpty) {
                for (final byte in utf8.encode(sharedFurtherPrefix)) {
                  input(byte);
                }
              }

              saveCursorPosition();
              clearToEnd(); // clear from here to end, to remove previous autocomplete results
              write('\n');
              final prefixLength =
                  autoCompletePrefix.length + sharedFurtherPrefix.length;
              for (final autoCompletion in autoCompletions) {
                final s = autoCompletion.substring(prefixLength);
                write(repl.env.styleWith(
                    autoCompletePrefix + sharedFurtherPrefix, [darkGray])!);
                write(s);
                write(' ');
              }
              restoreCursorPosition();
              // moveCursorUp(1);
            }
          }
        }
        break;
      case carriageReturn:
      case newLine:
        String contents = String.fromCharCodes(buffer);
        setCursor(buffer.length);
        input(char);
        if (repl.env.history.isEmpty || contents != repl.env.history.first) {
          repl.env.history.insert(0, contents.replaceFirst(promptPattern, ''));
        }
        while (repl.env.history.length > repl.maxHistory) {
          repl.env.history.removeLast();
        }
        if (char == carriageReturn) {
          write('\n');
        }
        if (repl.validator(previousLines + contents)) {
          return previousLines + contents;
        }
        previousLines += contents + '\n';
        buffer.clear();
        cursor = 0;
        clearToEnd(); // clear from here to end, to remove previous autocomplete results
        inContinuation = true;
        write(repl.continuation);
        break;
      default:
        input(char);
        break;
    }
    return null;
  }

  input(int char) {
    buffer.insert(cursor++, char);
    write(String.fromCharCodes(buffer.skip(cursor - 1)));
    moveCursor(-(buffer.length - cursor));
  }

  List<int> delete(int amount) {
    if (amount <= 0) return [];
    int wipeAmount = buffer.length - cursor;
    if (amount > wipeAmount) amount = wipeAmount;
    write(' ' * wipeAmount);
    moveCursor(-wipeAmount);
    var result = buffer.sublist(cursor, cursor + amount);
    for (int i = 0; i < amount; i++) {
      buffer.removeAt(cursor);
    }
    write(String.fromCharCodes(buffer.skip(cursor)));
    moveCursor(-(buffer.length - cursor));
    return result;
  }

  replaceWith(String text) {
    moveCursor(-cursor);
    write(' ' * buffer.length);
    moveCursor(-buffer.length);
    write(text);
    buffer.clear();
    buffer.addAll(text.codeUnits);
    cursor = buffer.length;
  }

  bool handleAnsi(int char) {
    switch (char) {
      case arrowLeft:
        setCursor(cursor - 1);
        return true;
      case arrowRight:
        setCursor(cursor + 1);
        return true;
      case arrowUp:
        if (historyIndex + 1 < repl.env.history.length) {
          if (historyIndex == -1) {
            currentSaved = String.fromCharCodes(buffer);
          } else {
            repl.env.history[historyIndex] = String.fromCharCodes(buffer);
          }
          replaceWith(repl.env.history[++historyIndex]);
        }
        return true;
      case arrowDown:
        if (historyIndex > 0) {
          repl.env.history[historyIndex] = String.fromCharCodes(buffer);
          replaceWith(repl.env.history[--historyIndex]);
        } else if (historyIndex == 0) {
          historyIndex--;
          replaceWith(currentSaved);
        }
        return true;
      case home:
        setCursor(0);
        return true;
      case end:
        setCursor(buffer.length);
        return true;
      default:
        return false;
    }
  }

  moveCursor(int amount) {
    if (amount == 0) return;
    int amt = amount < 0 ? -amount : amount;
    String dir = amount < 0 ? 'D' : 'C';
    write('$ansiEscape[$amt$dir');
  }

  moveCursorUp(int amount) {
    write('$ansiEscape[${amount}A');
  }

  moveCursorDown(int amount) {
    write('$ansiEscape[${amount}B');
  }

  /// Clears screen from current cursor to end of screen.
  clearToEnd() {
    write('$ansiEscape[J');
  }

  saveCursorPosition() {
    // write('$ansiEscape[s');
    write('${ansiEscape}7');
  }

  restoreCursorPosition() {
    // write('$ansiEscape[u');
    write('${ansiEscape}8');
  }

  clearScreen() {
    write('$ansiEscape[2J'); // clear
    write('$ansiEscape[H'); // return home
    rewriteBuffer();
  }

  rewriteBuffer() {
    write(inContinuation ? repl.continuation : repl.prompt);
    write(String.fromCharCodes(buffer));
    moveCursor(cursor - buffer.length);
  }
}

/// Return shared further prefix for the given strings, so that autocomplete
/// is even more helpful.
String calculateSharedPrefix(
    String autoCompletePrefix, Iterable<String> autoCompletions) {
  final initLength = autoCompletePrefix.length;
  String workingPrefix = autoCompletions.first.substring(initLength);
  for (final autoCompletion in autoCompletions.skip(1)) {
    final s = autoCompletion.substring(initLength);
    final sub = s.substring(0, workingPrefix.length);
    final subUnits = sub.codeUnits;
    final workingPrefixUnits = workingPrefix.codeUnits;
    int? breakingIdx;
    for (var i = 0; i < subUnits.length; i++) {
      if (subUnits[i] != workingPrefixUnits[i]) {
        breakingIdx = i;
        break;
      }
    }
    if (breakingIdx != null) {
      workingPrefix = sub.substring(0, breakingIdx);
    }
  }
  return workingPrefix;
}
