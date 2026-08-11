# The final report

What the report has to *contain* is in `SKILL.md`, next to the close-hygiene
rules that decide what may be deleted on the way out. This file is the shape:
the template, and the rules for filling each part honestly.

## Template

```markdown
## Cleanup — summary
Branch: `cleanup/YYYYMMDD` · Level: GREEN · N commits

| Phase | Result |
|---|---|
| 1 — dead code | 7 deps, 23 files, 41 exports removed |
| 1.5 — duplicate functions | 6 pairs found, 2 real (churn), 4 left alone |
| 2 — consolidation | 3 modules → 1 (`src/billing/`) |
| 3 — structure | 4 folders reorganized, 2 cycles broken |
| 4 — local reshaping | 5 tier A operations, 1 tier B; 2 targets skipped (uncovered) |

### Quality delta
Run the measurer again and diff it against the Step 0 baseline:

```bash
"${CLAUDE_PLUGIN_ROOT:-.}/scripts/metrics.sh" . > /tmp/metrics-after.txt
diff /tmp/metrics-before.txt /tmp/metrics-after.txt
```

`[metrics] maxfn 214 → 61 · fn_over_50 9 → 4 · maxnest 7 → 4 (approx) · loose_types 31 → 31`
Evidence, not a target: nothing here is optimized for its own sake. Report the
lines that moved and say which phase moved them; a line that did not move is
not worth a row. No baseline (the run started before it was taken, or the file
is gone) means no delta section — an unanchored "after" is a number pretending
to be a comparison.

### Revert anything
`git revert <sha>` — commits are atomic per category.

### Failed / not done
- dead exports: typecheck broke in `src/api/routes.ts` (dynamic import)
- orphan files: out of scope — user asked deps only

### Pending your decision
- (nothing)
```

The phase 1 line counts what each category actually removed, tallied per commit
from the report that category ran on — not the numbers of the first report,
which stopped describing the repo the moment the first commit landed. The last
regeneration settles the rest: whatever it still lists is what survived, and it
belongs under "Failed / not done", along with any category that was skipped
(level cap or user scope).

## Filling it honestly

The phase 1 line counts what each category actually removed, tallied per commit
from the report that category ran on — not the numbers of the first report,
which stopped describing the repo the moment the first commit landed. The last
regeneration settles the rest: whatever it still lists is what survived, and it
belongs under "Failed / not done", along with any category that was skipped
(level cap or user scope).

The quality delta is evidence, not a target: nothing here is optimized for its
own sake. Report the lines that moved and say which phase moved them; a line
that did not move is not worth a row. No baseline — the run started before it
was taken, or the file is gone — means no delta section at all. An unanchored
"after" is a number pretending to be a comparison.
