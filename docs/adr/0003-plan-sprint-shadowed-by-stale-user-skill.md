# 0003 — Panel-selection failure was a stale user-scope skill shadow, not a rubric bug

- Status: accepted
- Date: 2026-07-23
- Source: issue #8 (surfaced by the T1 behavioral harness, PR #7)

## Context

On its first live run the behavioral harness ([ADR 0001](./0001-behavioral-test-harness.md))
reported that `/plan-sprint` selected `product-manager` for the infra and data fixtures
instead of `devops-engineer` / `data-engineer`, and emitted a "general-purpose fallback —
repo has no `.claude/agents/` directory" message. Two hypotheses were on the table: (a) a
bug in `plan-sprint`'s panel rubric, or (b) plugin agent personas not being exposed to the
model under headless `--plugin-dir` with a foreign cwd.

Investigation showed **both were wrong.** The harness invoked a **bare `/plan-sprint`**,
and the operator's machine still had a pre-plugin copy at `~/.claude/skills/plan-sprint`
(plus stale `~/.claude/agents/{architect,product-manager,product-designer,senior-engineer}.md`).
The bare invocation resolved to that **user-scope skill**, which predates this plugin: it
uses a fixed PM + designer + architect trio, carries a `general-purpose` fallback clause,
and knows nothing of the `devops-engineer` / `data-engineer` agents. The plugin's own
`workflow:plan-sprint` was never being exercised.

This also silently degraded real usage: every bare `/plan-sprint` the operator ran was
getting the old skill.

## Decision

1. **Retire the shadow copies.** The stale `~/.claude/skills/{plan-sprint,work,deploy}` and
   `~/.claude/agents/*.md` were moved to `~/.claude/_pre-workflow-plugin-backup/` (reversible).
   The plugin is now the single source of these skills/agents.
2. **The behavioral harness invokes the plugin skill by its namespaced name**
   (`/workflow:plan-sprint`), never a bare name, so it can never be shadowed by a user-scope
   skill of the same name. Recorded in `tests/behavioral.sh`'s header.
3. **No change to `plan-sprint`'s rubric** — it was correct. Re-running the harness with the
   two fixes green across all four fixtures (web → architect+PM+designer, infra →
   architect+devops, data → architect+data, library → architect+PM) plus the no-tracker
   fallback, for ~$0.66.

## Consequences

- The plugin's dynamic-panel feature is confirmed working end-to-end via live `claude -p`.
- The harness proved its worth on day one by catching an environment bug that also affected
  the operator's daily use — not the class of bug it was designed for (prose regressions),
  but a more valuable one.
- **Distribution note:** bare-name shadowing is an installed-plugin concern too. Anyone who
  used the pre-plugin skills from `~/.claude` must retire them, or bare `/plan-sprint` keeps
  running the old copy. `CLAUDE.md` already warns against leaving these copies in place.
- The persona-exposure hypothesis (b) is closed as not-reproducible once the shadow is gone;
  reopen only with fresh evidence.
