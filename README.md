# Shortcut CLI

Both a CLI command and REPL environment for using [Shortcut](https://shortcut.com).

This is a personal, open-source effort and not an officially-sponsored tool.

## Usage

These instructions assume you've named this program `sc` and put it on your `PATH`.

First, ensure you have a [Shortcut API token](https://app.shortcut.com/internal/settings/account/api-tokens) defined as `SHORTCUT_API_TOKEN` in your environment. I suggest using a tool like [sops](https://github.com/mozilla/sops) to encrypt this credential:

```shell
export SHORTCUT_API_TOKEN=$(sops --decrypt --extract '["shortcut"]["api_token"]')
```

With that, you can run `sc` in one of two modes:

* Interactive Read-Eval-Print Loop (REPL) using `sc -r`
* CLI command for one-off programs using `sc -e`

### REPL

To start the REPL:

```
sc -r
```

Once the REPL starts, you should see this prompt:

```
sc>
```

Press `Ctrl-c` to see instructions for using the interactive console itself.

Execute `?` or `help` to see a list of all bindings, or pass a function as an argument to these commands to get more complete documentation for that function:

```
sc> ? ?
```

## Development

### Initial Build

```bash
# Get dependencies
dart pub get

# Executable saved as sc in the current directory
dart compile exe -o sc ./bin/sc_cli.dart

# Build code and run REPL
dart run ./bin/sc_cli.dart -r
```

### Adding new CLI Arguments

To add new command line options to `lib/src/options.dart`, update the `Options`
class and re-run `build_runner`:

```bash
dart run build_runner build
```

This generates a new `lib/src/options.g.dart` file.

## License

### Original Code

All code original to this project is licensed under the [Blue Oak Model License](https://blueoakcouncil.org/license/1.0.0).

### Project: cli\_repl

The cli\_repl code in this project has been copied and adapted from the [cli_repl](https://github.com/jathak/cli_repl) library by Jennifer Thakar, which is licensed under BSD 3-Clause "New" or "Revised" License.
