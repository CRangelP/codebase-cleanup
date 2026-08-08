# Phase 2 — Module consolidation

## What to look for

Do not look for isolated bad files. Look for **clusters** of small, tightly
coupled modules where each one has an interface almost as complex as its
implementation, and where navigating between them feels like friction.

The strongest signal reads like "to understand flow X I have to open five files
and none of them tells me enough on its own".

## Vocabulary

Use these terms precisely. Drift into "component", "service", "layer" or
"boundary" and the analysis turns generic.

- **module** — a unit with separable interface and implementation
- **interface** — what callers need to know; the cost
- **implementation** — what the module delivers; the benefit
- **depth** — how much leverage the interface gives; a property of the
  interface, not of the implementation
- **seam** — a cut point where callers and tests cross the same boundary
- **adapter** — translation between two formats; one adapter is a hypothetical
  seam, two adapters is a real seam
- **locality** — how close to its use the information lives

Depth is **not** the ratio of implementation lines to interface lines. That
metric rewards inflating the implementation. A deep module can be built
internally out of small, replaceable pieces — they just do not show up for the
caller.

## Deletion test

Imagine deleting the module.

- Complexity **disappears** → it was pass-through, consolidate
- Complexity **reappears spread across N callers** → it was paying for itself,
  keep it

## Survey

0. **Start from the phase 1.5 pair list.** Duplicate-function pairs that
   passed the pair-level co-change rule outrank anything below — two
   implementations of one intent are the consolidation candidate in its
   purest form.
1. **Map.** Import graph (knip's `cycles` already covers a good part of it),
   module sizes, who calls whom.
2. **Cross with churn volume (file-level).** `git log --format=%H
   --name-only | sort | uniq -c | sort -rn` — the intersection between
   "changed a lot" and "heavily coupled" is where consolidation pays the
   most. This is a different, weaker signal than the pair-level co-change of
   step 0: it says a file is hot, not that two files move together.
3. **Actually read the candidate clusters.** Do not judge by file name.
4. **Rank by confidence**, not by size.

## Presentation format

At most 5 candidates. For each one:

```markdown
### C1 — `src/payments/{validator,formatter,normalizer}.ts` → `src/payments/`
**Confidence:** high
**Why they are shallow:** each of the three exports one function, always called
in sequence by the same two call sites. None has its own test.
**Becomes:** a `payments` module with one public function `preparePayment()`.
**Risk:** low — no caller outside the directory.
**Deletion test:** deleting `formatter.ts` moves 4 lines into each of the 2
callers. Pass-through.
```

Finish with **one** explicit recommendation and **one** question. No
multi-round interview — if the user answers "go", proceed with the
recommendation.

## Implementation

One candidate per session. Per consolidation:

1. Create the new interface
2. Migrate callers
3. Remove the old modules
4. `git add -A`
5. Typecheck + tests
6. Commit `refactor: consolidate X into Y`

Step 4 is not bookkeeping. `git restore --staged --worktree .` brings back a
deleted file and drops a staged new one, but an unstaged new file survives the
rollback and poisons the next step — so the new interface has to be staged
before the gate runs. Staging everything is safe because the tree was clean
when the pipeline started.

Gate failed → `git restore --staged --worktree .`, record it, do not try to
fix it.

## What this phase does NOT do

It does not reorganize folders. Module depth is about interface design and
access through it, regardless of how the filesystem looks. The two things are
orthogonal — directory structure is phase 3.

It is not a rescue. In a genuinely old codebase it finds real candidates, but
it does not dig out the mud on its own. If the survey returns 40 candidates,
the problem is upstream and the way forward is to scope it per module.
