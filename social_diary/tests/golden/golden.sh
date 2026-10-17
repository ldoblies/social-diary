#!/bin/sh
# A refactor's proof that nothing a player sees changed: everything the
# addon draws and stores, dumped, to diff before and after.
#
#   tests/golden/golden.sh <label>        dump into $SD_GOLDEN/<label>/
#   diff -r $SD_GOLDEN/before $SD_GOLDEN/after
#
# SD_GOLDEN defaults to /tmp/sd-golden. Each label holds:
#   suite.txt    tests/run.lua's output (its last line: the checks passed)
#   uidump.txt   tests/uidump.lua with every testdata entry and zone page
#   rows.txt     every People row kind through the core and the ledger
#   tester.txt   /sd testdata's Tester: rows in stored order, and the route
#
# The dumps are not tests (they check nothing). rows_dump.lua and
# tester_dump.lua run beside the harness, so they go into a farm: symlinks
# to the addon's files, nothing written in the addon.
set -e
here=$(cd "$(dirname "$0")" && pwd)
addon=$(cd "$here/../.." && pwd)
base=${SD_GOLDEN:-/tmp/sd-golden}
[ -n "$1" ] || { echo "usage: $0 <label>" >&2; exit 2; }
out="$base/$1"
mkdir -p "$out"
cd "$addon"

luajit tests/run.lua > "$out/suite.txt" 2>&1 || true
tail -1 "$out/suite.txt"
SD_UIDUMP_ENTRIES=all luajit tests/uidump.lua > "$out/uidump.txt"

# A dump script run from a farm (its name, the file it writes).
Farm() {
    farm="$base/farm-$1"
    rm -rf "$farm"
    mkdir -p "$farm/tests"
    for f in "$addon"/*; do [ "$(basename "$f")" = tests ] || ln -s "$f" "$farm/$(basename "$f")"; done
    for f in harness.lua wowmock.lua fixtures.lua; do ln -s "$addon/tests/$f" "$farm/tests/$f"; done
    cp "$here/$1.lua" "$farm/tests/$1.lua"
    (cd "$farm" && luajit -e "dofile('tests/harness.lua').Run('tests', { '$1' }, {})") > "$out/$2" 2>&1
}
Farm rows_dump rows.txt
Farm tester_dump tester.txt

wc -l "$out"/*.txt
