#!/usr/bin/env bash
# PreToolUse/Bash guard for the cleanup protocol.
#
# The skill states five prohibitions in prose — no `git reset --hard`, no
# `git clean`, no push, no commit on main, no whole-tree staging. Prose is
# advice a model can miss; this script is the same five rules as mechanism.
# It is the plugin half of the rule the skill already has for the other
# direction: a blocked command is environment policy, not an obstacle.
#
# Contract (docs.claude.com/en/docs/claude-code/hooks): the hook JSON arrives on
# stdin, the command under judgement is .tool_input.command, exit 2 blocks the
# call and hands stderr back to the model. Exit 1 would NOT block — the hook
# contract reads it as a non-fatal error and lets the command through — so the
# only two exits here are 0 and 2.
#
# Fail open, always. A guard that blocks by accident is worse than no guard:
# the skill aborts the pipeline on some blocked commands, so a false positive
# kills a legitimate run. Anything unclear — no repo, no JSON, no command,
# no git — exits 0 and says nothing.
#
# Usage: guard.sh   (stdin: hook JSON · exit 0 = no decision · 2 = blocked)
set -uo pipefail

# --- When the guard is awake -------------------------------------------------
# Only inside a cleanup run, because these commands are perfectly normal
# everywhere else and a plugin's hooks run for every session that enables it.
# Two pieces of evidence, both created by the skill itself:
#
#   * HEAD is a cleanup/ branch — the run is in flight;
#   * an *untracked* CLEANUP_PROGRESS.md — a RED run, or a run that has not
#     committed its log yet, both of which happen before the branch exists.
#
# Untracked is the whole point of the second one. A tracked log on a normal
# branch is a finished cleanup that got merged, not a live run: keying on mere
# existence would leave the guard awake on main forever after the first merge.
inside_run() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
  case $branch in cleanup/*) return 0 ;; esac
  git rev-parse --show-toplevel >/dev/null 2>&1 || return 1
  local root; root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [[ -f $root/CLEANUP_PROGRESS.md ]] || return 1
  # tracked? then it is history, not a run.
  git -C "$root" ls-files --error-unmatch -- CLEANUP_PROGRESS.md >/dev/null 2>&1 && return 1
  return 0
}

on_trunk() { # is HEAD on the branch nobody may commit to?
  local b; b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
  case $b in main|master) return 0 ;; *) return 1 ;; esac
}

# --- Reading the command out of the hook JSON --------------------------------
# perl and not jq: the docs' examples use jq, this repo cannot assume it (the
# suites run on a stock macOS with bash 3.2, and gate.sh already reaches for
# perl for its watchdog). Two passes on purpose — the first lifts the raw
# string out of tool_input, the second unescapes it. Doing both at once is how
# a \\" inside the command turns into a broken quote.
extract_command() {
  perl -0777 -ne '
    exit 0 unless /"tool_input"\s*:\s*\{(.*?)\}\s*[,}]/s;
    my $t = $1;
    exit 0 unless $t =~ /"command"\s*:\s*"((?:[^"\\]|\\.)*)"/s;
    my $c = $1;
    $c =~ s/\\n/\n/g; $c =~ s/\\t/\t/g; $c =~ s/\\r//g;
    $c =~ s/\\(.)/$1/g;
    print $c;
  ' 2>/dev/null
}

deny() { # deny <what> <why>
  printf '[codebase-cleanup] blocked: %s\n%s\n' "$1" "$2" >&2
  exit 2
}

inside_run || exit 0

cmd=$(extract_command)
[[ -n ${cmd:-} ]] || exit 0

# --- One segment at a time ---------------------------------------------------
# A single Bash call carries a whole line: `git add -A && git commit -m x`.
# Judging the string as a whole would miss the second half, so the line is cut
# on the shell separators first and every piece is read on its own.
segments=$(printf '%s' "$cmd" | tr '\n;|&' '\012\012\012\012')

while IFS= read -r seg; do
  # shellcheck disable=SC2086
  set -- $seg
  [[ $# -gt 0 ]] || continue
  [[ $1 == git ]] || continue
  shift

  # Skip git's own options so `git -C dir reset --hard` reads like `git reset`.
  while [[ $# -gt 0 ]]; do
    case $1 in
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path)
        shift; [[ $# -gt 0 ]] && shift ;;
      --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*|-p|--paginate|--no-pager|--literal-pathspecs|--no-optional-locks)
        shift ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [[ $# -gt 0 ]] || continue

  sub=$1; shift
  case $sub in
    reset)
      for a in "$@"; do
        [[ $a == --hard ]] && deny "git reset --hard" \
          "The rollback of this protocol is \`git restore --staged --worktree .\`, which
leaves untracked files alone. A hard reset would take work that was in the
tree before the cleanup started."
      done
      ;;
    clean)
      deny "git clean" \
        "git clean wipes untracked files that must survive the run — tool output,
caches, local env files that never belonged to this cleanup. Nothing in the
protocol needs it."
      ;;
    push)
      deny "git push" \
        "This skill never pushes. The cleanup branch is handed over locally and
merging it is the user's decision, on their own schedule."
      ;;
    commit)
      on_trunk && deny "git commit on $(git rev-parse --abbrev-ref HEAD 2>/dev/null)" \
        "All the work belongs on the cleanup/ branch. Create it (or switch back to
it) and commit there."
      ;;
    add)
      for a in "$@"; do
        case $a in
          -A|--all|--no-ignore-removal|.)
            deny "git add $a" \
              "Stage by pathspec: \`git add -- <the paths this step touched>\`. Whole-tree
staging is what swallows a draft of the user's into the category's commit, and
what makes the commit stop being a description of one category."
            ;;
        esac
      done
      ;;
  esac
done <<EOF
$segments
EOF

exit 0
