#!/usr/bin/env bash
# tests/behavioral.d/30-idea.sh
# Check 3 (issue #3, ADR 0001): does `/idea` dispatch the `idea-architect` subagent?
# Sourced by tests/behavioral.sh: relies on pass()/fail()/sect() and $WF_REPO set
# by the runner. Self-contained: does not call anything defined in a sibling
# check file, and (see finding below) does not invoke `claude -p` at all.
#
# ── DROPPED to the manual layer — documented no-op, not an automated assertion ──
# behavioral.sh's header (spike item (d)) left denied-Task visibility in
# stream-json INCONCLUSIVE because the model never attempted `Task` at all under
# a blanket `--disallowedTools Task`. This ticket re-investigated by hand-running
# `claude -p /workflow:idea ... --output-format stream-json` against a throwaway
# fixture (pinned CLI: Claude Code 2.1.218), driving the prompt straight to step 2
# (dispatch idea-architect) before any stop, under two different deny strategies:
#
#   1. Blanket `--disallowedTools Task` (what bl_claude_p already uses for the
#      panel/idea checks): the `Task`/`Agent` tool is dropped from `ToolSearch`
#      entirely, so the model can't even find it to attempt the call. It searches
#      ("Task subagent dispatch idea-architect", "select:Task", ...), comes up
#      empty, and reports no Task tool is available. `permission_denials` stays
#      empty every time. This reproduces the ORIGINAL spike's inconclusive
#      reading: a blanket deny hides the attempt, so there is nothing to assert.
#
#   2. Subagent-scoped `--disallowedTools 'Task(idea-architect)'` instead: the
#      tool stays discoverable, and in most hand runs the attempted call was
#      denied and DID surface -- the final `result` event's `permission_denials`
#      array contained `{"tool_name":"Task","tool_input":{"subagent_type":
#      "workflow:idea-architect", ...}}`. This looked like a viable automated
#      assertion (and briefly shipped as one during this ticket's development)
#      -- UNTIL repeated hand runs of the *identical* invocation showed it is
#      **not deterministic**: in 3 of 5 hand runs, the identical call was NOT
#      denied at all. The `Agent` tool actually dispatched, `idea-architect` ran
#      to completion on fable, returned a real brief, and the session reported
#      back with a second turn ("The idea-architect returned. Its
#      recommendation: ..."), at real cost (multiple runs in the ~$0.34-0.42
#      range beyond the base per-invocation cost). The model's own denial text
#      in the runs that WERE blocked referenced "the auto mode classifier" --
#      consistent with Task/Agent permission enforcement in headless mode being
#      a heuristic/probabilistic gate rather than a hard, deterministic match on
#      `--disallowedTools`, at least for this subagent-scoped form.
#
# Conclusion: neither strategy is usable. Blanket deny hides the attempt (nothing
# to observe -- the original INCONCLUSIVE finding stands). Subagent-scoped deny
# makes it observable ONLY on the runs where the classifier happens to deny it --
# and on the others, it lets a real `Task` dispatch through, spending real
# fable-tier tokens on a live `idea-architect` run. Per ADR 0001 and this
# ticket's hard rule ("never run an unblocked Task to make the assertion pass" --
# zero sub-agent/fable spend), a mechanism with an empirically observed
# real-dispatch rate this high cannot ship as an automated gate, even though it
# mostly produces the evidence the ticket wants. The safe, conservative call is
# to drop check #3 to the manual layer entirely: this file invokes no `claude -p`
# call of any kind, so it carries zero risk of a live subagent/fable spend no
# matter how the CLI's headless permission classifier behaves on a given run.
#
# `/idea` dispatching `idea-architect` stays covered by:
#   - tests/validate.sh's static check ("idea: dispatches idea-architect" --
#     the SKILL.md content-invariant grep) that the dispatch instruction exists.
#   - TESTING.md's manual checklist (issue #5), which will record this finding
#     and the check-by-hand procedure.

sect "Behavioral: /idea dispatches the idea-architect subagent"
pass "SKIPPED (documented, not a failure): denied-Task visibility for /idea's dispatch is not safely automatable -- see this file's header for the hand-run evidence. Check #3 stays in the manual layer (TESTING.md, issue #5)."
