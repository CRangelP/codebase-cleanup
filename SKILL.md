---
name: codebase-cleanup
description: Full four-phase codebase cleanup — removes dead code (knip/vulture/cargo-udeps), consolidates shallow modules, reorganizes the folder structure and reshapes the functions that survived, running autonomously with atomic commits and rollback. Use WHENEVER the user mentions cleaning up, organizing, tidying or refactoring the project, or says "dar uma faxina" or "dá uma limpada"; talks about dead code, orphan files, unused dependencies, tech debt, god functions, messy folders or a bloated codebase; mentions duplicated code, copy-paste code, "código duplicado" or "função repetida"; asks to "give the codebase a deep clean", to "reorganiza essas pastas", or for an audit or health check; or says the repo "grew too big", "is hard to navigate", "cresceu demais" or "tem coisa que ninguém usa". Also use when the user wants only one of the four phases on its own. Do NOT use for formatting or lint, vulnerable dependency updates, bundle size optimization, database cleanup or git history rewriting.
---

# Codebase Cleanup

Codebase cleanup in four sequential phases. The order is not negotiable:

**Clear out the dead → decide the boundaries → move the files → reshape what is left.**

In reverse order you reorganize garbage into pretty folders and then find out
half of it should not exist. Each phase removes the noise that would get in the
next one's way: the module graph is only trustworthy once the dead code is
gone, folders only make sense once module boundaries have stabilized, and
reshaping the inside of a function that phase 2 was about to consolidate away
is work done twice.

## Operating principle

Do as much as possible without asking. The user installed this skill to avoid
typing fifteen commands — every unnecessary confirmation is a design failure,
not a courtesy.

What makes this safe is not asking, it is the structure of the work: a
dedicated branch, atomic commits per category, and a green gate (typecheck +
tests) before every commit. If something breaks, the rollback is to discard
whatever is not committed yet with `git restore --staged --worktree .` —
without asking anyone, because the previous commit was already correct. Since
every commit only happens on a green gate, HEAD is always a good state.

Restoring the tracked files to HEAD is a full rollback under two conditions,
and both are the pipeline's job to guarantee: the tree was clean when the work
started (Step 0 stops if it was not), and everything the step changed is staged
before the gate runs — `git restore --staged --worktree .` undoes a staged new
file, but leaves an untracked one behind. Hence the rule that repeats at every
step: **stage with pathspecs of this step's artifacts before the gate** —
`git add -- <paths this step produced or edited>`, never `git add -A` or
`git add .`, which would swallow unrelated untracked files (drafts, a local
`.env`, secrets) into the category commit.

Never use `git reset --hard` or `git clean`. `restore` covers the case and
survives environments with hooks that block destructive commands; `git clean`
would additionally wipe untracked files that must survive — tool output,
caches, local env files that never belonged to this cleanup.

**If a security hook blocks a command from the protocol**, do not work around
it. Branch on which command was blocked:

- **Rollback** (`git restore --staged --worktree .`) — **abort the pipeline.**
  The failed category's work is still in the tree; the next stage would fold
  it into another category and destroy atomic revert. Report: the branch name,
  that the tree is dirty with the failed step's changes, and the exact command
  the user must run by hand (`git restore --staged --worktree .`, or their
  environment's approved equivalent). Do not start the next category or folder.
- **Anything else** (branch creation, file deletion, …) — record the pending
  item in `CLEANUP_PROGRESS.md`, hand the ready-to-run command to the user and
  move on to the next step that does not depend on it.

A guard is environment policy, not an obstacle.

Installed as a plugin, this skill ships guards of its own (`hooks/hooks.json`
→ `scripts/guard.sh`) for exactly the five commands the rules above forbid:
`git reset --hard`, `git clean`, push, commit on `main`, and whole-tree
staging. They are awake only inside a run — a `cleanup/` branch, or an
untracked `CLEANUP_PROGRESS.md` — and they fail open. Hitting one of them
means the step was about to break the protocol, so the answer is never to
rephrase the command until it slips through: re-read the rule the guard names
and follow it. Everything the protocol actually runs is allowed, the rollback
and pathspec staging included.

There are **two scheduled checkpoints** in the pipeline (phase 2, choosing the
consolidation candidate; phase 3 on GREEN, confirming the folder plan before
any `git mv`), **one conditional checkpoint** in phase 4 that exists only when
the queue has a tier B operation in it, and **one conditional stop** at Step 0,
when the working tree is dirty before anything starts. Everything else runs on
its own — phase 4 included, as long as it stays in tier A.

---

## Rules that apply to the whole pipeline

**`/clear` between phases.** Not optional. Accumulated context from the
previous phase degrades the judgment of the next one, and
`CLEANUP_PROGRESS.md` exists so that this costs nothing.

**Never merge two steps.** "Configure knip and delete whatever it finds" is how
you delete a route handler registered by convention that knip did not know
about. The separation between configuring, verifying and deleting is what
prevents that.

**A red gate means rollback, not repair.** If typecheck or tests fail, the
previous commit was already correct. Revert, record, move on. Trying to fix it
turns a cleanup into an unsolicited debugging session. A gate that times out
(exit 4) follows the same path: it is inconclusive, so it rolls back like a red
one and is recorded as a timeout — never as a green.

**Never force push, never commit on main.** All the work lives on the cleanup
branch. Merging is the user's decision, on their own schedule.

## Step 0 — Calibrate autonomy

Before anything else, measure the safety net. The autonomy level is a function
of it, not a preference.

```bash
git rev-parse --is-inside-work-tree       # is there a repo at all?
git rev-parse --verify HEAD               # is there a commit to roll back to?
git status --porcelain                    # anything uncommitted?
git branch --show-current                 # current branch (empty = detached)
```

Read those three answers before running anything else:

**No commit to roll back to** — either `--is-inside-work-tree` fails, or it
succeeds and `--verify HEAD` fails. The level is **RED**, diagnosis only,
whatever the gate says afterwards. Without commits there is no rollback, and the
whole safety argument of this skill rests on being able to return to a good
HEAD. Say so in one line and produce a report.

The second half is not a corner case dressed up as one: `git init` and nothing
else is a work tree with an unborn HEAD, where `--is-inside-work-tree` answers
`true`, `git status --porcelain` prints nothing, and
`git restore --staged --worktree .` answers `fatal: could not resolve 'HEAD'`.
Every measurement says go, and the rollback the whole pipeline rests on does not
exist. Asking only whether a repository exists answers a different question from
the one this rule states.

`git branch --show-current`, never `rev-parse --abbrev-ref HEAD`: on an unborn
HEAD the latter exits 128 while printing the literal `HEAD`, which is what a
detached HEAD prints too — a state this skill treats differently.

**Dirty working tree** (`git status --porcelain` prints anything). **Stop and
ask.** This is the conditional stop, and it is not negotiable: the rollback of
this pipeline is `git restore --staged --worktree .`, which throws away
uncommitted work in the tracked files — including work that was already there
when you arrived. Present the three ways out and wait for the user to pick one:

1. `git stash push -u` — parks everything and gives you a clean tree;
2. commit the pending work first, on the current branch, and then start;
3. abort the cleanup.

Do not choose on the user's behalf, do not stash "to be helpful", do not start
anyway because "the diff looks small". Only an explicit answer unblocks the
pipeline. If they pick 1 or 2, run `git status --porcelain` again and confirm
it is empty before moving on.

**Detached HEAD** (`git branch --show-current` prints nothing, and `--verify HEAD`
succeeded — that pair is the whole test). Not a blocker: record
the current commit in `CLEANUP_PROGRESS.md` and create the cleanup branch
normally — it will branch off that commit, which is exactly what you want. Note
in the final report that the work started from a detached HEAD, so the user
knows where the branch came from.

With a clean tree and a repo, run the baseline gate with
`"${CLAUDE_PLUGIN_ROOT:-.}/scripts/gate.sh"` and classify. The script takes the
project directory as an argument and defaults to the current one, and detects
the stack from the root manifest, running typecheck and tests for each one it
finds. Which manifests it recognises, how it picks the npm script to run, and
why 124 and 137 are reserved are in `references/gate.md` — read it when a
result surprises you, not before.

Classify by the `[gate] checks=...` line, which lists what actually ran, and
not by the exit code alone: GREEN requires `typecheck` and `test` in the list;
a partial list caps at YELLOW, and the script itself says so. Exit 0 =
everything that ran passed; 1 = a check failed, which is RED — and the script
stops at the first red, so there is no `checks=` line to classify by, only the
`RED at '<cmd>'` line naming what broke; 2 = bad path (the argument is not a
directory the script can enter, so nothing was checked — fix the path and
rerun); 3 = no runnable check **or** some detected stack had no toolchain
(`PARTIAL` — including in a polyglot repo where another stack passed); 4 = a
check hit the watchdog (`GATE_TIMEOUT`, 900s per check by default, `0`
disables). In the exit-3 cases, finish the gate by hand before classifying.

**Exit 4 is an inconclusive gate, not a green one.** A timed-out check says
nothing about the code: treat it as red (rollback, record what timed out in
`CLEANUP_PROGRESS.md`) and never promote it to GREEN. On the Step 0 baseline,
exit 4 means the safety net could not be measured — report it and do not run
autonomously.


| Signal | Level | Behavior |
|---|---|---|
| Typecheck **and** tests pass | **GREEN** | Runs phase 1 in full without asking. Phase 2 and phase 3 each stop at their human checkpoint before mutating. Phase 4 runs tier A per covered target and stops at a checkpoint for tier B. |
| A partial net, or no test file in the stack | **YELLOW** | Runs phase 1 (deps and orphan files only, **not** exports). Does **not** run phase 2, phase 3 or phase 4; reports and stops. |
| A check fails, or no tests and no typecheck | **RED** | Diagnoses only. Does not delete, does not move, does not commit. May create the cleanup branch; does **not** commit `CLEANUP_PROGRESS.md`. Delivers a report. |
| No repository, or a repository with no commit | **RED** | Diagnoses only, regardless of the gate result — there is no HEAD to roll back to. |

**Take the quality baseline in the same breath**, at every level including RED —
the measurer is read-only, and this is the only chance to see the repo before
the run changes it:

```bash
"${CLAUDE_PLUGIN_ROOT:-.}/scripts/metrics.sh" . > /tmp/metrics-before.txt
```

Copy the `[metrics]` lines into `CLEANUP_PROGRESS.md` as well, so the baseline
survives a `/clear` and a swept temp directory. Exit 2 means the path was wrong
and 3 that no source was recognized; neither is a gate result and neither
changes the level — note it and move on. Without this file the final report has
no delta to show.

**Stack caps in `references/other-stacks.md` override the GREEN column.**
Python always confirms before deleting; JVM and Ruby are diagnosis / YELLOW by
default; .NET is YELLOW by default for code (deps flagged by the compiler may
go). Read that file before autonomous deletion — a GREEN gate on a stack whose
graph is unreliable does not unlock code deletion.

`checks=typecheck` because the stack has **no test file** is YELLOW, not GREEN,
even though the gate exits 0 — a suite that does not exist cannot pass. The
script names the stack in the `'test' not counted` line, and every stack whose
suite could not be counted goes through it. Read those lines, not only
`checks=`: in a polyglot repo one stack supplies the suite while another has
none, so `checks=typecheck,test` can be describing two different stacks. The
gate refuses to announce GREEN there and says why (`a detected stack has no
countable suite`). Only the user promotes a cap, by pointing at the suite that
lives somewhere the gate does not look; the skill never promotes itself.

**A baseline that already fails is RED, not YELLOW.** Exit 1 says a check
broke, and a broken baseline leaves no way to tell what the cleanup broke from
what was already broken. It also has nowhere to go: every commit here needs a
green gate, so a run that starts red deletes, rolls back and commits nothing,
category after category. **Fix it or warn before touching anything** — until
then the deliverable is the diagnosis, naming the check that failed.

Announce the detected level in one line and move on. Do not ask permission for
the level.

```bash
git checkout -b cleanup/$(date +%Y%m%d)
```

Two cleanups on the same day collide on that name, and `checkout -b` fails
instead of overwriting anything. Resolve it without asking: if the existing
branch has a `CLEANUP_PROGRESS.md`, it is an interrupted run of this same skill
— check it out and resume from the file. Otherwise, suffix the name (`-2`,
`-3`, and so on) until `git rev-parse --verify` says the ref is free. Never
force, never delete the branch that is in the way.

## Step 0.1 — Persistent state

**At RED, skip this step.** Do not create or commit `CLEANUP_PROGRESS.md` —
diagnosis goes only into the final report. The cleanup branch from Step 0 may
exist; nothing else is written into the repo.

On GREEN/YELLOW, create `CLEANUP_PROGRESS.md` at the root and **commit it
right away** (`chore: start cleanup log`), before any other work. It is the
only artifact that has to outlive a rollback: an untracked file survives
`git restore --staged --worktree .` by accident, a committed one survives by
design, and a staged one would be thrown away with the failed step. Keep it
updated at the end of every step, committed along with that step's changes.
Stage it with a pathspec (`git add -- CLEANUP_PROGRESS.md`), never
`git add -A`.

Phases are separated by `/clear` (dirty context from one phase degrades the
next), so this file is what allows resuming without the user re-explaining
anything.

```markdown
# Cleanup Progress
Branch: cleanup/20260808 · Level: GREEN · Started: 2026-08-08

- [x] Phase 1.1 — knip hints down to zero (3 rounds)
- [x] Phase 1.2 — deps removed (7) · commit a3f9c21
- [ ] Phase 1.3 — orphan files
...
## Decisions
- `lodash.merge` kept: used by a build script outside the graph
## Pending for the human
- (none)
```

When invoked, **always read this file first**. If it exists, resume where it
stopped instead of starting over.

## Step 0.2 — Single session or subagents

Full pipeline on a real repo: if the environment has subagents, run as
orchestrator — each phase goes to an implementation subagent with disposable
context, which is the same effect as `/clear` without depending on the user
remembering. Single-phase request or small repo: single session, no
orchestration.

Installed as a plugin, the delegations are declared and you call them by
name instead of composing them each time:

| Agent | Scope |
|---|---|
| `codebase-cleanup:cleanup-phase-1` | phases 1 and 1.5 |
| `codebase-cleanup:cleanup-phase-2-survey` | the candidates, read-only |
| `codebase-cleanup:cleanup-phase-2-impl` | the consolidation the user chose |
| `codebase-cleanup:cleanup-phase-3-survey` | the structure plan, read-only |
| `codebase-cleanup:cleanup-phase-3-impl` | the approved moves |
| `codebase-cleanup:cleanup-phase-4-survey` | the reshaping queue, read-only |
| `codebase-cleanup:cleanup-phase-4-impl` | tier A, plus the approved tier B |

The split into survey and implementation is where the checkpoint lives: the
survey agents cannot write at all, so the question reaches the user before
anything changed, and the implementation agents only start after the answer.
Phase 4 keeps the split for the same reason on a narrower question — tier B
changes a name in the domain, and no test can vouch for that choice.

Without plugin agents the same contract is composed by hand, and it is the
same four points:

- the path to this skill (the subagent reads SKILL.md and follows it, with
  references/ and scripts/ alongside) and the path to the repo;
- the instruction to read `CLEANUP_PROGRESS.md` before anything else;
- the scope of **one** phase — step 1.5 belongs to the phase 1 delegation
  (the `/clear` at its end is the phase 1 → phase 2 boundary), and phase 2
  becomes two delegations: the survey returns the candidates, the
  implementation only starts after the user's choice;
- returning a summary of what it did, with `CLEANUP_PROGRESS.md` updated as the
  canonical state.

Step 0 (calibrating the level, creating the branch), the phase 2 checkpoint,
the phase 3 checkpoint and the phase 4 tier B checkpoint stay with the
orchestrator — a subagent does not talk to the user. Level and branch reach
the subagents ready-made, through
`CLEANUP_PROGRESS.md`.

---

# PHASE 1 — Dead or alive

Goal: separate what is real code from what can disappear.

Do not use LLM judgment as the judge here. Use a tool, and interpret the
result. "This file looks unused" is a guess; "no entry point reaches this file
in the module graph" is a fact.

For non-JS/TS stacks, read `references/other-stacks.md`. The rest of this phase
assumes JS/TS (step 1.5 names its own fallback for other stacks).

## 1.1 Configure knip until the hints reach zero

Run `npx knip@6.32.0` with no config at all first (pin verified 2026-08-09;
never bare `npx knip`). knip has plugins for the vast majority of the
ecosystem's tools (Next, Vitest, ESLint, Playwright, and dozens of others)
that read their configuration and work out entry points on their own — writing
config before seeing what it already knows is wasted work.

**Handle the configuration hints before looking at any finding.** Hints mean
knip could not resolve a dependency, plugin or entry file — that is, the graph
is incomplete and every finding derived from it is suspect. A good chunk of the
"unused files" list evaporates on its own once the hints are gone.

Iterate on your own: write `knip.json`, run again, adjust, repeat. Do not show
every round to the user — report at the end how many rounds it took and how
many findings disappeared.

Configuration details (entry, project, paths, monorepo, when to use each
`ignore*`) are in `references/knip-config.md`. Read it before writing the file.

When the hints reach zero, commit `knip.json` on its own
(`chore: knip config`), before deleting anything. It cost several rounds to get
right and it is the input to every deletion that follows — if the first
category fails its gate, the rollback must not take the config with it.

The rule that saves the most rework: **do not use the `ignore` option.** It
does not exclude anything from the analysis, it only hides the report —
creating a blind spot. If something shows up wrong, the fix is to teach the
graph (entry, project, paths, plugin), not to silence the output.

## 1.2 Run in production mode

```bash
npx knip@6.32.0 --production --no-exit-code --reporter json > knip-report.json.tmp && mv knip-report.json.tmp knip-report.json
```

Write to a temp file and move only on success. A plain `> knip-report.json`
truncates the file before knip even starts, so a crash leaves an empty report
that 1.3 reads as "nothing to delete" — a silent failure. `--no-exit-code` is
what makes the `&&` usable: knip exits 1 whenever it finds issues, which is the
normal case here, and 2 only when it actually failed.

Check the report before 1.3 consumes it: `knip-report.json.tmp` has to be gone,
and `knip-report.json` has to be non-empty and parse as JSON. The temp file is
the check that catches a failed run — when knip breaks, the `&&` skips the `mv`
and the *previous* report stays on disk, non-empty and perfectly parseable, so
the content checks alone would wave a stale list through. A `.tmp` left behind
means the run did not finish: delete it and fix knip instead of proceeding.

Production mode excludes tests and devDependencies automatically. That matters
because a function imported only by a test is technically alive, but it is dead
as far as the application is concerned — and that is exactly the code you want
to find.

Never exclude tests with `ignore` to get the same effect.

## 1.3 Delete in atomic commits, one per category

**Default scope.** Run all three without asking (GREEN level) or the first two
(YELLOW). Each one is: delete → (deps only: install / re-resolve) → stage
pathspecs → gate → commit → regenerate the report. For the gate, use
`"${CLAUDE_PLUGIN_ROOT:-.}/scripts/gate.sh"` (it detects the stack and the
package manager and runs
typecheck + tests in the right order); if it exits with code 3, find the
stack's own check commands — the `package.json` scripts, the tox env, the
Makefile target, whatever this repo uses — and run them by hand.

**Partial run by category.** If the user asked for only one (or some) of the
three categories — e.g. "remove só as dependências não usadas" — run exactly
those, in the order below, and **do not** run the others. Record every skipped
category under `## Decisions` in `CLEANUP_PROGRESS.md` as out of scope for
this run (`orphan files: out of scope — user asked deps only`), and repeat
that list in the final report under "Failed / not done". A category the level
already forbids (YELLOW × exports) is a level cap, not a user scope skip —
say which.

**Staging — pathspecs only.** Staging before the gate is what makes the
rollback complete. Stage only the paths this category produced or edited:

```bash
git add -- path/to/edited path/to/removed-file package.json package-lock.json
# deletions of tracked files: `git add -- path` (or `git rm` already staged them)
```

Never `git add -A` or `git add .`. Step 0's dirty-tree stop is still the
precondition that nothing of the user's was already pending; pathspecs are
what keep a draft or local `.env` that appears mid-run out of the commit.

**Artifact hygiene (exclude + close).** Before the first category, put
`knip-report.json` and `knip-report.json.tmp` in the repo's exclude file —
and, before the first coverage run in phase 4, the coverage artifacts of the
stack's tool (`coverage/`, `.coverage`, `lcov.info`) alongside them —
repo-local, so the user's `.gitignore` stays untouched. Ask git where it is
rather than typing the path: `git rev-parse --git-path info/exclude`, because
in a linked worktree, a submodule or a `--separate-git-dir` checkout `.git`
is a *file* and appending to `.git/info/exclude` fails with `Not a directory`.
Otherwise every category would be tempted to commit the report the previous
one was read from, and the user reverting `chore: remove unused deps` would
get a tool artifact back along with the dependencies.

That exclude only reaches **untracked** paths. If a previous run already
committed `knip-report.json`, git keeps seeing it whatever the exclude says, and
the regeneration below puts a fresh diff on disk. Check with
`git status --porcelain` after writing the exclude lines; if the report still
shows up, **find out whose it is before touching it**. A tool artifact left by
an earlier run of this skill gets untracked in a commit of its own, before the
first category. Anything else is the user's: leave it tracked, say so in the
report, and never pathspec-add it into a category commit. On the way out, delete
only report files that are artifacts of this run — never a `knip-report.json`
the user tracks on purpose. Drop from the exclude only the lines you added,
because the exclude makes a leftover invisible to `git status` and nobody would
find it later. `references/knip-config.md` has the commands.

Also confirm the repo ignores `node_modules` before the deps category — a
global `.gitignore` does not travel with the repo — and add it to
`info/exclude` if it does not. Empty directories are not staged by pathspec
adds either: git tracks files. The leftovers `mkdir -p` creates in phase 3
are a working-tree problem and are swept there.

```
1. unused deps        → "chore: remove unused deps"
2. orphan files       → "chore: remove orphan files"
3. dead exports       → "chore: remove dead exports"
```

Kept separate because if something breaks in production two weeks from now, the
user needs to revert *one* commit — not a 400-file cleanup.

**Unused deps: install after pruning the manifest.** Removing an entry from
`package.json` does not remove the package from `node_modules`, and the gate
never installs — the resolver still finds the package on disk, typecheck and
tests pass, and the break only surfaces on CI or on the next machine that
installs from the pruned manifest. So, after editing the manifest and before
staging pathspecs, run the package manager's plain install (non-JS/TS stacks:
see the matching re-resolve / tidy / restore step in
`references/other-stacks.md`):

```bash
npm install                          # npm
pnpm install --no-frozen-lockfile    # pnpm
yarn install --no-immutable          # yarn berry (yarn 1: yarn install)
bun install                          # bun
```

Plain, never the frozen form. `--frozen-lockfile`, `--immutable` and the CI
defaults that turn them on refuse a lockfile that no longer matches the
manifest — which is exactly the state a correct prune produces, so a good
deletion would come back as a red gate for the wrong reason. `npm ci` is the
same refusal under another name: it aborts with `EUSAGE` when `package.json`
and `package-lock.json` are out of sync, and it never writes the lockfile, so
it cannot get the prune out of this state either. The updated lockfile goes in
this category's commit: it is what carries the prune to every other machine.

**Regenerate the report between categories.** After each category's commit, run
the 1.2 command again — same hardened form, same file — and read the next
category from the fresh report. The three feed each other: deleting orphan
files kills exports the old report still saw as alive and frees deps it saw as
used, while some exports it lists as dead live in files the previous category
already removed. On a frozen report those second-order items survive the
cleanup and a category tries to edit paths that no longer exist. The cost is
one extra knip run per category that commits.

A category that is skipped (YELLOW does not run exports) or that fails its gate
leaves no commit and nothing in the tree for knip to read differently, so there
is nothing to regenerate from — keep the current report and go to the next
category. The regeneration after the last category that did commit is the one
the final report counts against.

**If the gate fails:** `git restore --staged --worktree .`, record the category
as failed in `CLEANUP_PROGRESS.md` along with the error, and **move on to the
next category**. If that restore is blocked by a hook, **abort** — see the
operating principle; do not start the next category with a dirty tree. Do not
try to fix a red gate — if typecheck broke, knip was wrong about that
category, and the useful information is which category, not a patch. On the
deps category, a successful restore brings back `package.json` and the
lockfile but not `node_modules`: run the install again before starting orphan
files.

Do not run `knip --fix` until the config has settled for two or three rounds
with no surprises.

## 1.4 Full audit

With the garbage gone, the graph is clean and the audit becomes precise.
Follow the protocol in `references/audit.md` — nine dimensions with
`file:line` citations, severity and effort per finding, and the deliverable
template for `TECH_DEBT_AUDIT.md`. The protocol is distilled from ksimback's
tech-debt-audit (MIT; credited in the README), so no other skill needs to be
installed for this step.

Always include a **"looks bad but is fine"** section — the calls you considered
making and decided not to make, with the reason. If that section comes out
empty, the audit did not look deep enough and you must go back.

Commit the report (GREEN/YELLOW; at RED nothing is committed — it goes into
the final report instead). Update `CLEANUP_PROGRESS.md`.

## 1.5 Duplicate functions (report only)

Goal: functions with different names doing the same thing — duplicated
intent. This runs here for a reason: earlier, the pair list would be full of
code that 1.2–1.3 was about to delete anyway; later is too late, because
these pairs are the best input the phase 2 survey will get. A 90% pair across
two folders is a more obvious consolidation candidate than anything depth
analysis surfaces alone.

For JS/TS the ladder is: `similarity-ts` (AST comparison per function) if it
is on PATH, else `npx fallow@3.14.0 dupes` (pin verified 2026-08-09; never
bare `npx fallow`); other stacks fall back to `npx jscpd@5.0.14`. Tools,
flags, thresholds and the report format are in `references/duplication.md` —
read it before running anything.

**The churn rule.** High similarity is not a verdict. Check whether the pair
changes together in git history: pairs that co-change are real duplication
and become phase 2 candidates; pairs that evolve independently are structural
coincidence — two domains that will diverge, where abstracting early costs
more than duplicating. Record those as "left alone on purpose" with the churn
evidence.

Nothing is merged or deleted in this step — which of two duplicate functions
survives is a naming-and-intent decision, and that belongs to the phase 2
checkpoint. Commit the report (`chore: duplication survey`) on GREEN/YELLOW;
at RED nothing is committed and the pair table goes into the final report
instead. Update `CLEANUP_PROGRESS.md`. Step 1.5 closes phase 1: **tell the
user to run `/clear` before phase 2.**

---

# PHASE 2 — Consolidate modules

Goal: find out where "these three modules should be one".

Read `references/phase-2-consolidation.md` for the full survey protocol and the
analysis vocabulary.

## The irreducible checkpoint

Phase 2 is the irreducible *domain* checkpoint: consolidating modules changes
responsibility boundaries, and that is a decision about the *domain*, not about
the code. Green tests do not prove the new boundary is the right one — they
prove the behavior did not change, which is a different thing. Phase 3 adds a
second scheduled checkpoint (plan confirmation before any `git mv`); both are
required on GREEN.

Keep the cost of the checkpoint to a minimum:

1. Present **at most 5 candidates** ranked by confidence.
2. For each one: which modules, why they are shallow, what it becomes
   afterwards, and the risk of touching it.
3. **Recommend one** explicitly, with the reason in a single sentence.
4. Ask **one** question: which one to go with. Do not run a multi-round
   interview.

If the user answers "go" or equivalent, proceed with your recommendation.

## Decision criterion: the deletion test

Imagine deleting the module. If the complexity disappears, it was pass-through
and should be consolidated. If the complexity reappears spread across N
callers, it was paying for itself and should stay.

A shallow module is one whose interface is almost as complex as what it hides —
the cost of learning the interface approaches the cost of simply reading the
implementation. Consolidate clusters of small, tightly coupled modules, not
large isolated files (a large file is a phase 1 problem, and a large module
with a simple interface is exactly what you *want*).

## Implementation

After the choice, run on your own: one module at a time, one commit per
consolidation, and `"${CLAUDE_PLUGIN_ROOT:-.}/scripts/gate.sh"` once — after
staging pathspecs of what
this consolidation touched, right before the commit. Do not gate between the
intermediate steps: with the new interface in place and the callers not
migrated yet, the build is red by construction, and a gate you expect to fail
teaches nothing. The green that matters is the one at the end of the
consolidation, which is exactly the state that gets committed. Same rollback
protocol as phase 1 (including abort if a hook blocks the restore).

**One candidate per session.** Do not stack two — the second refactor inherits
the dirty context of the first and the error rate goes up.

Update `CLEANUP_PROGRESS.md`. Recommend `/clear` before phase 3.

---

# PHASE 3 — Folder structure

Goal: readable organization of directories and files.

It comes last because consolidating modules changes what the folders should be.
Moving a file before deciding the boundary is guaranteed rework.

Read `references/phase-3-structure.md` for the organization patterns and how to
choose between them.

## Diagnosis first, moves after

Produce a phased plan before moving anything: a map of the current structure,
circular dependencies, god modules, leaking abstractions, and the target
structure with a rationale. Only then execute.

## Checkpoint, then autonomous execution

**YELLOW does not run phase 3** — stop after the phase 1 report (and after
phase 2 only if the user later promotes the level). **RED** never reaches
here.

**GREEN: human checkpoint before any move.** Present the phased plan from the
diagnosis (current map → target structure → ordered moves, at most a short
list). Recommend one first move in a single sentence. Ask **one** question:
whether to proceed with that plan (or which slice). Do not start `git mv`
until the user answers. If they say "go" or equivalent, execute the agreed
plan; if they narrow the scope, record the rest as out of scope in
`CLEANUP_PROGRESS.md`.

After the checkpoint, run the agreed plan without re-asking per folder. One
folder per commit:

```bash
mkdir -p src/features/billing
git mv src/utils/format.ts src/features/billing/format.ts   # always git mv
```

`git mv` preserves history — `rm` + `create` destroys that file's `git blame`,
which is precisely the information someone will want six months from now.

Prefer updating **path aliases** over rewriting 200 imports — when every
consumer honors `tsconfig.json` `paths`. If the project uses `@/features/*`,
moving a folder can be one line in the tsconfig instead of a 3,000-line diff.
Bundler, test runner, linter and Docker build each resolve paths on their own,
though, so check the "Do not forget" list in
`references/phase-3-structure.md` before relying on the one-liner.

The move, the import or alias update and the `CLAUDE.md` update go in the
**same commit**. Splitting them would put a commit that does not build in the
history, and there is no gate that a half-done move can pass.

Stage with pathspecs of what this folder move touched (`git add -- …`), never
`git add -A`, and then `"${CLAUDE_PLUGIN_ROOT:-.}/scripts/gate.sh"` at the end
of each folder —
typecheck alone misses what a move actually breaks (config paths, dynamic
imports; the "Do not forget" list in `references/phase-3-structure.md` has
the rest). Failed: `git restore --staged --worktree .`, record it, next
folder. If that restore is blocked by a hook, **abort** the pipeline.

Phase 3 closes the same way phase 1 does: **tell the user to run `/clear`
before phase 4.** The folder plan is the largest context the pipeline carries,
and none of it helps decide whether a function is worth reshaping.

---

# PHASE 4 — Local reshaping

Goal: the inside of the functions that survived the first three phases.

It comes last for the reason that orders everything else: reshaping a function
inside a module phase 2 consolidates away, or inside a file phase 3 moves, is
work done twice. What reaches phase 4 is code that is alive, whose boundary is
settled and whose path is final.

Read `references/phase-4-refactor.md` for the protocol and
`references/refactoring-catalog.md` for the operations themselves — eleven, in
two tiers, with a worked before/after for each.

**Targets are inherited, never invented.** They come from the 1.4 audit
(`TECH_DEBT_AUDIT.md`, dimensions 1 and 3) and from the 1.5 pairs phase 2 did
not take, filtered by the churn ranking: only what is hot gets in the queue. A
file that is big, ugly and cold belongs in "looks bad but is fine", with the
numbers next to it.

**The safety net is measured per target, not per repository.** GREEN says the
suite that exists passes; it says nothing about which lines it executes. To
rewrite the inside of a function, what matters is whether *that function* is
exercised — a repo at GREEN with 4% coverage authorizes nothing, because the
green gate after the change proves only that the code still compiles, which is
what a broken refactor proves too. Uncovered target: skip it and record it, or
write a characterization test as its own commit first. There is no third exit.

**Tier A runs on its own** (`extract-function`, `guard-clauses`,
`named-constant`, `dead-branch`, `rename-local`): mechanical, local, and the
gate is real evidence for it. **Tier B stops at a checkpoint** (`extract-class`,
`domain-type`, `polymorphism`, `parameter-object`, `delegation`,
`type-boundary`): it picks an abstraction or a domain name, and a green test
proves the behavior did not change — not that the choice was right. Same
argument as phase 2, one altitude down. `type-boundary` is the typing and
nothing else: adding schema validation at the boundary rejects input that used
to pass, which is a behavior change and therefore not a refactor here — it
leaves as a recommendation in the report, never as a `refactor()` commit.

One operation per commit, `refactor(<operation-id>): <what>`. Stage with
pathspecs of what the operation touched (`git add -- src/billing/invoice.ts`),
then `"${CLAUDE_PLUGIN_ROOT:-.}/scripts/gate.sh"`, then commit. Unlike phase 2
there is no intermediate red state here: each operation is atomic, so a red
gate means the operation was wrong, not that it was unfinished. Failed:
`git restore --staged --worktree .`, record it, next target. If that restore is
blocked by a hook, **abort** the pipeline.

**Cap per session: 5 tier A operations, 1 tier B.** A review limit, not a
performance one: whoever merges this branch reads the diff. Hitting the cap is a
normal ending — record what is still in the queue and let the next session take
it. Update `CLEANUP_PROGRESS.md` after every operation, with the skipped targets
and the reason they were skipped.

**YELLOW does not run phase 4** — it reports the queue and stops. **RED** never
reaches here. Phase 4 closes the pipeline: go to the final report.

---

## Final report

**Close hygiene first** (GREEN/YELLOW, when the run wrote artifacts): delete
`knip-report.json.tmp` if present, delete the coverage artifacts this run
produced (`coverage/`, `.coverage`, `lcov.info` — phase 4 only, and only when
the run created them), and delete `knip-report.json` only when it
is an untracked tool artifact from this run (see Artifact hygiene above) — if
the user tracks it on purpose, leave the tracked file alone; drop from
`info/exclude` only the lines this run added; leave `CLEANUP_PROGRESS.md` and
`TECH_DEBT_AUDIT.md` committed unless the user asked to remove them — they are
the durable record, not tool noise. Say in the summary what was cleaned.

When wrapping up (or when interrupted), deliver a summary carrying: the branch,
the level and the commit count; one row per phase with what that phase actually
removed; the quality delta against the Step 0 baseline, measured by running
`"${CLAUDE_PLUGIN_ROOT:-.}/scripts/metrics.sh"` again and diffing it; how to
revert (`git revert <sha>` — commits are atomic per category); what failed or
was left undone, and why; and what is pending the user's decision. The template
and the rules for filling each part are in `references/final-report.md`.

If the level was RED, the report is diagnosis only: list what you would do and
what needs to exist or be fixed (tests, typecheck, a baseline that passes) to
make it possible. Where the gap is the suite itself, name the critical path and
**propose** the minimal characterization test that would pin it down — the one
piece of work that turns this repo into one the pipeline can act on. Proposing
it is not promoting the level: the user decides, and the next run measures
again. No `CLEANUP_PROGRESS.md` commit on RED.
