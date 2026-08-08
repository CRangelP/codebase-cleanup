#!/usr/bin/env bash
# Coherence tests for the skill's documentation: the claims that live in more
# than one file at once. A doc drift that used to be caught by reading — a
# rollback command typed slightly differently, an exit code the READMEs never
# heard of, a script missing from the file tree — fails here instead.
# Read-only: it opens the repository's files and never writes, stages or runs
# anything in it.
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
# run the gate also has to tell them to stage first.
PROTOCOL_FILES="SKILL.md references/phase-2-consolidation.md \
references/phase-3-structure.md"

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

# repo_files — every file of the repo except .git and this suite. The suite
# quotes the very strings it forbids, so scanning itself would fail on purpose.
repo_files() {
  find . -type f -not -path './.git/*' -not -path "./$SELF" | sort
}

# count_matches <pattern> — occurrences (not lines) across repo_files
count_matches() {
  local n
  n=$(repo_files | xargs grep -o -F -- "$1" 2>/dev/null | wc -l)
  printf '%s' "$((n))"
}

# tree_scripts <readme> — the *.sh names listed in the README's file tree
tree_scripts() {
  awk '
    /^codebase-cleanup\/$/ { inblock = 1; next }
    inblock && /^```/ { inblock = 0 }
    inblock { print }
  ' "$1" | grep -oE '[A-Za-z0-9_.-]+\.sh' | sort -u
}

# gate_exit_codes — the exit literals in the *bash body* of gate.sh: comments
# and single-quoted strings (the embedded perl watchdog has its own 124/127)
# are stripped first, so only what the gate can really return is left.
gate_exit_codes() {
  local q
  q=$(printf '\047')
  sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' scripts/gate.sh |
  awk -v q="$q" '
    {
      n = split($0, a, q) - 1
      if (insq) {
        if (n % 2 == 0) next          # still inside the quoted string
        insq = 0
        line = a[2]
        for (i = 3; i <= n + 1; i++) line = line q a[i]
        print line
        next
      }
      if (n % 2 == 1) {               # opens a string that stays open
        insq = 1
        line = a[1]
        for (i = 2; i <= n; i++) line = line q a[i]
        print line
        next
      }
      print
    }
  ' | grep -oE '(^|[^A-Za-z0-9_])exit[[:space:]]+[0-9]+' |
  grep -oE '[0-9]+$' | sort -u
}

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
  hits=$(repo_files | xargs grep -l -F -- "$dead" 2>/dev/null)
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
DEAD

# The exception: phase-3-structure.md explains why a "pure git mv" commit is
# not enough. Anywhere else the phrase would be the old, wrong instruction.
GITMV='pure `git mv`'
hits=$(repo_files | xargs grep -l -F -- "$GITMV" 2>/dev/null |
       grep -v '^\./references/phase-3-structure\.md$')
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
for f in $PROTOCOL_FILES; do
  if ! grep -q -F -- 'scripts/gate.sh' "$f" 2>/dev/null; then
    fail "gate step pairs with git add -A in $f" "no longer mentions scripts/gate.sh"
  elif grep -q -F -- 'git add -A' "$f" 2>/dev/null; then
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

echo "----"
echo "$((total-failures))/$total invariants held"
[[ $failures -eq 0 ]]
