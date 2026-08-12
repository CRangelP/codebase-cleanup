# Phase 4 — Local reshaping

Goal: fix the inside of what survived the first three phases. The unit of work
is the function, not the dependency, the module or the folder — a 200-line
function with five levels of nesting is not made better by living in a
well-named directory.

The operations themselves live in `references/refactoring-catalog.md`: what
each one is, which tier it belongs to, and what a green gate does and does not
attest about it. This file is the protocol around them — which target, under
what safety net, and what happens when the gate comes back red. Read both: the
catalog without this file is a list of ideas, and this file without the catalog
has nothing to apply.

## Why it runs after phase 3

The order of the pipeline becomes:

> clear out the dead → decide the boundaries → move the files → reshape what is left

Reshaping the inside of a function that lives in a module phase 2 is about to
consolidate, or in a file phase 3 is about to move, is guaranteed rework: the
consolidation rewrites the seam the extracted function sits on, and the move
replays the diff onto a path that no longer exists. Worse than the wasted work
is what it does to the history — two commits touching the same lines for
unrelated reasons, and `git revert` stops being surgical, which is the whole
reason the commits are atomic. Earlier still, some of the ugliest functions in
the repo turn out to be dead, and phase 1 removes them for free.

## Target selection — two filters, both required

### 1. The target is already written down

Targets come from phase 1.4's `TECH_DEBT_AUDIT.md` — dimension 1 (god
functions, god files, duplicated logic spread across sites) and dimension 3
(`any`, `# type: ignore`, untyped boundaries) — and from the phase 1.5 pairs
that phase 2 did not consume. A pair promoted to phase 2 candidate and never
chosen is still duplicated intent. A pair whose two copies live in the same
file is phase 2's deletion test to judge first, exactly as
`references/duplication.md` says, and it reaches this phase only when that test
left it standing — there is no module boundary to move then, only a function to
extract, which is this phase's unit.

A target that is written down nowhere is a target picked by taste, and this
project does not do that. If you find something the audit missed while reading
a file, add it to the audit as a `NEW` finding (`references/audit.md` says the
report is a living document) and let the second filter judge it. Do not fix it
inline because you were already in the file.

### 2. Churn — only what is hot gets in the queue

```bash
git log --no-merges --since="6 months ago" --format= --name-only | sed '/^$/d' | sort | uniq -c | sort -rn
```

This is the third time that ranking runs in the pipeline (1.4 pulls it, the
phase 2 survey crosses it with coupling); reuse the output if nothing has been
committed since.

Code that works and will not change again pays nothing back for being
reshaped: you spend the risk and collect no readability, because nobody is
coming to read it. A big, ugly, cold file goes to the audit's **"looks bad but
is fine"** section with its churn numbers attached — that is where it belongs,
and that entry is what stops the next cleanup from queueing it again.

The history has to exist for any of this to mean anything. Check the
repository once, exactly as `references/duplication.md` does it
(`git rev-parse --is-shallow-repository`, `git rev-list --count HEAD`): on a
shallow clone, or on a repo with a handful of commits, there is **no signal**.
Say so — "churn unavailable (shallow clone)" — select from the audit's
severity and effort alone, and record in the report that the hot/cold filter
was unavailable. Do not invent a ratio to fill the column. A squash-merge
history is the milder version: every file a PR touched shares one commit, so
the ranking is flattened and inflated at once, and the file has to be read
before its position is trusted.

## The safety net, per target

GREEN is a measure of the repository. It says the suite that exists passes; it
says nothing about which lines that suite executes. To transform the inside of
a function, the only thing that matters is whether **that function** is
exercised — a repo at GREEN with 4% coverage authorizes `extract-function` on
nothing at all, because the green gate after the change would prove that the
code still compiles and that the same 4% still passes, which is precisely what
a broken refactor also proves. The gate did not get weaker; the unit of work
changed under it. Deleting a file nothing imports is verified by the module
graph, moving a file is verified by the compiler, and rewriting the inside of a
function is verified by tests over that function and by nothing else.

So, before touching each target:

1. **Measure.** Use the stack's coverage tool when there is one —
   `vitest run --coverage`, `jest --coverage`, `pytest --cov`,
   `go test -cover ./...`, `cargo llvm-cov`, `dotnet test --collect:"XPlat Code Coverage"`
   — and read the number for that file and that function, never the project
   total. The project total is an average, and the average is exactly what
   hides the file you are about to open.
2. **Or admit the weaker evidence.** With no coverage tool available, the
   fallback is naming the test files that import the module — a proxy, not
   coverage. It says something in the file is reachable from a test, not that
   the branch you are flattening ever runs. Record which of the two you had,
   per target: a number and a proxy do not authorize the same thing, and here
   is what that means, because leaving it implied is how the third exit gets
   in. **A proxy is not "covered".** It authorizes nothing on its own: the
   target goes down the "not covered" branch in step 4 like any other, and the
   proxy only decides which way that branch is worth taking — a module a test
   file already imports is usually cheap to characterize, which makes writing
   the test the better of the two exits rather than skipping. A number per
   function is what authorizes work, and only tier A; **tier B never runs on a
   proxy**, because an operation that picks an abstraction needs to know which
   branches execute before it decides which ones deserve a name.
3. **Covered**, meaning a per-function number → proceed, at the tier the level
   allows.
4. **Not covered** → two exits, and only two: skip the target and record it as
   pending, naming what is missing; or write a characterization test as **its
   own commit** (`test: characterize <what>`, green before the refactor
   starts) and then proceed.

There is no third exit. "The suite passes, it will probably be fine" is the
sentence this whole skill exists to replace with a measurement.

A coverage run leaves artifacts behind (`coverage/`, `.coverage`,
`lcov.info`). They are tool output and get the same treatment as the knip
report in phase 1: repo-local exclude, never a pathspec in a commit, deleted
on the way out.

**What a characterization test is.** It records the behavior as it is today,
including the parts that look wrong. Its purpose is to detect change, not to
judge correctness: if the function returns `null` for an empty list where every
reviewer would expect `[]`, the test asserts `null`. A characterization test
that "fixes" the observed behavior is a behavior change wearing a test as a
disguise — it goes green against code nobody has refactored yet, and every
refactor after it is measured against an expectation that never held.

## Levels

| Level | Phase 4 |
|---|---|
| GREEN | tier A on its own, per covered target; tier B only after the checkpoint |
| YELLOW | does not run — reports the target queue and stops |
| RED | never reaches here — the characterization test the report proposes at RED belongs to `SKILL.md`'s final report |

YELLOW does not run phase 4, and not out of caution for its own sake: at
YELLOW something is missing from the net, and both halves matter here. If the
suite is what is missing, per-target coverage is zero by definition and every
target lands in the "not covered" branch — a queue of skips wearing the costume
of a run. If typecheck is what is missing, the error a reshaping operation
produces most often (a signature that stopped matching its caller) is exactly
the one nothing left is checking. Either way the honest output is the target
list in the report. Promoting the level is the user's move — pointing the gate
at the suite it could not see — never the skill's.

The caps in `references/other-stacks.md` are about how far a deletion graph
can be trusted, and phase 4 deletes nothing. What still binds here is the
suite: a stack whose tests the gate could not count is a stack whose per-target
coverage you cannot read either, and that is YELLOW already.

## The tier B checkpoint

Tier B changes a boundary, a domain word or a signature. Green tests prove the
behavior did not change; they do not prove the abstraction is right — the same
argument as the phase 2 checkpoint, one altitude down, which is why it is
answered by the same person and not by the gate.

Keep it cheap, in the shape phases 2 and 3 already use: **at most 5 tier B
candidates**, one recommended explicitly, **one** question, and the answer
picks a single one of them or none. That five is a different number from the
session cap below: the tier A queue is capped at five operations per session,
and the checkpoint adds at most one operation to that session, never five. No
multi-round interview — a checkpoint that costs five messages is a checkpoint
the user learns to skip.

```markdown
### R1 — `domain-type` · `src/billing/invoice.ts:44 applyDiscount()`
**Coverage:** 91% of the file (vitest), 6 cases reach this function
**Operation:** `domain-type` — the three `string` money parameters become `Money`
**Why this one:** finding #14 of the audit (dimension 3), 22 commits in 6 months
**What it costs:** 4 call sites, all inside `src/billing/`
**What the gate will not prove:** that `Money` is the right name for what the
domain calls "amount due"
```

If the user answers "go" or equivalent, proceed with the recommendation. If
they pick another candidate, record the rest as out of scope in
`CLEANUP_PROGRESS.md`.

## The execution loop

One operation, one commit:

1. Apply exactly **one** operation from `references/refactoring-catalog.md`,
   on one target.
2. `git add -- src/billing/invoice.ts` — pathspecs of what this operation
   touched, never `git add -A` or `git add .`, which would swallow an
   unrelated draft or a local `.env` into the commit.
3. `"${CLAUDE_PLUGIN_ROOT:-.}/scripts/gate.sh"`
4. Commit on green: `refactor(<id>): <what>`, with the id in kebab-case from
   the catalog — `refactor(guard-clauses): flatten the retry ladder in fetchInvoice`.
   Why the id and not a prose summary is in `references/refactoring-catalog.md`,
   under "Why the operation is named in the commit".

Unlike phase 2, **there is no red-by-construction intermediate state here**. A
consolidation is red between "the new interface exists" and "the callers point
at it", which is why it gates once at the end; a phase 4 operation is atomic by
construction — the file compiles before it and after it — so the gate runs on a
state you expect to be green, and every red is information rather than a
prediction coming true.

Gate red (exit 1), or timed out (exit 4, which is inconclusive and never a
green): `git restore --staged --worktree .`, record the target and the failure
in `CLEANUP_PROGRESS.md`, move to the next target. Do not try to fix it. A red
gate right after a transformation means the transformation was wrong — the
tests disagree with it, or it stopped compiling — and the useful information is
which operation on which function, not a patch stacked on top of a change
nobody has reviewed. If a hook blocks that restore, **abort**, exactly as in
phases 2 and 3: the failed operation is still in the tree, and the next commit
would fold it in and destroy the atomic revert.

**Cap per session: 5 tier A operations, 1 tier B.** A review limit, not a
performance one. Whoever merges this branch reads the diff, and a refactor
spread over 40 files is a diff nobody reads — it gets approved on trust, which
is the same as not being reviewed. Hitting the cap is a normal ending: record
what is still in the queue and let the next session take it, after `/clear`.

## What phase 4 does not do

- **No public API change** without an explicit request. A local variable gets
  renamed (`rename-local`); an export does not — renaming an export edits
  somebody else's code from inside a cleanup they never read.
- **No performance work**, no new behavior, no feature, nothing "while I am
  here". A faster function is a different function, and the gate only tells you
  the tests survived.
- **No rewrite.** If a function is past what the catalog can do to it, the
  deliverable is the finding and the operations it would take. Diagnosing is
  the job.

`type-boundary` needs saying out loud, because the tempting version of it is
not this operation. Adding schema validation at a trust boundary **changes
behavior** — input that used to pass starts being rejected — and green tests
after it prove only that no test sent the input that would now be refused.
Under this project's definition that is not a refactor, so it never runs here,
checkpoint or not: it leaves the pipeline as a recommendation in the final
report, and if the user wants it, it is their commit with their name on it, not
a `refactor(type-boundary)`. What phase 4 runs under this id is the typing the
catalog describes and nothing that executes at runtime — and, like every tier B
operation, it waits for the checkpoint.

## Record

`CLEANUP_PROGRESS.md`, updated at the end of every operation and committed in a
log-only commit after it (`git add -- CLEANUP_PROGRESS.md` — never staged into
the operation's commit):

- one line per operation: id, target, commit sha;
- every skipped target under what is pending, with the reason — no coverage,
  cold, or waiting on the tier B checkpoint;
- characterization tests written, and which target each one unblocked;
- under `## Decisions`, the targets left alone on purpose with their churn
  evidence. That entry is what stops the next cleanup from re-queueing the
  same file.

The final report gets its own row —
`| 4 — local reshaping | 5 tier A operations, 1 tier B; 2 targets skipped (uncovered) |`
— with skipped targets under "Failed / not done" and the tier B candidates the
user did not choose under "Pending your decision". The cold ones do not go
there: they belong to the audit's "looks bad but is fine" section, considered
and rejected with the numbers that justified it.
