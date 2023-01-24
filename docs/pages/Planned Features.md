- _NB: See also all [[TODO]] entries._
-
- ## Piped Lisp
- Collections
	- Seq Abstraction
		- TODO Initial `seq` function that provides a common representation of lists, strings, and maps
		- TODO Audit functions that have collection-specific handling, considering whether relying on `seq` is a better/viable approach.
	- Maps
	  collapsed:: true
		- DONE Audit mutable vs. immutable methods and rename accordingly
	- Lists
	  collapsed:: true
		- DONE Audit mutable vs. immutable methods and rename accordingly
- Date/time support
  collapsed:: true
	- DONE New `date-time` type
	- DONE `dt` function for converting a string to a `date-time`
	- DONE `now` function
	- DONE `plus-*` and `minus-*` dt fns
	- DONE `*-since` and `*-until` dt fns
	- TODO `date-time` accessors for year, month, day-of-month, etc.
- Printing
  collapsed:: true
	- DONE Reconcile `printToString` and `readableString`
		- Context: `readableString` arose during work on `ScEntity` and sub-classes
	-
- Navigation (App)
	- DONE `nav-*` for landing on particular pages in the web app. Blocked by [workspace-url](logseq://graph/docs?block-id=62f6affd-410e-419c-890c-cbb873069126)
- Shortcut API
	- TODO `req` function that—given a path or full URL string—makes the given API call to the Shortcut API. Consider having only one argument that is a map which supports `.path` `.url` `.params` and `.method` and does The Right Thing. Blocked by [workspace-url](logseq://graph/docs?block-id=62f6affd-410e-419c-890c-cbb873069126)
		- DONE A function called `url` or `base-url` or `workspace-url` for getting what is defined in `SHORTCUT_APP_HOST` or defaulting to the canonical production one.
		  id:: 62f6affd-410e-419c-890c-cbb873069126
		  :LOGBOOK:
		  CLOCK: [2022-08-15 Mon 17:00:57]--[2022-08-15 Mon 17:00:58] =>  00:00:01
		  CLOCK: [2022-08-15 Mon 17:00:59]--[2022-08-15 Mon 17:01:01] =>  00:00:02
		  :END:
	- TODO Consider memoizing `ScWorkflow`, `ScWorkflowState`, `ScMember`, `ScTeam`, possibly with some way to bust the cache so folks don't have to restart the program.
- Strings
	- TODO Intern strings, given they account for the majority of memory consumption within this Dart package in the running program
	- TODO Maybe: Regular expression support.
	- TODO `starts-with?` and `ends-with?` functions
-
-
-
- ## REPL
- TODO State machine to replace the crazy if/else chains that implement interactive entity creation and setting defaults.
- _Completed_
  collapsed:: true
	- DONE Story for viewing and setting everything that's configurable via `env.json` and/or environment variables.
	- DONE Change prompt when in a parent entity.
	  collapsed:: true
	  :LOGBOOK:
	  CLOCK: [2022-05-21 Sat 21:30:57]--[2022-05-21 Sat 21:30:58] =>  00:00:01
	  CLOCK: [2022-05-21 Sat 21:30:59]--[2022-05-21 Sat 21:31:00] =>  00:00:01
	  :END:
		- Thinking a line _previous_ to the main `sc>` prompt, with a starting `;` so copy and paste across lines is minimally disturbed.
			- This turned out to be too noisy. Went instead with `sc (mi 23)>` using the `readableString` representation of entities.
	- DONE Way to clear the buffer and get back default prompt without having to exit the REPL
	- DONE Story for opening up `EDITOR` to handle writing descriptions, comments. Perhaps `SHORTCUT_EDITOR` as possibility, too, so a non-terminal editor can be configured if `EDITOR` is a terminal one by default for folks.
	- DONE Consider replacing current ANSI library with [chalkdart](https://timmaffett.github.io/chalkdart_docs/index.html)
-
-
- ## Application-level
- TODO Integration with `bat`, `glow`, or other tools (expose via config) for viewing Markdown in a semi-formatted fashion at the terminal.
	- First attempt: ANSI codes appear to be stripped when printing sub-process's `stdout`
- TODO Search by commenter (find stories/epics with comments by so-and-so)
- _Completed_
	- DONE Reify bindings for all labels as `label-<name>` like we do for teams, members
	- DONE Parse fields in entity payloads that are known to be date-time values using `dt` so users don't have to `... | dt | ...`