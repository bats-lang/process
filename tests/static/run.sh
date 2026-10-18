#!/bin/sh
# Static tests. Each package under tests/static/accept/ must pass `bats
# check` against this checkout; each under tests/static/reject/ must fail
# it with an unsolved constraint (a proof the types demand and the code
# does not make), so a reject that fails for another reason (a typo) is a
# failure too. The accepts show the rejects are rejected for their one
# line.
#
# usage: tests/static/run.sh <repository-dir>   (bats must be on PATH)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
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
    elif [ "$kind" = reject ] && [ "$status" = fail ] && grep -q 'error(3): unsolved constraint' "$log" \
         && ! grep -q 'error(2)\|error(1)' "$log"; then
      echo "ok   reject/$n"
    else
      echo "FAIL $kind/$n ($status)"; tail -8 "$log"; fail=1
    fi
  done
done
exit $fail
