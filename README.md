<p align="center">
  <img height="60" src="https://user-images.githubusercontent.com/7189823/133838642-9a05e1ec-9a79-46ae-b22e-a8b931caf233.png" alt="Shortcut logo">
</p>

# Shortcut REPL

Both a CLI command and REPL environment for using [Shortcut](https://shortcut.com).

For detailed documentation, open the `docs/` folder as a [Logseq](https://logseq.com/) database.

## Usage

These instructions assume you've named this program `sc` and put it on your `PATH`.

First, ensure you have a [Shortcut API token](https://app.shortcut.com/internal/settings/account/api-tokens) defined as `SHORTCUT_API_TOKEN` in your environment. I suggest using a tool like [sops](https://github.com/mozilla/sops) to encrypt this credential:

```shell
export SHORTCUT_API_TOKEN=$(sops --decrypt --extract '["shortcut"]["api_token"]')
```

To be able to create and access Docs, you need the Shortcut cookie (called `sid` as of this writing) out of your browser and supply that as `SHORTCUT_APP_COOKIE` in your environment. Please include only the _value_ of the cookie, not the `sid=` portion you may see if you "Copy as cURL" from your browser's developer tools. You will also need the `tenant-organization2` and `tenant-workspace2` header values, which you can find using your browser's developer tooling while navigating within Docs.

```shell
export SHORTCUT_APP_COOKIE=<UUID goes here>
export SHORTCUT_ORGANIZATION2=<UUID goes here>
export SHORTCUT_WORKSPACE2=<UUID goes here>
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

## Releases

This repository as hosted on GitHub is set up with GitHub Actions to produce an executable for Linux, macOS, and Windows when a GitHub Release is created.

1. Create a new Release by visiting [this url](https://github.com/semperos/shortcut-repl/releases/new).
1. Give it an appropriate tag and version name.
1. After creating the release, verify that the `release` GitHub action completes successfully. It will automatically upload the executable artifacts to the release you just created.

## Project Status

This project is not an official Shortcut-sponsored project. It was originally developed by [Daniel Gregoire](https://danielgregoire.dev/) and donated to Shortcut as an open source resource intended for community use.

Furthermore, there are a number of features that are lacking, incomplete, broken, or that may change over time. A non-exhaustive list follows:

* **Shortcut's API:** Only parts of the v3 API are leveraged. The Docs functionality uses endpoints that are not guaranteed to remain stable over time.
* **Interactive entity creation:** The implementation is rubbish and incomplete. Will likely be removed. Use `create-*` with a map, remembering you can write things out in a separate file and use `load` or you can create a minimal entity and then use `! .description` (or whatever field) to open your default system `EDITOR` to edit fields there.
* **The Language (Lisp):** The Lisp implementation is ad hoc, incomplete, and in some ways broken. Useful, but don't get too fancy.

## License

Copyright © 2022–2023 Shortcut Software Company

Licensed under either of

 * Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
 * MIT license ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any
additional terms or conditions.

### Exceptions

**Project:** cli\_repl

The cli\_repl code in this project has been copied and adapted from the [cli_repl](https://github.com/jathak/cli_repl) library by Jennifer Thakar, which is licensed under BSD 3-Clause "New" or "Revised" License.
