# CLAUDE.md — workflow plugin

This repo **is a Claude Code plugin**, not an application. Its "code" is Markdown: skill
definitions and agent definitions that Claude Code loads. Keep that framing when working
here — there is no build step and no runtime beyond Claude Code itself.

## What this plugin does

Three slash commands that ship software end to end:
- `/workflow:plan-sprint` — a repo-tailored planning panel → tracker tickets + ADRs.
- `/workflow:work` — an autonomous build swarm (senior-engineers → soundcheck → architect merges).
- `/workflow:deploy` — cut a release (default assumption: a **tagged merge to `main`**).

## Layout

```
.claude-plugin/plugin.json        # manifest: name, version, dependencies: ["soundcheck"]
.claude-plugin/marketplace.json   # self-hosted marketplace; lists workflow + soundcheck
skills/<name>/SKILL.md            # the three commands
agents/<name>.md                 # architect, senior-engineer, product-manager,
                                 #   product-designer, devops-engineer, data-engineer
```

All component dirs live at the **plugin root**. Only `plugin.json` / `marketplace.json`
go inside `.claude-plugin/` — putting `skills/` or `agents/` in there is the classic
mistake and they won't load.

## Invariants — do not break these

- **Namespacing is mandatory.** Inside a plugin every command is `/workflow:<name>` and
  every agent is `workflow:<name>`. When a skill spawns an agent or invokes another skill,
  it MUST use the namespaced name. Bare `/work` or `agentType: architect` will not
  resolve. Grep for stray un-namespaced references after any edit.
- **Soundcheck is a hard dependency.** It's declared in `plugin.json` `dependencies` and
  listed in this repo's `marketplace.json` so it auto-installs (same-marketplace
  resolution), pinned to a soundcheck release tag (`source.ref`). Bump that `ref` when
  soundcheck cuts a new release. The `/workflow:work` security pass depends on it — don't
  reintroduce a "degrade to manual review" path as the primary behavior.
- **Agents are repo-agnostic.** Every agent learns the *target* repo's rules from that
  repo's `CLAUDE.md` / ADRs / conventions. Never hard-code assumptions about a specific
  stack or product into an agent.
- **The release model is "tagged merge to `main`."** It's the framework default that all
  three skills assume; `/workflow:deploy` still detects and honors a repo's actual
  mechanism. Keep both: the default is a preference, the detection is the safety net.
- **The merge path is a normal merge on green.** The architect never uses `--admin` or
  bypasses branch protection. Engineers open PRs and STOP — they never self-merge.

## Editing conventions

- Skills carry `name`, `description`, `argument-hint` frontmatter. The `description` is
  what Claude matches on to auto-invoke — keep the trigger phrases in it accurate.
- Agents carry `name`, `description`, `tools`; `senior-engineer` also has
  `isolation: worktree`. The `tools:` list is the agent's allowlist — keep it tight
  (panel agents are read-only + WebSearch; only the engineer gets Edit/Write).
- Panel agents (`product-manager`, `product-designer`, `devops-engineer`,
  `data-engineer`) all emit the **same ticket-draft block** so `plan-sprint` synthesis
  stays agent-agnostic. If you add a panelist, match that output format and add it to the
  panel rubric in `skills/plan-sprint/SKILL.md`.

## Develop & validate

```
claude --plugin-dir ~/dev/workflow     # load this working copy (shadows any installed copy)
/reload-plugins                         # pick up edits without a restart
claude plugin validate .                # run before every commit/release — must pass clean
```

Do **not** leave old copies of these skills/agents in `~/.claude/skills` or
`~/.claude/agents`: user-level agent definitions override same-named plugin agents, so a
leftover copy silently wins and the plugin's version never runs.

## Release

Dogfood `/workflow:deploy`: merge to `main`, bump `version` in `.claude-plugin/plugin.json`,
push a `vX.Y.Z` tag. Never move a published tag — cut a new version instead.
