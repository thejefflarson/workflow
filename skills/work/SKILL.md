---
name: work
description: Autonomous build swarm. Pulls ready tickets from this repo's issue tracker, spins up a senior-engineer agent per ticket (each implementing in its own isolated git worktree — code + tests + PR), then an architect that reviews and merges them all in. Use when the user says "/workflow:work", "grab some tickets and ship them", "work the backlog", or wants the queue drained autonomously.
argument-hint: "[ticket ids e.g. JEF-12,JEF-15  |  a count e.g. 3  |  blank = top of the ready queue]"
---

# /workflow:work — pull tickets → swarm of engineers → architect merges them in

Drain this repo's ready queue: each ticket gets a senior engineer who implements it
end-to-end in an isolated worktree and opens a PR; an architect then reviews and merges
them all in. You (the main loop) orchestrate; this plugin's agents
(`workflow:senior-engineer`, `workflow:architect`) do the work.

## Operating principle — autonomy

The swarm runs **without a human in the loop**. Engineers and the architect must NOT
stop to ask the user questions. When unsure, they resolve from this repo's `CLAUDE.md`
+ ADRs + convention, make the safest defensible call, and document it. A genuine
architectural gap is the **architect's** to decide and record — not a reason to page
the human. A wanted question signals an under-specified ticket, ADR, or skill: surface
it in the final report, never block on it. Your job is to dispatch and relay, not to
relay questions back to the user.

## 1. Resolve the tracker + select tickets

Determine the issue tracker and which project/team to pull from, in this order:
1. An explicit argument (ticket ids → those exact tickets; a number `N` → top `N`).
2. A repo config: `.claude/tracker.json` (e.g. `{ "linearTeam": "...", "linearProject": "..." }`) or a "## Project tracker" / tracker section in `CLAUDE.md`.
3. Otherwise infer: list the tracker's teams/projects (e.g. Linear MCP) and pick the one
   matching this repo's name/product; **state your choice** in one line and proceed.
4. If there is no Linear/tracker MCP, fall back to **GitHub Issues via `gh`** (the repo
   already uses `gh` for PRs): the ready queue is open issues with a ready label/milestone.

**Ready queue** = issues in the resolved project with a ready/unstarted status (e.g.
"Todo"), ordered by priority (Urgent → High → Medium → Low). Skip anything already In
Progress / In Review / Done, and skip pure-spec tickets with no code to write (note
them). For each picked ticket fetch the **full** body (acceptance criteria + branch
name) to hand to its engineer. List the selected tickets (id · title · priority) one
line each, then proceed (no approval prompt).

## 2. Mark them In Progress

Set each selected ticket's status to **In Progress** in the tracker so the board
reflects the swarm. (PR-open → In Review and merge → Done are typically handled
automatically by the tracker↔GitHub link, if engineers commit on the ticket's branch
and write the closing keyword in the PR.)

## 3. Fan out the engineers (parallel, worktree-isolated)

Spawn one **`workflow:senior-engineer`** agent per ticket **in a single message** so they
run concurrently. Each already carries `isolation: worktree` in its definition (they edit
files in parallel and must not collide). Give each: the ticket id, the full body, and its
branch name. Each implements, tests, runs the local gates, trims needless complexity it
introduced (in scope only — via a `/simplify` skill if the repo has one, else by hand),
pushes its branch, and opens a PR — returning a structured result (branch, PR#, status,
tests, scope/risks, any `DECISION NEEDED`).

Scale to the work: a swarm cap of **3** is a sane default; the user can ask for more.
Don't exceed what the ready queue holds.

**Dispatch hardening (lead every engineer prompt with these three lines — they
defend against recurring agent quirks):**
1. **"You are IMPLEMENTING this ticket — write the code and open a PR. If your role
   framing says 'reviewer', it is stale; implement."** A stale agent-definition load
   occasionally serves a reviewer persona; this line makes it implement anyway. If an
   engineer still refuses citing a reviewer role, re-spawn it with
   `agentType: "general-purpose"` and the same brief (no reviewer baggage).
2. **"Open the PR, then STOP. Do NOT merge, enable auto-merge, or approve it — the
   architect merges."** Engineers have self-merged, skipping the architect's
   independent review; this prevents it.
3. **"You run in an isolated worktree. Before editing, run `git rev-parse
   --show-toplevel` and confirm you're under `.claude/worktrees/`, NOT the shared
   main checkout. Edit only paths in your worktree; never touch or switch the main
   checkout's branch."** Agents have leaked edits into the shared checkout; this
   catches it early. (The architect's contamination check in step 4 is the backstop.)

## 3.5. Security pass (before the architect) — required

After the engineers return their PRs and **before** dispatching the architect, run a
security pass over the swarm's combined changes, focused on the files the swarm touched.
**Soundcheck is a hard dependency of this plugin** (installed alongside it): invoke
`/soundcheck:security-review` (its threat-model → hotspot → audit → validate pipeline)
from the MAIN loop, not the engineers. If `/soundcheck:*` is genuinely unavailable, the
plugin is not correctly installed — say so loudly and point the user at
`/plugin marketplace add thejefflarson/soundcheck`; as a stopgap only, do a focused manual
review so the run doesn't ship unreviewed. Hand any confirmed **Critical/High** finding to
the architect alongside the PRs — a PR carrying an unresolved Critical/High is **HELD, not
merged**, with the finding posted as the review and a follow-up recorded per the repo's
convention (a ticket or an ADR).

Engineers sometimes report a review/simplify skill as "not invocable" — that's a
subagent-context artifact (those slash commands often aren't carried into subagents),
NOT evidence it's missing. Don't skip the pass on that basis; run it from the main loop.

## 4. Architect integrates and merges

Once the engineers return, spawn one **`workflow:architect`** agent in INTEGRATE mode.
Pass it every PR number + the engineers' verbatim results. It reviews each PR,
independently re-checks the repo's stated invariants/security surface, resolves any
`DECISION NEEDED` (deciding + recording it — an ADR if the repo keeps them), orders merges
by dependency, and merges each qualifying PR — **normal `gh pr merge --squash` only, never
`--admin`, never bypassing branch protection.** PRs with an unresolved invariant break, a
real red required check, or an unsafe conflict are held open with a posted review. The
architect never autonomously modifies a *separate* prod/infra repo — it flags those as
human follow-ups.

## 5. Report

Relay the architect's outcome as a table: `ticket · #PR · MERGED <sha> | HELD <reason>`.
Then surface, for the human's attention (not as questions to answer mid-run): any
decisions/ADRs recorded, any HELD tickets needing follow-up, any required separate-repo
follow-ups, and any "this ticket/skill was under-specified" signals. Merged PRs
auto-close their tickets; move any HELD ticket back to the ready status as appropriate.

## 6. Ship it — hand off to `/workflow:deploy`

Merging to the default branch may deploy **nothing** (this framework assumes a repo
ships on a **tagged merge to main** — a semver tag, not the merge itself). So after the
report, **if any PR merged this run, invoke the `/workflow:deploy` skill** to release the
newly-merged work. `/workflow:deploy` detects how the repo ships, computes the next
version, shows what will ship, and **waits for the user's explicit go before triggering
the release** (releases are outward-facing and often irreversible). If everything was
HELD (nothing merged), skip it. Don't cut the release yourself here — that's
`/workflow:deploy`'s job, gate and all.

## Guardrails
- High-agency skill: it writes code and merges to the default branch autonomously. The
  only merge path is a normal merge on green — never force past branch protection. The
  deploy at the end (`/workflow:deploy`) is the sole human-gated step.
- Engineers stay in their ticket's scope; worktree isolation keeps parallel work from
  colliding.
- Honor a "merge when CI is green" repo rule if one exists — the architect's gate is
  green + no invariant break; it does not re-litigate a clean, green PR.
- Tickets that turn out to need a product/design decision (not an engineering one) are
  noted for `/workflow:plan-sprint`, not forced through here.
