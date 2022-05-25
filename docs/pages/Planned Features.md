- _NB: See also all [[TODO]] entries._
-
- ## Piped Lisp
- Maps
	- TODO Audit mutable vs. immutable methods and rename accordingly
- Lists
	- DONE Audit mutable vs. immutable methods and rename accordingly
- Date/time support
	- DONE New `date-time` type
	- DONE `dt` function for converting a string to a `date-time`
	- DONE `now` function
	- DONE `plus-*` and `minus-*` dt fns
	- DONE `*-since` and `*-until` dt fns
	- TODO `date-time` accessors for year, month, day-of-month, etc.
- Printing
	- TODO Reconcile `printToString` and `readableString`
		- Context: `readableString` arose during work on `ScEntity` and sub-classes
	-
-
- ## REPL
- DONE Change prompt when in a parent entity.
  collapsed:: true
  :LOGBOOK:
  CLOCK: [2022-05-21 Sat 21:30:57]--[2022-05-21 Sat 21:30:58] =>  00:00:01
  CLOCK: [2022-05-21 Sat 21:30:59]--[2022-05-21 Sat 21:31:00] =>  00:00:01
  :END:
	- Thinking a line _previous_ to the main `sc>` prompt, with a starting `;` so copy and paste across lines is minimally disturbed.
		- This turned out to be too noisy. Went instead with `sc (mi 23)>` using the `readableString` representation of entities.
- TODO Way to clear the buffer and get back default prompt without having to exit the REPL
- TODO State machine to replace the crazy if/else chains that implement interactive entity creation and setting defaults.
- TODO Story for viewing and setting everything that's configurable via `env.json` and/or environment variables.
- TODO Story for opening up `EDITOR` to handle writing descriptions, comments. Perhaps `SHORTCUT_EDITOR` as possibility, too, so a non-terminal editor can be configured if `EDITOR` is a terminal one by default for folks.
- TODO Consider replacing current ANSI library with [chalkdart](https://timmaffett.github.io/chalkdart_docs/index.html)
-
-
- ## sc
- DONE Parse fields in entity payloads that are known to be date-time values using `dt` so users don't have to `... | dt | ...`
- TODO Integration with `bat`, `glow`, or other tools (expose via config) for viewing Markdown in a semi-formatted fashion at the terminal.
	- First attempt: ANSI codes appear to be stripped when printing sub-process's `stdout`
- TODO Search by commenter (find stories/epics with comments by so-and-so)