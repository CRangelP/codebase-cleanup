# Phase 1 on non-JS/TS stacks

knip is JS/TS only. The logic of phase 1 is identical on any stack — what
changes is the tooling and, importantly, how **reliable** it is.

Detect the stack from the manifest: `package.json`, `pyproject.toml`/`requirements.txt`,
`go.mod`, `Cargo.toml`, `pom.xml`/`build.gradle`, `Gemfile`, `*.sln`/`*.csproj`.

**Stack caps override the GREEN column in `SKILL.md`.** When this file says
confirm, stay at YELLOW by default, or diagnosis only, that rule wins even if
the gate printed GREEN — the executor must read this table before deleting.
The levels table in `SKILL.md` points here for that reason.

## Python

**Do not run `pip install` (or `uv tool install` / `pipx`) without an explicit
confirmation from the user.** Installing into the active interpreter can write
into the project venv under cleanup, and on PEP 668 distros a bare
`pip install` aborts with `externally-managed-environment`. Ask once, naming
the tools and the preferred install path (`pipx`, `uv tool`, or the project's
own venv), and wait. If the tools are already on PATH, skip the install.

```bash
# Only after the user confirms — prefer an isolated install:
#   pipx install vulture pip-audit ruff deptry
#   # or: uv tool install …
#   # or: python -m pip install … inside the project's venv, if they say so
vulture src/ --min-confidence 80     # dead code
pip-audit                            # CVEs
ruff check --select F401,F841 src/   # unused imports and variables
deptry .                             # unused / undeclared deps
```

**Calibrate `--min-confidence`.** Below 80, vulture becomes noise. Even at 100
it gets these wrong: Django/Flask (views, signals, management commands),
pytest (fixtures, conftest), Celery tasks, Pydantic validators, `__all__`, and
anything reached through `getattr`.

Vulture is syntactic analysis, not a module graph. It is **substantially less
reliable than knip** — treat its output as a list of candidates to investigate,
never as a deletion list. At GREEN level, still confirm before deleting in
Python — autonomous deletion caps at YELLOW for this stack (see the table
below).

Whitelist whatever it consistently gets wrong:

```bash
vulture src/ whitelist.py
```

**Unused deps: re-resolve after pruning the manifest.** Editing
`pyproject.toml` / `requirements*.txt` does not remove the package from an
already-populated venv, so the gate can still import it. After pruning and
before staging, re-resolve with the project's tool — never a frozen/locked
form that refuses an intentionally changed lock:

```bash
pip install -r requirements.txt          # plain requirements
# or, matching the repo:
poetry lock && poetry install            # Poetry (not --no-update alone if the lock must drop)
uv sync                                  # uv
pip-compile && pip-sync                  # pip-tools, when that is the workflow
```

The updated lock (when the project has one) goes in this category's commit.

## Go

```bash
govulncheck ./...            # CVEs, with reachability analysis
staticcheck ./...            # U1000 = unused
golangci-lint run            # aggregator
go mod tidy                  # deps
deadcode ./...               # official, x/tools
```

x/tools' `deadcode` is conceptually the closest thing to knip — it starts from
the entry points and walks the call graph. Prefer it over `staticcheck U1000`
for orphan files.

Watch out for exported identifiers: in a library package, exported with no
internal use is the public interface, not dead code.

**Unused deps: `go mod tidy` after pruning `go.mod`.** Removing a require line
by hand leaves the old graph in `go.sum` / the module cache view the next
build may still see. After editing the manifest and before staging, run:

```bash
go mod tidy
```

`go.sum` changes belong in this category's commit. Do not use a mode that
refuses a changed `go.mod` — tidy is the sync step.

## Rust

```bash
cargo audit                  # CVEs
cargo udeps --all-targets    # unused deps (requires nightly)
cargo machete                # unused deps, faster, less precise
cargo +nightly udeps
```

The compiler already reports `dead_code` — `#![warn(dead_code)]` plus reading
the warnings covers most of it. Watch out for `#[cfg(feature = "...")]`: code
behind a disabled feature shows up as dead.

**Unused deps: refresh the lock after pruning `Cargo.toml`.** A removed
dependency can still satisfy resolution from `Cargo.lock` until the lock is
rewritten. After editing the manifest and before staging:

```bash
cargo generate-lockfile
# or a plain `cargo check` / `cargo build` that rewrites Cargo.lock — not
# `--locked` / `--frozen`, which refuse the intentional prune
```

`Cargo.lock` goes in this category's commit when the project tracks it.

## Java / Kotlin

```bash
mvn dependency:analyze              # declared and unused deps
./gradlew dependencies
```

Reflection, DI (Spring), annotations and SPI make static analysis unreliable.
On a JVM stack, stay at YELLOW level by default: remove only declared-and-unused
dependencies, and treat code as diagnosis.

**Unused deps:** after pruning the Maven/Gradle manifest, refresh the resolved
classpath before the gate (plain `mvn -q dependency:resolve` or
`./gradlew dependencies`, not a CI "frozen" restore that assumes the old
lock). Module metadata / lockfile updates that the prune produced belong in
the category commit.

## Ruby

```bash
bundle exec debride app/     # possibly dead code
bundle-audit check           # CVEs
```

Metaprogramming makes any result suspect. Diagnosis only — never autonomous
deletion of Ruby code under this skill, regardless of the gate colour.

**Unused deps:** after pruning the `Gemfile`, run a plain
`bundle install` (not `--deployment` / `--frozen`) so `Gemfile.lock` matches
before the gate; the lock update goes in the category commit.

## .NET (C# / F#)

```bash
dotnet build --nologo                # typecheck (this is what the gate runs)
dotnet test --nologo
dotnet list package --vulnerable     # CVEs
dotnet list package --deprecated
```

For deps and dead code, in order of confidence:

- **ReferenceTrimmer** (MSBuild task + analyzer): points out unused references
  and packages using the compiler's own `GetUsedAssemblyReferences`. It is
  compiler data, not a heuristic — the safest removal on the stack.
- **DotnetUnused** (CLI on top of Roslyn): unused methods, properties and
  fields; `--unused-packages` covers NuGet packages.
- Built-in analyzers `IDE0051`/`IDE0052`: unused private members, with nothing
  to install.

Reflection, DI (ASP.NET Core), serialization and attribute-based discovery have
the same effect as on the JVM: code analysis is unreliable. YELLOW by default —
deps flagged by the compiler can go, code is diagnosis.

**Unused deps: `dotnet restore` after pruning the project/package refs.** The
assets file and package cache still satisfy the old graph until restore runs.
After editing `.csproj`/`.fsproj`/`Directory.Packages.props` and before
staging:

```bash
dotnet restore
```

Do not use a restore mode that treats the previous lock/assets as immutable
when the prune intentionally changed them. Lockable files the prune updated
go in this category's commit.

---

## General rule

Confidence in automatic deletion follows the quality of the graph:

| Stack | Main tool | Autonomous deletion |
|---|---|---|
| JS/TS | knip (module graph) | yes, at GREEN |
| Go | deadcode (call graph) | yes, at GREEN |
| Rust | compiler + udeps | yes for deps, confirm code |
| Python | vulture (syntactic) | always confirm (YELLOW cap for deletion) |
| .NET | ReferenceTrimmer (compiler data) | yes for deps, code is diagnosis (YELLOW default) |
| JVM / Ruby | — | diagnosis only (YELLOW / diagnosis; never promote code deletion) |

When the tool does not build a reachability graph, it does not know what is
dead — it knows what *looks* dead. The difference matters when the order is to
delete without asking.

**After every unused-deps prune**, the stack-specific re-resolve / tidy /
restore above is mandatory before staging and the gate — same reason as the
JS/TS install step in `SKILL.md`: a populated environment makes a blind green
gate.

Phases 2 and 3 are stack-independent and apply to any language.
