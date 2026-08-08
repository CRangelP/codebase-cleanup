#!/usr/bin/env bash
# Coherence tests for the skill's documentation: the claims that live in more
# than one file at once. A doc drift that used to be caught by reading — a
# rollback command typed slightly differently, an exit code the READMEs never
# heard of, a script missing from the file tree — fails here instead.
# Read-only over the repository: it opens the repo's files and never writes,
# stages or runs anything inside it. Its self-tests need files to scan, so they
# build them in a mktemp -d of their own and delete it on the way out.
# Usage: coherence_test.sh   (exit 0 = every invariant held)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="scripts/coherence_test.sh"
cd "$ROOT" || { echo "cannot enter $ROOT" >&2; exit 2; }

failures=0
total=0

# The canonical rollback command. Every mention in the repo has to be this
# string, byte for byte — a variant is a different protocol.
ROLLBACK='git restore --staged --worktree .'

# Files that carry the rollback protocol.
ROLLBACK_FILES="SKILL.md README.md README.en.md \
references/phase-2-consolidation.md references/phase-3-structure.md \
scripts/rollback_test.sh"

# Files that spell out the protocol step by step: whoever tells the reader to
# run the gate also has to tell them to stage first. Derived, not listed — a
# new reference that starts calling the gate has to answer for it too, and a
# hand-kept list would silently leave it out. The READMEs are excluded on
# purpose: they present the skill, they do not walk the reader through it.
protocol_files() {
  grep -l -F -- 'scripts/gate.sh' SKILL.md references/*.md 2>/dev/null | sort
}

pass() { total=$((total+1)); echo "ok: $1"; }

fail() { # fail <name> <detail>
  total=$((total+1))
  failures=$((failures+1))
  echo "FAILED: $1"
  printf '%s\n' "$2" | sed 's/^/    /'
}

check() { # check <name> <ok:0|1> <detail>
  if [[ $2 -eq 0 ]]; then pass "$1"; else fail "$1" "$3"; fi
}

# repo_files [root] — every file under <root> (default: the repo) except .git
# and this suite, NUL-separated. The suite quotes the very strings it forbids,
# so scanning itself would fail on purpose. The root is a parameter so the
# self-tests below can point the scanner at a throwaway directory.
# NUL keeps names with spaces intact end to end; a name with a newline in it is
# still out of reach (grep -l prints one path per line) and is not defended.
repo_files() {
  local root=${1:-.}
  find "$root" -type f -not -path "$root/.git/*" -not -path "$root/$SELF" -print0
}

# count_matches <pattern> [root] — occurrences (not lines) across repo_files.
# /dev/null is passed to grep so it never falls back to reading stdin when the
# scan comes up empty.
count_matches() {
  local n
  n=$(repo_files "${2:-.}" | xargs -0 grep -o -F -- "$1" /dev/null 2>/dev/null | wc -l)
  printf '%s' "$((n))"
}

# files_with <string> [root] — the files under <root> that contain the fixed
# string, one per line, sorted (the sort belongs here, not in find: the NUL
# stream must stay in find's order all the way to grep).
files_with() {
  repo_files "${2:-.}" | xargs -0 grep -l -F -- "$1" /dev/null 2>/dev/null | sort
}

# tree_scripts <readme> — the *.sh names listed in the README's file tree
tree_scripts() {
  awk '
    /^codebase-cleanup\/$/ { inblock = 1; next }
    inblock && /^```/ { inblock = 0 }
    inblock { print }
  ' "$1" | grep -oE '[A-Za-z0-9_.-]+\.sh' | sort -u
}

# bash_body — reads a shell script on stdin and prints its bash body with
# quoted text and comments removed. One character-by-character pass does both,
# because doing them in two passes is wrong: stripping comments first mutilates
# a '# ...' that lives inside a string, and stripping strings first swallows a
# quote (an apostrophe, say) that lives inside a comment. The quoting state
# survives across lines, which is what the embedded multi-line perl watchdog of
# gate.sh needs. Each quoted run collapses to a single space so nothing on
# either side of it gets glued together.
bash_body() {
  local q
  q=$(printf '\047')
  awk -v q="$q" '
    {
      out = ""; prev = ""; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (insq) {                       # nothing escapes inside '\''...'\''
          if (c == q) insq = 0
        } else if (indq) {
          if (c == "\\") i++              # backslash escapes the next char
          else if (c == "\"") indq = 0
        } else {
          if (c == "#" && (i == 1 || prev == " " || prev == "\t")) break
          if (c == q) { insq = 1; out = out " " }
          else if (c == "\"") { indq = 1; out = out " " }
          else out = out c
        }
        prev = c
      }
      print out
    }
  '
}

# exit_codes — the exit literals in the *bash body* read from stdin, so only
# what the script can really return is left (the perl watchdog's own 124/127
# live inside a quoted string and do not count).
exit_codes() {
  bash_body |
  grep -oE '(^|[^A-Za-z0-9_])exit[[:space:]]+[0-9]+' |
  grep -oE '[0-9]+$' | sort -u
}

gate_exit_codes() { exit_codes < scripts/gate.sh; }

# 0. The suite's own scanners work. ------------------------------------------
# Every invariant below is only as trustworthy as the extractor that feeds it,
# so the extractor is exercised here on a synthetic script — a heredoc, never
# a file on disk — whose single real exit is 7.
got=$(exit_codes <<'SYNTH'
X="exit 99"
Y='exit 98'
# exit 97
echo hi # exit 96
exit 7
Z='first line
second # exit 95
exit 94'
SYNTH
)
check "exit-code extractor sees past quotes and comments" \
      "$([[ $got == 7 ]] && echo 0 || echo 1)" \
      "extracted [$(printf '%s' "$got" | tr '\n' ' ')], expected [7]"

# The file scanner has to reach a file whose name has a space in it, or a dead
# string could hide in one. Exercised on a throwaway tree, never in the repo.
SELFTMP=$(mktemp -d)
trap 'rm -rf "$SELFTMP"' EXIT
printf '%s\n' '--isolate-workspaces' > "$SELFTMP/a b.txt"
got=$(files_with '--isolate-workspaces' "$SELFTMP")
check "file scanner reads a file name with a space" \
      "$([[ $got == "$SELFTMP/a b.txt" ]] && echo 0 || echo 1)" \
      "found [$got], expected [$SELFTMP/a b.txt]"

# 1. The rollback command is one string, in every file that documents it. -----
for f in $ROLLBACK_FILES; do
  if grep -q -F -- "$ROLLBACK" "$f" 2>/dev/null; then
    pass "rollback verbatim in $f"
  else
    fail "rollback verbatim in $f" "missing the canonical form: $ROLLBACK"
  fi
done

# Every invocation has to be the canonical one. Naming the command in prose,
# `git restore` closed right after, is the only other allowed shape.
loose=$(count_matches 'git restore')
prose=$(count_matches 'git restore`')
canon=$(count_matches "$ROLLBACK")
if [[ $((loose-prose)) -eq $canon ]]; then
  pass "no rollback variant in the repo ($canon invocations, $prose mentions)"
else
  fail "no rollback variant in the repo" \
       "$((loose-prose)) invocations of 'git restore', $canon of them canonical"
fi

# 2. The gate's contract is the same in the code and in the docs. -------------
for f in scripts/gate.sh SKILL.md README.md README.en.md; do
  if grep -q -F -- 'GATE_TIMEOUT' "$f" 2>/dev/null; then
    pass "GATE_TIMEOUT documented in $f"
  else
    fail "GATE_TIMEOUT documented in $f" "no mention of the watchdog knob"
  fi
done

for f in README.md README.en.md; do
  if grep -q -F -- 'exit 0/1/2/3/4' "$f" 2>/dev/null; then
    pass "exit contract in the file tree of $f"
  else
    fail "exit contract in the file tree of $f" "the tree does not state exit 0/1/2/3/4"
  fi
done

undocumented=""
for code in $(gate_exit_codes); do
  case $code in
    0|1|2|3|4) ;;
    *) undocumented="$undocumented $code" ;;
  esac
done
check "gate.sh only exits documented codes" \
      "$([[ -z $undocumented ]] && echo 0 || echo 1)" \
      "exit code(s) outside the documented 0/1/2/3/4:$undocumented"

# 3. Strings the docs stopped meaning are gone from the repo. -----------------
# Each one described a protocol that no longer exists; a copy left behind
# contradicts the current one.
while IFS= read -r dead; do
  hits=$(files_with "$dead")
  if [[ -z $hits ]]; then
    pass "dead string absent: $dead"
  else
    fail "dead string absent: $dead" "$hits"
  fi
done <<'DEAD'
--isolate-workspaces
Typecheck at the end of each folder
one mandatory checkpoint
typecheck and tests between each step
only what has not been committed
"(test|typecheck|lint|build)"
Tests exist but fail
DEAD

# The exception: phase-3-structure.md explains why a "pure git mv" commit is
# not enough. Anywhere else the phrase would be the old, wrong instruction.
GITMV='pure `git mv`'
hits=$(files_with "$GITMV" | grep -v '^\./references/phase-3-structure\.md$')
check "\"$GITMV\" only in references/phase-3-structure.md" \
      "$([[ -z $hits ]] && echo 0 || echo 1)" "$hits"

# Inside that file, exactly once: the explanatory paragraph. A second
# occurrence would be the old instruction sneaking back past the file filter.
n=$(grep -c -F -- "$GITMV" references/phase-3-structure.md 2>/dev/null)
check "\"$GITMV\" appears exactly once in references/phase-3-structure.md" \
      "$([[ ${n:-0} -eq 1 ]] && echo 0 || echo 1)" "count=${n:-0}"

# 4. Whoever documents the gate as a step also documents staging. -------------
# The gate reads the working tree, so a protocol that runs it without `git
# add -A` first checks something the commit will not contain.
derived=$(protocol_files)

# Floor: the three files that carry the protocol today have to be in the
# derived list. Without it, a rename or a dropped mention would empty the list
# and the invariant would pass over nothing at all.
for f in SKILL.md references/phase-2-consolidation.md references/phase-3-structure.md; do
  if printf '%s\n' "$derived" | grep -qx -F -- "$f"; then
    pass "$f is derived as a protocol file"
  else
    fail "$f is derived as a protocol file" \
         "no longer mentions scripts/gate.sh — derived list: $(printf '%s' "$derived" | tr '\n' ' ')"
  fi
done

for f in $derived; do
  if grep -q -F -- 'git add -A' "$f" 2>/dev/null; then
    pass "gate step pairs with git add -A in $f"
  else
    fail "gate step pairs with git add -A in $f" \
         "runs the gate as a protocol step without staging first"
  fi
done

# 5. The file trees in the READMEs match what is on disk. --------------------
for readme in README.md README.en.md; do
  listed=$(tree_scripts "$readme")
  for path in scripts/*.sh; do
    name=${path##*/}
    if printf '%s\n' "$listed" | grep -qx -- "$name"; then
      pass "$name listed in the tree of $readme"
    else
      fail "$name listed in the tree of $readme" "on disk but absent from the tree"
    fi
  done
  for name in $listed; do
    if [[ -f scripts/$name ]]; then
      pass "$name of the tree of $readme exists on disk"
    else
      fail "$name of the tree of $readme exists on disk" "listed but there is no scripts/$name"
    fi
  done
done

# 6. Whoever shows a `git mv` also shows the mkdir -p it needs. ---------------
# Phase 3 applies a structure that does not exist yet, so the destination
# directory has to be created before the move: `git mv` into a missing
# directory dies with exit 128, and an agent running unsupervised reads that
# as a failed step. Only command lines count — a line that *starts* with
# `git mv` — so the prose mentions in the READMEs and in the explanatory
# paragraphs, where the phrase is named and not run, stay out of it.
gitmv_files() {
  grep -l -E '^git mv ' SKILL.md references/*.md 2>/dev/null | sort
}

moves=$(gitmv_files)

# Floor, same reason as in section 4: a derivation that comes back without the
# two files that carry the move today is broken, and the loop below would
# assert over an empty list and pass.
for f in SKILL.md references/phase-3-structure.md; do
  if printf '%s\n' "$moves" | grep -qx -F -- "$f"; then
    pass "$f is derived as a file that runs git mv"
  else
    fail "$f is derived as a file that runs git mv" \
         "no git mv command line — derived list: $(printf '%s' "$moves" | tr '\n' ' ')"
  fi
done

# The mkdir has to be on the line right above, not merely somewhere in the
# file: what is being read is a snippet, not a page.
for f in $moves; do
  orphan=$(awk '/^git mv / && prev !~ /^mkdir -p / { print FILENAME ":" FNR ": " $0 }
                { prev = $0 }' "$f")
  check "git mv preceded by mkdir -p in $f" \
        "$([[ -z $orphan ]] && echo 0 || echo 1)" "$orphan"
done

# 7. The level table says the same thing in the three files. -----------------
# The level is the whole dispatch of the skill: SKILL.md's table decides what
# runs, and both READMEs promise the user that same behavior. They drifted once
# — SKILL.md called a failing suite YELLOW and sent it into phase 1, while the
# protocol a few lines below refuses to commit without a green gate, so the
# announced level was one no run could ever honor. README.md is in Portuguese,
# so byte equality across the three is out; what is asserted instead is the part
# that has to hold in any language.
LEVEL_FILES="SKILL.md README.md README.en.md"

# level_names <file> — the level of each row of the file's level table, in
# order. Table rows are the only lines that start with `|`, and the first level
# word on a row is that row's level, whichever column the file puts it in.
level_names() {
  awk '/^\|/ && match($0, /GREEN|YELLOW|RED/) { print substr($0, RSTART, RLENGTH) }' "$1"
}

# Consecutive repeats collapse on purpose: SKILL.md carries a fourth row (no git
# repository, which is RED before the gate even runs) that the READMEs keep as a
# bullet under known limits. That asymmetry is deliberate — the table is what an
# agent dispatches on, the READMEs are prose for a human who already read the
# requirement. What may not differ is which levels exist and how they escalate.
level_shape() {
  level_names "$1" |
  awk 'NR == 1 || $0 != prev { print } { prev = $0 }' |
  tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

for f in $LEVEL_FILES; do
  shape=$(level_shape "$f")
  check "level table of $f reads GREEN YELLOW RED" \
        "$([[ $shape == 'GREEN YELLOW RED' ]] && echo 0 || echo 1)" \
        "levels in order: [$shape]"
done

# The condition that puts a run at YELLOW, in each file's own language, checked
# against the YELLOW row itself and not merely somewhere in the file — the row
# is what gets read at classification time.
yellow_row() { grep -E '^\|' "$1" | grep -F -m1 -- 'YELLOW'; }

for pair in \
  'SKILL.md|partial net, or no test file in the stack' \
  'README.en.md|partial net, or no test file in the stack' \
  'README.md|rede parcial, ou nenhum arquivo de teste no stack'
do
  f=${pair%%|*}
  cond=${pair#*|}
  row=$(yellow_row "$f")
  if printf '%s' "$row" | grep -q -F -- "$cond"; then
    pass "YELLOW row of $f states the canonical condition"
  else
    fail "YELLOW row of $f states the canonical condition" \
         "expected [$cond] — row reads: ${row:-<no YELLOW row>}"
  fi
done

echo "----"
echo "$((total-failures))/$total invariants held"
[[ $failures -eq 0 ]]
