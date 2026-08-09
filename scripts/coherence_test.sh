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
  # references/ and agents/ get the same treatment: both ship inside the
  # plugin, both are read by name at runtime, and a file missing from the tree
  # is a file the reader does not know is there.
  for path in references/*.md agents/*.md; do
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
        # A doc in the tree lives in references/ or in agents/. Naming the two
        # directories beats accepting either silently: a file that is in
        # neither is listed and shipped by nobody.
        if [[ -f references/$name ]]; then
          pass "references/$name of the tree of $readme exists on disk"
        elif [[ -f agents/$name ]]; then
          pass "agents/$name of the tree of $readme exists on disk"
        else
          fail "$name of the tree of $readme exists on disk" \
               "listed but there is no references/$name nor agents/$name"
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
for marker in \
  'exit 0/1/2/3/4' \
  'Exit 124' \
  'tests/*.rs' \
  '#[test]' \
  'src/test' \
  'test:unit' \
  'test:e2e' \
  'checks=typecheck,test' \
  'Go' \
  '.NET' \
  'Rust' \
  'Maven' \
  'Gradle' \
  'pytest' \
  'Exit 137' \
  'passWithNoTests' \
  '_spec.rb'
do
  for f in README.md README.en.md; do
    check "$f carries normative marker [$marker]" \
          "$(grep -q -F -- "$marker" "$f" 2>/dev/null && echo 0 || echo 1)" \
          "missing [$marker]"
  done
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
# may not declare hooks, mcpServers or permissionMode — Claude Code refuses the
# agent outright — so the ban is checked here rather than discovered on a user's
# machine.
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
        "plugin agents support none of hooks, mcpServers, permissionMode: $banned"

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

echo "----"
echo "$((total-failures))/$total invariants held"
[[ $failures -eq 0 ]]
