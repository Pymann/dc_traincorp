#!/usr/bin/env bash
# package_complete.sh STORE_DIR REQUIRED_LIST
#
# Checks that STORE_DIR holds <name>.kvwal for every store named in
# REQUIRED_LIST (one name per line, `#` comments and blank lines ignored).
#
# Prints each missing store name on its own line to stdout.
# Exit 0: complete.  Exit 1: at least one store missing.  Exit 2: bad call.
#
# Only presence is checked: a kvwal is a sparse file whose size says little
# about its content.  Whether the weights are any good is the gate's job.
set -u

if [ "$#" -ne 2 ]; then
  echo "usage: $0 STORE_DIR REQUIRED_LIST" >&2
  exit 2
fi
dir=$1
list=$2
[ -d "$dir" ]  || { echo "not a directory: $dir" >&2; exit 2; }
[ -f "$list" ] || { echo "no such file: $list" >&2; exit 2; }

wanted=0
missing=0
while IFS= read -r line || [ -n "$line" ]; do
  name=${line%%#*}
  name=$(printf '%s' "$name" | tr -d '[:space:]')
  [ -n "$name" ] || continue
  wanted=$((wanted + 1))
  if [ ! -f "$dir/$name.kvwal" ]; then
    printf '%s\n' "$name"
    missing=$((missing + 1))
  fi
done < "$list"

# An empty list would wave every package through.
[ "$wanted" -gt 0 ] || { echo "no store names in $list" >&2; exit 2; }
[ "$missing" -eq 0 ]
