# Phase 1 on non-JS/TS stacks

knip is JS/TS only. The logic of phase 1 is identical on any stack — what
changes is the tooling and, importantly, how **reliable** it is.

Detect the stack from the manifest: `package.json`, `pyproject.toml`/`requirements.txt`,
`go.mod`, `Cargo.toml`, `pom.xml`/`build.gradle`, `Gemfile`, `*.sln`/`*.csproj`.

## Python

```bash
pip install vulture pip-audit ruff deptry --quiet
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
Python.

Whitelist whatever it consistently gets wrong:

```bash
vulture src/ whitelist.py
```

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

## Java / Kotlin

```bash
mvn dependency:analyze              # declared and unused deps
./gradlew dependencies
```

Reflection, DI (Spring), annotations and SPI make static analysis unreliable.
On a JVM stack, stay at YELLOW level by default: remove only declared-and-unused
dependencies, and treat code as diagnosis.

## Ruby

```bash
bundle exec debride app/     # possibly dead code
bundle-audit check           # CVEs
```

Metaprogramming makes any result suspect. Diagnosis only.

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

---

## General rule

Confidence in automatic deletion follows the quality of the graph:

| Stack | Main tool | Autonomous deletion |
|---|---|---|
| JS/TS | knip (module graph) | yes, at GREEN |
| Go | deadcode (call graph) | yes, at GREEN |
| Rust | compiler + udeps | yes for deps, confirm code |
| Python | vulture (syntactic) | always confirm |
| .NET | ReferenceTrimmer (compiler data) | yes for deps, code is diagnosis |
| JVM / Ruby | — | diagnosis only |

When the tool does not build a reachability graph, it does not know what is
dead — it knows what *looks* dead. The difference matters when the order is to
delete without asking.

Phases 2 and 3 are stack-independent and apply to any language.
