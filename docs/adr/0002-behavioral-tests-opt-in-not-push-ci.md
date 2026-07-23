# 0002 — Behavioral tests run opt-in, never on push/PR CI

- Status: accepted
- Date: 2026-07-23
- Source: `docs/ideas/automate-behavioral-tests.md`

## Context

The behavioral smoke layer (see [ADR 0001](./0001-behavioral-test-harness.md)) invokes
`claude -p`, which needs an API key and spends tokens (~$1–3 per full run). The existing
`ci.yml` runs on every push and PR and is deliberately free and dependency-free — it must
stay that way so contributors and forks aren't blocked on secrets or billing.

## Decision

Keep the behavioral harness out of push/PR CI. Its homes are:

1. **`tests/behavioral.sh`** — the primary path, run locally before a release.
2. **`.github/workflows/behavioral.yml`** — a separate job triggered only by
   `workflow_dispatch`, gated on the `ANTHROPIC_API_KEY` secret, with a **pinned** Claude
   Code CLI version (CLI flag drift, not model flake, is the main maintenance risk).

`ci.yml` (checkout + `validate.sh`) is untouched and remains the every-push contract.
Fixtures are generated at runtime into `mktemp -d`, never committed — committed fixtures
would trip `validate.sh`'s unexpected-directory checks and risk plugin auto-discovery.

Safety boundary for the deploy check is **sandbox, not tool-blocking**: a local bare repo
as `origin`, `gh` disallowed, but `git tag`/`git push` allowed — otherwise the "gate held"
invariant would test nothing.

## Consequences

- Every-push CI stays free; behavioral coverage is opt-in and costs are bounded and visible
  (the harness prints `total_cost_usd` per run).
- Behavioral regressions are caught pre-release or on demand, not on every push — an
  accepted cadence for a plugin that changes rarely.
- Flake policy: one retry per LLM assertion, then fail; a check that flakes across two
  releases is demoted to a warning or deleted. Never loop-until-green.
