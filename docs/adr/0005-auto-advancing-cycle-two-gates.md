# 0005 — The four phases auto-advance into one cycle; two human gates remain

- Status: accepted
- Date: 2026-07-25

## Context

Originally each command was invoked by hand: run `/idea`, then separately `/plan-sprint`,
then `/work`, then `/deploy`. The owner wanted a single entry point (`/idea` or
`/plan-sprint`) to run the rest of the cycle without re-invoking each phase.

A fully gateless "autopilot" was considered — chaining all four phases with *no* human
confirmation, as the default for every install. It was rejected on two grounds: (1) it
would make a casual `/idea "what if…"` autonomously create tickets, merge to `main`, and
push a production release — for anyone who installs the plugin; and (2) Claude Code's
permission classifier blocks edits that strip a human-confirmation checkpoint from an
outward-facing action, which is a correct guardrail we chose not to circumvent.

## Decision

**Auto-advance the phases, keep the two gates.** Each phase ends by invoking the next
(`/idea` → `/plan-sprint` → `/work` → `/deploy`), so one command flows through to a
release. But the **two human gates on the outward-facing, irreversible actions stay**:

- `/plan-sprint` presents the plan and **confirms before creating tracker tickets**.
- `/deploy` presents the version + what ships and **confirms before pushing the release tag**.

`/idea` → `/plan-sprint` and `/plan-sprint` → `/work` are pure handoffs (no outward action
between them), so they auto-advance freely. The span between the two gates runs
autonomously, and its safety rests on *automated* rails, not human review of every step:
the soundcheck security pass, green-only normal merges (never `--admin`), and `/deploy`'s
preflights (green branch, healthy pipeline, non-empty diff, tag immutability).

## Consequences

- One `/idea` (or `/plan-sprint`) drives the whole loop, pausing only at "approve the
  sprint" and "cut the release" — the two decisions the plugin was always built to keep
  human. The README value prop ("humans on only the two decisions that matter") becomes
  literally true of the runtime flow, not just the intent.
- The gates are now a **tested invariant** (`validate.sh` asserts the deploy human-gate
  wording and the three auto-advance handoffs). Removing a gate fails the deterministic
  check *and* the permission classifier.
- Anyone wanting true gateless autopilot must make it an explicit opt-in later; it is
  deliberately not the default.
