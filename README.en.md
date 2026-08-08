**English** · [Português](README.md) · [![ci](https://github.com/CRangelP/codebase-cleanup/actions/workflows/ci.yml/badge.svg)](https://github.com/CRangelP/codebase-cleanup/actions/workflows/ci.yml)

# codebase-cleanup

Codebase cleanup skill for Claude Code. It works in three phases, in this
order: remove dead code, consolidate shallow modules, reorganize the folder
structure. Between the first and the second sits phase 1.5, which looks for
duplicate files and functions — the same idea implemented twice under
different names — and hands the pairs over as consolidation candidates. The
order matters — reorganizing folders before deleting what is dead is tidying
garbage into a nice drawer.

The skill runs everything it can safely run on its own. It stops and asks in
two situations: the choice of consolidation candidate in phase 2, because a
module boundary is a domain decision, not a code decision; and right at the
start, if the working tree is dirty — then you pick between `git stash`,
committing the pending work or aborting, and nothing happens before your
answer.

## Requirements

- Claude Code with skill support.
- `git` — all work happens on a `cleanup/YYYYMMDD` branch, never on main. With
  no git repository the skill only diagnoses: its rollback depends on having a
  good commit to go back to.
- For JS/TS projects: Node with `npx` (knip runs via `npx knip`, no prior
  installation).
- Other stacks use the tools of each ecosystem (vulture, deadcode,
  cargo-udeps, ReferenceTrimmer). Whatever is missing, the skill reports
  instead of installing on its own.
- The gate (`scripts/gate.sh`) detects the stack from the manifest and runs
  typecheck + tests for JS/TS, Go, Rust, Python, JVM, Ruby and .NET. The
  toolchain has to be reachable: on PATH for most stacks and, for Python, also
  from `$VIRTUAL_ENV/bin`, `.venv/bin`, `venv/bin` or the `uv run` and
  `poetry run` runners (in that order). Every check runs under a watchdog
  (`GATE_TIMEOUT`, 900s by default, `0` disables it): if it runs out of time,
  the gate exits 4 and counts as inconclusive. It is a bash script (the bash
  3.2 shipped with macOS is enough); on Windows, use WSL.

## Installation

The skill is a folder. Installing means copying it into the skills directory:

```bash
# global (applies to every project)
cp -R codebase-cleanup ~/.claude/skills/

# or per project
cp -R codebase-cleanup .claude/skills/
```

If you have the `codebase-cleanup.skill` package (a zip), unpack it straight
into the destination:

```bash
unzip codebase-cleanup.skill -d ~/.claude/skills/
```

The installed structure:

```
codebase-cleanup/
├── SKILL.md                          main instructions
├── README.md                         readme in Portuguese
├── README.en.md                      this file
├── LICENSE                           MIT
├── references/
│   ├── audit.md                      phase 1.4 audit protocol
│   ├── knip-config.md                knip configuration without pitfalls
│   ├── duplication.md                duplicate functions and the churn rule
│   ├── phase-2-consolidation.md      module consolidation protocol
│   ├── phase-3-structure.md          folder organization patterns
│   └── other-stacks.md               Python, Go, Rust, JVM, Ruby, .NET
└── scripts/
    ├── gate.sh                       multi-stack typecheck + tests, exit 0/1/2/3/4
    ├── test.sh                       runs the three suites in sequence
    ├── gate_test.sh                  gate contract tests (toolchain stubs)
    ├── rollback_test.sh              executable proof of the rollback protocol
    └── coherence_test.sh             coherence invariants between docs and code
```

To check the installation, open a new session (or run `/reload-skills`) and
see whether `codebase-cleanup` shows up in the list of available skills.

### Tests

Three suites, with nothing to install beyond `bash` and `git`:

```bash
bash scripts/test.sh            # runs all three, stopping at the first failure

bash scripts/gate_test.sh       # gate contract: exit codes, the checks= line, PARTIAL
bash scripts/rollback_test.sh   # what `git restore` brings back and what it destroys
bash scripts/coherence_test.sh  # docs and code saying the same thing
```

Each exits 0 when everything passed and prints the failing case when it does
not; `test.sh` only chains the three and stops at the first red. None of them
touches the repository you run it from: the gate suite uses
toolchain stubs, the rollback suite builds throwaway repositories inside a
`mktemp -d`, with `HOME` redirected and the commit identity passed via `-c` —
your git config is never read nor written —, and the coherence suite only
reads files.

CI runs the three suites on every push and PR: ubuntu (real GNU `timeout`,
procps) and macOS with the stock `/bin/bash` 3.2.

The suites also run outside macOS. In a Linux container the hang case
exercises the real GNU `timeout` instead of the perl backend:

```bash
docker run --rm -v "$PWD":/repo:ro node:22-bookworm bash -c \
  'apt-get update -qq && apt-get install -y -qq procps && cd /repo && bash scripts/test.sh'
# validated 2026-08: 57/57 cases, 5/5 properties, 49/49 invariants
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

## Usage

There is no mandatory command. The skill triggers when the request sounds like
cleanup: "clean this project up", "there's stuff here nobody uses",
"remove the dead dependencies", "reorganize these folders". You can also
invoke it directly with `/codebase-cleanup`.

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
| GREEN | typecheck and tests pass | runs the phases without asking; phase 2 stops at the checkpoint |
| YELLOW | partial net, or no test file in the stack | only deps and orphan files, no touching exports |
| RED | no tests and no typecheck, or a baseline already failing | diagnoses only; nothing is deleted |

A project that arrives with a red suite falls into RED, not YELLOW: with a
broken baseline there is no telling what the cleanup broke from what was
already broken, and since every commit demands a green gate, none of them would
happen. The skill names the failing check and stops there.

A stack with no test file at all does not count as tested: the gate does not
run the empty suite and the level stays at YELLOW. That covers Go and .NET
with no test file, a Rust crate with no `tests/*.rs` and no `#[test]`, and a
pytest run that exits 5 having collected nothing. If your suite lives outside
the usual place, promoting it is your call — the gate never promotes itself.

With the level announced, it creates the cleanup branch and proceeds:

- **Phase 1 — dead code.** Configures knip until the hints reach zero, runs
  in production mode and deletes in atomic commits, one per category: unused
  deps, orphan files, dead exports. Each commit only lands with a green gate.
  At the end, it produces an audit of what is left.
- **Phase 1.5 — duplicate functions** (closes phase 1). Sweeps for functions
  with different names doing the same thing (similarity-ts or fallow on
  JS/TS, jscpd on other stacks) and applies the churn rule: a pair that
  changes together in git is real duplication and becomes a phase 2
  candidate; a pair that evolves independently is structural coincidence and
  is left alone. Report only — nothing is deleted here.
- **Phase 2 — consolidation.** Surfaces up to 5 shallow module candidates
  (starting from the phase 1.5 pairs), recommends one and asks a single
  question. Answer "go" and it implements.
- **Phase 3 — structure.** Diagnosis of the folder tree, plan, and moves with
  `git mv`, one folder per commit.

Between phases the skill asks for `/clear` — context accumulated from one
phase degrades the judgment of the next. Progress lives in
`CLEANUP_PROGRESS.md` at the repo root, so the next session resumes where it
stopped without you re-explaining anything. In environments with subagents,
the skill can run as an orchestrator and dispatch each phase to a disposable
context; the protocol is in Step 0.2 of SKILL.md.

### How to revert

Each category lives in its own commit. If something breaks later:

```bash
git log --oneline          # on the cleanup/YYYYMMDD branch
git revert <sha>           # undoes only that category
```

Merging the branch is your decision, on your schedule. The skill never
pushes, never commits on main and never uses `git reset --hard` — its
rollback is `git restore --staged --worktree .`, which throws away everything
that has not been committed yet and coexists with hooks that block destructive
commands.

Note the "everything": a change of yours sitting in the working tree before the
skill started would go with it. That is why it demands a clean tree up front
and stops to ask when it does not find one — with a clean tree, what the
rollback discards is what the skill itself created.

## Known limits

- Knip only covers JS/TS. In other stacks the confidence of automatic deletion
  drops along with the quality of the tool's graph — the table in
  `references/other-stacks.md` says when to delete and when to only diagnose.
- A dynamic import with a string assembled at runtime is invisible to the
  graph. The skill handles this by teaching knip (explicit entry) instead of
  deleting, but it is worth reviewing the generated `knip.json`.
- RED level returns a report, not a cleanup. If the project has neither tests
  nor typecheck, the first step is to create a minimal verification; the skill
  points the way in the report itself.
- Exit 124 is reserved for the watchdog, exactly as in GNU `timeout`: a
  check that legitimately exits 124 under an active watchdog reads as TIMEOUT.
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

None of them is a runtime dependency: they were sources and development
tools — nothing beyond this folder needs to be installed to use
codebase-cleanup.

## License

MIT — use, copy, modify and redistribute freely. Full text in
[LICENSE](LICENSE).
