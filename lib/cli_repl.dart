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

library cli_repl;

import 'dart:async';

import 'package:sc_cli/src/sc.dart';

import 'src/repl_adapter.dart';

class Repl {
  /// Text displayed when prompting the user for a new statement.
  String prompt;

  /// Text displayed at start of continued statement line.
  String continuation;

  /// Called when a newline is entered to determine whether the queue a
  /// completed statement or allow for a continuation.
  StatementValidator validator;

  Repl(
      {this.prompt = '',
      String? continuation,
      StatementValidator? validator,
      this.maxHistory = 1000,
      required this.env})
      : continuation = continuation ?? ' ' * prompt.length,
        validator = validator ?? alwaysValid {
    _adapter = ReplAdapter(this);
  }

  late ReplAdapter _adapter;
  ScEnv env;

  /// Run the REPL, yielding complete statements synchronously.
  Iterable<String> run() => _adapter.run();

  /// Run the REPL, yielding complete statements asynchronously.
  ///
  /// Note that the REPL will continue if you await in an "await for" loop.
  Stream<String> runAsync() => _adapter.runAsync();

  /// Kills and cleans up the REPL.
  FutureOr<void> exit() => _adapter.exit();

  /// History is by line, not by statement.
  ///
  /// The first item in the list is the most recent history item.
  // List<String> history = [];

  /// Maximum history that will be kept in the list.
  ///
  /// Defaults to 50.
  int maxHistory;
}

/// Returns true if [text] is a complete statement or false otherwise.
typedef bool StatementValidator(String text);

final StatementValidator alwaysValid = (text) => true;
