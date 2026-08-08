**English** · [Português](README.md)

# codebase-cleanup

Codebase cleanup skill for Claude Code. It works in three phases, in this
order: remove dead code, consolidate shallow modules, reorganize the folder
structure. The order matters — reorganizing folders before deleting what is
dead is tidying garbage into a nice drawer.

The skill runs everything it can safely run on its own. The one place where it
stops and asks is the choice of consolidation candidate in phase 2, because a
module boundary is a domain decision, not a code decision.

## Requirements

- Claude Code with skill support.
- `git` — all work happens on a `cleanup/YYYYMMDD` branch, never on main.
- For JS/TS projects: Node with `npx` (knip runs via `npx knip`, no prior
  installation).
- Other stacks use the tools of each ecosystem (vulture, deadcode,
  cargo-udeps, ReferenceTrimmer). Whatever is missing, the skill reports
  instead of installing on its own.
- The gate (`scripts/gate.sh`) detects the stack from the manifest and runs
  typecheck + tests for JS/TS, Go, Rust, Python, JVM, Ruby and .NET — the
  toolchain only has to be on PATH. It is a bash script (the bash 3.2 shipped
  with macOS is enough); on Windows, use WSL.

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
    ├── gate.sh                       multi-stack typecheck + tests, exit 0/1/2/3
    └── gate_test.sh                  gate contract tests (toolchain stubs)
```

To check the installation, open a new session (or run `/reload-skills`) and
see whether `codebase-cleanup` shows up in the list of available skills.

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

Before touching any file, the skill measures the project's safety net with
`scripts/gate.sh` and classifies itself into one of three levels:

| Level | Condition | What it does |
|---|---|---|
| GREEN | typecheck and tests pass | runs the full phases without asking |
| YELLOW | partial net | only deps and orphan files, no touching exports |
| RED | no tests and no typecheck | diagnoses only; nothing is deleted |

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
rollback is `git restore --staged --worktree .`, which discards only what has
not been committed yet and coexists with hooks that block destructive
commands.

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
