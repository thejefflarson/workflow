# workflow

**Run your whole product loop — plan, build, ship — as a team of AI agents, with humans on
only the two decisions that matter.**

Most AI coding tools help you write a function. `workflow` runs the loop *around* the code:
it thinks an idea through, plans a sprint, builds the whole backlog in parallel, reviews and
merges it, and cuts the release. The four phases **auto-advance into one cycle** — a single
`/idea` (or `/plan-sprint`) flows all the way through to a release without you re-invoking
anything. It's opinionated so you don't have to configure it, and it pauses for a human at
exactly the two places a wrong call is expensive — **what to build** and **when to ship** —
and nowhere else.

Four commands, one loop:

```
/workflow:idea            think an idea all the way through  →  a solid brief
/workflow:plan-sprint     scope it into a sprint             →  tickets + ADRs
/workflow:work            build the backlog                  →  merged PRs
/workflow:deploy          ship it                            →  a tagged release
```

## Why it's different

- **The whole loop, not just codegen — and it auto-advances.** Ideation, planning,
  implementation, security review, merge, and release are one continuous flow that runs
  itself: `/workflow:idea` invokes `/workflow:plan-sprint`, which invokes `/workflow:work`,
  which invokes `/workflow:deploy`. You start it once; it stops only at the two gates.
- **The right model for each job — pay for depth only where it counts.** `/workflow:idea`
  thinks on **fable** (deep 0→1 reasoning); the architect and the planning panel run on
  **opus** (architecture and product judgment); the implementation swarm runs on **sonnet**
  (fast, capable coding). Tokens go where the hard thinking is, not into every keystroke.
- **A team tailored to *your* repo, not one generalist.** `plan-sprint` reads the repo and
  assembles the right panel: a Terraform repo gets a devops engineer, a dbt repo gets a data
  engineer, a web app gets a PM and a designer. Every agent learns *your* conventions,
  invariants, and ADRs from *your* repo — nothing is hard-coded to one stack.
- **Autonomous where it's safe, gated where it isn't.** The build swarm implements each
  ticket in an isolated worktree, runs a security pass, and merges on green — no babysitting.
  The only stops are the two irreversible, outward-facing calls: approving the sprint and
  triggering the release.
- **Real merge discipline.** Engineers open PRs and stop; a separate architect agent does
  the review and merges — normal merges on green only, never forcing past branch protection.
- **Opinionated defaults that keep it simple.** Releases are a tagged merge to `main`. Big
  architectural decisions are written down as ADRs in the repo. Security review
  ([soundcheck](https://github.com/thejefflarson/soundcheck)) is built in, not optional.

## The four commands

| Command | What it does |
| --- | --- |
| **`/workflow:idea`** `[idea]` | The front of the loop. Spins up a deep planning architect (on **fable**) that researches best practices, compares 2–3 real approaches, challenges the idea's assumptions, and recommends the simplest thing that works — then writes a decision-complete **brief** to `docs/ideas/` and hands it to `/workflow:plan-sprint`. Collaborative: it iterates with you before writing anything down. |
| **`/workflow:plan-sprint`** `[theme]` | Assembles a repo-tailored planning panel — the architect always, plus 1–2 of product-manager / product-designer / devops-engineer / data-engineer chosen from what the repo actually is. Synthesizes a small, shippable sprint, records big decisions as **ADRs** in `docs/adr/`, and cuts the tickets into your tracker *after you approve*. |
| **`/workflow:work`** `[ids \| N]` | The build swarm. Pulls ready tickets, runs one **senior-engineer** per ticket in an isolated git worktree (code + tests + PR), runs a **soundcheck** security pass over the combined diff, then an **architect** reviews every PR and merges the good ones in dependency order. Hands off to `/workflow:deploy` if anything merged. |
| **`/workflow:deploy`** `[version \| bump]` | Cuts the release. Computes the next semver from your conventional commits, preflights the branch and pipeline, shows exactly what will ship — then triggers it **only on an explicit human "go."** Default mechanism is a tagged merge to `main`; it detects and honors whatever your repo actually does. |

## Install

```
/plugin marketplace add thejefflarson/workflow
/plugin install workflow@workflow
```

**Soundcheck installs automatically** — it's a declared dependency bundled in this plugin's
marketplace, so the `/workflow:work` security pass always has it. (If you already run
soundcheck from its own marketplace you'll have a harmless second copy under
`soundcheck@workflow`.)

### What you'll want alongside it

- **A tracker.** Linear (via the Linear MCP) is first-class. Falls back to **GitHub Issues
  via `gh`**, then to a plain `docs/sprint-backlog.md` if there's no tracker at all. Point
  the skills at a project with `.claude/tracker.json`
  (`{ "linearTeam": "...", "linearProject": "..." }`) or a tracker section in `CLAUDE.md`.
- **`gh`** — for opening PRs and the GitHub-Issues fallback.

## The one assumption: a deploy is a tagged merge to `main`

`workflow` assumes you ship by pushing a semver tag to `main` that triggers a release job.
`/workflow:plan-sprint` plans each sprint to end in a tagged release and, if your repo
doesn't ship that way, *suggests* adopting it rather than assuming it. `/workflow:deploy`
still detects and honors your repo's actual mechanism — the default is a preference, not a
straitjacket.

## The agents

| Agent | Model | Role | Used by |
| --- | --- | --- | --- |
| `idea-architect` | fable | Deep 0→1 design spike: research, compare approaches, challenge assumptions, recommend the simplest build. | `/workflow:idea` |
| `architect` | opus | Feasibility + sequencing (PLAN); reviews & merges the swarm's PRs (INTEGRATE). Owns ADR decisions. | plan-sprint, work |
| `product-manager` | opus | Scopes user-facing product improvements into ticket drafts. | `/workflow:plan-sprint` |
| `product-designer` | opus | Works UX / states / copy / a11y for the PM's drafts. | `/workflow:plan-sprint` |
| `devops-engineer` | opus | Reliability / release-engineering / cost / toil drafts for infra repos. | `/workflow:plan-sprint` |
| `data-engineer` | opus | Data-quality / pipeline / schema / ML-lifecycle drafts for data & ML repos. | `/workflow:plan-sprint` |
| `senior-engineer` | sonnet | Implements one ticket end-to-end in an isolated worktree; opens a PR, never merges. | `/workflow:work` |

Security review is intentionally **not** an agent here — soundcheck owns it.

## Developing this plugin

```
claude --plugin-dir ~/dev/workflow      # load this repo as the `workflow` plugin
/reload-plugins                          # pick up edits without restarting
claude plugin validate ~/dev/workflow    # check manifests + frontmatter before release
```

`--plugin-dir` shadows any installed copy for the session. **Don't keep old copies of these
skills/agents in `~/.claude/skills` or `~/.claude/agents`** — user-level definitions override
same-named plugin ones, so a leftover silently wins. See [`CLAUDE.md`](./CLAUDE.md) for the
invariants and release steps.

## License

MIT
