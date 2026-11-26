#!/usr/bin/env bash
# Tests for tools/package_complete.sh and prophecy/required_stores.txt.
# Runs without aiml: plain bash, no training.
set -u
cd "$(dirname "$0")/.." || exit 2

check=tools/package_complete.sh
list=prophecy/required_stores.txt
fails=0

# expect NAME CONDITION...: run the condition, report ok/FAIL under NAME.
expect() {
  local name=$1; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

names() { sed 's/#.*//' "$list" | tr -d '[:blank:]' | grep -v '^$'; }

# run DIR [LIST]: sets $out and $rc from package_complete.sh.
run() {
  rc=0
  out=$("$check" "$1" "${2:-$list}" 2>/dev/null) || rc=$?
}

# 1 A full package passes and prints nothing.
mkdir "$tmp/full"
for n in $(names); do : > "$tmp/full/$n.kvwal"; done
run "$tmp/full"
expect "complete package -> 0, no output" test "$rc" = 0 -a -z "$out"

# 2 Extra stores do not matter.
cp -r "$tmp/full" "$tmp/extra"; : > "$tmp/extra/prophecy_kampf_transformer.kvwal"
run "$tmp/extra"
expect "extra store -> 0" test "$rc" = 0

# 3 One head store missing: exit 1, and exactly that store is named.
cp -r "$tmp/full" "$tmp/half"; rm "$tmp/half/prophecy_world_entity_et_body.kvwal"
run "$tmp/half"
expect "one store missing -> 1" test "$rc" = 1
expect "the missing store is named" test "$out" = prophecy_world_entity_et_body

# 4 A run that only did steps 1+2 (no heads, transformer, chance head).
mkdir "$tmp/early"
for n in prophecy_atlas prophecy_vocab prophecy_embedding_weights; do : > "$tmp/early/$n.kvwal"; done
run "$tmp/early"
want=$(( $(names | wc -l) - 3 ))
expect "steps 1-2 only -> 1" test "$rc" = 1
expect "steps 1-2 only: $want stores named" test "$(printf '%s\n' "$out" | wc -l)" = "$want"

# 5 Empty store directory.
mkdir "$tmp/empty"
run "$tmp/empty"
expect "empty dir -> 1" test "$rc" = 1

# 6 A directory (not a file) with the store's name does not count.
cp -r "$tmp/full" "$tmp/dir"; rm "$tmp/dir/prophecy_chance_head.kvwal"; mkdir "$tmp/dir/prophecy_chance_head.kvwal"
run "$tmp/dir"
expect "directory instead of file -> 1, named" test "$rc" = 1 -a "$out" = prophecy_chance_head

# 7 Comments, blank lines, surrounding spaces, no final newline.
printf '# c\n\n  prophecy_atlas  # trailing\nprophecy_vocab' > "$tmp/list.txt"
mkdir "$tmp/two"; : > "$tmp/two/prophecy_atlas.kvwal"; : > "$tmp/two/prophecy_vocab.kvwal"
run "$tmp/two" "$tmp/list.txt"
expect "list parsing -> 0" test "$rc" = 0
rm "$tmp/two/prophecy_vocab.kvwal"
run "$tmp/two" "$tmp/list.txt"
expect "last line without newline is read" test "$rc" = 1 -a "$out" = prophecy_vocab

# 8 Bad calls exit 2; an empty list is a bad call, not a pass.
rc=0; "$check" >/dev/null 2>&1 || rc=$?
expect "no args -> 2" test "$rc" = 2
run "$tmp/nope"
expect "missing dir -> 2" test "$rc" = 2
printf '# nothing\n' > "$tmp/none.txt"
run "$tmp/full" "$tmp/none.txt"
expect "empty list -> 2" test "$rc" = 2

# 9 Drift: every required store is still named under prophecy/sources.
for n in $(names); do
  expect "store $n appears in prophecy/sources" grep -rqF "\"$n\"" prophecy/sources
done

# 10 No duplicates in the list.
expect "no duplicate names" test -z "$(names | sort | uniq -d)"

# 11 training.yml uses the check and makes latest depend on it.
wf=.github/workflows/training.yml
expect "training.yml calls the check" \
  grep -qF 'tools/package_complete.sh aiondb prophecy/required_stores.txt' "$wf"
# shellcheck disable=SC2016  # the literal text of the workflow line
expect "latest depends on completeness" grep -qF '[ "$complete" = "true" ]' "$wf"

echo
if [ "$fails" = 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
