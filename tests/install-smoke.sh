#!/usr/bin/env bash
# tests/install-smoke.sh — token-free install smoke check (dependency auto-install,
# check #6 in ADR 0001's numbering; see docs/adr/0001-behavioral-test-harness.md).
# Standalone: no LLM calls, not sourced by tests/behavioral.sh. Best-effort per its
# own acceptance criteria — the one genuine unknown is whether `claude plugin
# install` needs interactive auth (a browser login, a device code, an SSH prompt).
# When it does, this degrades to a clean SKIP (exit 0) rather than a failure, and
# check #6 stays on the manual TESTING.md checklist.
#
# Idiom: same pass()/fail() reporting as tests/validate.sh, nonzero exit on any
# real failure. Portable to bash 3.2 (macOS): no associative arrays.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
REPO="$(pwd)"

fails=0
pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fails=$((fails + 1)); }
sect() { printf '\n\033[1m%s\033[0m\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# fail_and_exit MSG — records the failure, prints the running total, exits 1.
fail_and_exit() {
  fail "$1"
  printf '\n\033[31m%d check(s) failed.\033[0m\n' "$fails"
  exit 1
}

# skip_auth STEP — clean SKIP (exit 0) for the one genuine unknown this check
# can't resolve non-interactively: STEP needed a human at a browser/keyboard.
skip_auth() {
  printf '  \033[33mskip\033[0m %s needs interactive auth — check #6 stays manual\n' "$1"
  printf '\n\033[33mSkipped: interactive login required — check #6 stays manual.\033[0m\n'
  exit 0
}

# run_with_timeout SECS CMD... — uses timeout/gtimeout if available, else runs
# uncapped (this script isn't wired into push CI; see ADR 0002 for the same
# opt-in stance on tests/behavioral.sh).
run_with_timeout() {
  local secs="$1"
  shift
  if have timeout; then
    timeout "$secs" "$@"
  elif have gtimeout; then
    gtimeout "$secs" "$@"
  else
    "$@"
  fi
}

# looks_like_auth_prompt OUTPUT — heuristic for "this needs a human at a
# browser/keyboard", the one skip condition the ticket calls out.
looks_like_auth_prompt() {
  printf '%s' "$1" | grep -qiE \
    'login|authenticat|permission denied|publickey|please visit|browser to continue|device code|could not read from remote repository'
}

sect "Preflight"
if ! have claude; then fail "claude CLI not on PATH — install-smoke requires it"; fi
if ! have jq; then fail "jq not on PATH — install-smoke requires it to read the pinned ref"; fi
if [ "$fails" -ne 0 ]; then
  printf '\n\033[31mCannot run install-smoke checks.\033[0m\n'
  exit 2
fi
pass "claude CLI found: $(claude --version 2>/dev/null || echo unknown)"
pass "jq found"

ref=$(jq -r '.plugins[] | select(.name=="soundcheck") | .source.ref // empty' "$REPO/.claude-plugin/marketplace.json" 2>/dev/null)
if [ -z "$ref" ]; then
  fail_and_exit "no soundcheck source.ref pinned in .claude-plugin/marketplace.json"
fi
pass "pinned ref read from marketplace.json: $ref"

CONFIG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/wf-install-smoke.XXXXXX") || { fail "mktemp -d failed"; exit 1; }
cleanup() { rm -rf "$CONFIG_DIR"; }
trap cleanup EXIT

sect "Marketplace add (isolated CLAUDE_CONFIG_DIR)"
mkt_out=$(CLAUDE_CONFIG_DIR="$CONFIG_DIR" run_with_timeout 60 claude plugin marketplace add thejefflarson/workflow 2>&1)
mkt_status=$?
printf '%s\n' "$mkt_out" | sed 's/^/    /'
if [ "$mkt_status" -ne 0 ]; then
  looks_like_auth_prompt "$mkt_out" && skip_auth "marketplace add"
  fail_and_exit "marketplace add failed (exit $mkt_status)"
fi
pass "marketplace added"

sect "Plugin install (best-effort)"
inst_out=$(CLAUDE_CONFIG_DIR="$CONFIG_DIR" run_with_timeout 90 claude plugin install workflow 2>&1)
inst_status=$?
printf '%s\n' "$inst_out" | sed 's/^/    /'
if [ "$inst_status" -ne 0 ]; then
  looks_like_auth_prompt "$inst_out" && skip_auth "plugin install"
  fail_and_exit "plugin install failed (exit $inst_status)"
fi
pass "workflow plugin installed"

sect "Verify soundcheck resolved at pinned ref"
list_json=$(CLAUDE_CONFIG_DIR="$CONFIG_DIR" claude plugin list --json 2>/dev/null)
installed_version=$(printf '%s' "$list_json" | jq -r '[.[] | select(.id | startswith("soundcheck@"))][0].version // empty' 2>/dev/null)
if [ -z "$installed_version" ]; then
  fail "soundcheck not found in installed plugin list (dependency auto-install did not resolve)"
else
  want_version="${ref#v}"
  if [ "$installed_version" = "$want_version" ]; then
    pass "soundcheck installed at pinned ref ($ref -> version $installed_version)"
  else
    fail "soundcheck version mismatch: installed $installed_version, marketplace.json pins $ref (want $want_version)"
  fi
fi

# ── Result ───────────────────────────────────────────────────────────
printf '\n'
if [ "$fails" -eq 0 ]; then
  printf '\033[32mAll install-smoke checks passed.\033[0m\n'
  exit 0
else
  printf '\033[31m%d install-smoke check(s) failed.\033[0m\n' "$fails"
  exit 1
fi
