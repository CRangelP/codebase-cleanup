# Complementary tools — OpenCodeReview (optional)

This skill and [Alibaba OpenCodeReview](https://github.com/alibaba/open-code-review)
(OCR) solve different jobs. They are **neighbours**, not substitutes.

| | codebase-cleanup | OpenCodeReview |
|---|---|---|
| Job | Structural debt: dead code, shallow modules, folders, local reshaping | Defect/risk review on a diff or PR, with line-level comments |
| Mutates the tree? | Yes — deletions, moves, limited refactors behind a gate | Primary output is comments; auto-fix without a human is out of OCR's roadmap |
| Safety net | Gate (typecheck + tests), `cleanup/` branch, atomic commits, PreToolUse guards | File filters, review-filter, line relocation; CI can post comments |
| License | MIT (this repository) | Apache-2.0 |

**Use this skill** for a faxina on the tree. **Use OCR** for PR/diff review
and for defect heuristics the cleanup gate does not catch. Do not treat OCR's
"dead code" rules as a replacement for knip/vulture — those are review
heuristics on a diff; this skill deletes from a reachability graph.

## What this skill does **not** do

- Install, vendor, or call the OCR Go binary at runtime.
- Copy OCR prompts, rules, or source into this repository.
- Depend on `@alibaba-group/open-code-review` as a required toolchain.

OCR remains an **optional CLI the user installs** when they want review QA.
This project's own code stays MIT. Using the OCR CLI under Apache-2.0 does
not relicense this skill; no OCR code is embedded here.

## Optional recipe — review the `cleanup/` branch

After phases finish (or after you merge `cleanup/YYYYMMDD`), you may run OCR
against the cleanup branch to catch logical regressions the gate's tests
missed. Install and configure OCR yourself
([upstream README](https://github.com/alibaba/open-code-review)); requirements
such as Git ≥ 2.41 and an LLM endpoint (or delegation mode) are OCR's, not
this skill's.

Substitute the real branch name and base (`main` / `master`):

```bash
# Managed mode — OCR drives the LLM endpoint you configured
ocr review --from main --to cleanup/YYYYMMDD

# Preview first (lists what would be reviewed; no review spend yet)
ocr review --preview --from main --to cleanup/YYYYMMDD

# Delegation — OCR filters files + resolves rules; the host agent reviews
# with the model already attached to the session (no second API key)
ocr delegate --from main --to cleanup/YYYYMMDD
```

`ocr delegate` fits Claude Code sessions that already pay for a host model.
Comment language and other OCR defaults are configured on the OCR side.

Mention this recipe in the final cleanup summary under a short "Optional
next step" line when the run produced a `cleanup/` branch — never as a
required step, and never by installing OCR for the user.
