# The gate contract

`"${CLAUDE_PLUGIN_ROOT:-.}/scripts/gate.sh"` is the measurement the whole
pipeline is calibrated against.
`SKILL.md` carries what changes a decision — classify by `checks=`, not by the
exit code; a partial list caps at YELLOW; exit 4 is inconclusive and never
green. This file carries the rest: the mechanics you only need when a result
does not look like what you expected.

## What it measures, and what that implies for staging

The gate runs the project's own checks against the **working tree**, not against
the index and not against a commit. So the thing it certifies is the state of
the files on disk at that moment, and everything that reaches a commit
afterwards has to be a subset of what was measured. That is why every step in
the protocol that runs the gate stages with an explicit pathspec —
`git add -- <paths…>` — and never `git add -A`: the pathspec is the only thing
keeping an unrelated untracked file, created between the measurement and the
commit, out of a commit the gate was never asked about.

## Where the script is

Installed as a
plugin, `CLAUDE_PLUGIN_ROOT` holds the absolute path of this plugin's
directory, so the call resolves from whatever directory the run happens to be
in; installed as a plain skill the variable is unset and `:-.` falls back to
the path relative to this file, which is what it always was. Either way the
script accepts the project directory as an argument and defaults to the
current one.

## What it detects

The script detects the stack from the root manifest — `package.json`, `go.mod`,
`Cargo.toml`, `pyproject.toml`/`setup.cfg`, `pom.xml`/`build.gradle`,
`Gemfile`, `sln`/`csproj`/`fsproj` — and runs typecheck and tests for each one
it finds (compiling counts as typecheck).

## Which npm script it reads

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

## Why 124 and 137 are reserved

Exit code 124 is reserved for the watchdog, exactly as in GNU
timeout: a check that legitimately exits 124 is read as a timeout. So is 137
(128+SIGKILL) while the watchdog runs with `-k`, because that is what the
kill-after escalation produces against a check that ignores TERM — reading it
as a plain failure would report a hung check as a broken one.

## What this file does not decide

Nothing here promotes a level. A cap is lifted by the user, by pointing at a
suite the gate does not look at, and the skill never promotes itself — that
rule lives in `SKILL.md` because it is a rule about authority, not about
mechanics, and rules about authority have to survive a compaction.
