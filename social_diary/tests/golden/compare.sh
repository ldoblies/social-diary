#!/bin/bash
# Compares two golden.sh labels: silent and exit 0 when nothing changed.
#
#   tests/golden/compare.sh <before> <after>
#
# The dumps compare byte for byte. The plates' summaries and checks
# compare sorted, because plates.sh takes the forced pages in `pairs`
# order, which changes from run to run.
base=${SD_GOLDEN:-/tmp/sd-golden}
a="$base/$1"; b="$base/$2"
[ -d "$a" ] && [ -d "$b" ] || { echo "usage: $0 <before> <after> (labels under $base)" >&2; exit 2; }
status=0
for f in suite.txt uidump.txt rows.txt tester.txt; do
    cmp -s "$a/$f" "$b/$f" || { echo "== $f differs"; diff "$a/$f" "$b/$f" | head -40; status=1; }
done
for f in plates.txt plates/out.txt; do
    if ! cmp -s <(sort "$a/$f") <(sort "$b/$f"); then
        echo "== $f differs (sorted)"; diff <(sort "$a/$f") <(sort "$b/$f") | head -40; status=1
    fi
done
exit $status
