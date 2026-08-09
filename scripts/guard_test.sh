#!/usr/bin/env bash
# Executable proof of the PreToolUse guard: which commands it blocks, when it
# is awake, and — the half that matters more — everything it must let through.
# Each case builds its own throwaway repo inside a mktemp -d, so the suite
# never reads or writes anything outside of it: no user config, no system
# config, no repo of yours. Same isolation the rollback suite uses.
# Usage: guard_test.sh   (exit 0 = every case passed)
set -u

GUARD="$(cd "$(dirname "$0")" && pwd)/guard.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export GIT_CONFIG_NOSYSTEM=1

failures=0
total=0
RC=0
STDERR=""

g() { # g <repo> <git args...> — git confined to <repo>, throwaway identity
  local repo=$1; shift
  git -C "$repo" -c user.name=t -c user.email=t@example.invalid \
      -c init.defaultBranch=main "$@"
}

new_repo() { # new_repo <name> [branch] — repo with one commit, echoes the path
  local repo="$TMP/$1"
  mkdir -p "$repo"
  g "$repo" init -q
  printf 'x\n' > "$repo/a.txt"
  g "$repo" add -- a.txt
  g "$repo" commit -qm baseline
  [[ ${2:-} ]] && g "$repo" checkout -q -b "$2"
  printf '%s' "$repo"
}

# json <command> — the hook payload Claude Code puts on the guard's stdin.
# The command goes through a JSON escaper so a case can carry quotes and
# backslashes without hand-rolling the encoding.
json() {
  printf '%s' "$1" | perl -0777 -ne '
    s/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g;
    print "{\"session_id\":\"s\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$_\",\"description\":\"d\"}}";
  '
}

# run_guard <repo> <command> — sets RC and STDERR. Deliberately not a command
# substitution: $( ) runs the function in a subshell, where an assignment to
# STDERR dies with it, and every "blocked" case would then read an empty
# stderr and pass or fail for the wrong reason.
run_guard() {
  local repo=$1 cmd=$2 out
  out="$TMP/stderr.$$"
  ( cd "$repo" && json "$cmd" | "${BASH:-bash}" "$GUARD" 2>"$out" >/dev/null )
  RC=$?
  STDERR=$(cat "$out")
}

blocks() { # blocks <label> <repo> <command>
  local rc; run_guard "$2" "$3"; rc=$RC
  total=$((total+1))
  if [[ $rc -eq 2 && -n $STDERR ]]; then
    echo "ok: blocks $1"
  else
    failures=$((failures+1))
    echo "FAILED: blocks $1"
    echo "    exit $rc (wanted 2), stderr: ${STDERR:-<empty>}"
  fi
}

allows() { # allows <label> <repo> <command>
  local rc; run_guard "$2" "$3"; rc=$RC
  total=$((total+1))
  if [[ $rc -eq 0 && -z $STDERR ]]; then
    echo "ok: allows $1"
  else
    failures=$((failures+1))
    echo "FAILED: allows $1"
    echo "    exit $rc (wanted 0), stderr: ${STDERR:-<empty>}"
  fi
}

# 1. The five prohibitions, inside a cleanup run. -----------------------------
R=$(new_repo five cleanup/20260809)
blocks "git reset --hard"            "$R" "git reset --hard HEAD~1"
blocks "reset with the flag last"    "$R" "git reset HEAD~1 --hard"
blocks "git clean"                   "$R" "git clean -fd"
blocks "git push"                    "$R" "git push origin cleanup/20260809"
blocks "git push --force"            "$R" "git push --force"
blocks "git add -A"                  "$R" "git add -A"
blocks "git add --all"               "$R" "git add --all"
blocks "git add ."                   "$R" "git add ."

# The guard reads past git's own options: a -C somewhere else is still a reset.
blocks "reset behind -C"             "$R" "git -C sub reset --hard"
blocks "reset behind -c"             "$R" "git -c core.pager=cat reset --hard"

# A whole line is one Bash call: the second half counts too.
blocks "second half of a chain"      "$R" "npm test && git add -A"
blocks "third of three"              "$R" "echo a; echo b; git clean -xdf"

# 2. Everything the protocol actually runs. -----------------------------------
# This half is the one that keeps the guard from killing a legitimate run.
allows "the canonical rollback" "$R" "git restore --staged --worktree ."
allows "staging by pathspec"    "$R" "git add -- src/a.ts src/b.ts"
allows "git revert"             "$R" "git revert abc1234"
allows "git commit on cleanup/" "$R" "git commit -m 'chore: remove unused deps'"
allows "git mv"                 "$R" "git mv src/a.ts src/b/a.ts"
allows "git stash push -u"      "$R" "git stash push -u"
allows "git log"                "$R" "git log --oneline"
allows "git status"             "$R" "git status --porcelain"
allows "git checkout -b"        "$R" "git checkout -b cleanup/20260810"

# Neighbours that merely start with the same letters are not the command.
allows "git cleanup-branch"     "$R" "git cleanup-branch"
allows "git add -Applies"       "$R" "git add -Applies"
allows "a push in prose"        "$R" "echo 'do not git push'"
allows "npm run reset"          "$R" "npm run reset -- --hard"

# 3. When the guard is awake. -------------------------------------------------
# Outside a run these commands are ordinary work, and a plugin's hooks fire in
# every session that enables it.
M=$(new_repo asleep)
allows "reset on main, no run"  "$M" "git reset --hard"
allows "push on main, no run"   "$M" "git push"
allows "add -A on main, no run" "$M" "git add -A"

# An untracked log is a run in flight (a RED one, or one before its first
# commit): the guard wakes up even though the branch is not a cleanup/ one.
touch "$M/CLEANUP_PROGRESS.md"
blocks "reset with an untracked log" "$M" "git reset --hard"
blocks "commit on main"              "$M" "git commit -m x"

# Once that log is tracked it is history — a cleanup that got merged — and the
# guard has to go back to sleep. Keying on the file's mere existence would
# leave it awake on main forever after the first merge.
g "$M" add -- CLEANUP_PROGRESS.md
g "$M" commit -qm "chore: log"
allows "reset with a tracked log" "$M" "git reset --hard"
allows "push after the merge"     "$M" "git push"

# On a cleanup branch, commit is allowed; on main it is not. Same command.
allows "commit on the cleanup branch" "$R" "git commit -m x"

# 4. Fail open. ---------------------------------------------------------------
# A guard that blocks by accident is worse than no guard: the skill aborts the
# pipeline on some blocked commands, so a false positive kills a real run.
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"
allows "outside a git repo" "$NOGIT" "git push"

malformed() { # malformed <label> <payload>
  local rc out; out="$TMP/m.$$"
  ( cd "$R" && printf '%s' "$2" | "${BASH:-bash}" "$GUARD" 2>"$out" >/dev/null )
  rc=$?
  total=$((total+1))
  if [[ $rc -eq 0 && ! -s $out ]]; then
    echo "ok: fails open on $1"
  else
    failures=$((failures+1))
    echo "FAILED: fails open on $1"
    echo "    exit $rc (wanted 0), stderr: $(cat "$out")"
  fi
}
malformed "empty stdin"        ""
malformed "non-JSON stdin"     "not json at all"
malformed "no command field"   '{"tool_name":"Bash","tool_input":{"description":"d"}}'
malformed "no tool_input"      '{"tool_name":"Bash"}'
malformed "empty command"      '{"tool_name":"Bash","tool_input":{"command":""}}'

# 5. The exit codes are the two the hook contract defines. --------------------
# Exit 1 would not block: Claude Code reads it as a non-fatal error and runs
# the command anyway. So a guard that ever exits 1 is a guard that fails
# silently, and the script must never produce one.
codes=$(grep -o -E '(^|[^a-zA-Z0-9_])exit [0-9]+' "$GUARD" | grep -o -E '[0-9]+$' | sort -u | tr '\n' ' ')
total=$((total+1))
if [[ $(printf '%s' "$codes" | tr -d ' ') == "02" ]]; then
  echo "ok: guard.sh only exits 0 or 2"
else
  failures=$((failures+1))
  echo "FAILED: guard.sh only exits 0 or 2"
  echo "    exit codes found: $codes"
fi

# 6. A command with quotes survives the JSON round trip. ----------------------
blocks "quoted arg in a blocked chain" "$R" 'git commit -m "a \"quoted\" message" && git push'
allows "quotes in an allowed command"  "$R" 'git commit -m "a \"quoted\" message"'

echo "----"
if [[ $failures -eq 0 ]]; then
  echo "$total/$total guard cases passed"
  exit 0
fi
echo "$failures of $total guard cases FAILED"
exit 1
