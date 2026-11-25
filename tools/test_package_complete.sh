#!/usr/bin/env bash
# Tests for tools/package_complete.sh and prophecy/required_stores.txt.
# Runs without aiml: plain bash, no training.
set -u
cd "$(dirname "$0")/.."

check=tools/package_complete.sh
list=prophecy/required_stores.txt
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

names() { sed 's/#.*//' "$list" | tr -d '[:blank:]' | grep -v '^$'; }

# 1 A full package passes and prints nothing.
mkdir "$tmp/full"
for n in $(names); do : > "$tmp/full/$n.kvwal"; done
out=$("$check" "$tmp/full" "$list"); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && pass "complete package -> 0" || fail "complete package: rc=$rc out=$out"

# 2 Extra stores do not matter.
cp -r "$tmp/full" "$tmp/extra"; : > "$tmp/extra/prophecy_kampf_transformer.kvwal"
"$check" "$tmp/extra" "$list" >/dev/null && pass "extra store -> 0" || fail "extra store"

# 3 One head missing: exit 1, and exactly that store is named.
cp -r "$tmp/full" "$tmp/half"; rm "$tmp/half/prophecy_world_entity_et_body.kvwal"
out=$("$check" "$tmp/half" "$list"); rc=$?
[ "$rc" = 1 ] && [ "$out" = prophecy_world_entity_et_body ] && pass "one store missing -> 1, named" \
  || fail "one store missing: rc=$rc out=$out"

# 4 A run that only did steps 1+2 (no heads, transformer, chance head).
mkdir "$tmp/early"
for n in prophecy_atlas prophecy_vocab prophecy_embedding_weights; do : > "$tmp/early/$n.kvwal"; done
out=$("$check" "$tmp/early" "$list"); rc=$?
want=$(( $(names | wc -l) - 3 ))
[ "$rc" = 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" = "$want" ] && pass "steps 1-2 only -> 1, $want missing" \
  || fail "steps 1-2 only: rc=$rc"

# 5 Empty store directory.
mkdir "$tmp/empty"
"$check" "$tmp/empty" "$list" >/dev/null; rc=$?
[ "$rc" = 1 ] && pass "empty dir -> 1" || fail "empty dir: rc=$rc"

# 6 A directory (not a file) with the store name does not count.
cp -r "$tmp/full" "$tmp/dir"; rm "$tmp/dir/prophecy_chance_head.kvwal"; mkdir "$tmp/dir/prophecy_chance_head.kvwal"
out=$("$check" "$tmp/dir" "$list"); rc=$?
[ "$rc" = 1 ] && [ "$out" = prophecy_chance_head ] && pass "directory instead of file -> 1" || fail "directory: rc=$rc out=$out"

# 7 Comments, blank lines, trailing spaces, no final newline.
printf '# c\n\n  prophecy_atlas  # trailing\nprophecy_vocab' > "$tmp/list.txt"
mkdir "$tmp/two"; : > "$tmp/two/prophecy_atlas.kvwal"; : > "$tmp/two/prophecy_vocab.kvwal"
"$check" "$tmp/two" "$tmp/list.txt" >/dev/null && pass "list parsing" || fail "list parsing"
rm "$tmp/two/prophecy_vocab.kvwal"
out=$("$check" "$tmp/two" "$tmp/list.txt"); rc=$?
[ "$rc" = 1 ] && [ "$out" = prophecy_vocab ] && pass "last line without newline is read" || fail "last line: rc=$rc out=$out"

# 8 Bad calls exit 2, and an empty list is a bad call, not a pass.
"$check" >/dev/null 2>&1; [ $? = 2 ] && pass "no args -> 2" || fail "no args"
"$check" "$tmp/nope" "$list" >/dev/null 2>&1; [ $? = 2 ] && pass "missing dir -> 2" || fail "missing dir"
printf '# nothing\n' > "$tmp/none.txt"
"$check" "$tmp/full" "$tmp/none.txt" >/dev/null 2>&1; [ $? = 2 ] && pass "empty list -> 2" || fail "empty list"

# 9 Drift: every required store is still written under prophecy/sources.
for n in $(names); do
  grep -rqF "\"$n\"" prophecy/sources || fail "store '$n' not found in prophecy/sources"
done
pass "every required store appears in prophecy/sources"

# 10 No duplicates in the list.
dups=$(names | sort | uniq -d)
[ -z "$dups" ] && pass "no duplicate names" || fail "duplicates: $dups"

# 11 training.yml uses the check and makes latest depend on it.
wf=.github/workflows/training.yml
grep -q 'tools/package_complete.sh aiondb prophecy/required_stores.txt' "$wf" && pass "training.yml calls the check" \
  || fail "training.yml does not call the check"
grep -q '\[ "\$complete" = "true" \]' "$wf" && pass "latest depends on completeness" \
  || fail "latest does not depend on completeness"

echo
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
