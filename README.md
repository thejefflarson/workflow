# workflow

A small Claude Code plugin for shipping software end to end: **plan a sprint**, **work
the backlog**, **cut the release**. Three slash commands, a handful of repo-agnostic
agents, and one hard assumption — *a deploy is a tagged merge to `main`*.

The agents learn each repo from its own `README` / `CLAUDE.md` / ADRs, so the same plugin
works on a web product, a Rust CLI, or a Terraform monorepo.

## The three commands

| Command | What it does |
| --- | --- |
| **`/workflow:plan-sprint`** `[theme]` | Spins up a planning panel **tailored to the repo** — the architect always, plus 1–2 of product-manager / product-designer / devops-engineer chosen from the repo's contents (an infra-only repo gets devops, not a designer). Synthesizes a small sprint, records big decisions as **ADRs** in `docs/adr/`, and cuts the tickets into your tracker after you approve. |
| **`/workflow:work`** `[ids \| N]` | Autonomous build swarm. Pulls ready tickets, runs one **senior-engineer** per ticket (each in an isolated git worktree — code + tests + PR), runs a **soundcheck** security pass, then an **architect** reviews and merges them all in. Hands off to `/workflow:deploy` if anything merged. |
| **`/workflow:deploy`** `[version \| bump]` | Cuts a release. Assumes the framework default — a **tagged merge to `main`** — but detects the repo's actual mechanism, computes the next semver from conventional commits, preflights the branch + pipeline, then triggers the release **after an explicit human "go"**. |

## Install

```
/plugin marketplace add thejefflarson/workflow
/plugin install workflow@workflow
```

**Soundcheck installs automatically.** It's a declared `dependencies` entry and is listed
in this plugin's marketplace, so installing `workflow` pulls it in — the `/workflow:work`
security pass depends on it. (If you already run soundcheck from its own marketplace,
you'll have a second copy under `soundcheck@workflow`; harmless, or install workflow with
a cross-marketplace dependency instead.)

### Soft dependencies

- **A tracker.** Linear (via the Linear MCP) is the first-class tracker. Falls back to
  **GitHub Issues via `gh`**, then to a plain `docs/sprint-backlog.md` if there's no
  tracker at all. Point the skills at a project with `.claude/tracker.json`
  (`{ "linearTeam": "...", "linearProject": "..." }`) or a tracker section in `CLAUDE.md`.
- **`gh`** — required for PRs and the GitHub-Issues tracker fallback.
- **A `/simplify` skill** — used by the engineer if present; falls back to a manual pass.

## The release assumption

This framework assumes **a deploy is a semver tag pushed to `main`** that triggers a
release job. `/workflow:plan-sprint` plans each sprint to end in a tagged release and, if
your repo doesn't ship that way, *suggests* adopting it (as an optional ticket) rather
than assuming it. `/workflow:deploy` still detects and honors whatever mechanism your
repo actually uses.

## The agents

| Agent | Role | Used by |
| --- | --- | --- |
| `workflow:architect` | Feasibility + sequencing (PLAN); reviews & merges the swarm's PRs (INTEGRATE). Owns ADR decisions. | both |
| `workflow:senior-engineer` | Implements one ticket end-to-end in an isolated worktree; opens a PR. | `/workflow:work` |
| `workflow:product-manager` | Scopes user-facing product improvements into ticket drafts. | `/workflow:plan-sprint` |
| `workflow:product-designer` | Works UX / states / copy / a11y for the PM's drafts. | `/workflow:plan-sprint` |
| `workflow:devops-engineer` | Reliability / release-engineering / cost / toil ticket drafts for infra repos. | `/workflow:plan-sprint` |
| `workflow:data-engineer` | Data-quality / pipeline / schema / ML-lifecycle ticket drafts for data & ML repos. | `/workflow:plan-sprint` |

The panel is **tailored to the repo**: `plan-sprint` always runs the architect, then adds
1–2 of product-manager / product-designer / devops-engineer / data-engineer based on what
the repo actually is (a Terraform repo gets devops, a dbt repo gets data, a web app gets
the PM + designer). Security review is intentionally **not** an agent here — soundcheck
owns it.

## Developing this plugin

Iterate against a live copy without publishing:

```
claude --plugin-dir ~/dev/workflow      # loads this repo as the `workflow` plugin
/reload-plugins                          # pick up edits without restarting
claude plugin validate ~/dev/workflow    # check manifests + frontmatter before release
```

`--plugin-dir` overrides a same-named installed plugin for the session, so your working
copy shadows any published version. **Do not also keep the old skills/agents in
`~/.claude/skills` or `~/.claude/agents`** — user-level agent definitions override
same-named plugin agents, so a leftover copy silently wins.

Releasing dogfoods `/workflow:deploy`: merge to `main`, bump `version` in
`.claude-plugin/plugin.json`, and push a `vX.Y.Z` tag.

## License

MIT
