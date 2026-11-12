# process

Process spawning for the [Bats](https://github.com/bats-lang) programming language.

## API

See [docs/lib.md](docs/lib.md) for the full API reference.

## Safety

`unsafe = true` — wraps POSIX `posix_spawn`. Exposes a safe typed API with linear ownership for child processes and pipe endpoints.
