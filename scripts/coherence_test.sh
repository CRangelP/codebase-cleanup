#!/usr/bin/env bash
# Coherence tests for the skill's documentation: the claims that live in more
# than one file at once. A doc drift that used to be caught by reading — a
# rollback command typed slightly differently, an exit code the READMEs never
# heard of, a script missing from the file tree — fails here instead.
# Read-only over the repository: it opens the repo's files and never writes or
# stages inside it. Section 9 runs gate_test.sh only to read the NN/NN it prints
# (that suite uses its own stubs/tempdirs). Its self-tests need files to scan,
# so they build them in a mktemp -d of their own and delete it on the way out.
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

# reflow <file> — the file as one line, so a phrase that a hard wrap split in
# two still reads as a phrase. Both READMEs are wrapped by hand at ~80 columns,
# so an invariant that greps a sentence line by line is really asserting where
# the wrap happens to fall, and would go red on a rewrap that changed nothing.
reflow() { tr '\n' ' ' < "$1" | tr -s ' '; }

# paragraph_with <file> <needle> — the blank-line-delimited paragraph holding
# <needle>, as one line; nothing when there is none. Asserting a token inside
# the paragraph that states a rule is a different claim from asserting it
# somewhere in the file: the second is satisfied by any other mention, and the
# READMEs repeat these tokens in their known-limits sections. The needle is a
# literal (index, not match), so a token with regex punctuation still works.
paragraph_with() {
  awk -v needle="$2" '
    # buf is cleared before exit: END runs after exit too, and would print the
    # same paragraph a second time.
    /^[[:space:]]*$/ { if (index(buf, needle)) { print buf; buf = ""; exit } buf = ""; next }
    # Leading indentation is dropped before joining: these files are wrapped by
    # hand and a continuation line carries the indent of its list marker, so a
    # phrase split across two lines would come back with a run of spaces in the
    # middle, and no literal search would ever find it. (No apostrophes in here:
    # this awk program is a single-quoted shell string.)
    { line = $0; sub(/^[[:space:]]+/, "", line); buf = buf line " " }
    END { if (index(buf, needle)) print buf }
  ' "$1"
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

# tree_block <readme> — the fenced file-tree body (between codebase-cleanup/ and
# the closing fence). Shared by the script-name and doc-name extractors so a
# tree edited in one place cannot be read two different ways.
tree_block() {
  awk '
    /^codebase-cleanup\/$/ { inblock = 1; next }
    inblock && /^```/ { inblock = 0 }
    inblock { print }
  ' "$1"
}

# tree_scripts <readme> — the *.sh names listed in the README's file tree
tree_scripts() {
  tree_block "$1" | grep -oE '[A-Za-z0-9_.-]+\.sh' | sort -u
}

# tree_docs <readme> — SKILL.md, LICENSE, README*.md and references/*.md names
# listed in the tree. Same shape as tree_scripts: the tree is the contract for
# what the skill ships, not only for the scripts.
tree_docs() {
  tree_block "$1" | grep -oE '([A-Za-z0-9_.-]+\.md|LICENSE)' | sort -u
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

# Every invocation of the gate in the protocol resolves through the plugin
# root. Installed as a plugin the skill is copied into a cache directory whose
# path nobody can guess, and a bare `scripts/gate.sh` would then be read as
# relative to the *project* being cleaned, where it does not exist — the run
# would lose the one script that decides its level. The `:-.` keeps the plain
# skill install working, so the canonical form is the whole form, braces and
# fallback included. The READMEs are exempt on purpose: there the path names
# the file on disk (a file tree, a requirements list), it is not a step anyone
# runs.
GATE_CALL='"${CLAUDE_PLUGIN_ROOT:-.}/scripts/gate.sh"'
for f in SKILL.md references/*.md; do
  [[ -f $f ]] || continue
  loose=$(grep -o -F -- 'scripts/gate.sh' "$f" 2>/dev/null | wc -l)
  canon=$(grep -o -F -- "$GATE_CALL" "$f" 2>/dev/null | wc -l)
  check "the gate is called through the plugin root in $f" \
        "$([[ $((loose)) -eq $((canon)) ]] && echo 0 || echo 1)" \
        "$((loose)) mentions of scripts/gate.sh, $((canon)) of them canonical
the canonical form is $GATE_CALL"
done

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
# The gate reads the working tree, so a protocol that runs it without staging
# first checks something the commit will not contain. Staging is pathspec-only
# (`git add -- <paths…>`): blind `git add -A` / `git add .` would swallow
# unrelated untracked files into the category commit. Prose that says "never
# git add -A" still contains that substring, so the invariant keys on the
# positive form `git add --`, not on the forbidden spellings.
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

# IFS is pinned to newline for the same reason section 6 pins it: the list comes
# from grep -l, and under the default IFS a path containing a space would split
# into fragments, leaving grep to fail on stderr while the invariant reports a
# verdict for a file it never opened.
old_ifs=$IFS
IFS=$'\n'
for f in $derived; do
  # Require the pathspec form `git add -- <…>` (space after --). A bare
  # `git add --` substring would also match `git add --all` (≡ `git add -A`).
  # The test stays on the *positive* form, as the reasoning above demands: prose
  # that forbids a spelling still contains it, so keying on `git add -- .` as a
  # forbidden substring would fail a file whose only sin is documenting the ban.
  # Instead, collect the pathspecs actually written and ask whether any of them
  # names something narrower than the whole tree — `.` and `./` do not, they are
  # `git add .` wearing pathspec syntax, while `./src`, `.env` and `..` do.
  specs=$(grep -oE -- 'git add --[[:space:]]+[^[:space:]`"'"'"']+' "$f" 2>/dev/null \
          | sed -E 's/^git add --[[:space:]]+//')
  if [[ -n $specs ]] && printf '%s\n' "$specs" | grep -qvxE '\.|\./'; then
    pass "gate step pairs with pathspec staging in $f"
  elif [[ -n $specs ]]; then
    fail "gate step pairs with pathspec staging in $f" \
         "every \`git add --\` pathspec is \`.\` or \`./\`, which is \`git add .\` in disguise"
  else
    fail "gate step pairs with pathspec staging in $f" \
         "runs the gate as a protocol step without \`git add --\` pathspecs first"
  fi
done
IFS=$old_ifs

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

  # Same bidirectional contract for the docs the tree claims to ship: SKILL.md,
  # LICENSE, and every references/*.md. A script-only check let a reference
  # disappear from the tree (or land on disk unlisted) without a failure.
  docs=$(tree_docs "$readme")
  for required in SKILL.md LICENSE; do
    if printf '%s\n' "$docs" | grep -qx -F -- "$required"; then
      pass "$required listed in the tree of $readme"
    else
      fail "$required listed in the tree of $readme" "absent from the tree"
    fi
    if [[ -f $required ]]; then
      pass "$required of the tree of $readme exists on disk"
    else
      fail "$required of the tree of $readme exists on disk" "listed but missing on disk"
    fi
  done
  # references/, agents/ and docs/ get the same treatment: all three ship inside
  # the plugin and a file missing from the tree is a file the reader does not
  # know is there. They are not the same kind of file, though, and the tree is
  # where that shows: references/ is opened by name during a run and competes for
  # the model's reading budget, agents/ is loaded when a phase is delegated, and
  # docs/ is working material the skill never opens. Keeping research out of
  # references/ is the whole point of having docs/ — a 55 KB study of the plugin
  # spec sitting next to the phase protocols would be one more thing to walk past
  # on every run.
  for path in references/*.md agents/*.md docs/*.md; do
    [[ -f $path ]] || continue
    name=${path##*/}
    dir=${path%%/*}
    if printf '%s\n' "$docs" | grep -qx -F -- "$name"; then
      pass "$dir/$name listed in the tree of $readme"
    else
      fail "$dir/$name listed in the tree of $readme" "on disk but absent from the tree"
    fi
  done
  old_ifs=$IFS
  IFS=$'\n'
  for name in $docs; do
    [[ $name == *.md ]] || continue
    case $name in
      SKILL.md|README.md|README.en.md|CHANGELOG.md)
        if [[ -f $name ]]; then
          pass "$name of the tree of $readme exists on disk"
        else
          fail "$name of the tree of $readme exists on disk" "listed but missing on disk"
        fi
        ;;
      *)
        # A doc in the tree lives in references/, in agents/ or in docs/. Naming
        # the three directories beats accepting any of them silently: a file that
        # is in none is listed and shipped by nobody.
        if [[ -f references/$name ]]; then
          pass "references/$name of the tree of $readme exists on disk"
        elif [[ -f agents/$name ]]; then
          pass "agents/$name of the tree of $readme exists on disk"
        elif [[ -f docs/$name ]]; then
          pass "docs/$name of the tree of $readme exists on disk"
        else
          fail "$name of the tree of $readme exists on disk" \
               "listed but there is no references/$name, agents/$name nor docs/$name"
        fi
        ;;
    esac
  done
  IFS=$old_ifs
done

# 6. Whoever shows a `git mv` also shows the mkdir -p it needs. ---------------
# Phase 3 applies a structure that does not exist yet, so the destination
# directory has to be created before the move: `git mv` into a missing
# directory dies with exit 128, and an agent running unsupervised reads that
# as a failed step. Only command lines count — a line whose first word is
# `git mv` — so the prose mentions, where the phrase is named inside backticks
# and not run, stay out of it. That is the whole filter: the READMEs are
# scanned like everything else, because both already carry fenced bash blocks
# and a move added to one of them would be read and run like any other. Leading
# whitespace is allowed: a move written as a step inside a numbered list is
# still a command, and anchoring at column 0 would exempt it silently.
gitmv_files() {
  grep -l -E '^[[:space:]]*git mv ' SKILL.md README.md README.en.md references/*.md \
    2>/dev/null | sort
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

# The mkdir has to be in the same block as the move, and it has to have created
# the directory that move lands in — not merely some directory. What is being
# read is a snippet, not a page: a fence or a blank line ends the block, so a
# `git mv` in a later snippet cannot inherit an earlier snippet's mkdir. Inside
# a block one `mkdir -p` covers every move into that folder — one mkdir and
# three moves is the shape a real plan has, and demanding a redundant mkdir per
# line would reject correct documentation. Tracking the folders instead of a
# bare "some mkdir happened" flag is what catches the realistic version of the
# bug: a block that creates one destination and then moves into a second one.
# A move with no `/` in the destination is a rename in place and needs no
# directory, so it is never flagged.
# Both readers work on the last argument, not on a fixed field number: `git mv`
# takes flags and takes several sources into one directory, and `dest = $4`
# read the wrong token in either case — a flag shifted the fields, and the
# wrong token usually has no `/`, so the move was quietly exempted instead of
# checked. Trailing comments are cut first (the repo's own example carries one),
# option words are skipped, and surrounding single or double quotes are stripped
# so a quoted path registers under the name the move actually uses. `&&` and `;`
# split a line into commands before either rule runs: a one-liner
# `mkdir -p X && git mv …` used to match only the mkdir rule (and then `next`),
# so the move was never checked and every non-flag token — including `&&` and
# the move's own paths — polluted `made`.
gitmv_orphans() {
  local q
  q=$(printf '\047')
  awk -v q="$q" '
    function args(line,   i, n, out) {   # the words of <line>, comments and flags out
      sub(/[[:space:]]+#.*$/, "", line)
      n = split(line, out, "[[:space:]]+")   # a string, not a /literal/: mawk
      argc = 0
      for (i = 1; i <= n; i++) {
        if (out[i] == "" || out[i] ~ /^-/) continue
        gsub(/"/, "", out[i])
        gsub(q, "", out[i])
        argv[++argc] = out[i]
      }
      return argc
    }
    function split_cmds(line, segs,   tmp) {
      tmp = line
      gsub(/&&/, "\034", tmp)
      gsub(/;/, "\034", tmp)
      return split(tmp, segs, "\034")
    }
    function process(line,   n, i, d, dest) {
      if (line ~ /^[[:space:]]*mkdir -p/) {
        n = args(line)
        for (i = 2; i <= n; i++) {      # argv[1] is "mkdir"
          d = argv[i]; gsub(/\/+$/, "", d); made[d] = 1
        }
      } else if (line ~ /^[[:space:]]*git mv /) {
        n = args(line)
        dest = argv[n]                  # last word, never $4
        if (sub(/\/[^\/]*$/, "", dest) && !(dest in made))
          print FILENAME ":" FNR ": " $0
      }
    }
    /^[[:space:]]*```/       { split("", made); next }
    /^[[:space:]]*$/         { split("", made); next }
    {
      n = split_cmds($0, segs)
      for (i = 1; i <= n; i++) process(segs[i])
    }
  ' "$1"
}

# Section 0's rule: the invariant is only as good as the extractor. A scanner
# that never reports anything would make the loop below pass over everything,
# so it is exercised on a synthetic page first. Every line of the fixture pays
# for itself — delete any one rule of the scanner and the count moves:
# `git mv c` catches the destination check, `git mv e` the fence reset (the
# mkdir above it created the very folder it lands in, so only the fence can
# uncover it), `git mv g` the blank-line reset for the same reason, `git mv d`
# the leading-whitespace tolerance. `git mv h i` renames in place and must stay
# unflagged even though no mkdir names `i`.
# The last block pays for the argument reader and the command splitter:
# `git mv j` is only unflagged if single quotes came off the mkdir;
# `mkdir && git mv p` is only unflagged if `&&` splits before the rules run
# (otherwise the mkdir rule `next`s and the move is never checked);
# `mkdir && git mv r` into a different folder must stay flagged — proof the
# move half of a one-liner is still subject to the destination check;
# `git mv -f k` and the multi-source `git mv l m src/s/` are only flagged if
# the destination is read as the last word — a fixed `$4` reads `k` and `m`,
# neither of which has a `/`, so both uncovered moves would slip through as
# renames in place. `git mv q` is a plain uncovered move in the same block.
printf '%s\n' '```bash' 'mkdir -p src/x' 'git mv a src/x/a' 'git mv b src/x/b' \
              'git mv c src/y/c' '```' 'git mv e src/x/e' \
              '```bash' 'mkdir -p src/y' 'git mv f src/y/f' '' 'git mv g src/y/g' '```' \
              '' '   git mv d gone/d' \
              '```bash' 'mkdir -p src/z' 'git mv h i' '```' \
              '```bash' "mkdir -p 'src/q'" 'git mv j src/q/j' \
              'mkdir -p src/ok && git mv p src/ok/p' \
              'mkdir -p src/other && git mv r src/missing/r' \
              'git mv -f k src/r/k' \
              'git mv l m src/s/' \
              'git mv q src/bad/q' '```' \
              > "$SELFTMP/moves.md"
orphans=$(gitmv_orphans "$SELFTMP/moves.md")
got=$(printf '%s' "$orphans" | grep -c .)
check "git mv scanner flags the uncovered moves and only those" \
      "$([[ $got -eq 8 ]] && echo 0 || echo 1)" \
      "flagged $got line(s), expected 8:
$orphans"

# IFS is pinned to newline: the list comes from grep -l, and the default IFS
# would split a path containing a space into pieces, leaving awk to fail on
# stderr while $orphan stays empty — an "ok" for a file never read.
old_ifs=$IFS
IFS=$'\n'
for f in $moves; do
  orphan=$(gitmv_orphans "$f")
  check "git mv covered by a mkdir -p in $f" \
        "$([[ -z $orphan ]] && echo 0 || echo 1)" "$orphan"
done
IFS=$old_ifs

# 7. The level table says the same thing in the three files. -----------------
# The level is the whole dispatch of the skill: SKILL.md's table decides what
# runs, and both READMEs promise the user that same behavior. They drifted once
# — SKILL.md called a failing suite YELLOW and sent it into phase 1, while the
# protocol a few lines below refuses to commit without a green gate, so the
# announced level was one no run could ever honor. README.md is in Portuguese,
# so byte equality across the three is out; what is asserted instead is the part
# that has to hold in any language.
LEVEL_FILES="SKILL.md README.md README.en.md"

# LEVEL_CELL — a level standing alone in its own cell, bold or not. Both
# extractors below use it, and that is the point: naming a level in a row's
# prose ("not GREEN, a partial net") must not make the row count as that level's
# row for one of them and not the other. It is also what keeps some other table
# from being mistaken for this one — references/other-stacks.md has rows like
# `| Go | deadcode | yes, at GREEN |`, where GREEN is prose inside a cell, not
# the cell.
# Written with bracket expressions rather than backslash escapes: awk's `-v`
# eats one level of backslash before the regex is ever compiled, so `\|` would
# arrive as a bare alternation and the pattern would not compile.
LEVEL_CELL='[|][[:space:]]*[*]*(GREEN|YELLOW|RED)[*]*[[:space:]]*[|]'

# level_rows <file> — the rows of the level table. Anchored to the table, not
# to the file: the first run of consecutive `|` lines carrying a level cell is
# the table, and the run ends at the first line that is not a table row. A
# level word in some other table of the same file (an exit-code table, a
# per-stack table) is then neither counted as a row nor picked up as one.
level_rows() {
  awk -v cell="$LEVEL_CELL" '
    /^\|/ && $0 ~ cell { intable = 1; print; next }
    intable && !/^\|/ { exit }
  ' "$1"
}

# Consecutive repeats collapse on purpose: SKILL.md carries a fourth row (no git
# repository, which is RED before the gate even runs) that the READMEs keep as a
# bullet under known limits. That asymmetry is deliberate — the table is what an
# agent dispatches on, the READMEs are prose for a human who already read the
# requirement. What may not differ is which levels exist and how they escalate.
level_shape() {
  level_rows "$1" |
  awk -v cell="$LEVEL_CELL" 'match($0, cell) {
         l = substr($0, RSTART, RLENGTH)
         match(l, /GREEN|YELLOW|RED/)
         l = substr(l, RSTART, RLENGTH)
         if (l != prev) { out = out sep l; sep = " " }
         prev = l
       } END { print out }'
}

# Same rule as section 0, and both halves have to be paid for. The trailing
# GREEN outside the table is what proves the extractor stops at the table. The
# YELLOW that comes back *after* the RED row, inside the table, is what proves
# the collapse is of consecutive repeats and not a global dedupe: with a
# seen-set the fixture would still read GREEN YELLOW RED and a real table that
# lost a level would slip through the check unchanged.
# The decoy row on top is the third half: it names a level inside a cell of
# prose, the shape references/other-stacks.md already uses. Matching a level
# anywhere in a `|` line would open the table there, and the blank line under it
# would close the table again before the real one ever started — the extractor
# would read [GREEN] and every assertion below it would be about the wrong rows.
printf '%s\n' '| go | deadcode | yes, at GREEN |' '' \
              '| a | GREEN | x |' '| b | YELLOW | x |' '| c | YELLOW | x |' \
              '| d | RED | x |' '| e | YELLOW | x |' '' 'prose' '| f | GREEN | x |' \
              > "$SELFTMP/levels.md"
got=$(level_shape "$SELFTMP/levels.md")
check "level extractor collapses repeats and stops at the table" \
      "$([[ $got == 'GREEN YELLOW RED YELLOW' ]] && echo 0 || echo 1)" \
      "read [$got], expected [GREEN YELLOW RED YELLOW]"

for f in $LEVEL_FILES; do
  shape=$(level_shape "$f")
  check "level table of $f reads GREEN YELLOW RED" \
        "$([[ $shape == 'GREEN YELLOW RED' ]] && echo 0 || echo 1)" \
        "levels in order: [$shape]"
done

# The condition that puts a run at each level, in each file's own language,
# checked against that level's own row and not merely somewhere in the file —
# the row is what gets read at classification time. The shape check above
# cannot carry this on its own: flipping the RED row to YELLOW leaves the
# collapsed shape at GREEN YELLOW RED (SKILL.md's fourth row is RED too), which
# is exactly the drift this section exists to catch.
# The level is matched as a cell of its own — `| RED |` or `| **RED** |`, which
# covers both layouts in use (the READMEs put the level first, SKILL.md second)
# — and not as a substring of the row. A row is free to name another level in
# its prose without stealing that level's assertion.
level_row() {
  level_rows "$1" | grep -E -m1 -- "\|[[:space:]]*\**$2\**[[:space:]]*\|"
}

for triple in \
  'SKILL.md|GREEN|Typecheck **and** tests pass' \
  'SKILL.md|YELLOW|A partial net, or no test file in the stack' \
  'SKILL.md|RED|A check fails, or no tests and no typecheck' \
  'README.en.md|GREEN|typecheck and tests pass' \
  'README.en.md|YELLOW|partial net, or no test file in the stack' \
  'README.en.md|RED|no tests and no typecheck, or a baseline already failing' \
  'README.md|GREEN|typecheck e testes passam' \
  'README.md|YELLOW|rede parcial, ou nenhum arquivo de teste no stack' \
  'README.md|RED|sem testes e sem typecheck, ou baseline já vermelho'
do
  f=${triple%%|*}
  rest=${triple#*|}
  level=${rest%%|*}
  cond=${rest#*|}
  row=$(level_row "$f" "$level")
  check "$level row of $f states the canonical condition" \
        "$(printf '%s' "$row" | grep -q -F -- "$cond" && echo 0 || echo 1)" \
        "expected [$cond] — row reads: ${row:-<no $level row>}"
done

# 8. A command that lives in two files is one string, byte for byte. ---------
# Same rule as the rollback in section 1, and the same reason: both of these
# are copied by hand into two files, both get executed, and a flag fixed in one
# copy and not the other leaves two protocols behind. The stale copy is the
# dangerous one — the unhardened knip form (`> knip-report.json`) truncates the
# report before knip starts, so a crash reads as "nothing to delete"; the
# unwindowed churn command ranks by lifetime touch count, where a file rewritten
# three years ago outranks whatever is hot now.
KNIP_CMD='npx knip@6.32.0 --production --no-exit-code --reporter json > knip-report.json.tmp && mv knip-report.json.tmp knip-report.json'
KNIP_FILES="SKILL.md references/knip-config.md"

CHURN_CMD='git log --no-merges --since="6 months ago" --format= --name-only | sed '\''/^$/d'\'' | sort | uniq -c | sort -rn'
CHURN_FILES="references/audit.md references/phase-2-consolidation.md"

for f in $KNIP_FILES; do
  check "knip report command verbatim in $f" \
        "$(grep -q -F -- "$KNIP_CMD" "$f" 2>/dev/null && echo 0 || echo 1)" \
        "missing the canonical form: $KNIP_CMD"
done

for f in $CHURN_FILES; do
  check "churn ranking command verbatim in $f" \
        "$(grep -q -F -- "$CHURN_CMD" "$f" 2>/dev/null && echo 0 || echo 1)" \
        "missing the canonical form: $CHURN_CMD"
done

# ...and no variant of either anywhere else in the repo. The markers are the
# parts that only this command has a reason to use: knip only ever writes a
# report through `--reporter json`, and nothing else counts with `uniq -c`.
loose=$(count_matches '--reporter json')
canon=$(count_matches "$KNIP_CMD")
check "no knip report variant in the repo" \
      "$([[ $loose -eq $canon ]] && echo 0 || echo 1)" \
      "$loose uses of '--reporter json', $canon of them the canonical command"

loose=$(count_matches 'uniq -c')
canon=$(count_matches "$CHURN_CMD")
check "no churn ranking variant in the repo" \
      "$([[ $loose -eq $canon ]] && echo 0 || echo 1)" \
      "$loose uses of 'uniq -c', $canon of them the canonical command"

# 9. The validated-run line in the READMEs counts the suite that exists. ------
# Both READMEs publish the result of a docker run ("N/N casos") as evidence the
# contract was exercised. That number drifted once — the suite grew by eleven
# cases and the line was bumped by six — and a stale count is worse than none,
# because a reader who runs the command and gets a different total has to guess
# which of the two is lying. The total is whatever gate_test.sh prints at the
# end of a real run (`NN/NN cases passed`): call-site grep silently desyncs when
# cases move behind a loop or a conditional, and the perl-guarded block already
# proves the point — a host without perl runs ten fewer cases than a grep of
# the file would claim. Running the suite makes the READMEs answer to the same
# number a reader sees. The properties and invariants figures come from loops
# over derived lists and have no single printed total to pin; they stay on the
# honour system (Integrator syncs the README figures to the printed totals).
# Prefer the count from the parent `scripts/test.sh` run when present — that
# suite already exercised gate_test.sh under the same $BASH — so a full
# `scripts/test.sh` does not pay for a second full matrix pass. Alone, re-run
# under this process's interpreter (never bare `bash` from PATH: macOS CI pins
# /bin/bash 3.2 and Homebrew bash on PATH would defeat that premise).
gate_log="$SELFTMP/gate_test.out"
if [[ -n ${GATE_TEST_CASE_COUNT:-} ]]; then
  gate_cases=$GATE_TEST_CASE_COUNT
  : >"$gate_log"
else
  "${BASH:-bash}" scripts/gate_test.sh >"$gate_log" 2>&1 || true
  gate_cases=$(sed -n 's|^[0-9][0-9]*/\([0-9][0-9]*\) cases passed$|\1|p' "$gate_log" | tail -1)
fi
check "gate_test.sh printed a parsable NN/NN cases summary" \
      "$([[ -n $gate_cases ]] && echo 0 || echo 1)" \
      "GATE_TEST_CASE_COUNT=${GATE_TEST_CASE_COUNT:-unset}; last lines of gate_test.sh:
$(tail -n 5 "$gate_log" 2>/dev/null)"
for pair in 'README.md|casos' 'README.en.md|cases'; do
  f=${pair%%|*}
  word=${pair#*|}
  check "$f quotes gate_test.sh's real case count" \
        "$([[ -n $gate_cases ]] && grep -q -F -- "$gate_cases/$gate_cases $word" "$f" 2>/dev/null && echo 0 || echo 1)" \
        "gate_test.sh ran $gate_cases cases; the validated-run line of $f does not say so"
done

# 10. Normative PT↔EN markers, and the SKILL.md frontmatter budget. ----------
# Section 7 already locks the level-table shape and per-row conditions. What
# still drifted without a failure was the shared vocabulary around empty-suite
# caps and the exit contract outside the file-tree caption — language-neutral
# tokens that must appear in both READMEs — plus the description frontmatter,
# which is the only line that can eject the skill from auto-dispatch when it
# grows past the host's limit. Fail closed above 1000 characters so there is
# margin under the usual 1024 cap before a new trigger phrase breaks discovery.
#
# The exit contract and the JS/TS vocabulary are checked against the whole file:
# each of these is a string the gate prints or reads, and it has no business
# appearing anywhere else.
for marker in \
  'exit 0/1/2/3/4' \
  'Exit 124' \
  'Exit 137' \
  'test:unit' \
  'test:e2e' \
  'checks=typecheck,test'
do
  for f in README.md README.en.md; do
    check "$f carries normative marker [$marker]" \
          "$(grep -q -F -- "$marker" "$f" 2>/dev/null && echo 0 || echo 1)" \
          "missing [$marker]"
  done
done

# The per-stack rules are a different problem, and the file-wide grep was the
# wrong tool for it. `Go`, `.NET`, `Rust`, `Maven`, `Gradle` and `pytest` as
# bare words are practically impossible to violate in a README that long — and
# `Go` matched any substring, "Google" included. Twelve checks that could not
# fail inflate the count and buy nothing.
#
# What each of those names is doing in the README is naming the evidence that
# stack has to show before the gate will call its suite non-empty. So the
# assertion is co-occurrence *inside the empty-suite paragraph*: the stack and
# its evidence in the same paragraph, not both somewhere in a 400-line file.
# That is what makes them falsifiable — `tests/*.rs` and `#[test]` also live in
# the known-limits section further down, so dropping the whole Rust clause from
# the cap paragraph left the old markers green.
#
# Anchored on `passWithNoTests` rather than on a phrase of prose: it is the one
# token in that paragraph the gate itself reads, so the anchor moves only if the
# rule does.
CAP_ANCHOR='passWithNoTests'

# in_paragraph <paragraph> <token> — a token with punctuation is matched
# literally; a bare word is matched with alphabetic boundaries, which is what
# keeps `Go` from passing on "Google" the way the file-wide grep did.
in_paragraph() {
  case $2 in
    *[!A-Za-z]*) printf '%s' "$1" | grep -q -F -- "$2" ;;
    *)           printf '%s' "$1" | grep -q -E -- "(^|[^A-Za-z])$2([^A-Za-z]|$)" ;;
  esac
}

# The extractor is proven on a fixture first, and so is the word boundary: an
# extractor that returns the whole file would put every token back in scope and
# quietly restore the check this block exists to replace.
printf '%s\n' 'first paragraph, with Rust in it' '' \
              'second, the anchor ANCHOR lives here with Go' '' \
              'third, with Google and src/test' > "$SELFTMP/paras.md"
probe_para=$(paragraph_with "$SELFTMP/paras.md" 'ANCHOR')
check "paragraph extractor returns only the paragraph holding the anchor" \
      "$([[ $probe_para == 'second, the anchor ANCHOR lives here with Go ' ]] && echo 0 || echo 1)" \
      "read [$probe_para]"
check "paragraph extractor is empty when the anchor is absent" \
      "$([[ -z $(paragraph_with "$SELFTMP/paras.md" 'NO_SUCH_ANCHOR') ]] && echo 0 || echo 1)" \
      "an absent anchor must return nothing, so the floor below can catch it"
check "bare-word matching does not accept a longer word" \
      "$(in_paragraph 'third, with Google and src/test' 'Go' && echo 1 || echo 0)" \
      "[Go] matched inside Google — the boundary is what the old marker lacked"

for f in README.md README.en.md; do
  cap=$(paragraph_with "$f" "$CAP_ANCHOR")
  # Floor, same reason as sections 4 and 15: an empty paragraph would make every
  # token below report "missing" for one reason (the anchor moved) while reading
  # like another (the rule was deleted), and a paragraph that swallowed the file
  # would make them all pass.
  check "$f has an empty-suite paragraph to check" \
        "$([[ -n ${cap// /} ]] && echo 0 || echo 1)" \
        "no paragraph carries [$CAP_ANCHOR] — every per-stack assertion below
depends on finding it, and none of them means anything without it"
  for token in \
    'No test files found' \
    'passWithNoTests' \
    'Go' \
    '.NET' \
    'Rust' \
    'tests/*.rs' \
    '#[test]' \
    'Maven' \
    'Gradle' \
    'src/test' \
    'Ruby' \
    '_spec.rb' \
    '_test.rb' \
    'test_*.rb' \
    'pytest'
  do
    check "the empty-suite paragraph of $f names [$token]" \
          "$(in_paragraph "$cap" "$token" && echo 0 || echo 1)" \
          "[$token] is not in the paragraph that states the empty-suite cap.
A stack named there without its evidence, or evidence without its stack, is a
rule the reader cannot apply — and the same string somewhere else in the file
is not that rule."
  done
done

# The two-platform premise of the validated run. gate_test.sh counts the two
# -k cases as skips so the total stays the same on both platforms, which keeps
# section 9 honest — and costs exactly this: on macOS, removing the 137 branch
# from wd_timed_out leaves the suite green with the same NN/NN. Measured. The
# Linux leg covers it, so the number is not wrong; what would be wrong is a
# reader concluding from a local green that the matrix ran. The summary says so
# at runtime, and the READMEs have to say so where the validated run is
# published, which is where that conclusion gets drawn.
for pair in \
  'README.md|As duas pernas são necessárias' \
  'README.en.md|Both legs are required'
do
  f=${pair%%|*}
  phrase=${pair#*|}
  ci_para=$(paragraph_with "$f" 'procps')
  check "$f has a paragraph describing the CI matrix" \
        "$([[ -n ${ci_para// /} ]] && echo 0 || echo 1)" \
        "no paragraph carries [procps]; the check below needs it"
  check "$f states that one platform is not a complete validation" \
        "$(printf '%s' "$ci_para" | grep -q -F -- "$phrase" && echo 0 || echo 1)" \
        "missing [$phrase] — a green run on one platform skips cases the other
counts, and nothing in the number says so"
done

# The buffering notice, in the paragraph that describes the gate. gate_test.sh
# already asserts the line the gate prints (js-buffer-notice); this is the other
# half — the READMEs are where someone decides whether a quiet gate is a hung
# gate, and the notice only helps if it is also written down where they look.
# Anchored on GATE_TIMEOUT, the token that paragraph exists to introduce.
for pair in \
  'README.md|só aparece quando o comando termina' \
  'README.en.md|only appears once the command finishes'
do
  f=${pair%%|*}
  phrase=${pair#*|}
  gate_para=$(paragraph_with "$f" 'GATE_TIMEOUT')
  check "$f has a paragraph describing the gate" \
        "$([[ -n ${gate_para// /} ]] && echo 0 || echo 1)" \
        "no paragraph carries [GATE_TIMEOUT]; the check below needs it"
  check "$f says the JS test output is buffered until the command ends" \
        "$(printf '%s' "$gate_para" | grep -q -F -- "$phrase" && echo 0 || echo 1)" \
        "missing [$phrase] — on a long suite the gate goes quiet for minutes and
the watchdog default is 900s, so silence reads as a hang to whoever is watching"
done

# Bash ${#var} counts characters under a UTF-8 locale; awk's length() counts
# bytes and would burn the margin on the em dash and Portuguese accents that
# already live in the description (keep headroom under the 1000-char cap).
desc=$(awk '
  /^---[[:space:]]*$/ { fm++; next }
  fm == 1 && /^description:[[:space:]]*/ {
    sub(/^description:[[:space:]]*/, "")
    print
    exit
  }
  fm >= 2 { exit }
' SKILL.md)
desc_len=${#desc}
check "SKILL.md description stays at or under 1000 characters" \
      "$([[ -n $desc && $desc_len -le 1000 ]] && echo 0 || echo 1)" \
      "description is ${desc_len} characters (limit 1000)"

# 11. The guard blocks what the READMEs say it blocks. -----------------------
# The guard is the plugin half of five rules the skill states in prose, and a
# table that drifts from the script is worse than no table: a reader plans
# around a command that is not actually stopped, or fights one that is. So each
# command is one string in three places — the executable proof, and both
# READMEs — and the invariant is that the three agree. The proof is the anchor
# and not guard.sh itself on purpose: the script matches `-A` inside a case arm
# and never spells the whole command out, while guard_test.sh has to run it
# verbatim to test it.
GUARD_SECTION_PT='### Os guardas'
GUARD_SECTION_EN='### The guards'

guard_section() { # guard_section <readme> <heading> — the section's body
  awk -v h="$2" '
    $0 == h { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
  ' "$1"
}

for f in scripts/guard.sh scripts/guard_test.sh hooks/hooks.json; do
  check "$f exists" "$([[ -f $f ]] && echo 0 || echo 1)" "the guard ships incomplete without it"
done

check "hooks.json runs the guard through the plugin root" \
      "$(grep -q -F -- '${CLAUDE_PLUGIN_ROOT}/scripts/guard.sh' hooks/hooks.json 2>/dev/null && echo 0 || echo 1)" \
      "the hook command has to resolve from the plugin directory, not the cleaned project"

check "hooks.json registers the guard on PreToolUse" \
      "$(grep -q -F -- 'PreToolUse' hooks/hooks.json 2>/dev/null && echo 0 || echo 1)" \
      "any later event fires after the command already ran"

check "test.sh chains guard_test.sh" \
      "$(grep -q -F -- 'guard_test.sh' scripts/test.sh 2>/dev/null && echo 0 || echo 1)" \
      "a suite nobody runs is a suite that rots"

while IFS= read -r cmd; do
  [[ -n $cmd ]] || continue
  check "guard_test.sh exercises '$cmd'" \
        "$(grep -q -F -- "$cmd" scripts/guard_test.sh 2>/dev/null && echo 0 || echo 1)" \
        "the READMEs promise it is blocked and no case runs it"
  check "the guard table of README.md names '$cmd'" \
        "$(guard_section README.md "$GUARD_SECTION_PT" | grep -q -F -- "$cmd" && echo 0 || echo 1)" \
        "blocked by the guard and absent from the table"
  check "the guard table of README.en.md names '$cmd'" \
        "$(guard_section README.en.md "$GUARD_SECTION_EN" | grep -q -F -- "$cmd" && echo 0 || echo 1)" \
        "blocked by the guard and absent from the table"
done <<'GUARDED'
git reset --hard
git clean
git push
git commit
git add -A
GUARDED

# 12. The delegated phases exist as agents, and stay inside their limits. ----
# Step 0.2 hands each phase to an agent by name. A name that resolves to no
# file is a delegation that dies at call time, and the two read-only ones carry
# the checkpoint: a survey agent that can write is a survey that can decide,
# which is the one thing the checkpoint exists to prevent. Plugin agents also
# may not declare hooks, mcpServers or permissionMode. The reason this check
# exists is the mechanism, and it is the opposite of what this comment used to
# say: the host does not refuse the agent, it drops the fields without a word.
#   "For security reasons, `hooks`, `mcpServers`, and `permissionMode` are not
#    supported for plugin-shipped agents."
#    — code.claude.com/docs/en/plugins-reference#agents, consultado 2026-08-10
#   "plugin subagents don't support the `hooks`, `mcpServers`, or
#    `permissionMode` frontmatter fields. These fields are ignored when loading
#    agents from a plugin."
#    — code.claude.com/docs/en/sub-agents#choose-the-subagent-scope, idem
# The plugin loads, `claude plugin validate --strict` says nothing, and the
# author ships believing a guard is in place. A field that is refused is caught
# by the host; a field that is ignored is caught by nobody — which makes this
# check the only place the mistake can surface at all.
agent_frontmatter() { # agent_frontmatter <file> — the YAML block, or empty
  awk '/^---[[:space:]]*$/ { fm++; next } fm == 1 { print } fm >= 2 { exit }' "$1"
}

for a in cleanup-phase-1 cleanup-phase-2-survey cleanup-phase-2-impl \
         cleanup-phase-3-survey cleanup-phase-3-impl \
         cleanup-phase-4-survey cleanup-phase-4-impl; do
  f="agents/$a.md"
  check "agents/$a.md exists" \
        "$([[ -f $f ]] && echo 0 || echo 1)" \
        "Step 0.2 delegates to an agent with no file behind it"
  [[ -f $f ]] || continue

  check "$a declares its own name in the frontmatter" \
        "$(agent_frontmatter "$f" | grep -q -E "^name:[[:space:]]*$a\$" && echo 0 || echo 1)" \
        "the frontmatter name is what the @-mention resolves; a mismatch with the
filename is a delegation nobody can call"

  check "$a declares a description" \
        "$(agent_frontmatter "$f" | grep -q -E '^description:[[:space:]]*[^[:space:]]' && echo 0 || echo 1)" \
        "the description is what decides when the agent is invoked"

  check "$a reads CLEANUP_PROGRESS.md first" \
        "$(grep -q -F -- 'CLEANUP_PROGRESS.md' "$f" && echo 0 || echo 1)" \
        "the log is the canonical state a delegation resumes from"

  banned=$(agent_frontmatter "$f" | grep -E '^(hooks|mcpServers|permissionMode):' | tr '\n' ' ')
  check "$a declares no field a plugin agent may not have" \
        "$([[ -z $banned ]] && echo 0 || echo 1)" \
        "a plugin agent does not get these fields, and is not told so — they are
ignored on load, so the agent runs without the guard its frontmatter claims: $banned"

  check "Step 0.2 names $a" \
        "$(grep -q -F -- "codebase-cleanup:$a" SKILL.md && echo 0 || echo 1)" \
        "an agent nobody delegates to is an agent that rots"
done

# The surveys are the checkpoint. They run before the user has answered, so
# the guarantee has to be mechanical: no Write, no Edit, no way to change the
# repository while deciding what to propose. Phase 4's survey earns the same
# ban for a narrower reason: it reads coverage per target, and a survey that
# can write is one keystroke away from "fixing" the target it was measuring.
for a in cleanup-phase-2-survey cleanup-phase-3-survey cleanup-phase-4-survey; do
  f="agents/$a.md"
  [[ -f $f ]] || continue
  line=$(agent_frontmatter "$f" | grep -E '^disallowedTools:')
  ok=1
  case $line in
    *Write*) case $line in *Edit*) ok=0 ;; esac ;;
  esac
  check "$a cannot write" "$ok" \
        "a survey runs before the user answered; got '${line:-no disallowedTools}'"
done

# 14. The catalog's operation ids are one list, in every file that names them. -
# The eleven ids are the vocabulary phase 4 runs on: they are the commit message
# (`refactor(<id>): …`), the tier that decides whether a checkpoint is needed,
# and what the impl agent is allowed to do at all ("an operation that is in
# neither tier is out of scope"). They live in four places written by hand — the
# catalog's table, the catalog's own section headings, and the two tier lists in
# SKILL.md — and nothing until now compared them. An id that exists in one and
# not the others is either an operation nobody can run or a commit message
# nobody can trace back, and both fail silently.
catalog_table_ids() { # ids from the tier table of the catalog
  grep -oE '^\|[[:space:]]*[AB][[:space:]]*\|[[:space:]]*`[a-z-]+`' \
    references/refactoring-catalog.md 2>/dev/null |
    grep -oE '`[a-z-]+`' | tr -d '`' | sort -u
}
catalog_heading_ids() { # ids from the per-operation headings of the catalog
  grep -oE '^## `[a-z-]+`' references/refactoring-catalog.md 2>/dev/null |
    grep -oE '`[a-z-]+`' | tr -d '`' | sort -u
}
skill_ids() { # ids named in SKILL.md's two tier lists
  ids=$(catalog_table_ids | tr '\n' '|' | sed 's/|$//')
  [[ -n $ids ]] || return 0
  grep -oE "\`($ids)\`" SKILL.md 2>/dev/null | tr -d '`' | sort -u
}

table=$(catalog_table_ids)
headings=$(catalog_heading_ids)
n_table=$(printf '%s\n' "$table" | grep -c .)

# Floor: eleven is the number the phase was designed around. A derivation that
# comes back empty (a table that changed shape) would make every diff below
# compare nothing against nothing and pass.
check "the catalog table lists 11 operation ids" \
      "$([[ $n_table -eq 11 ]] && echo 0 || echo 1)" \
      "found $n_table: $(printf '%s' "$table" | tr '\n' ' ')"

check "every catalog id has its own section" \
      "$([[ "$table" == "$headings" ]] && echo 0 || echo 1)" \
      "table: $(printf '%s' "$table" | tr '\n' ' ')
headings: $(printf '%s' "$headings" | tr '\n' ' ')"

check "SKILL.md names every catalog id" \
      "$([[ "$(skill_ids)" == "$table" ]] && echo 0 || echo 1)" \
      "in SKILL.md: $(skill_ids | tr '\n' ' ')
in the catalog: $(printf '%s' "$table" | tr '\n' ' ')"

# 15. The JS gate classifies normalized output, never the colored capture. ----
# gate.sh's js_script() decides GREEN/YELLOW/RED by matching the runner's own
# text, with regexes anchored at ^ and $. The capture is the user's output and
# stays colored on purpose, so every anchor sat behind an SGR escape: a repo
# with zero tests reached GREEN ('\e[34m<i> tests 0\e[39m' never matches
# 'tests 0$', the reset is after the 0), and a suite that really failed was
# capped as uncounted because the failure guard could not see a colored FAIL.
# The fix normalizes once at the capture boundary — strip_ansi -> out_plain,
# with ev derived from out_plain — and this section is what keeps it: a new
# detector that reads $out again is born with the same blindness, and its
# fixtures would all pass because test fixtures are written without color.
# Displaying $out is the one legitimate read; it is not a pipeline into a
# matcher, so it never shows up here.
# bash_body is deliberately not used: it erases quoted text, which is exactly
# the '"$out"' we have to read. Whole-line comments are dropped instead, which
# is gate.sh's comment style; a matcher hidden in a trailing comment would be
# counted, and that only ever costs a false failure.
js_script_body() { # gate.sh's js_script() body, whole-line comments dropped
  awk '
    !f && /^[[:space:]]*js_script\(\)[[:space:]]*\{/ {
      f = 1; match($0, /^[[:space:]]*/); pad = substr($0, 1, RLENGTH); next
    }
    f && $0 == pad "}" { exit }
    f { print }
  ' scripts/gate.sh 2>/dev/null | grep -v '^[[:space:]]*#'
}

# The classification points: a shell pipeline whose sink is a matcher — grep -q
# (a decision), grep -v (the epilogue filter that builds ev) or awk. Anything
# else piped from the capture (strip_ansi itself) is normalization, not a
# verdict, and is not one of these.
js_classify_lines() {
  js_script_body | grep -E '\|[[:space:]]*(grep[[:space:]]+-[a-zA-Z]*[qv][a-zA-Z]*|awk)'
}

# The variables those lines read. The regexes on the same line are single
# quoted, and a '$' anchor inside them is not followed by a name character, so
# only the shell expansions come out.
js_classify_vars() {
  js_classify_lines | grep -oE '\$[A-Za-z_][A-Za-z_0-9]*' | sed 's/^\$//' | sort -u
}

n_classify=$(js_classify_lines | grep -c .)
classify_vars=$(js_classify_vars)
bad_vars=$(printf '%s\n' "$classify_vars" | grep -vE '^(out_plain|ev)$' | grep . || true)

# Floor, same reason as in section 4: six decision points is what the JS path
# was audited to have. An extraction that comes back empty — js_script renamed,
# the matchers moved behind a helper — would leave the checks below inspecting
# an empty list and passing over a gate nobody is guarding any more.
check "gate.sh js_script has at least 6 classification points" \
      "$([[ $n_classify -ge 6 ]] && echo 0 || echo 1)" \
      "found $n_classify; the extractor no longer sees the matchers"

check "every js_script classification reads out_plain or ev" \
      "$([[ -z $bad_vars ]] && echo 0 || echo 1)" \
      "reads: $(printf '%s' "$bad_vars" | tr '\n' ' ')-- \$out is the colored
capture shown to the user; anchored regexes do not survive SGR escapes"

# Without these two the invariant above is decorative: a gate with no strip_ansi
# and no out_plain has no classification point reading it, so the check passes
# by vacuity — over the exact code the fix removed.
check "gate.sh defines strip_ansi" \
      "$(grep -qE '^[[:space:]]*strip_ansi\(\)' scripts/gate.sh 2>/dev/null && echo 0 || echo 1)" \
      "the normalization the classification depends on is gone"

check "out_plain is derived from strip_ansi" \
      "$(js_script_body | grep -qE 'out_plain=.*\|[[:space:]]*strip_ansi' && echo 0 || echo 1)" \
      "out_plain must be the capture passed through strip_ansi, nothing else"

# The four checks above are shape-based: they find classification by looking for
# a pipeline that ends in a matcher. Five spellings escape that shape —
# `case $out in`, `[[ $out == *FAIL* ]]`, `[ -n "$(... | grep FAIL)" ]`, a
# here-string `grep -q <<<"$out"`, and `sed -n /FAIL/p` — so a detector written
# any of those ways would read the colored capture with the section still green.
# Counting closes all five at once and needs no catalogue of spellings: inside
# js_script the raw `$out` has exactly two legitimate readers, and both are
# named here. Anything else touching it is a third reader, and a third reader is
# the bug coming back.
raw_out=$(js_script_body | grep -oE '\$out\b|\$\{out\}' | grep -c .)
check "js_script reads the raw capture exactly twice" \
      "$([[ ${raw_out:-0} -eq 2 ]] && echo 0 || echo 1)" \
      "found ${raw_out:-0} reads of \$out; the only two allowed are the passthrough
that prints the user's own colored output and the one that feeds strip_ansi"

# 13. The plugin manifests agree with each other and with the docs. ----------
# The version in plugin.json is the cache key that decides whether an install
# sees an update at all: pinned and never bumped, a user stays on the version
# they first installed no matter how many commits land. That failure is silent
# on both ends — nobody gets an error, the fix just never arrives — so the
# pieces that have to agree are checked here instead of being remembered.
plugin_field() { # plugin_field <file> <key> — the string value, or empty
  perl -0777 -ne 'print $1 if /"'"$2"'"\s*:\s*"([^"]*)"/' "$1" 2>/dev/null
}

plugin_name=$(plugin_field .claude-plugin/plugin.json name)
plugin_version=$(plugin_field .claude-plugin/plugin.json version)
market_name=$(plugin_field .claude-plugin/marketplace.json name)

check "plugin.json declares a name" \
      "$([[ -n $plugin_name ]] && echo 0 || echo 1)" \
      "the name is the namespace of every skill in the plugin"

# The changelog's top entry and the manifest's version are one string. The
# manifest alone would be a number nobody can read a meaning into, and a
# changelog alone would be a story about a version that never shipped: the
# release is the pair, so drift between them is caught here.
changelog_version=$(sed -n 's|^## \[\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\].*|\1|p' CHANGELOG.md 2>/dev/null | head -1)
check "CHANGELOG.md opens with a semver entry" \
      "$([[ -n $changelog_version ]] && echo 0 || echo 1)" \
      "no '## [X.Y.Z]' heading found; the top entry is what a release note quotes"
check "CHANGELOG.md and plugin.json agree on the version" \
      "$([[ -n $changelog_version && $changelog_version == "$plugin_version" ]] && echo 0 || echo 1)" \
      "CHANGELOG.md says '${changelog_version:-none}', plugin.json says '${plugin_version:-none}'"

check "plugin.json declares an explicit version" \
      "$([[ $plugin_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo 0 || echo 1)" \
      "got '${plugin_version:-none}'; without semver here the version falls back to the
commit SHA and every push becomes an update"

# The install line the READMEs publish is plugin@marketplace. Both halves come
# from the manifests, so a rename on either side turns the documented command
# into one that resolves to nothing.
install_id="$plugin_name@$market_name"
for f in README.md README.en.md; do
  check "$f publishes the install id $install_id" \
        "$(grep -q -F -- "$install_id" "$f" 2>/dev/null && echo 0 || echo 1)" \
        "the documented /plugin install does not match the manifests"
done

# The guard's own exit codes. Exit 1 does not block — the hook contract reads
# it as a non-fatal error and lets the command through — so a guard that ever
# exits 1 fails silently, which is the one failure mode nobody would notice.
guard_codes=$(exit_codes < scripts/guard.sh | sort -u | tr '\n' ' ')
check "guard.sh only exits 0 or 2" \
      "$([[ $(printf '%s' "$guard_codes" | tr -d ' ') == "02" ]] && echo 0 || echo 1)" \
      "exit codes found: ${guard_codes:-none} (1 would not block)"

# 16. The rules that decide destructive authority, as invariants that bite. ---
# Four rules closed as prose in earlier PRs and one whose positive form let the
# forbidden form live beside it. They are grouped because they share a single
# acceptance test: a named mutation that the suite used to swallow has to fail
# here. An invariant that cannot fail is worse than no invariant, because it
# buys confidence without giving a guarantee — so each check below was written
# against a mutation first, and none of them was allowed to pass by construction.

# 16.1 The behavior column of the level table, not only the condition column.
# Section 7 asserts which levels exist and what each row's *condition* is. What
# the level actually AUTHORIZES lived only in prose, so rewriting YELLOW's cell
# to run phase 2 and delete exports left the suite green — and that cell is the
# whole difference between a level that reports and a level that mutates a repo
# whose tests never ran.
#
# The first version of this block grepped the phrasing in use (`**not** exports`,
# `does **not** run phase 2`). That measures wording, not authority, and it was
# wrong in both directions. Measured, on this table:
#   - a WEAKER cell stayed green: keeping both phrases and adding "but runs
#     phase 3 and phase 4 and commits everything without a checkpoint" passed
#     309/309 — the level that means "the safety net has holes" had just been
#     handed the mutating phases and nothing said so;
#   - a STRICTER cell went red: "does **not** delete exports" is a tighter
#     promise than "**not** exports" and failed, so the check fought the very
#     rewrite it should reward.
#
# So the cell is read as a contract instead: split into clauses, and for each
# capability ask whether that clause GRANTS it or DENIES it. A clause ends at a
# sentence, at a semicolon, or at an adversative — "does **not** run phase 2,
# BUT runs phase 3" grants phase 3, and any window measured in characters says
# the opposite (40 characters from the negation to the token, inside any window
# wide enough to cover the legitimate "does **not** run phase 2, phase 3 or
# phase 4", which spans 35). Only a clause boundary tells the two apart.
#
# Inside a clause the negation covers the whole clause, before or after the
# token, so "exports are never touched" reads as a denial. Across clauses a
# single grant outweighs any number of denials: a cell that refuses something
# twice and allows it once allows it.
#
# This makes the vocabulary of negation a closed list, and a rewrite outside it
# fails. That is the trade taken on purpose: this cell is a contract an agent
# dispatches on, and a loud false alarm costs one commit while a silent false
# green costs a repo.
BEHAVIOR_TOKEN_ABSENT='absent'

# The negation vocabulary is per language and cannot be shared: `no` is a
# negation in English and a preposition in Portuguese, so one merged list would
# read README.md's "param **no** checkpoint humano" as a denial of the very
# checkpoint that line exists to promise — the check would fail loudest on the
# sentence it protects.
NEG_EN='(^|[^a-z])(not|never|no|nor|none|nothing|neither|refuses|refuse|excludes|exclude|excluded)([^a-z]|$)'
NEG_PT='(^|[^a-z])(não|nunca|nem|nada|sem|nenhum|nenhuma|recusa)([^a-z]|$)'

neg_vocab() { # neg_vocab <file> — the negations that file writes its cells in
  case $1 in
    README.md) printf '%s' "$NEG_PT" ;;
    *)         printf '%s' "$NEG_EN" ;;
  esac
}

# behavior_cell <file> <level> — the "what it does" cell of that level's row.
# Column 4 under `-F'|'` in both layouts in use: the READMEs put the level
# first and SKILL.md puts it second, and the behavior column follows the other
# two either way. It reuses level_row, so a row that merely names a level in its
# prose still cannot steal that level's assertion.
behavior_cell() {
  level_row "$1" "$2" | awk -F'|' '{ print $4 }'
}

# authority <cell> <token-regex> <negations> — granted, denied or absent.
# LC_ALL=C for the reason gate.sh's strip_ansi carries it: BSD awk aborts on the
# first invalid byte under a UTF-8 locale, and an aborted scan prints nothing,
# which reads exactly like a clean one.
authority() {
  printf '%s' "$1" | env LC_ALL=C awk -v tok="$2" -v neg="$3" '
    {
      s = tolower($0)
      # markdown emphasis is not a word boundary: `**not**` has to read as not
      gsub(/[*`]/, " ", s)
      # ". " and not ".": a sentence ends at a period followed by a space, while
      # the period inside `CLEANUP_PROGRESS.md` is part of the token itself, and
      # splitting there would hand the second half a clause with no negation.
      gsub(/\. /, "\n", s)
      gsub(/; /, "\n", s)
      gsub(/ (but|however|except|mas|porém|exceto|todavia) /, "\n", s)
      n = split(s, clause, "\n")
      verdict = "absent"
      for (i = 1; i <= n; i++) {
        if (clause[i] !~ tok) continue
        if (clause[i] ~ neg) { if (verdict == "absent") verdict = "denied" }
        else verdict = "granted"
      }
      print verdict
    }'
}

# The parser is proven on fixtures before it is trusted on the real table, for
# the same reason section 7 proves its extractor: a reader that comes back
# "denied" for everything would make every assertion below pass by construction.
# Each fixture is one of the two failure modes the phrasing greps had.
probe_neg=$NEG_EN
for probe in \
  'runs phase 1, does **not** run phase 2, phase 3 or phase 4|phase 3|denied' \
  'does **not** run phase 2 by default, but runs phase 3 and commits|phase 3|granted' \
  'runs phase 1 (deps only); exports are never touched|exports|denied' \
  'phase 2 and phase 3 stop at the human checkpoint|checkpoint|granted' \
  'no further checkpoint is needed|checkpoint|denied' \
  'diagnoses only. does **not** commit `CLEANUP_PROGRESS.md`|cleanup_progress|denied' \
  'runs phase 1 in full without asking|phase 4|absent'
do
  cell=${probe%%|*}
  rest=${probe#*|}
  tok=${rest%%|*}
  want=${rest#*|}
  got=$(authority "$cell" "$tok" "$probe_neg")
  check "authority reader says $want for [$tok] in a clause that $want it" \
        "$([[ $got == "$want" ]] && echo 0 || echo 1)" \
        "read [$got] for token [$tok] in: $cell"
done

# The contract itself, per file and per level. `absent` fails like a grant does:
# a cell that simply stops mentioning phase 4 leaves a reader concluding it runs,
# which is how the READMEs drifted behind SKILL.md when phase 4 shipped.
for rule in \
  'SKILL.md|GREEN|phase 1|granted' \
  'SKILL.md|GREEN|phase 4|granted' \
  'SKILL.md|GREEN|checkpoint|granted' \
  'SKILL.md|YELLOW|exports|denied' \
  'SKILL.md|YELLOW|phase 2|denied' \
  'SKILL.md|YELLOW|phase 3|denied' \
  'SKILL.md|YELLOW|phase 4|denied' \
  'SKILL.md|RED|delete|denied' \
  'SKILL.md|RED|commit|denied' \
  'SKILL.md|RED|cleanup_progress|denied' \
  'README.en.md|GREEN|phase 4|granted' \
  'README.en.md|GREEN|checkpoint|granted' \
  'README.en.md|YELLOW|exports|denied' \
  'README.en.md|YELLOW|phase 2|denied' \
  'README.en.md|YELLOW|phase 3|denied' \
  'README.en.md|YELLOW|phase 4|denied' \
  'README.en.md|RED|delet|denied' \
  'README.en.md|RED|cleanup_progress|denied' \
  'README.md|GREEN|fase 4|granted' \
  'README.md|GREEN|checkpoint|granted' \
  'README.md|YELLOW|exports|denied' \
  'README.md|YELLOW|fase 2|denied' \
  'README.md|YELLOW|fase 3|denied' \
  'README.md|YELLOW|fase 4|denied' \
  'README.md|RED|deletado|denied' \
  'README.md|RED|cleanup_progress|denied'
do
  f=${rule%%|*}
  rest=${rule#*|}
  lvl=${rest%%|*}
  rest=${rest#*|}
  tok=${rest%%|*}
  want=${rest#*|}
  cell=$(behavior_cell "$f" "$lvl")
  # Floor, same reason as sections 4 and 15: an extractor that comes back empty
  # would compare nothing against nothing, and every rule below it would pass
  # over a table nobody is guarding.
  check "$f has an extractable behavior cell for $lvl" \
        "$([[ -n ${cell// /} ]] && echo 0 || echo 1)" \
        "no behavior column for $lvl in $f — section 7 checks the conditions,
this one checks what each level is allowed to do"
  got=$(authority "$cell" "$tok" "$(neg_vocab "$f")")
  check "the $lvl cell of $f has [$tok] $want" \
        "$([[ $got == "$want" ]] && echo 0 || echo 1)" \
        "the cell $got it, the contract says $want — cell reads:${cell}"
done

# 16.2 Stack caps override the GREEN column, in every file that can be read
# alone. The tables in SKILL.md and the READMEs decide behavior by gate level;
# references/other-stacks.md then lowers that ceiling per stack. An agent that
# reads only SKILL.md and never opens the reference would run at the table's
# level, so the pointer has to exist in each file that carries the table.
#
# One phrase per file, not one phrase for all of them: README.md is in
# Portuguese, and an English-only invariant leaves the Portuguese half of the
# repo with no net at all. Measured before this list existed — deleting the cap
# line from README.md, and turning its abort branch into a retry below, both
# left the suite at 309/309 green. Same shape as section 9, which already pairs
# each README with the word it uses.
#
# reflow, not a line-anchored grep: both READMEs are hard-wrapped by hand at
# ~80 columns, so a sentence spans two lines the moment a word is added before
# it. A grep that reads line by line asserts where the wrap falls, and would go
# red on a rewrap that changed no meaning at all — the Portuguese abort branch
# is split between "a skill **aborta** o" and "pipeline quando um comando".

for pair in \
  'SKILL.md|override the GREEN column' \
  'README.en.md|override the GREEN column' \
  'references/other-stacks.md|override the GREEN column' \
  'README.md|sobrescrevem a coluna GREEN'
do
  f=${pair%%|*}
  phrase=${pair#*|}
  check "$f states that stack caps override the GREEN column" \
        "$(reflow "$f" | grep -qF -- "$phrase" && echo 0 || echo 1)" \
        "missing [$phrase] — without it a .NET or JVM repo reads GREEN from the
table and runs with an authority its stack section refuses"
done

# 16.3 The abort branch of a blocked rollback. When a hook refuses the restore,
# the only safe move is to stop: working around the hook is the failure mode the
# guard exists to prevent, and 'retry' or 'continue' would be exactly that. The
# rule shipped as prose, so deleting the branch left the suite green — in either
# language, which is why this list has two rows and not one.
for pair in \
  'README.en.md|the skill **aborts** the pipeline when a command of the protocol is blocked' \
  'README.md|a skill **aborta** o pipeline quando um comando do protocolo é barrado'
do
  f=${pair%%|*}
  phrase=${pair#*|}
  check "$f keeps the abort branch of a rollback blocked by a hook" \
        "$(reflow "$f" | grep -qF -- "$phrase" && echo 0 || echo 1)" \
        "missing [$phrase] — a protocol command blocked by a hook has to stop the
run; working around the hook is what the guard exists to prevent"
done

# 16.4 A live 'git add -A' beside the correct form. Section 4 asserts the
# positive form (`git add -- <pathspec>`) is present, which a document can
# satisfy while also offering the forbidden form as a shortcut two words later.
# Banning the string outright is not available either: the prose that forbids it
# has to quote it. So the rule is proximity — every occurrence must be covered
# by a negation right before it, or be the left cell of the table of forbidden
# forms. The window is 48 characters against a measured worst case of 20.
# LC_ALL=C for the same reason gate.sh's strip_ansi carries it: BSD awk aborts
# on the first invalid byte under a UTF-8 locale, and an aborted scan reports
# nothing, which reads exactly like a clean scan.
# uncovered <extended-regex> — every .md occurrence of a form the docs forbid
# that no negation right before it covers. Two rules need this and neither can
# use a plain ban: the prose that forbids a form has to quote it, so the string
# is in the corpus by design. Proximity is what separates an instruction from a
# prohibition — the window is 48 characters against a measured worst case of 20
# for staging and 10 for npx, and the left cell of a table of forbidden forms is
# exempt because such a row is a list of what not to do.
# LC_ALL=C for the same reason gate.sh's strip_ansi carries it: BSD awk aborts on
# the first invalid byte under a UTF-8 locale, and an aborted scan prints
# nothing, which reads exactly like a clean one.
uncovered() {
  find . -name '*.md' -not -path './.git/*' -not -path './node_modules/*' -print0 \
  | xargs -0 -n1 env LC_ALL=C awk -v pat="$1" '
      { all = all $0 " " }
      END {
        s = all; done = ""
        while (match(s, pat)) {
          pre = done substr(s, 1, RSTART - 1)
          start = length(pre) - 47; if (start < 1) start = 1
          win = tolower(substr(pre, start))
          if (win !~ /never|nunca|n.o|instead|em vez|rather than|forbidden|proibid/ \
              && win !~ /\|[[:space:]]*.?$/)
            print FILENAME
          done = pre substr(s, RSTART, RLENGTH)
          s = substr(s, RSTART + RLENGTH)
        }
      }' 2>/dev/null | sort -u | tr '\n' ' '
}

# Bracket expression, not a backslash escape: awk's -v strips one level before
# the regex compiles, so '\.' would arrive as a bare '.' and the pattern would
# match the correct 'git add -- <pathspec>' too — the check would fail loudest
# on exactly the form it exists to protect.
stage_hits=$(uncovered 'git add (-A|[.])')
check "no live 'git add -A' or 'git add .' anywhere in the docs" \
      "$([[ -z ${stage_hits// /} ]] && echo 0 || echo 1)" \
      "uncovered occurrence in: ${stage_hits:-none} — whole-tree staging swallows
what the step did not touch and breaks the per-commit revert the skill promises"

# 16.5 Pinned npx. An unpinned 'npx <pkg>' resolves to whatever latest is on the
# day it runs, so the tool that decides which exports are dead can change under
# the protocol without a single file changing. Everything is pinned today and
# nothing stopped it from coming back.
bare_npx=$(uncovered 'npx [a-z][a-zA-Z0-9-]*([^a-zA-Z0-9@-]|$)')
check "every npx in the docs pins a version" \
      "$([[ -z ${bare_npx// /} ]] && echo 0 || echo 1)" \
      "unpinned: ${bare_npx:-none} — an unpinned tool changes what counts as dead
code without any file in this repo changing"

# 17. What decides destructive authority survives a compaction. -------------
# Section 16 proved these rules cannot be deleted in silence. This one answers a
# question that no amount of invariants about the TEXT can: is the text still in
# the model's context when the rule is needed?
#
#   "When the conversation is summarized to free context, Claude Code re-attaches
#    the most recent invocation of each skill after the summary, keeping the
#    first 5,000 tokens of each. Re-attached skills share a combined budget of
#    25,000 tokens."
#    — code.claude.com/docs/en/skills#skill-content-lifecycle, consultado 2026-08-10
#
# A codebase cleanup is a long session by nature, so auto-compaction is the
# expected case and not the exception. Measured before this section existed, on
# a 44.801-byte SKILL.md: the level table survived, and the block holding "a red
# gate means rollback, not repair" and "never force push, never commit on main"
# sat at byte 40.732 — past any plausible reading of the cut. The level went on
# being announced; what disappeared was what the level obliges.
#
# The budget is in BYTES because this suite has no tokenizer. The conversion used
# to be a guess — 3 bytes per token, described here as pessimistic — and the guess
# was wrong in the dangerous direction. The host itself publishes the number:
#
#   $ claude plugin details codebase-cleanup
#     codebase-cleanup   ~370 always-on   ~15.7k on-invoke
#
# 44.801 bytes over ~15.700 tokens is 2,854 bytes per token for this file, so the
# old 15.000-byte budget was 5.257 tokens — above the very cut it was defending.
# A check that is generous with a safety margin is not a safety margin.
#
# 14.000 bytes is 4.905 tokens at the measured rate, which keeps the margin on the
# side that costs nothing: a rule that fits here fits under any tokenizer, and one
# that does not may still fit under a kinder one, so the check errs early rather
# than wrong. Re-measure with the command above when the file changes shape — a
# rate derived from one file is not a constant of nature.
SURVIVAL_BUDGET=14000   # 5.000 tokens x 2,854 bytes/token, measured by the host

byte_offset() { # byte_offset <file> <literal> — bytes before the first match
  LC_ALL=C grep -abo -F -- "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1
}

# Proven on a fixture first: an offset finder that returns empty for everything
# would make every rule below read as missing, and one that returns 0 would make
# them all pass. Both failure modes are silent on the real file.
printf 'aaaa\nbbbb\n' > "$SELFTMP/off.md"
check "byte offset finder reports the real position" \
      "$([[ $(byte_offset "$SELFTMP/off.md" 'bbbb') == 5 ]] && echo 0 || echo 1)" \
      "read [$(byte_offset "$SELFTMP/off.md" 'bbbb')], expected 5"
check "byte offset finder is empty for a string that is not there" \
      "$([[ -z $(byte_offset "$SELFTMP/off.md" 'cccc') ]] && echo 0 || echo 1)" \
      "an absent string must return nothing, so the floor below can catch it"

# One entry per rule that decides what the skill may destroy. Every one of them
# is already asserted somewhere else in this file as TEXT; here the claim is
# about POSITION, and the two together are what make the rule reliable.
while IFS='|' read -r label needle; do
  [[ -n $label ]] || continue
  off=$(byte_offset SKILL.md "$needle")
  # Floor: an anchor that no longer matches would report an empty offset, and
  # `[[ "" -lt 15000 ]]` is true in bash. The rule would pass by disappearing.
  check "SKILL.md still carries the rule [$label]" \
        "$([[ -n $off ]] && echo 0 || echo 1)" \
        "anchor not found: [$needle] — section 16 asserts this rule exists; if it
was reworded, this anchor has to be rewritten with it"
  check "[$label] is inside the budget that survives a compaction" \
        "$([[ -n $off && $off -lt $SURVIVAL_BUDGET ]] && echo 0 || echo 1)" \
        "at byte ${off:-?} of SKILL.md, past the ${SURVIVAL_BUDGET}-byte survival
budget. After an auto-compaction Claude Code re-attaches only the first 5.000
tokens of the skill, so this rule would be absent from the context of a long
run — which is the only kind of run this skill has."
done <<'AUTHORITY_RULES'
rollback|git restore --staged --worktree .
staging by pathspec|git add -- <paths this step produced or edited>
the level table|A partial net, or no test file in the stack
stack caps override GREEN|Stack caps in
a red gate rolls back|A red gate means rollback, not repair
never force push, never commit on main|Never force push, never commit on main
never merge two steps|Never merge two steps
the scheduled checkpoints|two scheduled checkpoints
AUTHORITY_RULES

echo "----"
echo "$((total-failures))/$total invariants held"
[[ $failures -eq 0 ]]
