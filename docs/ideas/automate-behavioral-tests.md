# Idea brief: Automate the behavioral checks in TESTING.md

> Produced by `/idea` (idea-architect, fable). Front of the loop — feeds `/plan-sprint`.

**IDEA:** Automate the manual behavioral checklist in `TESTING.md` — the six pre-release
checks (panel selection, tracker fallback, `/idea`, `/work` rehearsal, `/deploy` gate,
dependency auto-install) — for the `workflow` plugin.

## Problem & context
The plugin's real risk is behavioral: does prose in a `SKILL.md` actually steer a model to
pick the right panel, stop at the right gate, dispatch the right agent? `tests/validate.sh`
proves the prose *exists*; only the manual checklist proves it *works*, and it runs once
per release (~30 min). Between releases, every edit to `plan-sprint`'s rubric or `deploy`'s
gate ships on faith. The original plan said "don't automate — nondeterministic, no CI key."
That's right about a full eval harness and about `/work`, but it overlooks that the skills
mandate **deterministic one-line announcements** ("Panel: …", the tracker choice, the
computed version) precisely so a human can check them — and anything a human checks by
reading one line, ~150 lines of bash + `claude -p` can check too.

## Goals / non-goals
- **Goals:** automate the checks whose pass/fail is a mechanical read of a mandated output
  line or a filesystem/git invariant; keep every-push CI free (no LLM); shrink the manual
  ritual from ~30 min to ~10; make skill-prose edits testable same-day.
- **Non-goals:** judging prose/plan/agent quality; a reusable eval framework; multi-run
  statistical scoring; mocking Linear/`gh`/git; touching `validate.sh` or the push/PR CI.

## Assumptions challenged
- *"These checks are LLM-driven and nondeterministic"* — **shaky.** The judgment is; the
  **announcement contract** is not. Losing the mandated line is itself a regression.
- *"An eval harness costs more than the plugin"* — **true for a framework, false for a
  smoke harness** in the existing `validate.sh` idiom.
- *"CI has no API key"* — **preserved.** Behavioral tests live in an opt-in
  `workflow_dispatch` job gated on a secret; every-push CI stays free.
- *"Stopping at the gate needs a human"* — **false.** `claude -p` is single-turn; it exits
  at the gate by construction. "Never approve" is free.
- *"All six or none"* — **false.** They split: 3.5 automatable, 2 genuinely need real money.

## Recommended approach — thin headless smoke harness

| # | Check | Verdict | Mechanism |
|---|---|---|---|
| 1 | Panel selection | **Automate** (highest value) | 4 generated fixtures; `claude -p /plan-sprint --plugin-dir $REPO --output-format json --disallowedTools Task` + "stop after announcing the panel." Assert expected agents present **and** the disallowed one absent **within the `Panel:` line**. Disallowing `Task` caps cost at zero opus tokens. |
| 2 | Tracker fallback (no-tracker branch) | **Automate** (free, same runs) | No Linear MCP + no remote → assert it announces `docs/sprint-backlog.md`. gh-enabled variant → manual. |
| 3 | /idea dispatch | **Automate dispatch only** | stream-json + `--disallowedTools Task`; assert a `Task` event with `subagent_type: idea-architect` appears (visible even when denied). Brief quality stays manual. |
| 5 | /deploy dry gate | **Automate** | Fixture: git repo w/ `v0.1.0` tag, a `feat:` commit, `on: push: tags:` workflow, and a **local bare repo as `origin`**. Disallow `Bash(gh:*)`. **Hard assert:** tags/refs unchanged after run (gate held). **Soft assert:** result text mentions `v0.2.0`. |
| 4 | /work rehearsal | **Stays manual** | Needs real PRs, tracker, soundcheck, a swarm — dollars per run to re-test what `validate.sh` pins statically + the architect enforces. |
| 6 | Dependency auto-install | **Token-free script if the CLI cooperates** | `CLAUDE_CONFIG_DIR=$(mktemp -d) claude plugin marketplace add … && install`; assert soundcheck at pinned ref. Tests published state → release ritual, not push CI. |

## Key decisions (see ADRs 0001–0002)
1. Automate 1 / 2-partial / 3-dispatch / 5; keep 4 and the gh-tracker variant manual.
2. Assert on the mandated one-line announcements, **line-scoped** — not a `--json-schema`
   wrapper (which would perturb the prompt under test).
3. Print mode's turn-end **is** the gate — no approving, no answering "no."
4. Fixtures are **generated at runtime into `mktemp -d`**, never committed (committed
   fixtures would trip `validate.sh`'s unexpected-dir checks / plugin discovery).
5. Safety = **sandbox, not tool-blocking** for deploy (local bare origin, `gh` disallowed,
   `git tag/push` allowed) — else the invariant tests nothing.
6. **Home:** `tests/behavioral.sh` (local, primary) + `.github/workflows/behavioral.yml` on
   `workflow_dispatch`, gated on `ANTHROPIC_API_KEY`, pinned CLI version. `ci.yml` untouched.
7. **Flake policy:** one retry per LLM assertion, then fail; a check that flakes across two
   releases gets demoted or deleted. Never loop-until-green.
8. Pin `--model sonnet` for harness runs (conservative floor + cost cap).
9. Rewrite `TESTING.md` to a three-layer split: deterministic (`validate.sh`, every push) →
   behavioral smoke (`behavioral.sh`, pre-release + on-demand) → manual (~10 min).

## Risks & unknowns
- Skill namespacing under `-p --plugin-dir` (`/plan-sprint` vs `/workflow:plan-sprint`) —
  settle with one hand-run in the first hour.
- Denied-`Task` visibility in stream-json (check #3) — verify; fallback is manual, **never**
  an unblocked `Task`.
- CLI flag drift (`--disallowedTools`, `--strict-mcp-config`) — pin the npm CLI version.
- `claude plugin install` may need interactive login — the one genuine unknown; a 5-min
  attempt settles it. If blocked, #6 stays manual.
- False confidence: the harness proves announcements and gates, **not** judgment quality —
  `TESTING.md`'s rewrite must say so or the manual layer atrophies.

## Rough shape & sequence
1. **Spike the lever** (½ day): one fixture, one hand-run — settle namespacing, confirm the
   `Panel:` line reaches `.result`, confirm stop-at-announcement.
2. **`tests/behavioral.sh` core:** fixture generators (4 shapes) + panel/tracker checks,
   line-scoped assertions, retry-once, cost printout from JSON `total_cost_usd`.
3. **Deploy check:** bare-origin fixture + hard/soft assertions.
4. **/idea dispatch check** via stream-json (or drop per the verify step).
5. **`behavioral.yml`** (dispatch, secret-gated, pinned CLI) + rewrite `TESTING.md` split +
   `install-smoke.sh` attempt.
Each step lands independently; step 2 alone captures most of the value.

## Deferred
`/work` e2e automation (revisit only on evidence of a real regression the static checks
missed), nightly scheduling, LLM-as-judge grading, the gh-enabled tracker variant,
multi-run statistical assertions, snapshot testing of skill prose.

## Handoff to /plan-sprint
**Theme:** *Add a behavioral smoke layer — headless `claude -p` checks for panel selection,
tracker fallback, idea dispatch, and the deploy gate; generated fixtures; opt-in workflow;
`TESTING.md` rewritten around the three-layer split.* Frame it as **extending the existing
test idiom, not adding a framework.** Likely panel: **architect + devops-engineer** (tooling
repo, no UI).
