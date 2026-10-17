#!/bin/bash
# Compares two golden.sh labels: silent and exit 0 when nothing changed.
#
#   tests/golden/compare.sh <before> <after>
#
# The dumps compare byte for byte.
base=${SD_GOLDEN:-/tmp/sd-golden}
a="$base/$1"; b="$base/$2"
[ -d "$a" ] && [ -d "$b" ] || { echo "usage: $0 <before> <after> (labels under $base)" >&2; exit 2; }
status=0
for f in suite.txt uidump.txt rows.txt tester.txt; do
    cmp -s "$a/$f" "$b/$f" || { echo "== $f differs"; diff "$a/$f" "$b/$f" | head -40; status=1; }
done
exit $status
