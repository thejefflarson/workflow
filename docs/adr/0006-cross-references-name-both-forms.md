# 0006 — Cross-references must name both the namespaced and bare form

- Status: accepted
- Date: 2026-08-11
- Supersedes: the "reference own skills/agents by BARE name" invariant in `CLAUDE.md`

## Context

The auto-advance cycle ([ADR 0005](./0005-auto-advancing-cycle-two-gates.md)) has each
phase invoke the next. Those invocations were written with **bare** names — `/idea` said
"invoke `/plan-sprint`" — on the stated belief that a bare name "resolves in both modes:
project-scoped and installed (where Claude maps the bare reference to the namespaced
`workflow:*`)."

**That belief was wrong.** A user ran `/workflow:idea` in another repo, with the plugin
installed globally, and it produced the brief but never advanced to plan-sprint.

Two findings explain it:

1. **Empirical.** In a foreign repo with the plugin installed, the session's registered
   slash commands are `workflow:idea`, `workflow:plan-sprint`, `workflow:work`,
   `workflow:deploy` — and **no bare `plan-sprint`**. The bare form is registered *only in
   this repo*, where `.claude/skills` also loads project-scoped. So the bare reference
   worked in every test we ran here and nowhere else.
2. **Documentation.** The plugins reference states a plugin's `name` "is used for
   namespacing components… the agent `agent-creator` for the plugin `plugin-dev` will
   appear as `plugin-dev:agent-creator`." There is **no documented guarantee** that a bare
   `/name` resolves to the namespaced component when installed.

A bare name inside a `SKILL.md` is not a literal command lookup — it is an *instruction to
the model*, which must then map it onto the available `workflow:*` component. Sometimes it
does; it is not reliable. The same reasoning applies to agent dispatch, and it is the
likeliest cause of the `general-purpose fallback — repo has no .claude/agents/ directory`
message seen during the [ADR 0003](./0003-plan-sprint-shadowed-by-stale-user-skill.md)
investigation from a foreign cwd.

## Decision

Every cross-reference to one of this plugin's own skills or agents **names both forms**:

> invoke the plan-sprint skill — **`/workflow:plan-sprint`** when this plugin is installed,
> or bare `/plan-sprint` when running project-scoped from the source repo; use whichever
> actually resolves.

This is correct in both modes and depends on no inference. Bare-only breaks the installed
case (the normal case for users); namespaced-only breaks the in-repo dev loop by resolving
to the installed copy instead of the working tree. Agent dispatch additionally states:
never silently fall back to `general-purpose` because a bare name didn't resolve.

`validate.sh`'s old check — *fail if `workflow:` appears anywhere under `.claude/`* — was
enforcing the broken behavior and is replaced by assertions that **both** forms appear on
each handoff and agent dispatch.

## Consequences

- The auto-advance chain works where it matters: in other repos, with the plugin installed.
  Previously the headline feature only worked in its own source repo.
- Cross-references are more verbose. That is the cost of resolving in both modes without
  relying on model inference.
- Lesson recorded: **test plugin behavior from a foreign repo, not just in-repo.** Every
  behavioral test to date ran with the source repo's project-scoped components loaded,
  which masked this for the plugin's entire life. The `TESTING.md` manual layer should
  include one foreign-repo run of the full cycle.
