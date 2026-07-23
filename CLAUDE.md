# CLAUDE.md — workflow plugin

This repo **is a Claude Code plugin**, not an application. Its "code" is Markdown: skill
definitions and agent definitions that Claude Code loads. Keep that framing when working
here — there is no build step and no runtime beyond Claude Code itself.

## What this plugin does

Four slash commands — one continuous loop that ships software end to end:
- `/idea` — a rough idea → a decision-complete design brief (deep planning architect on
  fable) → hands off to plan-sprint. Collaborative, not autonomous.
- `/plan-sprint` — a repo-tailored planning panel → tracker tickets + ADRs.
- `/work` — an autonomous build swarm (senior-engineers → soundcheck → architect merges).
- `/deploy` — cut a release (default assumption: a **tagged merge to `main`**).

(Installed, these are `/workflow:<name>`. In-repo they load project-scoped as `/<name>` —
see the reference-convention invariant below.)

## Layout

```
.claude-plugin/plugin.json        # manifest: name, version, dependencies, component paths
.claude-plugin/marketplace.json   # self-hosted marketplace; lists workflow + soundcheck
.claude/skills/<name>/SKILL.md    # the four commands: idea, plan-sprint, work, deploy
.claude/agents/<name>.md          # idea-architect, architect, senior-engineer,
                                  #   product-manager, product-designer, devops-engineer,
                                  #   data-engineer
```

**Components live under `.claude/`, not the plugin root**, and `plugin.json` points at them
(`"skills": "./.claude/skills"`, `"agents": [ ...explicit file list... ]`). This mirrors
soundcheck and is deliberate: a repo's `.claude/skills` + `.claude/agents` are
auto-discovered as **project-scoped** components whenever you're working in this repo, so
in-repo work always exercises the *source* here, not the globally-installed copy. Only
`plugin.json` / `marketplace.json` go inside `.claude-plugin/`.

Because `plugin.json` lists each agent file explicitly, **adding an agent means adding its
path to the `agents` array** (and specifying the default `agents/` dir is bypassed once you
use the override).

## Invariants — do not break these

- **Reference own skills/agents by BARE name; keep external deps namespaced.** Inside this
  plugin's skills and agents, refer to a sibling as `senior-engineer` / `architect` /
  `/plan-sprint` — NOT `workflow:senior-engineer` or `/workflow:plan-sprint`. Bare names
  resolve in *both* modes: project-scoped (in-repo dev, where agents load bare) and
  installed (where Claude maps the bare reference to the namespaced `workflow:*`). A
  hardcoded `workflow:` prefix breaks the in-repo dev-loop — it would resolve to the
  installed copy instead of your working tree. **External** dependencies keep their names:
  `/soundcheck:security-review`, `/soundcheck:pr-review`, `/simplify` (built-in). Grep for
  stray `workflow:` after any edit — there should be none in `.claude/`.
- **Soundcheck is a hard dependency.** Declared in `plugin.json` `dependencies` and listed
  in this repo's `marketplace.json` so it auto-installs (same-marketplace resolution),
  pinned to a soundcheck release tag (`source.ref`). Bump that `ref` when soundcheck cuts a
  new release. The `/work` security pass depends on it — don't reintroduce a "degrade to
  manual review" path as the primary behavior.
- **Right model per role (token economy is a feature).** Set `model:` in agent frontmatter:
  `idea-architect` → **fable** (deep 0→1 reasoning); `architect` + the four planning panel
  agents → **opus** (architecture / product judgment); `senior-engineer` → **sonnet** (fast
  implementation). Don't flatten these to one tier — matching model to task is part of the
  value prop.
- **Agents are repo-agnostic.** Every agent learns the *target* repo's rules from that
  repo's `CLAUDE.md` / ADRs / conventions. Never hard-code assumptions about a specific
  stack or product into an agent.
- **The release model is "tagged merge to `main`."** The framework default that all skills
  assume; `/deploy` still detects and honors a repo's actual mechanism. Keep both: the
  default is a preference, the detection is the safety net.
- **The merge path is a normal merge on green.** The architect never uses `--admin` or
  bypasses branch protection. Engineers open PRs and STOP — they never self-merge.

## Editing conventions

- Skills carry `name`, `description`, `argument-hint` frontmatter. The `description` is
  what Claude matches on to auto-invoke — keep the trigger phrases accurate. Use the bare
  `/name` form in trigger phrases (matches project-scope and soundcheck's convention).
- Agents carry `name`, `description`, `tools`, `model`; `senior-engineer` also has
  `isolation: worktree`. The `tools:` list is the agent's allowlist — keep it tight (panel
  and idea agents are read-only + WebSearch; only the engineer gets Edit/Write).
- Panel agents (`product-manager`, `product-designer`, `devops-engineer`, `data-engineer`)
  all emit the **same ticket-draft block** so `plan-sprint` synthesis stays agent-agnostic.
  If you add a panelist: match that output format, add it to the panel rubric AND the intro
  agent list in `.claude/skills/plan-sprint/SKILL.md`, and add its file to `plugin.json`.
- Stage separation: `/idea` produces a brief + ADRs (no tickets); `/plan-sprint` produces
  tickets (no code); `/work` writes code + merges; `/deploy` releases. Don't blur them.

## Develop & validate

When you're working inside this repo, the `.claude/` components auto-load project-scoped —
you're already running the source. For an explicit load of this repo as the installed-style
plugin:

```
claude --plugin-dir ~/dev/workflow     # load this working copy as the `workflow` plugin
/reload-plugins                         # pick up edits without a restart
./tests/validate.sh                     # deterministic checks — run before every commit
claude plugin validate .                # manifest/frontmatter schema check (also inside validate.sh)
```

`tests/validate.sh` (bash + jq + grep, runs in CI) enforces the invariants above —
structure, frontmatter, the `model:` tiers, the bare-name convention, and the load-bearing
content lines. Behavioral checks (panel selection, merge discipline, tracker fallback) are
manual and live in `TESTING.md`. When you add a skill, agent, or invariant, add its check.

Do **not** leave old copies of these skills/agents in `~/.claude/skills` or
`~/.claude/agents`: user-level definitions override same-named plugin agents, so a leftover
copy silently wins and the plugin's version never runs.

## Release

Dogfood `/deploy`: merge to `main`, bump `version` in `.claude-plugin/plugin.json`, push a
`vX.Y.Z` tag. Never move a published tag — cut a new version instead.
