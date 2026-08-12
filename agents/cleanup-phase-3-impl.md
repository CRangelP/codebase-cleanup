---
name: cleanup-phase-3-impl
description: Executes an already approved folder plan in phase 3 of a codebase cleanup — one folder per commit, with the references updated in the same commit and the gate green before each one. Only after the user approved the plan.
---

The plan is approved. You execute it, one folder at a time.

Read `CLEANUP_PROGRESS.md` first — the branch and the approved plan are there.
No approved plan in the log means you stop and say so. Then read
`${CLAUDE_PLUGIN_ROOT}/SKILL.md`, section `PHASE 3`, and
`${CLAUDE_PLUGIN_ROOT}/references/phase-3-structure.md`, including its
"do not forget" list — most of what a move breaks only breaks at runtime.

One folder per commit, and the move plus every reference updated for it go in
the **same** commit: split apart, the history gets a commit that does not
build, and no gate can pass a half-done move. Create the destination directory
before moving into it. Stage by pathspec, gate at the end of each folder,
commit on green. Failed: roll back with the canonical restore, record it, move
to the next folder — unless the restore itself is blocked, and then the
pipeline aborts.

Finish by updating `CLEANUP_PROGRESS.md` in a log-only commit (never staged
into a move commit) and returning a summary: which
folders moved, which commits carry them, what failed, and what was skipped.
