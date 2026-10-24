# process

## An argument is an array of the size it needs (#59)

`arg_entry` is `[l:agz][cap:pos][n:nat | n <= cap; cap <= ARG_ENTRY_MAX]
@(arr(byte, l, cap), int n)`: an entry owns an array of its own capacity
and says how many of its bytes are the content, so the type states the
length and the bound (`ARG_ENTRY_MAX` is 524288). A builder's `into_arr` is
an entry as it is (a short argument takes 64 bytes, not 524288), and so is
a builder's `to_arr` (an array of `BUILDER_CAP` bytes), so a caller that
builds entries that way is unchanged; a caller that made an entry from an
array and a length it had no proof about must now have one.

What a spawn accepts is unchanged and now in the types: the entries of a
list and the NUL after each take at most `ARG_TOTAL_MAX` (524287) bytes,
else the result is E2BIG. `_build_from_list` joins them into a builder of
that type (`_fitted`), reads each byte at an index proved below the
entry's length and capacity, and the array spawn hands the C is that
builder's own (`into_arr`), as big as the entries are.

## Spawn keeps its old signatures; the proved ones are beside them (#61, #64)

`spawn`, `spawn_inherit_env` and `spawn_inherit_env_with` take
`path: !borrow(byte, lp, 524288)`, as they always did. They are the
**unproved forms, kept for compatibility**: their C reads the path as a
string, and nothing in the types says where its NUL is, so only an array of
524288 bytes is safe to pass. A dependent moves to the proved forms in a PR
of its own; these three are removed by a ticket of their own, once every
dependent has moved, and not before. (PR #62 replaced them in place; that
failed `verify` in the package repository for pwa, whose published source
calls the old ones, so #64 restored them.)

The proved forms, `spawn_proved`, `spawn_inherit_env_proved` and
`spawn_inherit_env_with_proved`, state the NUL in the type. `path_of_string_proved`
makes the path: the bytes of a string and a zero after them, in the builder's
own array (at least the string's length plus one, not a fixed 524288 bytes),
with the proof `NUL_AT(cs, n, k)`: byte `k` of the `n` bytes whose cells are
`cs` is zero. The proof is made from the array package's own cell proofs
(`CLEN`, `NTH` after `barr_set`), so nothing here is a runtime check. The
proved spawns take the proof and a `cborrow(lp, np, cs)` of the same cells
(`barr_freeze`), and the type of the path is the only thing the C call
relies on. `NUL_AT` is a dataprop, not linear, so one proof serves each
spawn of the path. Rejected by `tests/static/reject/`: a cell that is not
zero (`nul-not-zero`), a NUL of another array (`nul-other-array`), a byte
past the array (`index-past-end`). `nul-other-array` sets the NUL in one
`barr_alloc(n)` array and borrows a second `barr_alloc(n)` array of the same
`n`, so the arrays differ only in their cells (they used to differ in size
too, which alone would reject it) and the one failing constraint is that the
cells are the same; its control is `accept/nul-same-array`, the same program
borrowing the NUL's own array. Every reject has an `expect` (the function, the
line and patsopt's error word for word, `tests/static/expect.py`, as sha256's,
array's and arith's, process#63): a reject that fails for another constraint
(the `n <= 1048576` bound of `barr_alloc`) fails the run. `tests/dynamic/nulpath`
spawns with a 1-byte path (`"x"`, spawn's ENOENT, 1002: a NUL at the wrong
byte gives EACCES, 1013) and a path with an early NUL (`"/bin/sh"`, a zero,
`"junk"`: the C reads `/bin/sh` and the child exits 4), under valgrind. The
path at the old 524288 bound is a third case there, made on the array path the
proved spawns take (`barr_alloc`, a NUL at byte 524287, every other byte set with
the NUL's `NTH` kept by `setc_nth_other`; no string is needed): the kernel
refuses it as too long (ENAMETOOLONG, 36 on Linux and 63 on macOS and the BSDs, so the test holds no number: it takes the platform's own from a second path too long everywhere, one 4999-byte component, and the bound path must give that same status; #72); a NUL moved to byte 0 gives 1013. `tests/dynamic/oldspawn` calls each of the
three unproved forms, so an edit cannot drop them without a failing test.

The name: a stricter variant is added beside the plain one with a word that
says what it adds. arith's `and_proved` returns the number with the proof of
what it is; array adds `barr_alloc` and `cborrow_get` beside `alloc` and
`borrow_get`, never in place of them. `_proved` is arith's word, for a
function whose call carries a proof.

## The wait has outcome forms beside the old ones (#52, wait/signal)

`child_wait` and `child_try_wait` keep their types: a child ended by a
signal and a failed `waitpid` are both `err(-1)` (and `none`), which is why
bats `with-env` (bats#282) exits 1 where a shell exits 128 + n. They are
**deprecated, kept for compatibility**; process#81 removes them once every
dependent has moved.

`child_wait_outcome` and `child_try_wait_outcome` are beside them. Their
answers are linear datatypes with a constructor for each outcome, decoded
once in C from the platform's own macros (`WIFEXITED`/`WEXITSTATUS`,
`WIFSIGNALED`/`WTERMSIG`): `child_exited(status)`, `child_signaled(signal)`,
`child_wait_failed(errno)` and `child_wait_unexpected(raw status)` (neither
an exit nor a signal), plus `child_running()` / `child_ended(outcome)` for the
poll. `waitpid` is retried on EINTR, so an interrupted wait is not a failed
one. No runtime check: the match is `case+`, so a caller handles each
constructor (`tests/static/reject/outcome-not-matched`, `outcome-dropped`;
`accept/outcome-all`). `tests/dynamic/waitoutcome` runs real children (exit
0, 7, 255; SIGKILL, SIGTERM, SIGSEGV; a pid that is no child, ECHILD; a child
still running, then ended by exit and by signal) and `tests/dynamic/oldwait`
calls each old form, so an edit cannot drop them. The C writes the number through a pointer to a local, so no state is shared between waits.

## CI is pinned

Every input to CI is pinned in the source (bats-lang/repository-prototype#269),
so a commit that passes keeps passing:

* `bats.lock` is committed: CI never runs `bats lock` for the package, so
  `bats check` and `bats build` fetch exactly the locked versions, and fail
  when the lock is missing or does not match `bats.toml`. A library's lock
  pins only its own CI and tests; its dependents still resolve their own.
* The compiler is the commit in `.github/bats-version`, read by every
  workflow that builds bats (and by the publish workflow).
* The package repository is fetched at the commit in
  `.github/repository-version`, so what the test packages under `tests/`
  lock (`bats lock --dev`) is pinned too.
* `publish.yml` and `relock-pins.yml` in bats-lang/repository-prototype are
  called by commit, never `@main`.

Pins move only through a reviewed pull request that runs the same CI. The
daily `relock.yml` (the shared `relock-pins.yml`) relocks against the
newest, moves the compiler and repository pins, pushes `relock/<date>`,
opens a pull request listing the old and new versions and dispatches
`check.yml` on it, so a breaking publish shows as a red relock pull
request and main stays green. GITHUB_TOKEN cannot change workflow files,
so without a `RELOCK_TOKEN` secret that pull request lists a workflow pin
that would move instead of moving it: move it in a pull request of its
own. A pull request that needs newer packages runs `bats lock
--repository <dir>` and commits `bats.lock` (and
`.github/repository-version`) with the change.

## The proofs are mutation-checked under the infinite-precision solver (bats-lang/quire#594)

The 32-bit solver can make a proof's context contradictory, so a lemma then proves nothing; CI runs
the GMP build (the bats setup action runs `bats ats2 install`), so a check of the proofs is made
with that build as `--ats-home`. quire's `tests/static/mutation_check.py` (from a clone of
bats-lang/quire) takes the statement of each `prfun`, `prfn` and `primplement` of a module, makes it
false, and the compiler must reject it:

```
python3 -B -I quire/tests/static/mutation_check.py --root . --run WORK --ats-home GMP_HOME/.bats/ats2 \
  --inplace src/lib.bats
```

`src/lib.bats` has no lemma of its own: its one proof is the dataprop `NUL_AT`, whose constructor
`NUL_mk` joins the array package's lemmas (`CLEN`, `NTH`), so the checker finds nothing to mutate
("no lemma to mutate"). What guards `NUL_AT` instead is a reject fixture for each way to break it,
in `tests/static/reject/`, each with an exact `expect` (`tests/static/expect.py`): the zero (`nul-not-zero`),
the cells of the length against the cells of the zero (`nul-cells-mixed`), the guard `k < n`
(`nul-index-equals-length`), a byte past the array (`index-past-end`), and, for each of the three
proved spawns, a NUL of another array than the path's (`nul-other-array`, `nul-other-array-spawn`,
`nul-other-array-env-with`), each with its control in `tests/static/accept/`. The fixtures
are the mutants of `NUL_AT` and of the spawns' types: weaken the dataprop (free the value, free
the cells, drop the guard) or a spawn's link of the proof to the path, and the fixture for that
link is accepted or fails its `expect`, which fails the run.

A new `prfun`, `prfn` or `primplement` is run through the checker (an accepted mutant that is
equivalent is explained in a `--known` file, `tests/static/mutation_known.txt`, as gestures' is),
and a proof that is a constructor's guard or a signature's link gets a reject fixture that fails for
that one line. `tests/static/run.sh` runs the scripts with `python3 -B -I`, so no `__pycache__` is
written into the tree that `bats upload` (its last step) needs clean.
