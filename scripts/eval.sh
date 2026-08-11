#!/usr/bin/env bash
# eval.sh — does the model, reading this skill, behave like the protocol says?
#
# Every other suite in this repo proves TEXT (coherence), SCRIPTS (gate, guard,
# rollback, metrics) or that those two fail when they should (mutation). None of
# them touches the product: what a model does when it reads SKILL.md. This one
# runs the real model against a real fixture and grades the STATE OF THE
# REPOSITORY afterwards.
#
# Two decisions worth stating, because they are what keeps this honest.
#
# The graders are deterministic. Not an LLM judging prose — the same reason the
# protocol refuses LLM judgment in phase 1.5: a judge that accepts anything is
# worse than no judge. Every question here is answered by git and the file
# system. "Is there a cleanup branch", "does the log name a level", "did the
# entry point survive", "is the original commit still reachable".
#
# Every case runs twice: with the skill installed in the fixture, and without.
# The second arm is not decoration. A grader that passes on both is measuring
# the model's good sense, not the skill — and the difference between the two is
# the only thing that can be attributed to this repository. That is the same
# rule mutation_test.sh has enforced since #37: a verdict with no attributable
# cause is not evidence.
#
# NOT part of scripts/test.sh, on purpose: each case is a paid model run of a
# couple of minutes. Run it before cutting a release, or when SKILL.md changes
# in a way that could change behaviour.
#
# And a warning this file has to carry, because it is the one suite here that
# does not answer the same way twice: these graders are stochastic. A run can
# end at max_turns with the log half-written, and a grader that reads that log
# then reports red for a reason that has nothing to do with the skill. Observed
# already: `the log names the YELLOW level` failed on a run whose only change
# was in metrics.sh, which cannot affect the level. Read a single red here as a
# question, not as a verdict — re-run it before treating it as a defect. The
# other suites in this repo are the opposite by construction, and mixing the two
# kinds of evidence is how a flaky test teaches people to ignore failures.
#
# The fixtures ship knip vendored, and that is not a convenience. Phase 1 runs
# `npx knip@6.32.0`; with no local install that command needs the registry, and
# a download inside a run capped by --max-turns is either dead time or a red
# with nothing to do with the skill — the same class of noise this file already
# refuses to mix with the deterministic suites. The vendored tree is built once,
# outside the timed run, and copied per fixture.
#
# Usage:  bash scripts/eval.sh [case-name]
# Env:    EVAL_TURNS (default 20), EVAL_KEEP=1 to keep fixtures,
#         EVAL_FIXTURE_ROOT to move the fixture tree (the vendored knip lives
#         under it, in .vendor/, and survives between runs).
set -uo pipefail

SKILL_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TURNS=${EVAL_TURNS:-20}
ONLY=${1:-}
pass=0; fail=0; skipped=0

# Fixtures live under $HOME and not in $TMPDIR: a project-scoped skill in
# `.claude/skills/` was not picked up from a macOS /var/folders path during the
# first run of this suite, and a fixture the host quietly ignores would make
# every case fail for a reason that has nothing to do with the skill.
FIXROOT=${EVAL_FIXTURE_ROOT:-$HOME/.cache/codebase-cleanup-eval}

# Pinned to the version the protocol pins (SKILL.md 1.1: "never bare `npx knip`").
# A fixture running a different knip than the one the skill names would grade a
# tool the protocol never asked for.
KNIP_VERSION=6.32.0
VENDOR="$FIXROOT/.vendor/knip-$KNIP_VERSION"

command -v claude >/dev/null 2>&1 || { echo "eval: no \`claude\` on PATH — skipping" >&2; exit 0; }

say()  { printf '%s\n' "$*"; }
ok()   { pass=$((pass+1)); say "ok:     $1"; }
bad()  { fail=$((fail+1)); say "FAILED: $1"; say "        $2"; }

# ---------------------------------------------------------------------------
# vendor_knip — a node_modules tree carrying knip, built once and copied per
# fixture. Three measurements decided this shape, and each one shows up in the
# fixture below:
#
#   1. Without a local install the command the protocol runs needs the registry:
#      with a cold npm cache and npm_config_offline, `npx knip@6.32.0` fails
#      ENOTCACHED. With the tree in place, the same command answers 6.32.0.
#   2. `npm install` — which the deps category runs to re-resolve after deleting
#      a dependency — PRUNES what node_modules has and package.json does not
#      declare: 20 packages down to 3, the vendored knip among them. So the
#      fixture DECLARES knip instead of smuggling it in.
#   3. Declaring it does not hand the run a fake target: knip does not report
#      itself. On this fixture it lists `src/dead.ts`, and an unused dependency
#      when one is present, never the knip devDependency.
#
# Fails closed. A missing vendor tree is not a degraded run, it is a run whose
# phase 1 either stalls on a download or goes red for a reason that is not the
# skill — and this suite costs minutes and money per case.
vendor_knip() {
  if [[ -x $VENDOR/node_modules/.bin/knip ]]; then
    local have
    have=$(node -p "require('$VENDOR/node_modules/knip/package.json').version" 2>/dev/null)
    [[ $have == "$KNIP_VERSION" ]] && return 0
    rm -rf "$VENDOR"
  fi
  say "eval: vendoring knip@$KNIP_VERSION into $VENDOR (once, needs the network)"
  mkdir -p "$VENDOR"
  printf '{"name":"knip-vendor","version":"1.0.0","private":true}\n' > "$VENDOR/package.json"
  ( cd "$VENDOR" && npm i -D "knip@$KNIP_VERSION" --no-audit --no-fund ) >/dev/null 2>&1
  if [[ ! -x $VENDOR/node_modules/.bin/knip ]]; then
    echo "eval: could not vendor knip@$KNIP_VERSION — run this once with network access" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# fixture <name> <arm>  — a repository to clean. arm=with installs the skill.
fixture() {
  local dir="$FIXROOT/$1-$2"
  rm -rf "$dir"; mkdir -p "$dir/src"
  cat > "$dir/package.json" <<EOF
{
  "name": "eval-fixture",
  "version": "1.0.0",
  "main": "src/index.ts",
  "scripts": { "typecheck": "echo ok", "test": "echo ok" },
  "devDependencies": { "knip": "$KNIP_VERSION" }
}
EOF
  printf 'export const used = 1\n' > "$dir/src/index.ts"
  printf 'export const orphan = 2\n' > "$dir/src/dead.ts"
  cp -R "$VENDOR/node_modules" "$dir/node_modules"
  if [[ $2 == with ]]; then
    mkdir -p "$dir/.claude/skills"
    # A copy, not a symlink: the run must see the same tree a user would get,
    # and .git is dropped so the fixture's own history stays readable.
    cp -R "$SKILL_ROOT" "$dir/.claude/skills/codebase-cleanup"
    rm -rf "$dir/.claude/skills/codebase-cleanup/.git"
  fi
  # A real project with node_modules has it ignored, and the protocol reads that
  # state: "confirm the repo ignores node_modules before the deps category — a
  # global .gitignore does not travel with the repo". A fixture that tracked the
  # vendored tree would also hand `git add -A` twenty megabytes at baseline.
  printf 'node_modules/\n' > "$dir/.gitignore"
  git -C "$dir" init -q
  git -C "$dir" -c user.email=eval@local -c user.name=eval add -A
  git -C "$dir" -c user.email=eval@local -c user.name=eval commit -qm baseline
  printf '%s' "$dir"
}

run_arm() { # run_arm <dir> <prompt> — leaves the transcript in $LAST_OUT
  LAST_OUT=$(cd "$1" && claude -p "$2" --max-turns "$TURNS" 2>&1)
}

# ---------------------------------------------------------------------------
# Graders. Each answers one question about the repository, from git alone.
has_cleanup_branch() { git -C "$1" branch --format='%(refname:short)' | grep -q '^cleanup/'; }
# `^{commit}` is not decoration: `rev-parse --verify` echoes any well-formed
# 40-hex string back without checking that the object exists, so the floor below
# caught this grader passing a sha of forty zeros. Peeling to a commit is what
# makes the question "is the rollback target still there" instead of "does this
# look like a sha".
baseline_reachable() { git -C "$1" rev-parse --verify -q "$2^{commit}" >/dev/null; }
file_exists()        { [[ -e $1/$2 ]]; }
log_names_level()    { grep -qiE 'YELLOW' "$1/CLEANUP_PROGRESS.md" 2>/dev/null; }

# A commit that carries both a source change and the progress log is two steps
# merged into one, and the protocol's whole revert story depends on them being
# separate: reverting a category must not take the log with it.
commits_are_atomic() {
  local sha
  for sha in $(git -C "$1" log --format=%H "$2..HEAD" 2>/dev/null); do
    local files; files=$(git -C "$1" show --name-only --format= "$sha")
    if printf '%s\n' "$files" | grep -q '^src/' && printf '%s\n' "$files" | grep -q 'CLEANUP_PROGRESS.md'; then
      return 1
    fi
  done
  return 0
}

# The measurement the tool takes of itself. This is the defect this suite found
# on its first run: with the skill installed inside the fixture, the Step 0
# baseline reported files=12 loc=3270 for a repository whose source was two
# one-line files, because it measured the protocol's own scripts.
baseline_excludes_tooling() {
  ! grep -qE 'files=(1[0-9]|[2-9][0-9])' "$1/CLEANUP_PROGRESS.md" 2>/dev/null
}

# The phase ceiling. YELLOW runs phase 1 and stops (SKILL.md, the level table:
# "Does **not** run phase 2, phase 3 or phase 4; reports and stops"), so the
# question is whether a later phase left a mark. Each grader below is anchored
# on the ARTIFACT the phase produces and never on the prose of the answer, for
# the same reason the graders above read git: a run that writes "I stopped after
# phase 1" and moved a file has told the truth about its intention and nothing
# about the repository, and only git knows which one happened.
#
# They ask `--all --not <base>` instead of `<base>..HEAD`, and that is a
# deliberate difference from the atomicity grader above. A grader that asserts
# an ABSENCE and reads only HEAD comes back empty — and therefore green —
# whenever the run ends with HEAD off the cleanup branch, so the one shape that
# would hide a violation is also the shape that makes it invisible. Every commit
# the run wrote is reachable from some ref and not from the baseline, so this
# form cannot be satisfied by a wandering HEAD. There is a floor for exactly
# that below.
run_commit_subjects() { git -C "$1" log --format=%s --all --not "$2" 2>/dev/null; }

# Phase 3 moves files with `git mv` and never with rm+create ("git mv preserves
# history"), so a rename is the signature of phase 3 and `--diff-filter=R` is
# how that question is put to git.
no_phase_3_renames() {
  [[ -z $(git -C "$1" log --diff-filter=R --name-only --format= --all --not "$2" 2>/dev/null) ]]
}

# Phase 4 fixes the subject of every operation it lands: one operation per
# commit, `refactor(<operation-id>): <what>`. No other phase writes that prefix.
no_phase_4_refactors() {
  ! run_commit_subjects "$1" "$2" | LC_ALL=C grep -q '^refactor('
}

# Dead exports is the exclusion that is easiest to lose, because it happens
# inside the phase that IS running: YELLOW does phase 1 with deps and orphan
# files only. The subject is fixed by the category list, "chore: remove dead
# exports", so the commit is the artifact.
no_dead_exports_commit() {
  ! run_commit_subjects "$1" "$2" | LC_ALL=C grep -qi '^chore: remove dead exports'
}

# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Floors for the graders themselves. Each one above answers a question about a
# repository; a grader stuck on "yes" would make the whole suite green while
# measuring nothing, and that failure is silent — the run costs minutes and
# money, so nobody re-reads it. These fixtures are synthetic and free.
self_check() {
  local t; t=$(mktemp -d)
  local r="$t/r"; mkdir -p "$r/src"
  git -C "$r" init -q
  printf 'x\n' > "$r/src/index.ts"
  git -C "$r" -c user.email=e@l -c user.name=e add -A
  git -C "$r" -c user.email=e@l -c user.name=e commit -qm base
  local base; base=$(git -C "$r" rev-parse HEAD)

  has_cleanup_branch "$r" && bad "floor: no cleanup branch reads as absent" "reported one on a repo that has none" || ok "floor: no cleanup branch reads as absent"
  git -C "$r" checkout -q -b cleanup/19700101
  has_cleanup_branch "$r" && ok "floor: a cleanup branch is detected" || bad "floor: a cleanup branch is detected" "missed a branch named cleanup/19700101"

  file_exists "$r" src/index.ts && ok "floor: an existing file reads as present" || bad "floor: an existing file reads as present" "missed src/index.ts"
  file_exists "$r" src/nope.ts  && bad "floor: a missing file reads as absent" "reported a file that is not there" || ok "floor: a missing file reads as absent"

  log_names_level "$r" && bad "floor: a missing log does not name a level" "found YELLOW with no CLEANUP_PROGRESS.md" || ok "floor: a missing log does not name a level"
  printf 'Level: YELLOW\n' > "$r/CLEANUP_PROGRESS.md"
  log_names_level "$r" && ok "floor: a log naming YELLOW is detected" || bad "floor: a log naming YELLOW is detected" "missed the level in the log"

  # atomicity: one commit touching src/ and the log together has to fail.
  git -C "$r" -c user.email=e@l -c user.name=e add -A
  git -C "$r" -c user.email=e@l -c user.name=e commit -qm "log only"
  commits_are_atomic "$r" "$base" && ok "floor: separate commits read as atomic" || bad "floor: separate commits read as atomic" "flagged a log-only commit"
  printf 'y\n' >> "$r/src/index.ts"; printf 'more\n' >> "$r/CLEANUP_PROGRESS.md"
  git -C "$r" -c user.email=e@l -c user.name=e add -A
  git -C "$r" -c user.email=e@l -c user.name=e commit -qm "source and log together"
  commits_are_atomic "$r" "$base" && bad "floor: a merged commit is caught" "a commit carrying src/ and the log together passed" || ok "floor: a merged commit is caught"

  baseline_reachable "$r" "$base" && ok "floor: a live commit is reachable" || bad "floor: a live commit is reachable" "could not resolve $base"
  baseline_reachable "$r" "0000000000000000000000000000000000000000" && bad "floor: an absent commit is unreachable" "resolved a sha that does not exist" || ok "floor: an absent commit is unreachable"

  # The vendored knip, proved where it actually matters: cold npm cache, no
  # network. Without this pair, "vendored" would mean "this machine happened to
  # have knip in its npm cache", which is a property of the laptop and not of
  # this repository — and the case would only discover it on a plane.
  if command -v npx >/dev/null 2>&1; then
    local cold="$t/cold"
    local vend="$t/vendored"; mkdir -p "$vend"
    printf '{"name":"v","version":"1.0.0","private":true}\n' > "$vend/package.json"
    cp -R "$VENDOR/node_modules" "$vend/node_modules"
    if ( cd "$vend" && npm_config_cache="$cold" npm_config_offline=true npx "knip@$KNIP_VERSION" --version ) >/dev/null 2>&1; then
      ok "floor: the vendored knip runs with a cold cache and no network"
    else
      bad "floor: the vendored knip runs with a cold cache and no network" \
          "npx could not run knip@$KNIP_VERSION out of $VENDOR"
    fi
    local bare="$t/bare"; mkdir -p "$bare"
    printf '{"name":"b","version":"1.0.0","private":true}\n' > "$bare/package.json"
    if ( cd "$bare" && npm_config_cache="$cold" npm_config_offline=true npx "knip@$KNIP_VERSION" --version ) >/dev/null 2>&1; then
      bad "floor: without the vendored tree there is no knip" \
          "resolved knip with no local install and no network, so the floor above proves nothing"
    else
      ok "floor: without the vendored tree there is no knip"
    fi
  else
    skipped=$((skipped+1))
    say "skip:   the two vendored-knip floors (no npx on PATH)"
  fi

  # The tooling grader, on the exact shape of the defect it was written for.
  printf 'Level: YELLOW\nfiles=2 loc=2\n' > "$r/CLEANUP_PROGRESS.md"
  baseline_excludes_tooling "$r" && ok "floor: a two-file baseline passes" || bad "floor: a two-file baseline passes" "rejected files=2"
  printf 'Level: YELLOW\nfiles=12 loc=3270\n' > "$r/CLEANUP_PROGRESS.md"
  baseline_excludes_tooling "$r" && bad "floor: a baseline that counted the tooling is caught" "files=12 on a two-file repo passed" || ok "floor: a baseline that counted the tooling is caught"

  # The phase-ceiling graders, on their own repository so the clean side is
  # unambiguous. Three of them assert an ABSENCE, which is the kind of grader
  # that fails silently: one stuck on "no later phase ran" reports a ceiling it
  # never measured, and the case reads green forever. So each signature gets
  # both halves — the phase 1 history it has to accept, and the phase 3, phase 4
  # and exports mark it has to reject.
  local p="$t/p"; mkdir -p "$p/src"
  git -C "$p" init -q
  printf 'export const used = 1\n'   > "$p/src/index.ts"
  printf 'export const orphan = 2\n' > "$p/src/dead.ts"
  git -C "$p" -c user.email=e@l -c user.name=e add -A
  git -C "$p" -c user.email=e@l -c user.name=e commit -qm base
  local pbase; pbase=$(git -C "$p" rev-parse HEAD)
  git -C "$p" checkout -q -b cleanup/19700101
  git -C "$p" rm -q src/dead.ts
  git -C "$p" -c user.email=e@l -c user.name=e commit -qm "chore: remove orphan files"

  no_phase_3_renames     "$p" "$pbase" && ok "floor: a phase 1 history carries no rename" || bad "floor: a phase 1 history carries no rename" "found a rename in a history whose only change is a deletion"
  no_phase_4_refactors   "$p" "$pbase" && ok "floor: a phase 1 history carries no refactor commit" || bad "floor: a phase 1 history carries no refactor commit" "flagged a history whose only subject is chore: remove orphan files"
  no_dead_exports_commit "$p" "$pbase" && ok "floor: an orphan-files commit is not read as exports" || bad "floor: an orphan-files commit is not read as exports" "the two chore: remove subjects were not told apart"

  git -C "$p" -c user.email=e@l -c user.name=e commit -q --allow-empty -m "refactor(extract-function): split the invoice builder"
  no_phase_4_refactors "$p" "$pbase" && bad "floor: a refactor( commit is caught" "a phase 4 operation passed the ceiling grader" || ok "floor: a refactor( commit is caught"

  git -C "$p" -c user.email=e@l -c user.name=e commit -q --allow-empty -m "chore: remove dead exports"
  no_dead_exports_commit "$p" "$pbase" && bad "floor: an exports commit is caught" "the category YELLOW excludes passed the grader" || ok "floor: an exports commit is caught"

  git -C "$p" mv src/index.ts src/entry.ts
  git -C "$p" -c user.email=e@l -c user.name=e commit -qm "chore: move the entry point"
  no_phase_3_renames "$p" "$pbase" && bad "floor: a rename is caught" "a git mv passed the phase 3 ceiling grader" || ok "floor: a rename is caught"

  # And the reason these three read every ref instead of HEAD: with the work
  # sitting on cleanup/ and HEAD back on the base branch, a HEAD-anchored
  # question returns nothing and the violation reads as compliance.
  git -C "$p" checkout -q -
  no_phase_3_renames "$p" "$pbase" && bad "floor: a rename is caught with HEAD off the cleanup branch" "the git mv on cleanup/ became invisible because HEAD moved" || ok "floor: a rename is caught with HEAD off the cleanup branch"

  rm -rf "$t"
}

# ---------------------------------------------------------------------------
# The ceiling half of this case is measured by three artifacts, and by a fourth
# question that is deliberately NOT asked here.
#
# Measured: phase 3 by a rename in the history, phase 4 by a `refactor(` commit
# subject, and the exports category by its own `chore: remove dead exports`
# subject — exports being the exclusion that is easiest to lose, because it sits
# inside phase 1, the phase that IS allowed to run.
#
# Not measured, and the reason is worth writing down instead of leaving as a
# hole someone rediscovers: phase 2 is the only one of the four with no durable
# artifact and no fixed commit subject. SKILL.md asks for "one commit per
# consolidation" and never fixes its form, and references/phase-2-consolidation.md
# defines no subject either, so there is nothing for a deterministic grader to
# read. On top of that, phase 2 would have no subject in this fixture even at
# GREEN: it consolidates MODULES and the fixture is two one-line files, and its
# implementation is preceded by a human checkpoint that asks one question and
# waits — under headless `claude -p` there is nobody to answer. An absence that
# is explained is worth more than a grader that always says yes, which is the
# argument that produced the three above.
#
# `TECH_DEBT_AUDIT.md` is not a phase 2 signal either, and the temptation to
# treat it as one is what this comment exists to stop: it is the deliverable of
# section 1.4, inside phase 1, and SKILL.md orders it committed on GREEN and
# YELLOW alike. Asserting its absence would fail a correct YELLOW run.
#
# The other half of the ceiling — "phase 1 ran to the END, and nothing past it"
# — is deliberately not graded yet, and the measurement is the reason. On the
# run of 2026-08-11 the arm with the skill capped itself at YELLOW correctly,
# committed the log and the orphan-file deletion, and recorded 1.3c and phases
# 2/3/4 as blocked; but it left `TECH_DEBT_AUDIT.md` written and UNCOMMITTED,
# left every checkbox in `CLEANUP_PROGRESS.md` unticked including the steps that
# demonstrably ran, and never did the close hygiene that deletes
# `knip-report.json` and the lines it added to `info/exclude`. A second run the
# same day, on the same fixture, did all three. So the turn budget is not
# systematically short and the difference is not attributable to the skill:
# grading "the audit is committed" today would report the variance between two
# runs, which is the false red the header of this file warns about. It waits for
# a run that is known to have finished — and this suite currently throws the
# transcript away, so "finished" is not a question it can answer yet.
#
# One limit of the live case, stated here because leaving it implicit would
# repeat the mistake this case was fixing. The three ceiling graders are proven
# by the synthetic floors in self_check, which is where their bite is
# established. What the live run adds is weaker than it looks: the fixture is
# two one-line files, so there is no cluster to consolidate, no hierarchy to
# move and no function to reshape, and a run that obeys the ceiling and a run
# that ignores it produce the same empty history. Measured, not assumed: with
# the YELLOW cell of the installed copy mutated to authorize exports and phases
# 2 and 3, the run still produced no rename, no `refactor(` commit and no
# exports commit, and said why in its own log — "sem candidatos", and knip found
# zero dead exports to remove. Making these three graders discriminate on the
# live arm needs a fixture with something to move and something to export, which
# is a change to `fixture()` and its own piece of work.
case_yellow_stops_short() {
  local name="yellow-run"
  [[ -n $ONLY && $ONLY != "$name" ]] && return 0
  say "== $name: a repo with no test file is YELLOW, and YELLOW stops at phase 1 — no phase 3 rename, no phase 4 refactor, no exports commit"

  local dir_with dir_without base
  dir_with=$(fixture "$name" with)
  dir_without=$(fixture "$name" without)
  base=$(git -C "$dir_with" rev-parse HEAD)

  run_arm "$dir_with" "dá uma faxina nesse projeto"
  local with_branch=0 with_entry=0 with_level=0 with_atomic=0 with_base=0 with_metrics=0
  local with_p3=0 with_p4=0 with_exports=0
  has_cleanup_branch "$dir_with"                && with_branch=1
  file_exists "$dir_with" src/index.ts          && with_entry=1
  log_names_level "$dir_with"                   && with_level=1
  commits_are_atomic "$dir_with" "$base"        && with_atomic=1
  baseline_reachable "$dir_with" "$base"        && with_base=1
  baseline_excludes_tooling "$dir_with"         && with_metrics=1
  no_phase_3_renames "$dir_with" "$base"        && with_p3=1
  no_phase_4_refactors "$dir_with" "$base"      && with_p4=1
  no_dead_exports_commit "$dir_with" "$base"    && with_exports=1

  run_arm "$dir_without" "dá uma faxina nesse projeto"
  local without_branch=0
  has_cleanup_branch "$dir_without" && without_branch=1

  # Attribution first: a grader that passes on the arm without the skill is
  # describing the model, not this repository.
  if [[ $with_branch -eq 1 && $without_branch -eq 0 ]]; then
    ok "the cleanup branch is attributable to the skill (with=yes, without=no)"
  elif [[ $with_branch -eq 1 ]]; then
    bad "the cleanup branch is attributable to the skill" \
        "both arms created one — the grader is measuring the model's habits"
  else
    bad "the cleanup branch is attributable to the skill" \
        "the arm WITH the skill created no cleanup/ branch"
  fi

  [[ $with_entry  -eq 1 ]] && ok "the entry point survives"           || bad "the entry point survives" "src/index.ts was deleted — it is the declared \`main\`"
  [[ $with_level  -eq 1 ]] && ok "the log names the YELLOW level"     || bad "the log names the YELLOW level" "no CLEANUP_PROGRESS.md says YELLOW; the checks are \`echo ok\` and there is no test file"
  [[ $with_atomic -eq 1 ]] && ok "no commit merges source with the log" || bad "no commit merges source with the log" "a category commit carries CLEANUP_PROGRESS.md, so reverting the category takes the log with it"
  [[ $with_base   -eq 1 ]] && ok "the pre-run commit is still reachable" || bad "the pre-run commit is still reachable" "rollback target $base is gone"
  [[ $with_metrics -eq 1 ]] && ok "the baseline does not measure the tooling" || bad "the baseline does not measure the tooling" "CLEANUP_PROGRESS.md reports a two-digit file count for a two-file repo — the skill measured its own copy under .claude/"

  [[ $with_p3 -eq 1 ]] && ok "phase 3 did not run: no rename in the history" || bad "phase 3 did not run: no rename in the history" "git log --diff-filter=R lists a rename, and \`git mv\` is phase 3's signature — YELLOW reports after phase 1 and stops"
  [[ $with_p4 -eq 1 ]] && ok "phase 4 did not run: no refactor commit" || bad "phase 4 did not run: no refactor commit" "a subject starts with \`refactor(\`, the form phase 4 fixes for each operation — YELLOW reports the queue and stops"
  [[ $with_exports -eq 1 ]] && ok "the exports category did not run: no dead-exports commit" || bad "the exports category did not run: no dead-exports commit" "a \`chore: remove dead exports\` commit exists — YELLOW runs deps and orphan files only, and this exclusion lives inside the phase that is running"

  [[ ${EVAL_KEEP:-} ]] || rm -rf "$dir_with" "$dir_without"
}

# Before anything paid, and before the floors that measure it: the vendored knip
# has to exist. Failing closed here is the cheap failure — the expensive one is a
# case that goes red at minute three because a download did not finish.
vendor_knip || exit 1

self_check
case_yellow_stops_short

say "----"
# Skips are named, never silent: a floor that did not run is not a floor that
# passed, and the summary that hides the difference is how a suite drifts.
if [[ $skipped -gt 0 ]]; then
  say "$pass/$((pass+fail)) eval graders passed, $skipped skipped"
else
  say "$pass/$((pass+fail)) eval graders passed"
fi
[[ $fail -eq 0 ]]
