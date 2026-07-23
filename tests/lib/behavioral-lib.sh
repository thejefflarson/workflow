#!/usr/bin/env bash
# tests/lib/behavioral-lib.sh — generic helpers for tests/behavioral.d/*.sh checks.
# Sourced by tests/behavioral.sh, which defines pass()/fail()/sect() and $WF_REPO
# before sourcing this file. Nothing repo-shape-specific lives here (no fixture
# generators) — those belong in the check files that need them.
# Portable to bash 3.2 (macOS): no associative arrays.

# ── fixture scaffolding: mktemp -d + cleanup on exit ────────────────────────
BL_FIXTURE_DIRS=""

bl_cleanup_fixtures() {
  local d
  for d in $BL_FIXTURE_DIRS; do
    [ -n "$d" ] && rm -rf "$d"
  done
}
trap bl_cleanup_fixtures EXIT

# bl_new_fixture_dir LABEL -> prints a fresh mktemp -d path, registered for cleanup.
bl_new_fixture_dir() {
  local label="${1:-fixture}" d
  d=$(mktemp -d "${TMPDIR:-/tmp}/wf-behavioral-${label}.XXXXXX") || return 1
  BL_FIXTURE_DIRS="$BL_FIXTURE_DIRS $d"
  printf '%s\n' "$d"
}

# ── claude -p wrapper: pinned model, no sub-agents, no live MCP, retry-once ──
# bl_claude_p PROMPT CWD -> prints the raw `claude -p --output-format json` result
# on success (exit 0), prints nothing on failure after one retry (exit 1).
#
# --disallowedTools Task caps cost at zero sub-agent tokens (panel/tracker
# selection happens in the main loop before fan-out) and gives print mode a
# structural stop point. --mcp-config '{"mcpServers":{}}' --strict-mcp-config is
# load-bearing, not optional: without it a "no tracker" fixture can still reach a
# real, operator-configured Linear MCP (see behavioral.sh header).
bl_claude_p() {
  local prompt="$1" cwd="$2" out attempt
  for attempt in 1 2; do
    out=$(cd "$cwd" && claude -p "$prompt" \
      --plugin-dir "$WF_REPO" \
      --model sonnet \
      --disallowedTools Task \
      --mcp-config '{"mcpServers":{}}' \
      --strict-mcp-config \
      --output-format json 2>/dev/null)
    if [ -n "$out" ] && printf '%s' "$out" | jq -e '.result // empty' >/dev/null 2>&1; then
      printf '%s' "$out"
      return 0
    fi
  done
  return 1
}

# bl_print_cost JSON — prints the total_cost_usd from a claude -p JSON result.
bl_print_cost() {
  local cost
  cost=$(printf '%s' "$1" | jq -r '.total_cost_usd // "unknown"' 2>/dev/null)
  printf '    total_cost_usd: %s\n' "${cost:-unknown}"
}

# ── asserts: full-text and line-scoped (case-insensitive ERE) ───────────────
# bl_assert_has TEXT PATTERN LABEL — PATTERN anywhere in TEXT.
bl_assert_has() {
  local text="$1" pat="$2" label="$3"
  if printf '%s' "$text" | grep -qiE -- "$pat"; then pass "$label"; else fail "$label"; fi
}

# bl_assert_lacks TEXT PATTERN LABEL — PATTERN must be ABSENT from TEXT.
bl_assert_lacks() {
  local text="$1" pat="$2" label="$3"
  if printf '%s' "$text" | grep -qiE -- "$pat"; then fail "$label -- disallowed match in: $text"; else pass "$label"; fi
}

# bl_line TEXT PREFIX -> the first line of TEXT starting with PREFIX, or empty.
bl_line() {
  printf '%s\n' "$1" | grep -m1 -E -- "^${2}"
}

# bl_assert_line_has TEXT PREFIX PATTERN LABEL — PATTERN must be on the line
# starting with PREFIX (e.g. "Panel:"), not merely present anywhere in TEXT.
bl_assert_line_has() {
  local text="$1" prefix="$2" pat="$3" label="$4" line
  line=$(bl_line "$text" "$prefix")
  if [ -z "$line" ]; then fail "$label (no line starting with \"$prefix\")"; return; fi
  bl_assert_has "$line" "$pat" "$label"
}

# bl_assert_line_lacks TEXT PREFIX PATTERN LABEL — PATTERN must be ABSENT from
# the line starting with PREFIX.
bl_assert_line_lacks() {
  local text="$1" prefix="$2" pat="$3" label="$4" line
  line=$(bl_line "$text" "$prefix")
  if [ -z "$line" ]; then fail "$label (no line starting with \"$prefix\")"; return; fi
  bl_assert_lacks "$line" "$pat" "$label"
}
