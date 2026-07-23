# 0004 — The /idea dispatch check stays manual (supersedes ADR 0001's "automate #3")

- Status: accepted
- Date: 2026-07-23
- Source: issue #3 (PR #13), amending [ADR 0001](./0001-behavioral-test-harness.md)

## Context

[ADR 0001](./0001-behavioral-test-harness.md) listed behavioral check **#3 — `/idea`
dispatches the `idea-architect` sub-agent** under "Automate," conditional on the spike
confirming that a *denied* `Task` is observable in `--output-format stream-json`. The idea
was to assert dispatch without spending fable tokens by disallowing `Task` and reading the
denied-attempt event.

Implementation (PR #13) settled the spike empirically against the pinned CLI (2.1.218):

- **Blanket `--disallowedTools Task`:** the `Task`/`Agent` tool disappears from the model's
  tool list entirely, so it never attempts a call — `permission_denials` stays empty.
  Nothing to observe.
- **Subagent-scoped `--disallowedTools 'Task(idea-architect)'`:** the attempt *becomes*
  observable when denied — but denial is **not deterministic**. Across repeated identical
  runs, ~60% were *not* denied: `idea-architect` actually dispatched and ran to completion
  on fable (real spend). The model's denial text referenced an "auto mode classifier,"
  consistent with headless `Task`/`Agent` permission enforcement being a probabilistic
  classifier rather than a hard match on `--disallowedTools`.

ADR 0001 also set a hard rule: **never run an unblocked `Task` to make an assertion pass**
(zero sub-agent/fable spend). A mechanism that dispatches for real ~60% of the time
violates that rule and cannot be made a safe automated gate.

## Decision

**Check #3 stays manual.** This supersedes the "#3 → Automate" element of ADR 0001; the
rest of ADR 0001 stands. The shipped `tests/behavioral.d/30-idea.sh` is a documented no-op
that makes **zero live calls** and prints why #3 is manual. `TESTING.md` lists #3 in the
manual layer.

The manual check remains cheap: run `/idea` once and confirm it dispatches `idea-architect`
(on fable) and returns a brief with 2–3 compared approaches — a ~1-minute read, done in the
pre-release ritual.

## Consequences

- No fable spend risk in the behavioral harness from check #3.
- The automatable behavioral checks are #1 (panel), #2 (no-tracker fallback), and #5
  (`/deploy` gate); #3 and #6 are manual/conditional.
- General lesson recorded for this repo: **headless `--disallowedTools` on `Task` is not a
  reliable test lever** — it either hides the attempt or lets it through. Don't build future
  checks that depend on deterministically denying a sub-agent dispatch.
