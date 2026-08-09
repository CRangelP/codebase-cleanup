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

for m in M1 M2 M3 M4 M5; do
  W=$(mktemp -d)
  cp -R "$SRC/." "$W/" 2>/dev/null
  rm -rf "$W/.git"

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

  if ( cd "$W" && "${BASH:-bash}" scripts/coherence_test.sh >/dev/null 2>&1 ); then
    echo "MISSED  $m — $(desc "$m")"
    undetected=$((undetected + 1))
  else
    echo "caught  $m — $(desc "$m")"
  fi
  rm -rf "$W"
done

echo "----"
if [[ $undetected -eq 0 ]]; then
  echo "5/5 mutations caught"
else
  echo "$undetected of 5 slipped through"
fi
[[ $undetected -eq 0 ]]
