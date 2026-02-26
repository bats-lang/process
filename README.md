# process

Process spawning for the [Bats](https://github.com/bats-lang) programming language.

## Features

- Spawn child processes with explicit argv and envp
- Pipe configuration: stdin, stdout, stderr (pipe, dev_null, inherit)
- Wait for child exit with exit code
- Linear ownership for child handles and pipe endpoints

## Usage

```bats
#use process as P
#use result as R

val sr = $P.spawn(exec_bv, exec_len, argv_bv, argc, envp_bv, envc,
  $P.dev_null(), $P.dev_null(), $P.pipe_new())
case+ sr of
| ~$R.ok(sp) => let
    val+ ~$P.spawn_pipes_mk(child, sin, sout, serr) = sp
    val wr = $P.child_wait(child)
    ...
  end
| ~$R.err(_) => ...
```

## API

See [docs/lib.md](docs/lib.md) for the full API reference.

## Safety

`unsafe = true` — wraps POSIX `posix_spawn`. Exposes a safe typed API with linear ownership for child processes and pipe endpoints.
