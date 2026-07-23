#!/usr/bin/env bash
# tests/behavioral.d/10-panel.sh
# Check 1: /plan-sprint's panel selection matches the repo-shape table in TESTING.md.
# Check 2: on a no-tracker fixture (no .claude/tracker.json, no CLAUDE.md tracker
#          section, no git remote, no live MCP -- see bl_claude_p), the tracker
#          announcement names the docs/sprint-backlog.md fallback.
# Sourced by tests/behavioral.sh: relies on pass()/fail()/sect() and the bl_*
# helpers from tests/lib/behavioral-lib.sh, and $WF_REPO set by the runner.

# ── fixture generators (the 4 repo shapes from TESTING.md's table) ──────────
wf_git_init() (
  cd "$1" || exit 1
  git init -q
  git add -A
  git -c user.email=fixture@example.invalid -c user.name=fixture commit -q -m "fixture: initial" >/dev/null
)

wf_gen_fixture_web() {
  local d
  d=$(bl_new_fixture_dir web) || return 1
  cat >"$d/README.md" <<'EOF'
# Loglines

A hosted web app that lets small support teams turn customer chat transcripts
into searchable, taggable case notes. Customers sign up, invite teammates, and
pay a monthly per-seat subscription.
EOF
  cat >"$d/package.json" <<'EOF'
{ "name": "loglines-web", "version": "0.0.0", "private": true, "dependencies": { "react": "^18.0.0" } }
EOF
  mkdir -p "$d/app"
  printf 'export default function Home() { return null; }\n' >"$d/app/page.tsx"
  wf_git_init "$d"
  printf '%s\n' "$d"
}

wf_gen_fixture_infra() {
  local d
  d=$(bl_new_fixture_dir infra) || return 1
  cat >"$d/README.md" <<'EOF'
# platform-infra

Terraform-managed cloud infrastructure for the company's internal platform:
Kubernetes clusters, networking, IAM, and the observability stack. Consumed
only by the platform/SRE team -- there is no end-user product or UI here.
EOF
  cat >"$d/main.tf" <<'EOF'
terraform {
  required_version = ">= 1.0"
}

resource "null_resource" "placeholder" {}
EOF
  wf_git_init "$d"
  printf '%s\n' "$d"
}

wf_gen_fixture_data() {
  local d
  d=$(bl_new_fixture_dir data) || return 1
  cat >"$d/README.md" <<'EOF'
# revenue-warehouse

A dbt project that models raw billing and product-usage events into the
revenue data warehouse used by finance and analytics for reporting. No UI --
the consumers are internal data analysts.
EOF
  cat >"$d/dbt_project.yml" <<'EOF'
name: revenue_warehouse
version: '1.0.0'
config-version: 2
EOF
  wf_git_init "$d"
  printf '%s\n' "$d"
}

wf_gen_fixture_library() {
  local d
  d=$(bl_new_fixture_dir library) || return 1
  cat >"$d/README.md" <<'EOF'
# ratelimit-rs

A token-bucket rate-limiting crate for Rust services. Published so other
engineering teams can `cargo add ratelimit-rs` and call it from their own
service code. There is no web UI, no CLI binary, and no end-user-facing
surface at all -- the only consumers are developers writing Rust.
EOF
  cat >"$d/Cargo.toml" <<'EOF'
[package]
name = "fixture-lib"
version = "0.1.0"
edition = "2021"
EOF
  mkdir -p "$d/src"
  printf 'pub fn noop() {}\n' >"$d/src/lib.rs"
  wf_git_init "$d"
  printf '%s\n' "$d"
}

# ── run one fixture through /plan-sprint, assert Tracker:/Panel: lines ──────
# The prompt suffix reinforces (does not override) what plan-sprint/SKILL.md's
# own step 1 and step 2 already document: resolve autonomously and state each
# choice in one line. Asking for a "Tracker:" prefix keeps that announcement
# grep-able the same way the skill's own "Panel:" example already is. See
# behavioral.sh's header for the two harness-prompt bugs this wording fixes.
WF_PLAN_SPRINT_PROMPT='/plan-sprint -- behavioral-harness smoke run. Actually do steps 1 and 2: inspect this repo for real (README, manifests, .claude/tracker.json, CLAUDE.md, git remote -v) and resolve every open question yourself per your own autonomy principle -- never ask a clarifying question. When step 2 says to spawn the panel in parallel, stop there instead of calling any tool to do so, and do not create tickets or write files -- but you must still make and print the real decisions: emit exactly two lines, (1) your one-line tracker-resolution announcement prefixed "Tracker:" (state the actual resolved value, e.g. "docs/sprint-backlog.md" if no tracker is configured -- never guess a project name), (2) the "Panel: ..." line in the terse canonical format from step 2 of the skill (agent names joined by "+", then an em dash and a short reason) naming ONLY the agents you actually selected -- do not narrate or name any agent you considered and excluded. Always print both real lines, even though you will not fan out.'

# Agent-name patterns tolerant of the abbreviations observed in spike runs (e.g.
# "PM + Designer + Architect" as well as "product-manager, product-designer,
# architect"). Case-insensitive EREs, matched by bl_assert_has/bl_assert_lacks
# against the roster segment (see wf_roster_segment below).
WF_PAT_ARCHITECT='architect'
WF_PAT_PM='product-manager|\bpm\b'
WF_PAT_DESIGNER='product-designer|designer'
WF_PAT_DEVOPS='devops-engineer|devops'
WF_PAT_DATA='data-engineer|data.engineer'

# wf_roster_segment LINE -> LINE truncated at the first "reason" separator (an
# em dash or " -- "), so a disallow-check only ever looks at the actual roster,
# never at free-text explaining why a role was considered and excluded. Real
# spike runs showed the model reliably naming excluded roles in its reasoning
# ("... product-designer dropped ...") even when explicitly told not to --
# truncating the line is a deterministic fix, prompt wording alone was not.
wf_roster_segment() {
  local seg="$1"
  seg="${seg%%—*}"
  seg="${seg%% -- *}"
  printf '%s\n' "$seg"
}

# wf_panel_case NAME DIR REQUIRED_PATTERN... -- DISALLOWED_PATTERN
# Each REQUIRED_PATTERN must independently appear in the Panel: line's roster
# segment (AND, not OR -- checked one assert per pattern); DISALLOWED_PATTERN
# must not appear there either. Patterns are case-insensitive EREs (see
# bl_assert_line_has/_lacks).
wf_panel_case() {
  local name="$1" dir="$2"
  shift 2
  local required="" disallowed="" seen_sep=0 arg
  for arg in "$@"; do
    if [ "$arg" = "--" ]; then
      seen_sep=1
      continue
    fi
    if [ "$seen_sep" -eq 0 ]; then required="$required $arg"; else disallowed="$arg"; fi
  done

  local json
  if ! json=$(bl_claude_p "$WF_PLAN_SPRINT_PROMPT" "$dir"); then
    fail "$name: claude -p /plan-sprint failed (after retry)"
    return 1
  fi
  bl_print_cost "$json"

  local result
  result=$(printf '%s' "$json" | jq -r '.result // empty')
  if [ -z "$result" ]; then
    fail "$name: no .result in JSON output"
    return 1
  fi

  local panel_line roster
  panel_line=$(bl_line "$result" 'Panel:')
  if [ -z "$panel_line" ]; then
    fail "$name: no line starting with \"Panel:\""
    return 1
  fi
  roster=$(wf_roster_segment "$panel_line")

  local a
  for a in $required; do
    bl_assert_has "$roster" "$a" "$name: Panel roster names $a"
  done
  bl_assert_lacks "$roster" "$disallowed" "$name: Panel roster omits $disallowed"
  WF_LAST_PANEL_RESULT="$result"
}

sect "Behavioral: /plan-sprint panel selection (4 fixtures, see TESTING.md table)"

d=$(wf_gen_fixture_web) && wf_panel_case "web fixture" "$d" \
  "$WF_PAT_ARCHITECT" "$WF_PAT_PM" "$WF_PAT_DESIGNER" -- "$WF_PAT_DEVOPS"

d=$(wf_gen_fixture_infra) && wf_panel_case "infra fixture" "$d" \
  "$WF_PAT_ARCHITECT" "$WF_PAT_DEVOPS" -- "$WF_PAT_DESIGNER"

d=$(wf_gen_fixture_data) && wf_panel_case "data fixture" "$d" \
  "$WF_PAT_ARCHITECT" "$WF_PAT_DATA" -- "$WF_PAT_DESIGNER"

WF_LAST_PANEL_RESULT=""
d=$(wf_gen_fixture_library) && wf_panel_case "library fixture" "$d" \
  "$WF_PAT_ARCHITECT" "$WF_PAT_PM" -- "$WF_PAT_DEVOPS"

sect "Behavioral: /plan-sprint no-tracker fallback (reuses the library-fixture run)"
# None of the 4 fixtures has a .claude/tracker.json, a CLAUDE.md tracker section,
# a git remote, or (thanks to bl_claude_p's --strict-mcp-config) a reachable
# Linear MCP -- so any of them is a valid "no tracker" case. We reuse the
# library-fixture run rather than spending a 5th claude -p call.
if [ -n "${WF_LAST_PANEL_RESULT:-}" ]; then
  bl_assert_line_has "$WF_LAST_PANEL_RESULT" 'Tracker:' 'sprint-backlog\.md' \
    "no-tracker fixture: announces the docs/sprint-backlog.md fallback"
else
  fail "no-tracker fixture: no result captured from the library-fixture run"
fi
