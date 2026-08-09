# Step 1.4 — the audit protocol

Distilled from ksimback's
[tech-debt-audit](https://github.com/ksimback/tech-debt-skill) (MIT, source
commit `5a15c1c`; third-party notice in LICENSE) and adapted to run inside
this pipeline. Check `CLEANUP_PROGRESS.md` for what 1.1–1.3 actually
committed: do not re-report what is recorded there as removed — but whatever
was left out is a finding of this step (YELLOW does not touch exports, RED
deletes nothing, and a category that failed its gate stays pending). Leave
duplicated-intent analysis to step 1.5, which runs next.

## Before judging

Reread the README and the package manifest first — that is what makes both
the contradiction check below and dimension 9 verifiable. Then write a 1–2
paragraph mental model of the architecture as it actually is — you built
most of it while configuring the phase 1 dead-code tool. If the model
contradicts the README, the contradiction is itself a finding.

Pull churn data, then rank the most modified files:

```bash
git log --no-merges --stat --since="6 months ago"
git log --no-merges --since="6 months ago" --format= --name-only | sed '/^$/d' | sort | uniq -c | sort -rn
```

Both filters have to be on both commands. Without `--since` the ranking is a
lifetime touch count, and a file rewritten hard three years ago and untouched
since outranks whatever is actually hot now. Without `--no-merges` a merge
commit re-attributes every file it brings in, so the two views end up
describing different commit sets and the intersection below is skewed by
exactly the noise the flag removes.

Intersect the 20 largest files with the 20 most modified — that intersection
is where debt usually hides, and it is what separates "actually has debt"
from "just looks messy".

## The nine dimensions

Cite `file:line` for every finding. Use `rg`, `ast-grep` and the stack's own
linters — much of their output already exists from phase 1; reuse it instead
of re-running. A tool missing from PATH becomes a note in the report, never
an installation — the same rule as the rest of the skill.

1. **Architectural decay** — circular deps (`npx madge --circular` on JS/TS,
   `pydeps --show-cycles` on Python; other stacks in
   `references/other-stacks.md`), layering violations, god files (>500 LOC)
   and god functions, abstractions that exist but nobody uses, duplicated
   logic spread across 3+ sites where an abstraction should exist (pairwise
   function clones belong to step 1.5; this is the spread-out kind). Report
   any dead code that 1.1–1.3 did not remove — check `CLEANUP_PROGRESS.md`.
2. **Consistency rot** — multiple ways of doing the same thing (HTTP
   clients, error handling, logging, config loading, validation, date
   handling); naming drift; folders that no longer reflect the code — this
   feeds phase 3 directly.
3. **Type and contract debt** — `any` / `unknown` / `as any` /
   `# type: ignore` / loose dicts; untyped API boundaries; missing schema
   validation at trust boundaries.
4. **Test debt** — coverage gaps on critical paths; tests that assert
   implementation instead of behavior; skipped or flaky tests; high-churn
   files with no tests.
5. **Dependency and config debt** — CVEs (`npm audit` / `pip-audit` /
   `cargo audit` / `govulncheck`); duplicate deps doing the same job; env
   var sprawl (referenced but undocumented, defaults inconsistent across
   envs). Report unused deps only where 1.3 did not remove them — check
   `CLEANUP_PROGRESS.md`.
6. **Performance and resource hygiene** — N+1 queries, sync work in async
   paths, blocking I/O on hot paths, uncleaned listeners or handles.
7. **Error handling and observability** — swallowed exceptions, blanket
   catches, errors logged but not handled, inconsistent error shapes,
   missing structured logs on critical paths.
8. **Security hygiene** — hardcoded secrets, string-concat SQL, missing
   input validation at trust boundaries, permissive auth or CORS, weak
   crypto. Hygiene only — this is not a pen test or threat model.
9. **Documentation drift** — README claims that no longer match reality,
   comments contradicting adjacent code, public APIs without docs.

## Deliverable — `TECH_DEBT_AUDIT.md` at the repo root

On GREEN/YELLOW, write it to the repo root and commit it; at RED nothing is
written into the repo — the same content goes into the final report instead.

- **Executive summary** — max 10 bullets, ranked by impact.
- **Architectural mental model** — the system as it actually is.
- **Findings table** — `ID | Category | File:Line | Severity
  (Critical/High/Medium/Low) | Effort (S/M/L) | Description |
  Recommendation`. Aim for 30–80 findings; padding past that is noise.
- **Top 5 "if you fix nothing else, fix these"** — concrete diff sketches or
  refactor outlines, not vague advice.
- **Quick wins** — low effort × medium-or-higher severity, as a checklist.
- **"Looks bad but is fine"** — the calls you considered making and rejected,
  with reasons. **Required.** If it comes out empty, the audit did not look
  deep enough and you must go back.
- **Open questions for the maintainer** — what you could not tell was debt
  versus intentional.

## Rules

- A finding without a citation is a vibe, and vibes do not get fixed.
- No sycophancy and no filler. Never open with "overall the codebase is
  well-structured" — say what is broken.
- Read code before judging it: a pattern that looks wrong in isolation may
  be load-bearing. When it is, it goes into "looks bad but is fine" with the
  reason, not into the findings table.
- Unsure whether something is debt or intentional? Put it in open questions —
  do not assert.
- Recommend specific, scoped changes. Never recommend rewrites — diagnosing
  is the job, rewriting is the easy way out of it.
- A category with nothing material gets the line "Nothing material" and
  nothing else. Padding makes an audit feel thorough without being thorough.
- **Repeat runs**: if `TECH_DEBT_AUDIT.md` already exists, read it first;
  mark resolved findings `RESOLVED`, tag new ones `NEW`. The audit is a
  living document, not a snapshot.
- **Large repos** (>50k LOC or >5 top-level modules): in environments with
  subagents, dispatch one per module — each gets the path to this reference,
  the scope of one module, the citation requirement and a 200-finding cap.
  Whoever runs this step (the orchestrator, or the phase 1 subagent when
  phase 1 is itself delegated) merges, dedupes and ranks down to the 30–80
  target.
