# CLAUDE.md — workflow plugin

This repo **is a Claude Code plugin**, not an application. Its "code" is Markdown: skill
definitions and agent definitions that Claude Code loads. Keep that framing when working
here — there is no build step and no runtime beyond Claude Code itself.

## What this plugin does

Four slash commands — one continuous loop that ships software end to end:
- `/idea` — a rough idea → a decision-complete design brief (deep planning architect on
  fable) → auto-advances to plan-sprint. Collaborative on the brief; then hands off.
- `/plan-sprint` — a repo-tailored planning panel → tracker tickets + ADRs → auto-advances to work.
- `/work` — an autonomous build swarm (senior-engineers → soundcheck → architect merges) → auto-advances to deploy.
- `/deploy` — cut a release (default assumption: a **tagged merge to `main`**).

**The phases auto-advance into one cycle** — each invokes the next, so a single `/idea`
(or `/plan-sprint`) flows through to release without manual re-invocation. **Two human
gates remain**, at exactly the two outward-facing/irreversible decisions: `/plan-sprint`
confirms the plan *before* creating tickets, and `/deploy` confirms *before* pushing the
release tag. Everything between those gates runs autonomously.

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
- **Soundcheck is a hard dependency — cross-marketplace.** Declared in `plugin.json`
  `dependencies` as `{ "name": "soundcheck", "marketplace": "soundcheck" }`, permitted by
  `allowCrossMarketplaceDependenciesOn: ["soundcheck"]` in this repo's `marketplace.json`.
  It resolves from soundcheck's **own** marketplace, so it updates independently of workflow
  — there's no bundled copy in our marketplace and **no `ref` to bump here**. Trade-off:
  installers must `marketplace add thejefflarson/soundcheck` first (Claude Code won't
  auto-add a marketplace), or the install is `dependency-unsatisfied`. The `/work` security
  pass depends on it — don't reintroduce a "degrade to manual review" path as the primary
  behavior, and don't re-bundle soundcheck into our marketplace (that reintroduces the
  duplicate-copy problem).
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
- **Auto-advancing cycle, two human gates.** The four phases chain automatically (`/idea`
  invokes `/plan-sprint`, `/plan-sprint` invokes `/work`, `/work` invokes `/deploy`), but
  the two gates on outward-facing/irreversible actions **must stay**: `/plan-sprint`
  confirms before creating tickets, `/deploy` confirms before pushing the tag. Adding the
  auto-advance handoffs is fine; removing either gate is not — the safety of the autonomous
  span between them (soundcheck pass, green-only merge, deploy preflights) presupposes a
  human said "build this" and "ship this."

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
  tickets (no code); `/work` writes code + merges; `/deploy` releases. They auto-advance
  (each ends by invoking the next) but stay distinct stages — don't blur their bodies, and
  keep the two gates (see the auto-advancing-cycle invariant above).

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
content lines. Behavioral checks run in a second layer — `tests/behavioral.sh` (opt-in,
real `claude -p`) for panel selection, tracker fallback, and the `/deploy` gate; the
residue (`/work` rehearsal, judgment quality) stays manual. See `TESTING.md` for the
three-layer split. When you add a skill, agent, or invariant, add its check.

Do **not** leave old copies of these skills/agents in `~/.claude/skills` or
`~/.claude/agents`: user-level definitions override same-named plugin agents, so a leftover
copy silently wins and the plugin's version never runs.

## Release

Dogfood `/deploy`. **Before tagging, update the manifests so the marketplace serves
accurate, versioned metadata** — this is easy to forget and ships a wrong listing:
- Bump `version` in `.claude-plugin/plugin.json`.
- Set the `workflow` entry's `source.ref` in `.claude-plugin/marketplace.json` to the new
  `vX.Y.Z` tag. (soundcheck is a cross-marketplace dependency now — it updates from its own
  marketplace, so there's nothing soundcheck-related to bump here.)
- Refresh `description` / `keywords` in **both** manifests if the command set changed.

Then merge to `main` and push the `vX.Y.Z` tag **at that commit** — the git tag IS the
release: the marketplace source `ref` resolves it and there is no separate build/publish
pipeline. Never move a published tag — cut a new version instead.
