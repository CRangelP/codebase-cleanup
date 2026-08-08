#!/usr/bin/env bash
# Executable proof of the rollback protocol used by the skill:
# what `git restore --staged --worktree .` really brings back, and what it
# destroys. Each case builds its own throwaway repo inside a mktemp -d, so the
# suite never reads or writes anything outside of it — no user config, no
# system config, no repo of yours.
# Usage: rollback_test.sh   (exit 0 = all five properties hold)
set -u

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Isolation: git must not see the user's identity, aliases or hooks.
# The identity needed to commit is passed per command via -c, never written.
export HOME="$TMP"
export GIT_CONFIG_NOSYSTEM=1

failures=0
total=0
CASE=""
CASE_OK=1
CASE_MSG=""

g() { # g <repo> <git args...> — git confined to <repo>, throwaway identity
  local repo=$1; shift
  git -C "$repo" -c user.name=t -c user.email=t@example.invalid \
      -c init.defaultBranch=main "$@"
}

new_repo() { # new_repo <name> — fresh repo with a 2-file baseline, echoes path
  local repo="$TMP/$1"
  mkdir -p "$repo"
  g "$repo" init -q
  printf 'a1\n' > "$repo/a.txt"
  printf 'b1\n' > "$repo/b.txt"
  g "$repo" add -A
  g "$repo" commit -qm baseline
  printf '%s' "$repo"
}

rollback() { # rollback <repo> — the exact command the skill documents
  g "$1" restore --staged --worktree .
}

begin() { CASE=$1; CASE_OK=1; CASE_MSG=""; }

note_fail() {
  CASE_OK=0
  CASE_MSG="$CASE_MSG
    $1"
}

end() {
  total=$((total+1))
  if [[ $CASE_OK -eq 1 ]]; then echo "ok: $CASE"
  else
    failures=$((failures+1))
    echo "FAILED: $CASE"
    printf '%s\n' "$CASE_MSG" | sed '/^$/d'
  fi
}

assert_content() { # assert_content <path> <expected>
  if [[ ! -f $1 ]]; then note_fail "missing file: $1"; return 0; fi
  local got; got=$(cat "$1")
  [[ $got == "$2" ]] || note_fail "content of $1: got '$got', want '$2'"
  return 0
}

assert_exists() { # assert_exists <path>
  [[ -e $1 ]] || note_fail "should still exist: $1"
  return 0
}

assert_absent() { # assert_absent <path>
  [[ -e $1 ]] && note_fail "should no longer exist: $1"
  return 0
}

assert_status() { # assert_status <repo> <expected porcelain output>
  local st; st=$(g "$1" status --porcelain)
  [[ $st == "$2" ]] || note_fail "git status --porcelain: got '$st', want '$2'"
  return 0
}

assert_status_has() { # assert_status_has <repo> <expected porcelain line>
  # For cases where the property is one entry, not the whole report: an extra
  # unrelated line is noise, and demanding equality would make the test brittle
  # for no gain. Where emptiness itself is the property, assert_status stays.
  local st; st=$(g "$1" status --porcelain)
  printf '%s\n' "$st" | grep -qx -F -- "$2" ||
    note_fail "git status --porcelain: got '$st', want a line '$2'"
  return 0
}

# 1. A staged deletion is fully undone. -------------------------------------
begin "staged deletion comes back"
REPO=$(new_repo staged-deletion)
rm "$REPO/a.txt"
g "$REPO" add -A
rollback "$REPO"
assert_content "$REPO/a.txt" a1
assert_content "$REPO/b.txt" b1
assert_status "$REPO" ""
end

# 2. A staged new file is wiped — this is why artifacts are committed early. -
begin "staged new file is wiped"
REPO=$(new_repo staged-new-file)
printf 'c1\n' > "$REPO/c.txt"
g "$REPO" add -A
rollback "$REPO"
assert_absent "$REPO/c.txt"
assert_content "$REPO/a.txt" a1
assert_status "$REPO" ""
end

# 3. An untracked new file survives — this is why `git clean` stays banned. --
begin "untracked new file survives"
REPO=$(new_repo untracked-new-file)
printf 'c1\n' > "$REPO/c.txt"
rollback "$REPO"
assert_exists "$REPO/c.txt"
assert_content "$REPO/c.txt" c1
assert_status_has "$REPO" "?? c.txt"
end

# 4. A rename is undone on both ends. ---------------------------------------
begin "rename is undone on both ends"
REPO=$(new_repo rename)
g "$REPO" mv a.txt renamed.txt
rollback "$REPO"
assert_content "$REPO/a.txt" a1
assert_absent "$REPO/renamed.txt"
assert_status "$REPO" ""
end

# 5. An uncommitted edit to a tracked file is LOST. -------------------------
#    The rollback cannot tell the user's work in progress from the skill's:
#    it resets the file to HEAD. That is why Step 0 stops hard on a dirty tree.
begin "uncommitted edit to tracked file is lost"
REPO=$(new_repo uncommitted-edit)
printf 'work in progress\n' > "$REPO/a.txt"
rollback "$REPO"
assert_content "$REPO/a.txt" a1
assert_status "$REPO" ""
end

echo "----"
echo "$((total-failures))/$total properties held"
[[ $failures -eq 0 ]]
