- _NB: See also all [[TODO]] entries._
-
- ## Piped Lisp
- TODO Date/time support with dedicated data type and functions for relative dates/times in support of things like easy iteration creation.
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
-
- ## sc
- TODO Integration with `bat`, `glow`, or other tools (expose via config) for viewing Markdown in a semi-formatted fashion at the terminal.
-