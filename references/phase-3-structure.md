# Phase 3 — Folder structure

## Diagnosis

Before moving any file, produce:

1. **Map of the current structure** — depth, what lives where, what has no
   clear owner
2. **Circular dependencies** — from knip's `cycles` or from `madge --circular`.
   `cycles` is not in knip's default issue set: run `npx knip --cycles`
   (shortcut for `--include cycles`), otherwise the report comes back silent
   on this point
3. **God modules** — directories that everyone imports
4. **Leaking abstractions** — a module's internal detail referenced from
   outside
5. **Target structure** with a rationale per move
6. **Phased plan** — the order of the moves, starting with the lowest risk

## Choose the pattern

There is no universally correct structure. There is a structure consistent
with what the project already is.

**By feature (colocation)** — utils, styles, tests and types live in the same
directory as the logic they serve. Choose it when the project has features
with clear boundaries and the global `utils/` has turned into a dumping
ground.

The real gain is not aesthetic: a global `utils/` is where dead code hides for
years, because nobody knows who calls what. Colocation turns "is this dead?"
into a local question, answerable by looking at one directory.

**By layer** (`controllers/`, `services/`, `repositories/`) — choose it when
the project is already like that and is consistent. Migrating layer→feature in
a large codebase is a project of its own, not a cleanup; if the diagnosis
points there, deliver it as a recommendation and do not execute without an
explicit signal.

**Language convention** — Go, Rust, Python and Node have expected layouts
(`cmd/`, `internal/`, `src/`, `tests/`). If the project does not follow its own
language's convention, that is the first target and the one with the best
return: anyone new understands it without explanation.

## Heuristics

- A directory with a single file almost always should not be a directory
- Depth beyond 4 levels usually means an invented category
- A generic name (`helpers`, `common`, `shared`, `misc`) signals that nobody
  knew where to put things — investigate the contents, they are rarely cohesive
- A file whose name repeats the directory (`user/userService.ts`) means
  naming redundancy, not structural redundancy
- If two directories always change together in `git log`, they are probably one

## Execution

One folder per commit. Always:

```bash
mkdir -p src/features/billing
git mv src/utils/format.ts src/features/billing/format.ts
```

The `mkdir -p` is not decoration: phase 3 applies a structure that does not
exist yet, and moving into a directory nobody created fails with `fatal:
renaming ... failed: No such file or directory` and exit 128. That is a
missing precondition, not a failed step — create the directory and repeat the
move. Do not fall back to `mv` plus `git rm`/`git add`: that is `rm` +
`create` under another name.

`git mv` preserves history. `rm` + `create` destroys that file's `git blame` —
exactly the information someone will want six months from now when asking "why
is this like this".

**Prefer updating path aliases over rewriting imports** when every consumer of
the code honors `tsconfig.json` `paths`. If the project uses `@/features/*`,
moving a folder can be one line of config instead of a 3,000-line diff nobody
can review. The catch is that the alias only holds where it is read: the
bundler, the test runner, the linter and the Docker build each resolve paths
their own way, and `paths` in `tsconfig.json` does not reach any of them by
itself. Check the "Do not forget" list below before betting the move on a
one-line change.

**One commit per folder, and everything the move needs goes in it**: the
`git mv`, the import or alias update, and the `CLAUDE.md`/docs update. Do not
split the move from the import rewrite. A "pure `git mv`" commit does not
compile — every import pointing at the old path is broken — so it cannot pass
the gate, and committing it anyway puts a state in history that the user cannot
revert to. A commit per folder keeps the useful property: something broke after
the merge, `git revert <sha>` takes that folder back with its imports and its
docs, in one shot.

`git add -A` and then `scripts/gate.sh` at the end of each folder — staged
first, so that the rollback also undoes files created during the move. Typecheck
alone is not enough here: the "Do not forget" list below is mostly made of
things that only break at runtime, and the test suite is what catches part of
them. Failed → `git restore --staged --worktree .`, record it, next folder.

## Do not forget

Things that point at paths and break silently when folders move:

- `tsconfig.json` (`paths`, `include`), `jsconfig.json`
- bundler config (vite, webpack, rollup), `jest.config`, `vitest.config`
- `knip.json` — if you changed the structure, `entry`/`project` changed
- `.eslintrc` with per-directory `overrides`
- CI: paths in workflows, `Dockerfile`, `.dockerignore`
- `CODEOWNERS`
- dynamic imports with a string built at runtime — typecheck does **not** catch
  them
- `CLAUDE.md` and docs that describe the old structure

The last item is the most forgotten and the most expensive: a `CLAUDE.md`
describing a structure that no longer exists makes every future agent work from
the wrong map. Update it in the same commit as the move.
