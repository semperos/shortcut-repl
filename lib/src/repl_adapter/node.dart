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

import 'package:async/async.dart';
import 'package:js/js.dart';

import '../../cli_repl.dart';

class ReplAdapter {
  Repl repl;

  ReplAdapter(this.repl);

  Iterable<String> run() sync* {
    throw UnsupportedError('Synchronous REPLs not supported in Node');
  }

  ReadlineInterface? rl;

  Stream<String> runAsync() {
    var output = stdinIsTTY ? stdout : null;
    var rl = this.rl = readline.createInterface(
        ReadlineOptions(input: stdin, output: output, prompt: repl.prompt));
    var statement = "";
    var prompt = repl.prompt;

    late StreamController<String> runController;
    runController = StreamController<String>(
        onListen: () async {
          try {
            var lineController = StreamController<String>();
            var lineQueue = StreamQueue<String>(lineController.stream);
            rl.on('line',
                allowInterop((value) => lineController.add(value as String)));

            while (true) {
              if (stdinIsTTY) stdout.write(prompt);
              var line = await lineQueue.next;
              if (!stdinIsTTY) print('$prompt$line');
              statement += line;
              if (repl.validator(statement)) {
                runController.add(statement);
                statement = "";
                prompt = repl.prompt;
                rl.setPrompt(repl.prompt);
              } else {
                statement += '\n';
                prompt = repl.continuation;
                rl.setPrompt(repl.continuation);
              }
            }
          } catch (error, stackTrace) {
            runController.addError(error, stackTrace);
            await exit();
            runController.close();
          }
        },
        onCancel: exit);

    return runController.stream;
  }

  FutureOr<void> exit() {
    rl?.close();
    rl = null;
  }
}

@JS('require')
external ReadlineModule require(String name);

final readline = require('readline');

bool get stdinIsTTY => stdin.isTTY ?? false;

@JS('process.stdin')
external Stdin get stdin;

@JS()
class Stdin {
  external bool? get isTTY;
}

@JS('process.stdout')
external Stdout get stdout;

@JS()
class Stdout {
  external void write(String data);
}

@JS()
class ReadlineModule {
  external ReadlineInterface createInterface(ReadlineOptions options);
}

@JS()
@anonymous
class ReadlineOptions {
  external get input;
  external get output;
  external String get prompt;
  external factory ReadlineOptions({input, output, String? prompt});
}

@JS()
class ReadlineInterface {
  external void on(String event, void callback(object));
  external void question(String prompt, void callback(object));
  external void close();
  external void pause();
  external void setPrompt(String prompt);
}
