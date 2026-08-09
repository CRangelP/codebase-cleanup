---
name: codebase-cleanup
description: Full three-phase codebase cleanup — removes dead code (knip/vulture/cargo-udeps), consolidates shallow modules and reorganizes the folder structure, running autonomously with atomic commits and automatic rollback. Use WHENEVER the user mentions cleaning up, organizing, tidying or refactoring the project, or says "dar uma faxina" or "dá uma limpada"; talks about dead code, orphan files, unused dependencies, tech debt, messy folders, confusing structure or a bloated codebase; mentions duplicated code, duplicate functions, copy-paste code, "código duplicado" or "função repetida"; asks to "give the codebase a deep clean" or to "reorganiza essas pastas"; or says the repo "grew too big", "is hard to navigate", "cresceu demais" or "tem coisa que ninguém usa". Also use when the user wants only one of the three phases on its own. Do NOT use for formatting or lint, vulnerable dependency updates, bundle size optimization, database cleanup or git history rewriting.
---

# Codebase Cleanup

Codebase cleanup in three sequential phases. The order is not negotiable:

**Clear out the dead → decide the boundaries → move the files.**

In reverse order you reorganize garbage into pretty folders and then find out
half of it should not exist. Each phase removes the noise that would get in the
next one's way: the module graph is only trustworthy once the dead code is
gone, and folders only make sense once module boundaries have stabilized.

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

There are **two scheduled checkpoints** in the pipeline (phase 2, choosing the
consolidation candidate; phase 3 on GREEN, confirming the folder plan before
any `git mv`) and **one conditional stop** at Step 0, when the working tree is
dirty before anything starts. Everything else runs on its own.

---

## Step 0 — Calibrate autonomy

Before anything else, measure the safety net. The autonomy level is a function
of it, not a preference.

```bash
git rev-parse --is-inside-work-tree       # is there a repo at all?
git status --porcelain                    # anything uncommitted?
git rev-parse --abbrev-ref HEAD           # current branch (HEAD = detached)
```

Read those three answers before running anything else:

**No git repository** (`--is-inside-work-tree` fails). The level is **RED**,
diagnosis only, whatever the gate says afterwards. Without commits there is no
rollback, and the whole safety argument of this skill rests on being able to
return to a good HEAD. Say so in one line and produce a report.

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

**Detached HEAD** (`--abbrev-ref HEAD` prints `HEAD`). Not a blocker: record
the current commit in `CLEANUP_PROGRESS.md` and create the cleanup branch
normally — it will branch off that commit, which is exactly what you want. Note
in the final report that the work started from a detached HEAD, so the user
knows where the branch came from.

With a clean tree and a repo, run the baseline gate with `scripts/gate.sh`
(path relative to this skill's directory; it accepts the project directory as
an argument) and classify. The
script detects the stack from the root manifest — `package.json`, `go.mod`,
`Cargo.toml`, `pyproject.toml`/`setup.cfg`, `pom.xml`/`build.gradle`,
`Gemfile`, `sln`/`csproj`/`fsproj` — and runs typecheck and tests for each one
it finds (compiling counts as typecheck).

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
autonomously. Exit code 124 is reserved for the watchdog, exactly as in GNU
timeout: a check that legitimately exits 124 is read as a timeout.

| Signal | Level | Behavior |
|---|---|---|
| Typecheck **and** tests pass | **GREEN** | Runs phase 1 in full without asking. Phase 2 and phase 3 each stop at their human checkpoint before mutating. |
| A partial net, or no test file in the stack | **YELLOW** | Runs phase 1 (deps and orphan files only, **not** exports). Does **not** run phase 2 or phase 3; reports and stops. |
| A check fails, or no tests and no typecheck | **RED** | Diagnoses only. Does not delete, does not move, does not commit. May create the cleanup branch; does **not** commit `CLEANUP_PROGRESS.md`. Delivers a report. |
| No git repository | **RED** | Diagnoses only, regardless of the gate result — there is no HEAD to roll back to. |

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

**Which npm script the gate reads.** For typecheck it takes the first of
`typecheck`, `type-check`, `check-types` the manifest defines, and stops there.
`tsc` is not on that list by name alone: as a script name it usually means an
emitting compile, and the output would land beside the sources. Exception: when
the script *value* carries `--noEmit` as a real shell word (comments stripped),
`tsc` counts as typecheck — a trailing `# use --noEmit in CI` does not. The
reverse is still uncovered: a script *named* `typecheck` whose body is
`tsc -p .` with no `--noEmit` emits just the same, and the gate cannot tell. If
the manifest has one, read it before phase 1.

For the suite it takes `test`; failing that, a lone `test:*` script, since a
repo that declares one slice and no whole is declaring its suite. Two or more
slices and no `test` count as nothing — half a net classified GREEN would
unlock dead-export deletion on code the other half covers — and a slice
declared with an empty command still counts as one of them. The exact npm-init
placeholder (`echo "Error: no test specified" && exit 1`) is recognised by
value and reported as `'test' not counted` with `npm init placeholder` — YELLOW,
not RED. A watch-mode slice never runs at all, because it does not exit:
`watch`, `ui` and `debug` are matched as whole segments of the name, so
`test:watch:all` is caught and `test:watchdog` is not. Not running one and not
counting one are separate questions. `watch` and `debug` name a mode of the
suite — the same tests, started so they never stop — so a `test:watch` beside a
lone `test:unit` does not split anything and the real slice is still the suite.
`ui` is not a mode word: `vitest --ui` does not exit either, but `test:ui` is
just as often a scope of its own, so it is never run *and* never leaves the
count — `test:unit` next to `test:ui` is two slices, not one. All of these print
the `'test' not counted` line naming the slices, and so does a manifest that
declares no test script at all. A split suite is **not** promotable by hand: it
is in the manifest, only divided, so run every slice before deciding.

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

The contract of each delegation:

- the path to this skill (the subagent reads SKILL.md and follows it, with
  references/ and scripts/ alongside) and the path to the repo;
- the instruction to read `CLEANUP_PROGRESS.md` before anything else;
- the scope of **one** phase — step 1.5 belongs to the phase 1 delegation
  (the `/clear` at its end is the phase 1 → phase 2 boundary), and phase 2
  becomes two delegations: the survey returns the candidates, the
  implementation only starts after the user's choice;
- returning a summary of what it did, with `CLEANUP_PROGRESS.md` updated as the
  canonical state.

Step 0 (calibrating the level, creating the branch), the phase 2 checkpoint
and the phase 3 checkpoint stay with the orchestrator — a subagent does not
talk to the user. Level and branch reach the subagents ready-made, through
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
`scripts/gate.sh` (it detects the stack and the package manager and runs
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
repo-local, so the user's `.gitignore` stays untouched. Ask git where it is
rather than typing the path: `git rev-parse --git-path info/exclude`, because
in a linked worktree, a submodule or a `--separate-git-dir` checkout `.git`
is a *file* and appending to `.git/info/exclude` fails with `Not a directory`.
Otherwise every category would be tempted to commit the report the previous
one was read from, and the user reverting `chore: remove unused deps` would
get a tool artifact back along with the dependencies.

That exclude only reaches **untracked** paths. If a previous run of this skill
already committed `knip-report.json`, git keeps seeing it no matter what the
exclude says, and the regeneration below puts a fresh diff on disk. Check with
`git status --porcelain` after writing the exclude lines; if the report still
shows up, find out whose it is first — `git log -1 --format=%s --
knip-report.json`. A previous run of this skill left `chore:` there and the
file is a tool artifact: untrack it in a commit of its own before the first
category (`git rm --cached knip-report.json`, then stage that pathspec only —
`chore: untrack knip report`). Anything else means the user tracks it on
purpose: leave it tracked, say so in the report, and do **not** pathspec-add
it into category commits. Do not fold that untrack into another category. On
the way out (final report / close), delete the report files and drop from the
exclude file only the lines you added — leave anything that was already there,
it is the user's — because the exclude makes a leftover invisible to
`git status` and nobody would find it later.

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
consolidation, and `scripts/gate.sh` once — after staging pathspecs of what
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
`git add -A`, and then `scripts/gate.sh` at the end of each folder —
typecheck alone misses what a move actually breaks (config paths, dynamic
imports; the "Do not forget" list in `references/phase-3-structure.md` has
the rest). Failed: `git restore --staged --worktree .`, record it, next
folder. If that restore is blocked by a hook, **abort** the pipeline.

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

## Final report

**Close hygiene first** (GREEN/YELLOW, when the run wrote artifacts): delete
`knip-report.json` / `knip-report.json.tmp` if present; drop from
`info/exclude` only the lines this run added; leave `CLEANUP_PROGRESS.md` and
`TECH_DEBT_AUDIT.md` committed unless the user asked to remove them — they are
the durable record, not tool noise. Say in the summary what was cleaned.

When wrapping up (or when interrupted), deliver:

```markdown
## Cleanup — summary
Branch: `cleanup/YYYYMMDD` · Level: GREEN · N commits

| Phase | Result |
|---|---|
| 1 — dead code | 7 deps, 23 files, 41 exports removed |
| 1.5 — duplicate functions | 6 pairs found, 2 real (churn), 4 left alone |
| 2 — consolidation | 3 modules → 1 (`src/billing/`) |
| 3 — structure | 4 folders reorganized, 2 cycles broken |

### Revert anything
`git revert <sha>` — commits are atomic per category.

### Failed / not done
- dead exports: typecheck broke in `src/api/routes.ts` (dynamic import)
- orphan files: out of scope — user asked deps only

### Pending your decision
- (nothing)
```

The phase 1 line counts what each category actually removed, tallied per commit
from the report that category ran on — not the numbers of the first report,
which stopped describing the repo the moment the first commit landed. The last
regeneration settles the rest: whatever it still lists is what survived, and it
belongs under "Failed / not done", along with any category that was skipped
(level cap or user scope).

If the level was RED, the report is diagnosis only: list what you would do and
what needs to exist or be fixed (tests, typecheck, a baseline that passes) to
make it possible. No `CLEANUP_PROGRESS.md` commit on RED.
