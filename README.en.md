**English** · [Português](README.md) · [![ci](https://github.com/CRangelP/codebase-cleanup/actions/workflows/ci.yml/badge.svg)](https://github.com/CRangelP/codebase-cleanup/actions/workflows/ci.yml)

# codebase-cleanup

Codebase cleanup skill for Claude Code. It works in four phases, in this
order: remove dead code, consolidate shallow modules, reorganize the folder
structure, reshape the inside of the functions that survived. Between the
first and the second sits phase 1.5, which looks for duplicate files and
functions — the same idea implemented twice under different names — and hands
the pairs over as consolidation candidates. The order matters — reorganizing
folders before deleting what is dead is tidying garbage into a nice drawer,
and reshaping a function inside a module phase 2 consolidates away is work
done twice.

The skill runs everything it can safely run on its own. It stops and asks in
four situations: the choice of consolidation candidate in phase 2, because a
module boundary is a domain decision, not a code decision; the confirmation of
the folder plan in phase 3, before any `git mv`; phase 4, when the queue has a
tier B operation in it, which picks an abstraction or a domain name; and right
at the start, if the working tree is dirty — then you pick between `git stash`,
committing the pending work or aborting, and nothing happens before your
answer.

## Requirements

- Claude Code with skill support.
- `git` — all work happens on a `cleanup/YYYYMMDD` branch, never on main. With
  no git repository — or in one whose first commit was never made — the skill
  only diagnoses: its rollback depends on having a good commit to go back to,
  and `git init` alone gives none.
- For JS/TS projects: Node with `npx` (knip runs via `npx knip@6.32.0`,
  pinned — never bare `npx knip`).
- Other stacks use the tools of each ecosystem (vulture, deadcode,
  cargo-udeps, ReferenceTrimmer). Whatever is missing, the skill reports
  instead of installing on its own; `pip install` only with confirmation.
- The gate (`scripts/gate.sh`) detects the stack from the manifest and runs
  typecheck + tests for JS/TS, Go, Rust, Python, JVM, Ruby and .NET. The
  toolchain has to be reachable: on PATH for most stacks and, for Python, also
  from `$VIRTUAL_ENV/bin`, `.venv/bin`, `venv/bin` or the `uv run` and
  `poetry run` runners (in that order). Every check runs under a watchdog
  (`GATE_TIMEOUT`, 900s by default, `0` disables it): if it runs out of time,
  the gate exits 4 and counts as inconclusive. On JS/TS the suite's output is
  buffered and only appears once the command finishes — a test that leaves a
  detached grandchild holding the pipe would block the gate until that
  grandchild died, with the watchdog powerless. The gate says so before it
  starts; on a long suite it goes quiet, and going quiet is the expected shape,
  not a symptom of a hang. It is a bash script (the bash 3.2 shipped with macOS
  is enough); on Windows, use WSL.

## Installation

As a plugin, which is the recommended route — it brings versioning, updates
and the `PreToolUse` guards:

```bash
/plugin marketplace add CRangelP/codebase-cleanup
/plugin install codebase-cleanup@codebase-cleanup
```

Updating later is `/plugin update codebase-cleanup@codebase-cleanup`.

**Install scope decides where the skill exists, and `list` does not make that
obvious.** Installed from inside a project, the plugin gets `local` scope tied
to that directory — anywhere else, `claude plugin list` still says `enabled`,
`claude plugin details` still counts `Skills (1)`, and the model sees no skill
at all. To have it everywhere, install with `--scope user`; to find out where it
is actually active, the answer is the `projectPath` in
`~/.claude/plugins/installed_plugins.json`.

For a
team, declare it in the repository's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "codebase-cleanup": {
      "source": { "source": "github", "repo": "CRangelP/codebase-cleanup" }
    }
  },
  "enabledPlugins": { "codebase-cleanup@codebase-cleanup": true }
}
```

That installs nothing on anyone's machine: each person is asked once whether
they trust it and want it installed.

Copying the folder still works, and it is still a skill:

```bash
# global (applies to every project)
cp -R codebase-cleanup ~/.claude/skills/

# or per project
cp -R codebase-cleanup .claude/skills/
```

Copied that way it loads as a plugin too, because `.claude-plugin/` travels
with it — what changes is only where updates come from. If you have the
`codebase-cleanup.skill` package (a zip), unpack it straight into the
destination:

```bash
unzip codebase-cleanup.skill -d ~/.claude/skills/
```

**If you are migrating from the copy to the plugin, delete the copy.** Both forms
load at once and both carry "give this project a cleanup" in the `description`.
Explicit invocation disambiguates through the namespace
(`/codebase-cleanup:codebase-cleanup` is always the plugin), but the automatic
trigger sits on the fence and may land on the copy — the version you installed
that day, without the phases and fixes that came after:

```bash
rm -rf ~/.claude/skills/codebase-cleanup
```

The installed structure:

```
codebase-cleanup/
├── SKILL.md                          main instructions
├── README.md                         readme in Portuguese
├── README.en.md                      this file
├── LICENSE                           MIT
├── CHANGELOG.md                      what changed in each version
├── .claude-plugin/
│   ├── plugin.json                   plugin manifest (name, version, license)
│   └── marketplace.json              catalogue, for /plugin install
├── agents/
│   ├── cleanup-phase-1.md            phases 1 and 1.5
│   ├── cleanup-phase-2-survey.md     consolidation candidates (read-only)
│   ├── cleanup-phase-2-impl.md       implements the chosen candidate
│   ├── cleanup-phase-3-survey.md     structure plan (read-only)
│   ├── cleanup-phase-3-impl.md       executes the approved moves
│   ├── cleanup-phase-4-survey.md     reshaping queue (read-only)
│   └── cleanup-phase-4-impl.md       applies tier A and the approved tier B
├── docs/
│   ├── plugin-spec-research.md       host limits, official advice and mere habit
│   ├── attribution-frontier.md       what the skill buys and what the model already brings
│   ├── open-code-review-comparison-research.md  complementarity with OpenCodeReview
│   └── archify-folder-reorg-research.md  Archify as a map, not as Phase 3
├── hooks/
│   └── hooks.json                    registers the guard on the PreToolUse event
├── references/
│   ├── gate.md                       the gate contract: exit codes, watchdog, scripts
│   ├── audit.md                      phase 1.4 audit protocol
│   ├── complementarity-opencodereview.md  optional OCR on the cleanup/ branch
│   ├── final-report.md               the report template and how to fill it
│   ├── knip-config.md                knip configuration without pitfalls
│   ├── duplication.md                duplicate functions and the churn rule
│   ├── phase-2-consolidation.md      module consolidation protocol
│   ├── phase-3-structure.md          folder organization patterns
│   ├── phase-4-refactor.md           phase 4 protocol and the per-target net
│   ├── refactoring-catalog.md        the 11 operations, in two tiers
│   └── other-stacks.md               Python, Go, Rust, JVM, Ruby, .NET
└── scripts/
    ├── gate.sh                       multi-stack typecheck + tests, exit 0/1/2/3/4
    ├── guard.sh                      blocks the five commands the protocol forbids
    ├── test.sh                       runs the six suites in sequence
    ├── metrics.sh                    quality metrics, exit 0/2/3
    ├── gate_test.sh                  gate contract tests (toolchain stubs)
    ├── guard_test.sh                 what the guard blocks and what it lets through
    ├── rollback_test.sh              executable proof of the rollback protocol
    ├── eval.sh                      what the model does reading the skill (not in test.sh)
    ├── metrics_test.sh               measurer cases, on synthetic repos
    ├── coherence_test.sh             coherence invariants between docs and code
    ├── mutate.sh                     applies a mutation and proves it applied (STALE aborts)
    └── mutation_test.sh              mutates destructive-authority rules; each must fail
```

To check the installation, open a new session (or run `/reload-skills`) and
see whether `codebase-cleanup` shows up in the list of available skills.

### Tests

Six suites, with nothing to install beyond `bash` and `git`:

```bash
bash scripts/test.sh            # runs all six, stopping at the first failure

bash scripts/gate_test.sh       # gate contract: exit codes, the checks= line, PARTIAL
bash scripts/guard_test.sh      # what the guard blocks, and what it lets through
bash scripts/rollback_test.sh   # what `git restore` brings back and what it destroys
bash scripts/metrics_test.sh    # the quality measurer, on synthetic repos

# not in test.sh: runs the real model, costs minutes and money
bash scripts/eval.sh            # what the model does reading the skill
bash scripts/coherence_test.sh  # docs and code saying the same thing
bash scripts/mutation_test.sh   # would the suite above fail if the rule vanished?
```

The first `eval.sh` run downloads `knip@6.32.0` once, into
`~/.cache/codebase-cleanup-eval/.vendor/`, and copies that tree into every
fixture. That is deliberate: phase 1 runs `npx knip@6.32.0`, and with no local
copy that command needs the registry — a download inside a run capped by
`--max-turns` is either dead time or a red that has nothing to do with the
skill. With no network and no vendored tree the suite stops before spending the
first minute of model time, instead of finding out mid-case.

Every mutation made by hand — to prove an invariant bites, or that an eval case
fails when the rule disappears — goes through `mutate.sh`, which aborts when the
edit changed nothing. The reason is asymmetric: the expensive mutation is the one
that runs the model against the mutated copy, and its failure mode is silent in
the worst direction — an expression that does not match makes the run happen
against the **original** text, the green comes back, and it reads as "the case
does not bite" when nothing was ever mutated. `mutation_test.sh` runs that
guard's floors first and stops if they fail.

On the eval side the mutation is no longer made by hand:

```bash
EVAL_MUTATE='s/\Q<the sentence>\E/<the replacement>/' bash scripts/eval.sh yellow-run
```

The expression is applied to the copy **installed inside the fixture**, never to
this repository, and through the same `mutate.sh`. An expression that matches
nothing stops the suite **before** the first minute of model time, instead of
returning a green about a mutation that never happened. The old procedure — copy
the whole repository, edit, check by `grep`, run the copy — carried both failure
modes: the edit that does not apply, and the copy's `SKILL_ROOT` resolving to `/`.

`14/14 mutations caught` claims the **suite** notices the edit — not that the
model's **behavior** would change. Those are different questions, and when both
were finally measured on the same contract they disagreed: rewriting the RED
cell of the level table on its own moved nothing (51/51 — the run refused,
quoting a paragraph three sections below that the edit never touched), and only
rewriting all **four** seats together moved the behavior (47/51, with three
commits landed on a repository whose gate had said RED). The redundancy those
runs revealed is written down in section 16.7 of `coherence_test.sh`, because
redundancy no suite claims is redundancy a future cleanup removes.

Each exits 0 when everything passed and prints the failing case when it does
not; `test.sh` only chains the six and stops at the first red. None of them
touches the repository you run it from: the gate suite uses
toolchain stubs, the guard and rollback suites build throwaway repositories
inside a `mktemp -d`, with `HOME` redirected and the commit identity passed via
`-c` — your git config is never read nor written —, and the coherence suite
only reads files.

CI runs the six suites on every push and PR: ubuntu (real GNU `timeout`,
procps) and macOS with the stock `/bin/bash` 3.2. Both legs are required, not
redundant: on macOS the two `timeout -k` cases are skipped and counted, so the
total does not move and a regression in the watchdog's 137 branch passes green
there with the same `NN/NN`. That is why the `gate_test.sh` summary names what
the machine did not run — a complete validation takes both platforms.

The suites also run outside macOS. In a Linux container the hang case
exercises the real GNU `timeout` instead of the perl backend:

```bash
docker run --rm -v "$PWD":/repo:ro node:22-bookworm bash -c \
  'apt-get update -qq && apt-get install -y -qq procps && cd /repo && bash scripts/test.sh'
# validated 2026-08: 145/145 cases, 47/47 guard cases, 5/5 properties,
# 37/37 metrics cases, 525/525 invariants, 14/14 mutations caught
```

The .NET heuristic was validated against the real SDK
(`mcr.microsoft.com/dotnet/sdk:8.0` and `:10.0`, 2026-08): `dotnet test` with
no test project really is a no-op exit 0 on both, and the `xunit`, `nunit` and
`mstest` templates all match the markers — on 10.0 mstest matches only through
the `MSTest` token.

The third one turns into a test what used to depend on re-reading everything:
the rollback command written the same way everywhere, the gate's exit code
contract matching the READMEs, old instructions left behind, and a file tree
that agrees with what is on disk.

### No other skill is required

codebase-cleanup is self-contained by design. The pipeline calls tools
(knip, similarity-ts, jscpd, gate.sh), not other skills — and the knowledge
that came from third-party skills was absorbed into this one's files: the
phase 1.4 audit protocol lives in `references/audit.md`, and the phase 2
consolidation vocabulary in `references/phase-2-consolidation.md`.
Installing the skills named in the credits changes nothing at runtime; they
are sources, not dependencies.

### What `SKILL.md` carries, and what it defers

Every byte of `SKILL.md` is paid on **every** invocation: it enters the context
whole when the skill fires, including on invocations that never reach the phase
that text describes. The `references/*.md` are read only when the model decides
to open one. That is the only lever there is, and it has a price: what goes down
into a reference may not be read.

So the criterion is not size, it is **when the text is read**. What decides an
action stays in `SKILL.md` — the levels, the checkpoints, the rollback, and
every rule about what the skill may destroy. What goes down is what you only
consult after a result surprises you: the gate's internal mechanics, the final
report template, the procedure for a `knip-report.json` a previous run left
tracked.

The v0.4.0 extraction removed 4,431 bytes: **45,672 → 41,241** (851 → 770
lines). In tokens, which is the unit you pay in, measured by the host with
`claude plugin details codebase-cleanup`:

```
v0.3.5   44,801 bytes   ~15.7k on-invoke     (~370 always-on)
v0.4.0   41,241 bytes   ~14.3k on-invoke     (~370 always-on)
```

**~1,400 fewer tokens on every invocation** from that extraction. The two
measurements sit on different byte counts on purpose: between them the file
*grew* with the #55 fixes, and hiding that would make the extraction look
larger than it was. Since then `SKILL.md` has grown again with the phases and
the measured rules (today ~48 KB / ~880 lines at v0.10.0): the criterion remains
when the text is read, not a byte ceiling.

The arithmetic that preceded the measurement was wrong, and it is worth
recording how. Estimated from the file's average rate (2.85 bytes/token) the
projected saving was ~1,550 tokens, 11% above the real one. The extracted text —
commands, tables, code blocks — costs about 2.54 bytes per token, far denser
than the prose that stayed. **An average rate does not estimate a specific
cut**, and the ruler that counts is the host's.

The number alone says nothing — the pair says something, and the reduction is a
result, not a target. Nothing was removed "to make it smaller": a block whose
reading question had no clear answer stayed where it was.

Two things keep that arithmetic honest. Section 21 of `coherence_test.sh` walks
the reference graph from `SKILL.md` and fails any file nobody points at — an
orphaned reference is not deferred content, it is deleted content with extra
steps. And every extraction is asserted on **both sides**: the rule that decides
is still in `SKILL.md`, the procedure arrived intact at its destination.
Asserting only one side is how an extraction quietly becomes a deletion.

## Usage

There is no mandatory command. The skill triggers when the request sounds like
cleanup: "clean this project up", "there's stuff here nobody uses",
"remove the dead dependencies", "reorganize these folders". You can also
invoke it directly: `/codebase-cleanup:codebase-cleanup` when installed as a
plugin (plugin skills are always namespaced by the plugin name), or
`/codebase-cleanup` on a copied install.

Partial requests work — "remove only the unused dependencies" runs the
requested category and records the rest as out of scope.

### What happens when it runs

Before anything else it checks the ground: if the working tree has uncommitted
changes, it stops and asks what to do (stash, commit or abort) instead of
risking your work in progress on the first rollback. With a clean tree, it
measures the project's safety net with `scripts/gate.sh` and classifies itself
into one of three levels:

| Level | Condition | What it does |
|---|---|---|
| GREEN | typecheck and tests pass | runs phase 1 without asking; phase 2 and phase 3 stop at the human checkpoint; phase 4 applies tier A per covered target and stops at the tier B checkpoint |
| YELLOW | partial net, or no test file in the stack | only deps and orphan files, no touching exports; does not run phase 2, phase 3 or phase 4 |
| RED | no tests and no typecheck, or a baseline already failing | diagnoses only; nothing is deleted; no `CLEANUP_PROGRESS` commit |

Stack caps in `references/other-stacks.md` override the GREEN column (Python
always confirms before deleting; JVM/Ruby/.NET code stay YELLOW or diagnosis
by default).

A project that arrives with a red suite falls into RED, not YELLOW: with a
broken baseline there is no telling what the cleanup broke from what was
already broken, and since every commit demands a green gate, none of them would
happen. The skill names the failing check and stops there.

A stack with no test file at all does not count as tested: the gate does not
count an empty suite, whether it declined to run it or ran it and got nothing
back, and the level stays at YELLOW. That covers JS/TS whose runner exits on an
empty suite ("No test files found") — including when it exits 0 because it was
told to, as with `--passWithNoTests`, since exit 0 is not proof a suite ran —,
Go and .NET with no test file, a Rust
crate with no `tests/*.rs` and no `#[test]`, a Maven or Gradle build with no
`src/test` anywhere, a Ruby `spec/` or `test/` holding no `*_spec.rb`,
`*_test.rb` or `test_*.rb` (the `Rake::TestTask` default), and a pytest run
that exits 5 having collected nothing. A
manifest carried for tooling and nothing else — a `requirements.txt` for the
docs build, a `Gemfile` for fastlane — is not a stack without a suite: with no
source of that language in the repo, the gate says nothing about it. If your
suite lives outside the usual place, promoting it is your call — the gate never
promotes itself.

In JS/TS the exact `npm init` placeholder (`echo "Error: no test specified" &&
exit 1`) is also YELLOW, with `'test' not counted` and the `npm init
placeholder` marker — not RED for a broken suite. The same cap covers a sliced
suite: with no `test` script and both `test:unit` and `test:e2e` in the
manifest, no slice answers for the whole suite and the gate counts none of
them. Promoting by hand is the wrong move
here, because the suite is not somewhere else, it is split; run every slice. A
lone slice does count as the suite, with one exception: watch mode never exits,
so the gate skips it. `watch`, `ui` and `debug` are read as whole segments of
the name, which catches `test:watch:all` and leaves `test:watchdog` alone. Being
skipped and being uncounted are not the same, though: `watch` and `debug` are a
mode of the suite, so `test:watch` next to a lone `test:unit` leaves that slice
as the suite; `test:ui` may well be a suite of its own, so it is skipped and
still counted, and `test:unit` next to it is a split.

In a polyglot repo the cap survives the other stacks. Go with tests next to a
JS half that was never counted still prints `checks=typecheck,test`, because
each word came from a different manifest — and there the gate refuses to say
GREEN, naming the stack that has no suite instead.

With the level announced, it creates the cleanup branch and proceeds:

- **Phase 1 — dead code.** Configures knip until the hints reach zero, runs
  in production mode and deletes in atomic commits, one per category: unused
  deps, orphan files, dead exports. Before the first deletion, it writes an
  explicit **Preview (phase 1.3)** into `CLEANUP_PROGRESS.md` — the concrete
  deps, files and exports the report would remove — and commits that log
  update alone (`chore: preview phase 1 deletions`). On GREEN it proceeds
  without asking after that record exists; on YELLOW (or any stack cap) the
  preview omits what the level will not touch **and** what the user scoped
  out — scoped-out categories still get a Decisions line. Each delete step
  stages only pathspecs of that step's artifacts (`git add -- …`, never
  `git add -A`), and only lands with a green gate. At the end, phase **1.4**
  produces a full audit; every unit in the sweep ends `reviewed` or
  `skipped` with a reason, and the counts plus `coverage_rate` land under
  `## Coverage` in the progress log — a rate below 100% without a recorded
  Decisions gap leaves the step incomplete.
- **Phase 1.5 — duplicate functions** (closes phase 1). Sweeps for functions
  with different names doing the same thing (similarity-ts or fallow on
  JS/TS, jscpd on other stacks) and applies the churn rule: a pair that
  changes together in git is real duplication and becomes a phase 2
  candidate; a pair that evolves independently is structural coincidence and
  is left alone. The same **coverage mandate** applies: every detector pair
  is `reviewed` or `skipped` with a reason and a `coverage_rate` before the
  survey commit. Report only — nothing is deleted here.
- **Phase 2 — consolidation.** Surfaces up to 5 shallow module candidates
  (starting from the phase 1.5 pairs), recommends one and asks a single
  question. Answer "go" and it implements.
- **Phase 3 — structure.** Diagnosis of the folder tree, plan, and moves with
  `git mv`, one folder per commit.
- **Phase 4 — local reshaping.** Inherits targets from the 1.4 audit and from
  the 1.5 pairs phase 2 did not take, filtered by churn. The safety net is
  per target (is that function covered?), not the whole repository. Tier A
  runs on its own — up to 5 operations per session; tier B stops at a
  checkpoint and applies at most 1. One `refactor(<operation-id>)` per
  commit. Uncovered target: skip and record it, or write a characterization
  test as its own commit and then proceed — there is no third exit.

The final report (template in `references/final-report.md`) includes open
findings from the 1.4 audit as **Residual risks**, each with the audit's own
severity (`Critical` / `High` / `Medium` / `Low`) — unfinished business from
the cleanup, not a second audit. When the run left a `cleanup/` branch, the
summary may point to an optional OCR review under **Optional next step**
(see [Complementarity with OpenCodeReview](#complementarity-with-opencodereview));
never as a required protocol stage.

Between phases the skill asks for `/clear` — context accumulated from one
phase degrades the judgment of the next. Progress lives in
`CLEANUP_PROGRESS.md` at the repo root (including Preview and Coverage), so
the next session resumes where it stopped without you re-explaining anything. In environments with subagents,
the skill runs as an orchestrator and dispatches each phase to a disposable
context. Installed as a plugin, those subagents come declared in `agents/`:
`cleanup-phase-1` (phases 1 and 1.5), plus a survey and an implementation
agent for each of phases 2, 3 and 4. The survey agents cannot write — that is
how the checkpoint stops depending on good intentions: the question reaches you
before anything changed, and the implementation only starts after your answer.
The protocol is in Step 0.2 of SKILL.md.

### Complementarity with OpenCodeReview

This skill and [Alibaba OpenCodeReview](https://github.com/alibaba/open-code-review)
(OCR) solve different jobs. Cleanup mutates the tree behind a gate — dead
code, shallow modules, folders, local reshaping. OCR reviews a diff or PR
and leaves line-level comments; auto-fix without a human is out of its
roadmap. They are neighbours, not substitutes: OCR's "dead code" heuristics
on a diff are not a replacement for knip or vulture.

The skill does **not** install, vendor, or call the OCR Go binary. OCR stays
an optional CLI you install yourself when you want review QA after a cleanup.
The recipe — `ocr review` / `ocr delegate` against `cleanup/YYYYMMDD` — lives
in `references/complementarity-opencodereview.md`. When a run produced that
branch, the final summary may mention it as an optional next step; it is
never required.

### How to revert

Each category lives in its own commit. If something breaks later:

```bash
git log --oneline          # on the cleanup/YYYYMMDD branch
git revert <sha>           # undoes only that category
```

Merging the branch is your decision, on your schedule. The skill never
pushes, never commits on main and never uses `git reset --hard` — its
rollback is `git restore --staged --worktree .`, which throws away everything
that has not been committed yet. If a security hook blocks that restore, the
skill **aborts** the pipeline (it does not work around the hook): it reports
the branch, the dirty tree and the manual command, then stops.

Note the "everything": a change of yours sitting in the working tree before the
skill started would go with it. That is why it demands a clean tree up front
and stops to ask when it does not find one — with a clean tree, what the
rollback discards is what the skill itself created. Pathspec staging (instead
of `git add -A`) keeps drafts and local `.env` files out of the category
commit.

### The guards

Installed as a plugin, those prohibitions stop being text the model can
forget. `hooks/hooks.json` registers `scripts/guard.sh` on the `PreToolUse`
event, and it stops five commands before they run:

| Command | Why |
|---|---|
| `git reset --hard` | would take work that was in the tree before the cleanup started |
| `git clean` | would wipe untracked files that must survive: tool output, caches, local `.env` files |
| `git push` | the skill never publishes; merging is your decision |
| `git commit` on `main` | all the work lives on the cleanup branch |
| `git add -A` | whole-tree staging swallows into the commit what does not belong to the category |

The guard is only awake inside a run: HEAD on a `cleanup/` branch, or an
**untracked** `CLEANUP_PROGRESS.md` — which is what a RED run leaves behind,
and what exists before the first commit. A tracked log on a normal branch is a
cleanup that got merged, not a run in flight, so there it goes back to sleep;
without that distinction it would stay awake on main forever after the first
merge. Outside a run these commands are ordinary work, and it says nothing.

When in doubt it lets through. No repo, no JSON, no command: it exits 0 and
stays quiet. A guard that blocks by accident is worse than no guard, because
the skill **aborts** the pipeline when a command of the protocol is blocked —
a false positive kills a legitimate run. What it blocks and what it lets
through lives in `scripts/guard_test.sh`, including
`git restore --staged --worktree .`, `git revert`, `git mv`,
`git stash push -u` and pathspec `git add --`.

There is one thing those 47 cases do not reach, and it is worth naming: they
build the hook JSON by hand and call the script, so they prove the guard's
**behaviour** — not its delivery. That the `matcher` in `hooks.json` actually
routes the call, and that exit 2 reaches the model with its stderr attached, was
checked by hand with the plugin installed, not by a suite.

Since that is the only leg of the contract no suite covers, here is the
measurement, taken in a throwaway repository, inside a `cleanup/` branch, asking
the model for exactly the forbidden command:

> Blocked by the codebase-cleanup plugin hook: `git add -A` (whole-tree staging)
> is forbidden during cleanup, so it cannot swallow someone else's file into the
> category commit. I will not route around it — a block that fired is final.
> […] To stage by pathspec: `git add -- novo.ts`

The three things that matter are all there: the block arrived, the **reason**
arrived with it, and the model offered the correct form instead of looking for a
way around. That is what the distinction protects — a guard that blocks without
delivering the reason becomes an opaque error, and a model that cannot read the
reason rephrases the command until it slips through.

## Known limits

- Knip only covers JS/TS. In other stacks the confidence of automatic deletion
  drops along with the quality of the tool's graph — the table in
  `references/other-stacks.md` says when to delete and when to only diagnose.
- A dynamic import with a string assembled at runtime is invisible to the
  graph. The skill handles this by teaching knip (explicit entry) instead of
  deleting, but it is worth reviewing the generated `knip.json`.
- RED level returns a report, not a cleanup. That covers a project with
  neither tests nor typecheck, and one that arrives with a red suite. With no
  tests, the first step is to create a minimal verification; with a broken
  suite, it is to fix the check the report names.
- Exit 124 is reserved for the watchdog, exactly as in GNU `timeout`: a
  check that legitimately exits 124 under an active watchdog reads as TIMEOUT.
  Exit 137 reads the same way while the watchdog runs with `-k`, since that is
  the code the kill-after escalation produces against a check that ignores TERM.
- With a single `.sln`/`.slnx` at the root the gate passes it explicitly to
  `dotnet`; with two or more it abstains and invokes with no argument, and
  the ambiguity is MSBuild's again. It fails closed: run the gate by hand
  pointing at the solution.
- A Rust crate whose tests exist only as doc-tests (or come out of a macro)
  falls to the YELLOW cap — the evidence searched for is `tests/*.rs` or
  `#[test]` in the sources. Promote by hand if the suite lives elsewhere.
- A folder with no git falls into RED as well, even with typecheck and tests
  passing. With no commit there is no rollback, and the rollback is what holds
  up the autonomy of the rest of the pipeline.
- The unused-deps category runs the package manager's plain install after
  pruning the manifest, so the lockfile is rewritten and `node_modules`
  re-resolved. That part is outside the rollback: `git restore` brings back
  `package.json` and the lockfile, never the installed tree. Run the install
  again if that category is the one that fails; the other two never touch the
  manifest and do not need it.

## Credits

Skills and materials used in building this one:

- [tech-debt-audit](https://github.com/ksimback/tech-debt-skill), by ksimback
  (MIT) — the phase 1.4 audit protocol (`references/audit.md`) is distilled
  from it: the nine dimensions, the report template and the required "looks
  bad but is fine" section.
- [codebase-design and improve-codebase-architecture](https://github.com/mattpocock/skills),
  by Matt Pocock — phase 2's analysis vocabulary (module, interface,
  implementation, depth, seam, adapter, locality), the deletion test and the
  definition of a shallow module come from these skills. Seam and module
  depth trace back to Michael Feathers and John Ousterhout (*A Philosophy of
  Software Design*).
- [skill-creator](https://github.com/anthropics/claude-plugins-official),
  Anthropic's official plugin — it drove the best-practice review, the
  comparative evals and the description optimization of this skill.
- [Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing),
  from Wikipedia's WikiProject AI Cleanup — the basis of the local adaptation
  `humanizer-pt-br`, used to write this README.
- [OpenCodeReview](https://github.com/alibaba/open-code-review), by Alibaba
  (Apache-2.0) — not embedded here; its review discipline (preview before
  spend, coverage checklists, severity on findings) informed the named
  preview, coverage mandate and residual-risks sections of this protocol.
  Optional post-cleanup QA recipe:
  `references/complementarity-opencodereview.md`.

None of them is a runtime dependency: they were sources and development
tools — nothing beyond this folder needs to be installed to use
codebase-cleanup. OCR remains optional and external if you choose to run it.

## License

MIT — use, copy, modify and redistribute freely. Full text in
[LICENSE](LICENSE).

The optional OpenCodeReview CLI is licensed under Apache-2.0 and is **not**
vendored, bundled, or required by this skill. Describing how to use it does
not relicense this repository; this project's own source and documentation
stay MIT.
