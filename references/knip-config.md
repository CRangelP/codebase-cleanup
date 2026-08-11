# knip configuration

Read this before writing `knip.json`. Applies to JS/TS only.

This guide was written against knip v6. The pipeline pins
`npx knip@6.32.0` (verified 2026-08-09); check that pin with
`npx knip@6.32.0 --version`. If you intentionally use another major, validate
whatever diverges against the official docs (knip.dev) — especially the
schema, cycle detection and option names. Adjust the `$schema` version below
to the major in use. Never bare `npx knip`.

## Index
- [Order of work](#order-of-work)
- [Skeleton](#skeleton)
- [Import aliases](#import-aliases)
- [Production mode](#production-mode)
- [When you need to suppress something](#when-you-need-to-suppress-something)
- [Plugins](#plugins)
- [Monorepo](#monorepo)
- [Cycle detection](#cycle-detection)
- [Pitfalls](#pitfalls)

## Order of work

1. `npx knip@6.32.0` with no config at all
2. Resolve **every** configuration hint
3. Only then write/adjust `knip.json`
4. Repeat 2–3 until the hints reach zero
5. `npx knip@6.32.0 --production --no-exit-code --reporter json > knip-report.json.tmp && mv knip-report.json.tmp knip-report.json`
6. Check the result before using it: `knip-report.json.tmp` gone, and
   `knip-report.json` non-empty and parsing as JSON

The temp file plus `&&` is what keeps a crashed run from wiping the previous
report — a plain `>` truncates it before knip starts. `--no-exit-code` is
required there because knip exits 1 on every run that finds issues; only exit
2 means it failed. The missing `.tmp` is the load-bearing half of step 6: when
knip breaks, the `&&` skips the `mv` and the *previous* report stays on disk,
non-empty and perfectly parseable, so the content checks alone would wave a
stale list through.

The right mindset: when knip reports something unexpected, it is telling the
truth about the module graph — it could not reach that code from an entry. A
surprising result is either a real finding or a configuration gap, almost never
a false positive to silence.

## Skeleton

```jsonc
{
  "$schema": "https://unpkg.com/knip@6/schema.json",
  "entry": ["src/main.ts", "scripts/*.ts", "!scripts/scratch.ts"],
  "project": ["src/**/*.{ts,tsx}", "scripts/**/*.ts"]
}
```

- `entry` — the graph's roots, where the walk starts
- `project` — the universe of files under consideration
- a dead file is in `project` but unreachable from `entry`
- the `!` prefix negates the pattern
- the `!` suffix marks the pattern as production-mode only

Use `knip.jsonc` (schema `schema-jsonc.json`) if you want comments — worth it
to document why each exotic entry exists.

## Import aliases

The single largest source of mass false positives. knip includes the tsconfig's
`compilerOptions.paths` automatically, but **not** webpack, Babel, vite or jest
`moduleNameMapper` aliases. Declare those by hand:

```jsonc
{
  "paths": {
    "@lib": ["./lib/index.ts"],
    "@lib/*": ["./lib/*"]
  }
}
```

Same semantics as TypeScript: values are arrays of relative paths, and patterns
without `*` are exact matches. Each workspace can have its own `paths`.

## Production mode

```bash
npx knip@6.32.0 --production
```

Excludes tests and devDependencies automatically. This is what separates "alive"
from "alive only for the tests" — code that exists only to satisfy the suite is
debt, not functionality.

**Never** try to get the same effect with `ignore` on `**/*.test.ts`.

## When you need to suppress something

Avoid `ignore`: it does not exclude anything from the analysis, it only
suppresses the report, creating a blind spot. There is always a more surgical
option:

| Situation | Option |
|---|---|
| Generated code, should not count as a dead file | `ignoreFiles` |
| Dep used in a way invisible to the graph | `ignoreDependencies` |
| Only certain issue types in generated files | `ignoreIssues` |
| Export used only inside its own file | `ignoreExportsUsedInFile` |
| Binary called from a script, with no matching package | `ignoreBinaries` |
| Enum/namespace member | `ignoreMembers` |
| Specifier that does not resolve | `ignoreUnresolved` |
| Tests getting in the way | `--production` (never `ignore`) |

`ignoreFiles` differs from `ignore` by affecting only the unused-files section —
the file is still analyzed for exports, deps and unresolved imports. It is
almost always what you meant when you reached for `ignore`.

```jsonc
{
  "ignoreFiles": ["src/generated/**", "fixtures/**"],
  "ignoreDependencies": ["hidden-package", "@org/.+"],
  "ignoreIssues": {
    "src/generated/**": ["exports", "types"]
  },
  "ignoreExportsUsedInFile": { "interface": true, "type": true }
}
```

`ignoreDependencies`, `ignoreBinaries`, `ignoreUnresolved` and `ignoreMembers`
accept regex. Real regex (not a string) works only in a dynamic `.ts` config.

An alternative to pattern-based suppression: JSDoc tags.

```ts
/** @internal */
export const x = 1;
```

```jsonc
{ "tags": ["-internal"] }
```

## Plugins

```jsonc
{
  "playwright": true,                    // force enable
  "webpack": false,                      // disable
  "mocha": {
    "config": "config/mocha.config.js",
    "entry": ["**/*.spec.js"]
  }
}
```

Overriding a plugin's `entry` is rarely necessary — plugins already read the
custom patterns from each tool's own configuration. Plugin configuration works
at the root and per workspace, and one level can disable what another enabled.

## Monorepo

A gotcha that breaks silently: **in a project with workspaces, root-level
`entry` and `project` are ignored.** Use the `"."` workspace.

```jsonc
{
  "workspaces": {
    ".":            { "entry": ["scripts/*.ts"], "project": ["scripts/**/*.ts"] },
    "packages/*":   { "entry": ["src/index.ts"], "project": ["src/**/*.ts"] },
    "packages/cli": { "entry": ["bin/cli.js"] }
  }
}
```

- a workspace is a directory with a `package.json`
- workspaces declared here and absent from `package.json`/`pnpm-workspace.yaml`
  are **added** to the analysis
- root-only options: `include`, `exclude`, `ignoreWorkspaces`, `workspaces`
- workspaces do not nest in the config (but they can nest on the filesystem)
- a project with a single root `package.json` → see "integrated monorepos" in
  the docs, not workspaces

In a monorepo, to investigate a single package use `-W <dir>` (long form
`--workspace <dir>`), which narrows the analysis to that workspace and the
ones it depends on. Add `--strict` so each dependency is required to be in
that workspace's own `package.json` instead of being resolved from the root:

```bash
npx knip@6.32.0 -W packages/api --strict
```

## Cycle detection

Native in v6 — no need for madge in most cases.

```jsonc
{
  "cycles": {
    "dynamicImports": true,
    "allow": [["src/i18n/index.ts", "src/i18n/middleware.ts"]]
  }
}
```

Dynamic-import edges are **out** by default: a dynamic import defers
evaluation, so it does not cause the initialization hazard that cycle detection
exists to catch. Turn `dynamicImports` on only if you want the full graph for
phase 3.

Paths in `allow` are relative to the root and omit the trailing repetition of
the first file.

## Pitfalls

**`--fix` too early.** Running it before the config settles is destructive.
Wait for two or three rounds where the output no longer surprises you.

**Auto-imports and auto-mocking** (Nuxt, Jest) make code look orphaned. The fix
is to extend the `entry` patterns, not to ignore.

**Convention-based routes** (Next pages, handlers registered by glob) and
dynamic imports with a string built at runtime are invisible to the graph.
Declare them as entries explicitly.

**Multiple `.eslintrc`/`jest.config.js`** in a repo with a single
`package.json` show up as unused. That is an integrated monorepo case, not an
ignore case.

**`treatConfigHintsAsErrors: true`** is good for CI once the config has
stabilized — it stops anyone from changing the build and leaving the graph
full of holes unnoticed.

## When a previous run left `knip-report.json` tracked

`SKILL.md` carries the rule — find out whose the file is before touching it, and
never delete or untrack one the user keeps on purpose. This is how you find out,
and what to do once you know.

```bash
git log -1 --format=%s -- knip-report.json
```

A `chore:` subject from an earlier run of this skill means the file is a tool
artifact that got committed by mistake. Untrack it in a commit of its own,
before the first category, staging that pathspec and nothing else:

```bash
git rm --cached knip-report.json
git add -- knip-report.json
git commit -m "chore: untrack knip report"
```

Do not fold that untrack into a category commit. The categories are the unit the
user reverts, and a revert that also puts a tool artifact back is a revert that
did something the user did not ask for.

Any other subject means the user tracks the report on purpose — a repo that
commits its own analysis output is a legitimate choice. Leave the tracked file
alone, note it in the final report, and keep it out of every category commit.
