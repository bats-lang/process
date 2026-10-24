#!/bin/sh
# Static tests. Each package under tests/static/accept/ must pass `bats
# check` against this checkout; each under tests/static/reject/ must fail
# it exactly as its `expect` says (process#63, as sha256's, array's and
# arith's, quire#585): the function, the line of its src/bin/<name>.bats
# and patsopt's error word for word, and no other error. expect.py decides;
# a reject with no expect, an empty one or another error fails, so a reject
# that fails for another constraint (a bound, a typo) is a failure too.
# expect_test.py tests expect.py itself and runs first. The accepts show
# the rejects are rejected for their one line.
#
# usage: tests/static/run.sh <repository-dir>   (bats must be on PATH)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
python3 -B -I "$ROOT/tests/static/expect_test.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp -R "$1" "$TMP/repo"
(cd "$ROOT" && bats upload --repository "$TMP/repo" >/dev/null)
PKG=$(sed -n 's/^name *= *"\(.*\)"/\1/p' "$ROOT/bats.toml" | head -1)
NEW=$(ls -t "$TMP/repo/$PKG"/*.bats | head -1)
for a in "$TMP/repo/$PKG"/*.bats; do
  [ "$a" = "$NEW" ] || rm -f "$a" "$a.sha256"
done

fail=0
for kind in accept reject; do
  for d in "$ROOT"/tests/static/$kind/*/; do
    [ -f "$d/bats.toml" ] || continue
    n=$(basename "$d"); w="$TMP/w-$kind-$n"
    cp -R "$d" "$w"
    log="$TMP/$kind-$n.log"
    if (cd "$w" && bats lock --dev --repository "$TMP/repo" && bats check --repository "$TMP/repo") > "$log" 2>&1; then
      status=pass
    else
      status=fail
    fi
    if [ "$kind" = accept ] && [ "$status" = pass ]; then
      echo "ok   accept/$n"
    elif [ "$kind" = reject ] && [ "$status" = fail ] \
         && python3 -B -I "$ROOT/tests/static/expect.py" "$d" "$log" > "$TMP/$n.expect" 2>&1; then
      echo "ok   reject/$n"
    elif [ "$kind" = reject ] && [ "$status" = fail ]; then
      echo "FAIL reject/$n: rejected, but not as its expect says: $(cat "$TMP/$n.expect")"; tail -8 "$log"; fail=1
    else
      echo "FAIL $kind/$n ($status)"; tail -8 "$log"; fail=1
    fi
  done
done
exit $fail
