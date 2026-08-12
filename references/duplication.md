# Phase 1.5 — finding duplicate functions

The target is duplicated **intent**: functions with different names doing the
same thing. That is the symptom phase 2 cares about — two implementations of
one idea are the strongest consolidation candidate there is, stronger than
anything depth analysis finds on its own.

Honest ceiling first: true semantic detection (same purpose, entirely
different implementation) is still an open goal for every tool below. What
they catch reliably is the renamed clone — same structure, different names,
different literals. Treat every list as candidates to read, never as
conclusions.

## The tool ladder (JS/TS)

Try in this order; each step down trades precision for availability.

**1. similarity-ts** — compares functions by AST structure and reports pairs
with a percentage. It is a Rust binary (`cargo install similarity-ts`, if the
user wants it around); if it is not on PATH, do not install it — step down
the ladder.

```bash
similarity-ts ./src --threshold 0.85 --min-tokens 25 --print
```

- `--threshold` 0.80–0.85: below that, noise dominates.
- `--min-tokens` 20–30: filters trivial two-liners that are similar by accident.
- `--print` shows the code, which saves a round of file opening.

Output looks like this (upstream format — note the indentation and the
`Score` suffix if you parse it):

```
Duplicates in src/utils.ts:
────────────────────────────────────────────────────────────
  src/utils.ts:10-20 calculateTotal <-> src/helpers.ts:5-15 computeSum
  Similarity: 92.50%, Score: 9.2 points
```

The same author ships `similarity-py`/`similarity-rs` (beta) and
`similarity-generic` (experimental); this reference sends other stacks to
jscpd instead because it is the mature option, not because the family does
not exist.

**2. fallow** — runs without a global install (`npx fallow@3.14.0 dupes`;
pin verified 2026-08-09) and finds clone families (not just pairs) with four
modes: `strict` (exact tokens), `mild` (default), `weak` (different
literals), `semantic` (renamed variables). Start on `mild`, escalate to
`semantic` if the output is thin. Also covers dead code, complexity and
boundaries in the same binary. TS/JS only. Always pin the exact version —
never bare `npx fallow`.

**3. jscpd** — the multi-language fallback (223 formats), and the only rung
for non-JS/TS stacks:

```bash
npx jscpd@5.0.14 src --reporters ai --min-tokens 50 --cross-formats "js-ts"
```

Pin verified 2026-08-09. Always `npx jscpd@5.0.14`, never bare `npx jscpd`.

- Token-level: it finds copy-paste (including with edits), **not** renamed
  intent. In Python, Go or Java this is the honest ceiling; say so in the
  report instead of overselling the sweep.
- The `ai` reporter is compact output (~79% fewer tokens than the default),
  made to be read in-session without flooding context. Keep it and
  `--min-tokens` on every invocation, or the runs are not comparable.
- `--cross-formats "js-ts"` compares `.js` against `.ts` — a half-done
  JS→TS migration is a duplicate factory, and this is the flag that catches it.
  On a non-JS/TS stack, drop the flag — there is nothing for it to pair.

## The churn rule

High similarity alone does not mean "consolidate". Two look-alike
implementations that belong to different domains and will diverge should stay
separate — abstracting too early costs more than duplicating. The practical
discriminator is whether the pair changes together.

**Check the repository once, before any pair.** The recipe reads history, so
it is only as good as the history present locally:

```bash
git rev-parse --is-shallow-repository   # true → no usable history
git rev-list --count HEAD               # total commits on the branch
```

On `true` (or on a repo with a handful of commits), the churn rule produces
**no signal**: do not compute ratios, mark every pair as "churn unavailable
(shallow clone)" in the report and decide by reading the code. Either deepen
the clone first (`git fetch --unshallow`) or say in the report that the
discriminator was unavailable. A history made of squash merges is the milder
version of the same problem: every file touched by a PR co-changes in one
single commit, which inflates `co` for pairs that never moved together — read
the pair before trusting a high ratio there.

Then compute numerator AND denominator, validating each side first (bash —
uses process substitution):

```bash
git ls-files --error-unmatch -- "pathA" >/dev/null || echo "pathA not tracked"
git ls-files --error-unmatch -- "pathB" >/dev/null || echo "pathB not tracked"
a=$(git log --follow --format=%H -- pathA | sort -u)
b=$(git log --follow --format=%H -- pathB | sort -u)
co=$(comm -12 <(printf '%s\n' "$a") <(printf '%s\n' "$b") | grep -c .)
na=$(printf '%s\n' "$a" | grep -c .); nb=$(printf '%s\n' "$b" | grep -c .)
echo "co-changes: $co / min($na,$nb)"
```

`git log --follow` (one pathspec per side) survives renames — which matters
here, because phase 3 of this very skill moves files; `rev-list -- path`
would cut the history at the rename and undercount.

**`min(na,nb) == 0` is a measurement error, never a verdict.** A tracked file
always has at least one commit, so a zero denominator means the path was
wrong (typo, path relative to the wrong directory, file not committed yet) or
the history is missing — which is exactly what `git ls-files
--error-unmatch` catches before the log runs. Fix the path and re-measure; if
it cannot be fixed, the pair goes to the report as "no signal", **not** as
structural coincidence.

With both denominators above zero, the verdict is exhaustive — every pair
lands in one of two buckets:

- `co / min(na,nb)` **≥ 1/3** → **real duplication**. Promote the pair to the
  phase 2 candidate list.
- **Below 1/3** → **structural coincidence** (zero co-changes is just the
  obvious end of this bucket). Leave it, and record it in the report as
  "left alone on purpose" with the `co/min` numbers — that entry is what
  stops the next cleanup from re-flagging the same pair.

Three blind spots to keep in mind:

- **Granularity.** The detector reports function pairs; the recipe counts
  file co-changes. Two 500-line utility drawers that get touched weekly will
  pass the 1/3 cut for reasons unrelated to the duplicated pair. For pairs
  inside big shared files, confirm with a line-range log before promoting:
  `git log -L 10,20:src/utils.ts -s --format=%H`. The `-s` matters: without
  it `-L` prints the full diff of every matching commit, not just the hashes.
- **Same-file pairs.** The churn test cannot separate them at all; judge
  those by the deletion test in phase 2.
- **Thin history.** With `min(na,nb)` at 3 or less the ratio says little —
  two files born in the same scaffold commit score 1/1 with zero shared
  evolution. Read the pair before promoting it, and record the thin
  denominator in the report. This is the same axis as the repository
  pre-check above: a shallow clone or a squash-merge history gives every pair
  a thin or fake denominator, and the honest output there is "no signal", not
  a ratio.

## What the report contains

One table, committed with the phase 1 artifacts (GREEN/YELLOW only — at RED
nothing is committed; the table goes into the final report instead):

| A | B | Similarity | Co-changes | Verdict |
|---|---|---|---|---|
| `src/utils.ts:10 calculateTotal` | `src/helpers.ts:5 computeSum` | 92% | 7/19 | phase 2 candidate |
| `src/billing/round.ts:3` | `src/shipping/round.ts:3` | 88% | 0/14 | left alone: domains diverge |

**Only step 1 fills `Similarity` with a percentage.** fallow reports clone
families and jscpd reports token-level clones; neither gives a per-pair score,
so inventing one is a lie the next cleanup will inherit. When the ladder
degraded, write what the tool actually said and name the tool:

| A | B | Similarity | Co-changes | Verdict |
|---|---|---|---|---|
| `src/a.ts:10 parseUser` | `src/b.ts:40 readUser` | fallow group #3 (semantic) | 5/12 | phase 2 candidate |
| `src/a.py:1` | `src/b.py:1` | 74 tokens (jscpd) | 2/9 | left alone: domains diverge |

A pair whose rows come from step 2 or 3 also carries a weaker claim — token
or family membership, not measured structural similarity — and the report
should say which rung produced it.

The "phase 2 candidate" rows feed the survey in
`references/phase-2-consolidation.md` and outrank candidates found by depth
analysis alone. Nothing gets merged or deleted in this phase — which of two
duplicate functions survives is a naming-and-intent decision, and that is
exactly what the phase 2 checkpoint exists for.

## Coverage mandate

Detectors over-produce; agents under-read. Before committing the survey
(GREEN/YELLOW) or folding the table into the final report (RED):

1. The **unit list** is every pair (or clone-family member pairing) the chosen
   ladder rung emitted after the threshold / min-tokens filters — not a
   hand-picked sample.
2. Close every unit as **`reviewed`** (verdict column filled) or **`skipped`**
   with a reason (generated sources, vendored/minified, path outside the
   user's scope, tool noise the rung cannot score). "Left alone on purpose"
   after the churn rule is **reviewed**, not skipped — a verdict was reached.
3. Write the tally into `CLEANUP_PROGRESS.md` under `## Coverage` →
   `### 1.5 duplication`:

   ```markdown
   ### 1.5 duplication
   - reviewed: N · skipped: M · coverage_rate: R% (N+M / N+M pairs)
   - skipped: pathA ↔ pathB — reason
   ```

   Same arithmetic as the audit: `(reviewed + skipped) / units_planned × 100`.
   An empty detector result is `0/0` at 100% — the question was asked. A
   non-empty list with rows missing from both the table and the skipped
   bullets is an incomplete sweep; do not close the step.
