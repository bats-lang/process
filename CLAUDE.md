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
builder's own (`into_arr`), as big as the entries are. `spawn`'s `path` is
still an array of 524288 bytes: its C reads a string from it, and nothing
in the types says where its NUL is, so a smaller one has to say its size at
run time (not done).

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
