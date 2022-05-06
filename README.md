# Shortcut CLI

Both a CLI command and REPL environment for using [Shortcut](https://shortcut.com).

This is a personal, open-source effort and not an officially-sponsored tool.

## Usage

These instructions assume you've named this program `sc` on your `PATH`.

First, ensure you have a [Shortcut API token](https://app.shortcut.com/internal/settings/account/api-tokens) defined as `SHORTCUT_API_TOKEN` in your environment. I suggest using a tool like [sops](https://github.com/mozilla/sops) to encrypt this credential:

```shell
export SHORTCUT_API_TOKEN=$(sops --decrypt --extract '["shortcut"]["api_token"]')
```

With that, you can run `sc` in one of two modes:

* Interactive Read-Eval-Print Loop (REPL)
* CLI command

Most things that can be done at the REPL can be done as one-off commands as well.

### REPL

To start the REPL:

```
sc -r
```

Once the REPL starts, you should see this prompt:

```
sc>
```

The prompt is rudimentary; you probably want to wrap your call to `sc -r` with `rlwrap` or a similar tool.

Execute `?` or `help` to get overall help. Pass arguments to these commands to get more fine-grained documentation.

```
sc> ? story
```

## Development

### Initial Build

```bash
# Get dependencies
dart pub get

# Executable
dart compile exe -o sc ./bin/sc_cli.dart

# Development, REPL
dart run ./bin/sc_cli_dev.dart -r
```

### Adding new CLI Arguments

To add new command line options to `lib/src/options.dart`, update the `Options`
class and re-run `build_runner`:

```bash
dart run build_runner build
```

This generates a new `lib/src/options.g.dart` file.

## Ideas

- [x] `pwd`
- [x] `.` alias for `pwd`
- [x] Strip leading `sc>` to allow easier copy and paste
- [x] Don't make `where` require a query arg
- [x] Add `search` function that takes either an ScQuery or a string query directly
- Extend searching with ability to set page size
- [x] Consider removing `fetch` branch to execute search once `search` is implemented
- Optionally print `ScExpr`s as JSON to allow for easier manipulation via tools like `jq` or `zq`
- Style the titles of entities with underline and/or different coloration per-letter to display progress.
- [x] Change `sc>` prompt when a question is being asked and when the next thing evaluated will be bound. Maybe `sc?>` and  `sc*>`?
- [x] Polymorphic fetcher: all public IDs will be unique, use parallel requests to get first-OK response and use that. (Status: Non-parallel version implemented)
- Dependency/relationship tree between stories
- Option to log to a file in a debug mode

## License

The cli\_repl code has been adapted from the [cli_repl](https://github.com/jathak/cli_repl) library by Jennifer Thakar, which is licensed under BSD 3-Clause "New" or "Revised" License.