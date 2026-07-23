# 0001 — Behavioral tests: a headless smoke harness, not an eval framework

- Status: accepted
- Date: 2026-07-23
- Source: `docs/ideas/automate-behavioral-tests.md`

## Context

`tests/validate.sh` proves the plugin's prose *exists* (structure, frontmatter, invariant
strings) but not that it *works* — that a `SKILL.md` actually steers a model to pick the
right panel, stop at the right gate, or dispatch the right agent. Those behaviors were
verified only by the manual `TESTING.md` checklist, run once per release, so any edit to a
rubric or gate shipped unverified between releases.

The original testing plan rejected automation as nondeterministic and expensive. That holds
for a full eval framework and for the multi-agent `/work` swarm, but not for the checks
whose pass/fail is a **mandated one-line announcement** ("Panel: …", the tracker choice,
the computed version) or a **git/filesystem invariant** — the skills emit those lines
specifically so a human can check them in one read.

## Decision

Add a thin behavioral **smoke** layer in the existing `validate.sh` idiom (bash + `claude
-p` + line-scoped `grep`), not an eval framework. Automate the four checks that reduce to a
mandated line or an invariant; keep the two that need real remotes and real money manual.

- **Automate:** (1) panel selection, (2) the no-tracker fallback branch, (3) `/idea` agent
  dispatch, (5) the `/deploy` dry gate.
- **Stay manual:** (4) the `/work` rehearsal and the gh-enabled tracker variant.
- **Token-free CLI script where possible:** (6) dependency auto-install.

Cost control is structural, not budgetary: `--disallowedTools Task` caps panel/idea runs at
zero sub-agent tokens (selection happens in the main loop before fan-out); print mode exits
at each human gate by construction, so "never approve" is automatic; harness runs pin
`--model sonnet` as a conservative floor and cost cap.

## Consequences

- Skill-prose regressions in panel selection, tracker fallback, idea dispatch, and the
  deploy gate become catchable same-day instead of once per release.
- The harness proves **announcements and gates, not judgment quality** — brief/ticket/plan
  quality stay in the manual layer. `TESTING.md` must state this or the manual layer will
  atrophy.
- `/work` end-to-end automation is deferred; its invariants remain covered by `validate.sh`
  static checks plus the architect's independent enforcement. Revisit only on evidence of a
  real regression those miss.
