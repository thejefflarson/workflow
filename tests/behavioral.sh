#!/usr/bin/env bash
# Behavioral smoke checks for the workflow plugin — real `claude -p` calls, real money.
# Opt-in only (see ADR 0002): never wired into tests/validate.sh or ci.yml. Run this
# locally before a release, or via .github/workflows/behavioral.yml on workflow_dispatch.
# Portable to bash 3.2 (macOS): no associative arrays.
#
# Idiom: same pass()/fail() reporting as tests/validate.sh, nonzero exit on any failure.
# Extensibility: this file globs and SOURCES tests/behavioral.d/*.sh — adding a check
# means dropping a new file there, never editing this one or an existing check file.
#
# ── Spike findings (recorded 2026-07-22, pinned CLI: Claude Code 2.1.218) ──────────
# Settled by hand-running `claude -p` against a generated fixture from this worktree:
#   (a) Skill namespacing: the bare `/plan-sprint` resolves correctly under
#       `--plugin-dir "$REPO"` — no `workflow:` prefix needed. Confirmed via the
#       session-init event's `slash_commands` list (both `plan-sprint` and the
#       namespaced `workflow:plan-sprint` are registered; the bare form dispatches
#       the real skill content, confirmed by its behavior matching SKILL.md's prose).
#   (b) The mandated "Panel: ..." line reaches `--output-format json`'s `.result`
#       field (a plain string). jq path: `.result`. No wrapping JSON schema needed.
#   (c) Print mode's turn-end IS the gate: with `--disallowedTools Task`, the run
#       reliably stops after emitting the announcement (stop_reason "end_turn",
#       terminal_reason "completed") — cheap (3 turns, $0.07-0.15/run) and fast
#       (5-25s) when the prompt explicitly asks it to stop right after the
#       announcement (the harness does this — see bl_claude_p's prompt suffix in
#       10-panel.sh). WITHOUT that explicit stop instruction, `/plan-sprint`'s own
#       "autonomy" principle is not reliably followed on a thin/ambiguous fixture —
#       it sometimes asks a clarifying question instead of resolving autonomously
#       and announcing. That's a real, separate behavioral finding (possible
#       skill-prose gap), out of scope for this scaffold ticket — flagged for a
#       follow-up. The harness's prompt suffix only reinforces what step 1/2 of
#       plan-sprint/SKILL.md already documents (resolve autonomously, state the
#       choice in one line); it does not tell the model what to choose.
#   (d) Denied-`Task` visibility in `--output-format stream-json`: INCONCLUSIVE.
#       Across every hand-run (with and without the stop suffix), the model never
#       actually attempted to call `Task` — it either complied with the stop
#       instruction directly or (without it) stopped to ask a clarifying question
#       first. `permission_denials` was empty in every run. This still needs a
#       real Task-attempt to observe; leave open for the ticket that builds the
#       `/idea` dispatch check (stream-json, subagent_type visible even when denied).
#   SAFETY FINDING (not in the original spike list, found by running this for
#   real): this account has a live Linear MCP server configured account-wide. A
#   naive `claude -p /plan-sprint` run against a "no-tracker" fixture still
#   discovered and queried the *real* Linear workspace (list_teams, list_projects)
#   via the ToolSearch tool, even though the fixture had no `.claude/tracker.json`
#   and the session's `mcp_servers` init field showed `[]`. Fix: every harness
#   invocation passes `--mcp-config '{"mcpServers":{}}' --strict-mcp-config` (see
#   bl_claude_p in tests/lib/behavioral-lib.sh) so a fixture run can never reach a
#   real tracker, regardless of what's configured on the operator's machine. This
#   is load-bearing — do not remove it when editing the wrapper.
#
# ── Full-harness dry runs (real money, real findings, same day) ────────────────
# Ran the complete 4-fixture harness for real four times while building
# 10-panel.sh, fixing bugs found in the harness's own prompt/check logic between
# runs (never the expected-roster patterns, which stayed fixed to TESTING.md's
# table throughout). Two harness bugs were found and fixed this way (details
# below); the final (4th) run's result, with both fixed:
#   - web fixture: PASS -- architect + product-manager + product-designer, no devops.
#   - library fixture: PASS -- architect + product-manager, no devops.
#   - no-tracker fallback (reuses the library-fixture run): PASS -- announces
#     "docs/sprint-backlog.md".
#   - infra fixture: FAIL. Expected architect + devops-engineer, no designer.
#     Across 3 runs the roster included devops in 1, and consistently omitted it
#     in the other 2 (product-manager appeared instead) -- the designer omission
#     itself was consistently correct once the harness's own bugs were fixed.
#   - data fixture: FAIL, reproducibly across all runs. Expected architect +
#     data-engineer; got architect + product-manager every time (correctly
#     omitting designer).
#   These two are genuine, repeatable panel-selection mismatches against
#   plan-sprint/SKILL.md's own edge rules ("infra-only repo -> architect +
#   devops, no PM, no designer"; data repo -> architect + data-engineer) --
#   exactly the class of regression this harness exists to catch (ADR 0001). NOT
#   fixed here (out of this scaffold ticket's scope: the harness, not the skill
#   prose) -- flagged as a follow-up ticket against plan-sprint/SKILL.md's panel
#   rubric for infra/data repo shapes.
#   One early run's data-fixture output additionally said "(agentType:
#   general-purpose fallback -- repo has no `.claude/agents/` directory defining
#   these roles)". Worth a closer look in the follow-up: `--plugin-dir
#   "$WF_REPO"` combined with a `cwd` that ISN'T `$WF_REPO` (the harness's
#   fixture dirs) may not always expose the plugin's named agent personas to the
#   model, which could itself be contributing to the infra/data mismatches above
#   (not just a rubric gap) -- this also matters for real `/plan-sprint` usage
#   against other repos per CLAUDE.md's documented `claude --plugin-dir
#   ~/dev/workflow` usage pattern.
#   Two harness bugs found and fixed (not skill bugs, see 10-panel.sh):
#     1. An early "do not fan out agents" prompt phrasing was misread as license
#        to skip deciding at all (printed a placeholder "Skipped" line instead
#        of a real roster) -- fixed by making the prompt explicit that step 2's
#        *decision* still has to happen and be printed, only the Task call is
#        skipped.
#     2. A free-form "Panel: ..." line let the model narrate *excluded* agents
#        by name in its reasoning ("... product-designer dropped ..."), which
#        made a naive substring-based disallow-check false-positive on a role
#        that was genuinely absent from the roster. Prompt wording alone
#        (asking for the terse canonical format) reduced but did not eliminate
#        this. Fixed deterministically in the check instead: wf_roster_segment()
#        truncates the Panel: line at its first reason-separator (an em dash or
#        " -- ") before any disallow/require check runs, so free-text
#        rationale can never trip the checks either way.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
WF_REPO="$(pwd)"
export WF_REPO

fails=0
pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fails=$((fails + 1)); }
sect() { printf '\n\033[1m%s\033[0m\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

sect "Preflight"
if ! have claude; then
  fail "claude CLI not on PATH — behavioral checks require it"
  printf '\n\033[31mCannot run behavioral checks.\033[0m\n'
  exit 2
fi
if ! have jq; then
  fail "jq not on PATH — behavioral checks require it to parse claude -p JSON output"
  printf '\n\033[31mCannot run behavioral checks.\033[0m\n'
  exit 2
fi
pass "claude CLI found: $(claude --version 2>/dev/null || echo unknown)"
pass "jq found"

# shellcheck source=tests/lib/behavioral-lib.sh
. "$WF_REPO/tests/lib/behavioral-lib.sh"

sect "Discovering checks (tests/behavioral.d/*.sh)"
found=0
for f in "$WF_REPO"/tests/behavioral.d/*.sh; do
  [ -f "$f" ] || continue
  found=$((found + 1))
  pass "sourcing $(basename "$f")"
  # shellcheck source=/dev/null
  . "$f"
done
if [ "$found" -eq 0 ]; then
  fail "no checks found under tests/behavioral.d/*.sh"
fi

# ── Result ───────────────────────────────────────────────────────────
printf '\n'
if [ "$fails" -eq 0 ]; then
  printf '\033[32mAll behavioral checks passed.\033[0m\n'; exit 0
else
  printf '\033[31m%d behavioral check(s) failed.\033[0m\n' "$fails"; exit 1
fi
