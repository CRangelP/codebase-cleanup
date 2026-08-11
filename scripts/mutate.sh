#!/usr/bin/env bash
# mutate.sh — applies a mutation and proves it applied.
#
# The suites in this repo prove things by breaking them on purpose. `mutation_test.sh`
# does that with fourteen scripted edits and guards each one with a checksum: an edit
# whose target text was reworded changes nothing, the suite stays green, and it reports
# "caught" forever for a rule nobody is protecting anymore. That guard exists since #37.
#
# Everything OUTSIDE that file was unguarded, and that is where the expensive mutations
# live. Proving that an eval case bites means editing the installed copy of SKILL.md and
# running the model against it — minutes and paid quota per attempt — and the failure mode
# is silent in the worst possible direction: a mutation that does not apply runs the model
# against the ORIGINAL text, comes back green, and reads as "the case does not bite" when
# nothing was ever mutated.
#
# It is not hypothetical. Writing the invariant for #85, the first verification mutation
# was stale: the perl expression did not match, the file did not change, and the suite
# answered `465/465 invariants held` — one step away from being read as "the invariant I
# just wrote does not fail". It only surfaced because the checksum was compared by hand.
# Twelve more ad-hoc mutations went through the #69 work verified the same way: by habit,
# not by mechanism. Habit is what this file replaces.
#
# Reporting WHAT changed matters as much as reporting THAT something changed: a greedy
# expression that swallows half the file also moves the checksum, and the red it produces
# is not the red anyone wanted.
#
# Usage:
#   scripts/mutate.sh <file> '<perl -0pi expression>'   apply, verify, report
#   scripts/mutate.sh --self-check                      run the floors below
#
# Exit: 0 applied · 1 STALE (nothing changed) · 2 bad usage
set -uo pipefail

say() { printf '%s\n' "$*"; }

apply_mutation() { # <file> <perl expr>
  local file=$1 expr=$2 before after keep rc
  [[ -f $file ]] || { say "mutate: no such file: $file" >&2; return 2; }

  keep=$(mktemp) || return 2
  cp "$file" "$keep"
  before=$(cksum < "$file")

  perl -0pi -e "$expr" "$file"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    say "mutate: perl failed (exit $rc) on $file" >&2
    cp "$keep" "$file"; rm -f "$keep"; return 2
  fi

  after=$(cksum < "$file")
  if [[ $before == "$after" ]]; then
    say "STALE   $file is byte-identical after the edit — the expression matched nothing"
    say "        expr: $expr"
    say "        A run against this copy would exercise the ORIGINAL text, and its green"
    say "        would read as evidence about a mutation that never happened."
    rm -f "$keep"
    return 1
  fi

  # What changed, not only that something did. The line counts come first because
  # they are the number a greedy expression makes absurd, and the body is bounded
  # so a huge diff cannot scroll the counts off the screen.
  local removed added
  removed=$(diff "$keep" "$file" | grep -c '^<')
  added=$(diff "$keep" "$file" | grep -c '^>')
  say "mutated $file — $removed line(s) removed, $added added"
  diff -u "$keep" "$file" | sed -n '3,23p' | sed 's/^/        /'
  [[ $(diff -u "$keep" "$file" | wc -l) -gt 23 ]] && say "        ... (diff truncated)"
  rm -f "$keep"
  return 0
}

# ---------------------------------------------------------------------------
# Floors. Synthetic, free, and run before mutation_test.sh does anything, because
# a guard that does not bite is worse than no guard: it moves the trust without
# moving the protection.
self_check() {
  local t pass=0 fail=0 f out rc
  t=$(mktemp -d)
  ok()  { pass=$((pass+1)); say "ok:     $1"; }
  bad() { fail=$((fail+1)); say "FAILED: $1"; say "        $2"; }

  f="$t/subject.txt"
  printf 'alpha\nbeta\ngamma\n' > "$f"

  # 1. An expression that matches nothing must abort, not pass quietly.
  out=$(apply_mutation "$f" 's/nonexistent-token/x/'); rc=$?
  if [[ $rc -eq 1 ]] && printf '%s' "$out" | grep -q '^STALE'; then
    ok "floor: an expression that matches nothing reports STALE and exits 1"
  else
    bad "floor: an expression that matches nothing reports STALE and exits 1" "rc=$rc, output was [$out]"
  fi

  # 2. And it must leave the file alone, so the caller can retry on the same copy.
  if [[ $(cat "$f") == "$(printf 'alpha\nbeta\ngamma')" ]]; then
    ok "floor: a stale mutation leaves the file untouched"
  else
    bad "floor: a stale mutation leaves the file untouched" "the file changed on a mutation that reported STALE"
  fi

  # 3. A real edit applies and exits 0.
  out=$(apply_mutation "$f" 's/beta/BETA/'); rc=$?
  if [[ $rc -eq 0 ]] && grep -q BETA "$f"; then
    ok "floor: a matching expression applies and exits 0"
  else
    bad "floor: a matching expression applies and exits 0" "rc=$rc, file is [$(cat "$f")]"
  fi

  # 4. The report names the size of the change. One line in, one line out.
  if printf '%s' "$out" | grep -q '1 line(s) removed, 1 added'; then
    ok "floor: the report counts the lines a one-line edit moved"
  else
    bad "floor: the report counts the lines a one-line edit moved" "got [$out]"
  fi

  # 5. A greedy expression is visible in the counts. This is the half that
  #    distinguishes "it changed" from "it changed what I meant": the checksum
  #    moves for both, and only the count tells them apart.
  printf 'one\ntwo\nthree\nfour\nfive\n' > "$f"
  out=$(apply_mutation "$f" 's/^.*$/gone/s'); rc=$?
  if [[ $rc -eq 0 ]] && printf '%s' "$out" | grep -q '5 line(s) removed'; then
    ok "floor: a greedy expression shows up as five lines removed, not as success"
  else
    bad "floor: a greedy expression shows up as five lines removed, not as success" "rc=$rc, got [$out]"
  fi

  # 6. Bad usage is its own exit code: a missing file is not a stale mutation,
  #    and a caller that treats them alike retries an edit on a path that does
  #    not exist.
  out=$(apply_mutation "$t/absent.txt" 's/a/b/' 2>&1); rc=$?
  if [[ $rc -eq 2 ]]; then
    ok "floor: a missing file exits 2, not 1"
  else
    bad "floor: a missing file exits 2, not 1" "rc=$rc, got [$out]"
  fi

  rm -rf "$t"
  say "----"
  say "$pass/$((pass+fail)) mutate.sh floors passed"
  [[ $fail -eq 0 ]]
}

case ${1:-} in
  --self-check) self_check ;;
  "" ) say "usage: mutate.sh <file> '<perl expr>' | mutate.sh --self-check" >&2; exit 2 ;;
  * )
    [[ $# -eq 2 ]] || { say "usage: mutate.sh <file> '<perl expr>'" >&2; exit 2; }
    apply_mutation "$1" "$2"
    ;;
esac
