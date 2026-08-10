#!/usr/bin/env bash
# mutation_test.sh — the acceptance criterion of "every rule that decides
# destructive authority is an invariant that bites", made executable.
#
# The other five suites answer "does the code do what it says". This one answers
# a question they cannot: "would the suite notice if the rule were removed?" An
# invariant that cannot fail is worse than no invariant, because it buys
# confidence without giving a guarantee — and four of the five regressions below
# were, at the time this file was written, silently green.
#
# Each mutation is a real edit an author could plausibly make, not a scrambled
# byte: it reads like an improvement and quietly widens what the skill is
# allowed to destroy. Every one of them must make coherence_test.sh FAIL.
#
# Runs on a throwaway copy. Nothing here touches the working tree.
# Usage: mutation_test.sh   (exit 0 = every mutation is caught)
set -u

cd "$(dirname "$0")/.." || exit 2
SRC=$PWD
undetected=0

# perl, not sed: these edits span a full table row and the BSD and GNU dialects
# of sed disagree about in-place editing, which would make this suite pass or
# fail by platform rather than by behavior. perl is already a dependency of the
# repo's own tooling checks.
apply() {
  case $1 in
    M1) perl -0pi -e 's/\| A partial net, or no test file in the stack \| \*\*YELLOW\*\* \| [^|]*\|/| A partial net, or no test file in the stack | **YELLOW** | Runs phase 1 (deps, orphan files and exports). Also runs phase 2 and phase 3; reports and continues. |/' SKILL.md ;;
    M2) perl -ni -e 'print unless /Stack caps in .references\/other-stacks\.md. override the GREEN column/' SKILL.md ;;
    M3) perl -0pi -e 's/the skill \*\*aborts\*\* the pipeline when a command of the protocol is blocked/the skill retries the command when it is blocked/' README.en.md ;;
    M4) perl -0pi -e 's/(`git add -- <paths this step produced or edited>`)/$1, or `git add -A` when that is quicker,/' SKILL.md ;;
    M5) perl -0pi -e 's/npx knip\@6\.32\.0 --cycles/npx knip --cycles/' references/phase-2-consolidation.md ;;
  esac
}

desc() {
  case $1 in
    M1) echo "YELLOW's behavior cell authorizes exports and phases 2 and 3" ;;
    M2) echo "the stack-cap override disappears from SKILL.md" ;;
    M3) echo "a rollback blocked by a hook retries instead of aborting" ;;
    M4) echo "a live 'git add -A' offered beside the correct form" ;;
    M5) echo "npx without a pinned version" ;;
  esac
}

# expect <id> — the check whose FAILED line this mutation has to produce.
# A red exit is evidence only when its cause is attributed: without this, any
# unrelated breakage in the copy reads as a catch. Measured, not guessed — each
# string is the name coherence_test.sh prints when the mutation is applied.
expect() {
  case $1 in
    M1) echo "YELLOW does not authorize deleting exports" ;;
    M2) echo "the stack-cap override is stated in every file carrying the level table" ;;
    M3) echo "a blocked rollback still has an abort branch" ;;
    M4) echo "no live 'git add -A' or 'git add .' anywhere in the docs" ;;
    M5) echo "every npx in the docs pins a version" ;;
  esac
}

# copy_repo <dir> — a throwaway copy of the working tree, without .git.
copy_repo() {
  cp -R "$SRC/." "$1/" 2>/dev/null
  rm -rf "$1/.git"
}

MUTATIONS="M1 M2 M3 M4 M5"
total=0
for m in $MUTATIONS; do total=$((total + 1)); done

# The control run. Every result below reads a non-zero exit as "the suite
# noticed", so the suite has to be green on an UNMUTATED copy first — otherwise
# a repo already red for an unrelated reason reports every mutation as caught,
# which is precisely the false confidence this file exists to remove. Measured:
# with the version in plugin.json broken and nothing else touched, the old
# version of this suite printed "5/5 mutations caught" and exited 0.
CTL=$(mktemp -d)
ctl_log=$(mktemp)
copy_repo "$CTL"
if ( cd "$CTL" && "${BASH:-bash}" scripts/coherence_test.sh >"$ctl_log" 2>&1 ); then
  echo "control the unmutated copy is green — a red below is attributable"
else
  echo "CONTROL the unmutated copy is ALREADY RED; no result below would mean anything"
  grep '^FAILED' "$ctl_log" | sed 's/^/        /'
  rm -rf "$CTL"; rm -f "$ctl_log"
  exit 1
fi
rm -rf "$CTL"; rm -f "$ctl_log"

for m in $MUTATIONS; do
  W=$(mktemp -d)
  copy_repo "$W"

  # A mutation that no longer edits anything would report "caught" forever,
  # which is the same false confidence this suite exists to remove. If the text
  # it targets was reworded, this fails loudly instead of going quiet.
  before=$(cd "$W" && cat SKILL.md README.en.md references/phase-2-consolidation.md | cksum)
  ( cd "$W" && apply "$m" )
  after=$(cd "$W" && cat SKILL.md README.en.md references/phase-2-consolidation.md | cksum)
  if [[ $before == "$after" ]]; then
    echo "STALE   $m — the mutation changed nothing; its target text was reworded"
    undetected=$((undetected + 1)); rm -rf "$W"; continue
  fi

  out=$(cd "$W" && "${BASH:-bash}" scripts/coherence_test.sh 2>&1)
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "MISSED  $m — $(desc "$m")"
    undetected=$((undetected + 1))
  elif ! printf '%s\n' "$out" | grep -qF -- "FAILED: $(expect "$m")"; then
    # Red, but somewhere else: the invariant that owns this rule stayed silent
    # and another check took the blame. Counting this as a catch is how a suite
    # keeps its number while losing the guarantee behind it.
    echo "MISATTR $m — suite went red, but not at [$(expect "$m")]"
    printf '%s\n' "$out" | grep '^FAILED' | sed 's/^/        /'
    undetected=$((undetected + 1))
  else
    echo "caught  $m — $(desc "$m")"
  fi
  rm -rf "$W"
done

echo "----"
if [[ $undetected -eq 0 ]]; then
  echo "$total/$total mutations caught"
else
  echo "$undetected of $total slipped through"
fi
[[ $undetected -eq 0 ]]
