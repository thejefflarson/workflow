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
#   (a) Skill namespacing: the harness MUST invoke `/workflow:plan-sprint` (the
#       plugin's namespaced skill under `--plugin-dir "$REPO"`). A bare
#       `/plan-sprint` is UNSAFE: if the operator has a user-scope
#       `~/.claude/skills/plan-sprint`, the bare form silently dispatches THAT
#       instead of the plugin. This was issue #8 (ADR 0003): a stale pre-plugin
#       copy shadowed the real skill and produced wrong panels + a
#       "general-purpose fallback" message. Always name the plugin skill.
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
#   - infra fixture: PASS -- architect + devops-engineer, no designer.
#   - data fixture: PASS -- architect + data-engineer, no designer.
#   ROOT-CAUSE NOTE (issue #8, ADR 0003): earlier runs of THIS harness showed
#   infra/data selecting product-manager instead of devops/data-engineer, plus a
#   "general-purpose fallback -- repo has no .claude/agents/ directory" message.
#   That was NOT a rubric bug and NOT a persona-exposure bug. The harness invoked
#   BARE `/plan-sprint`, which resolved to a stale user-scope
#   `~/.claude/skills/plan-sprint` (the pre-plugin skill: fixed PM+designer+
#   architect trio, general-purpose fallback, no devops/data agents). Fixed by
#   (1) retiring the shadow copies from ~/.claude and (2) invoking
#   `/workflow:plan-sprint`. The plugin's dynamic panel was correct all along;
#   the harness caught a real environment bug that also broke the operator's own
#   bare `/plan-sprint` usage.
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
