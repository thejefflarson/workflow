#!/usr/bin/env bash
# Deterministic checks for the workflow plugin — no LLM in the loop.
# Layers 1 (structure/manifest/frontmatter) and 2 (content invariants from CLAUDE.md).
# Portable to bash 3.2 (macOS): no associative arrays.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

fails=0
pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fails=$((fails + 1)); }
sect() { printf '\n\033[1m%s\033[0m\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# assert_has FILE "fixed string" [label]
assert_has() {
  local f="$1" s="$2" label="${3:-$2}"
  if grep -qF -- "$s" "$f" 2>/dev/null; then pass "$f: $label"; else fail "$f: missing \"$label\""; fi
}
# assert_absent FILE "ERE pattern" label
assert_absent() {
  local f="$1" re="$2" label="$3"
  if grep -qE -- "$re" "$f" 2>/dev/null; then fail "$f: $label"; else pass "$f: $label"; fi
}
# frontmatter value for a key (first match), e.g. fm_val file model
fm_val() { grep -m1 -E "^$2:" "$1" 2>/dev/null | sed -E "s/^$2:[[:space:]]*//"; }

SKILLS="idea plan-sprint work deploy"
AGENTS="idea-architect architect product-manager product-designer devops-engineer data-engineer senior-engineer"
PANELISTS="product-manager devops-engineer data-engineer" # share the ticket-draft block (designer has its own)

expected_model() {
  case "$1" in
    idea-architect) echo fable ;;
    senior-engineer) echo sonnet ;;
    architect|product-manager|product-designer|devops-engineer|data-engineer) echo opus ;;
    *) echo "" ;;
  esac
}

# ── Layer 1a: manifests ──────────────────────────────────────────────
sect "Manifests"
if have jq; then
  jq empty .claude-plugin/plugin.json 2>/dev/null && pass "plugin.json is valid JSON" || fail "plugin.json invalid JSON"
  jq empty .claude-plugin/marketplace.json 2>/dev/null && pass "marketplace.json is valid JSON" || fail "marketplace.json invalid JSON"

  [ "$(jq -r '.name' .claude-plugin/plugin.json)" = "workflow" ] && pass "plugin name is workflow" || fail "plugin name != workflow"
  ver=$(jq -r '.version' .claude-plugin/plugin.json)
  echo "$ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' && pass "version is semver ($ver)" || fail "version not semver ($ver)"
  jq -e '.dependencies | index("soundcheck")' .claude-plugin/plugin.json >/dev/null && pass "declares soundcheck dependency" || fail "missing soundcheck dependency"

  # every dependency is listed in the marketplace (same-marketplace auto-install)
  for dep in $(jq -r '.dependencies[]' .claude-plugin/plugin.json); do
    jq -e --arg d "$dep" '.plugins[] | select(.name==$d)' .claude-plugin/marketplace.json >/dev/null \
      && pass "dependency '$dep' is listed in marketplace.json" \
      || fail "dependency '$dep' NOT in marketplace.json (won't auto-resolve)"
  done
  # soundcheck source pin must be present
  ref=$(jq -r '.plugins[] | select(.name=="soundcheck") | .source.ref // ""' .claude-plugin/marketplace.json)
  [ -n "$ref" ] && pass "soundcheck pinned to $ref" || fail "soundcheck source.ref is empty (should pin a release tag)"

  # component paths point under .claude/
  [ "$(jq -r '.skills' .claude-plugin/plugin.json)" = "./.claude/skills" ] && pass "skills path -> ./.claude/skills" || fail "skills path override wrong/missing"
  for a in $AGENTS; do
    jq -e --arg p "./.claude/agents/$a.md" '.agents | index($p)' .claude-plugin/plugin.json >/dev/null \
      && pass "agents[] lists $a.md" || fail "agents[] missing ./.claude/agents/$a.md"
  done
else
  fail "jq not found — cannot check manifests (install jq)"
fi

# ── Layer 1b: structure ──────────────────────────────────────────────
sect "Structure"
[ -d .claude/skills ] && pass ".claude/skills exists" || fail ".claude/skills missing"
[ -d .claude/agents ] && pass ".claude/agents exists" || fail ".claude/agents missing"
[ ! -d skills ] && [ ! -d agents ] && pass "no stray root-level skills/ or agents/" || fail "root-level skills/ or agents/ present (should live under .claude/)"
[ ! -d .claude-plugin/skills ] && [ ! -d .claude-plugin/agents ] && pass "no components under .claude-plugin/" || fail "components wrongly nested under .claude-plugin/"

for s in $SKILLS; do
  [ -f ".claude/skills/$s/SKILL.md" ] && pass "skill present: $s" || fail "skill missing: $s"
done
for a in $AGENTS; do
  [ -f ".claude/agents/$a.md" ] && pass "agent present: $a" || fail "agent missing: $a"
done
# no unexpected skills/agents (forces this list to stay in sync with the roster)
for d in .claude/skills/*/; do n=$(basename "$d"); echo " $SKILLS " | grep -q " $n " || fail "unexpected skill dir: $n"; done
for f in .claude/agents/*.md; do n=$(basename "$f" .md); echo " $AGENTS " | grep -q " $n " || fail "unexpected agent file: $n"; done

# ── Layer 1c: frontmatter ────────────────────────────────────────────
sect "Frontmatter"
for s in $SKILLS; do
  f=".claude/skills/$s/SKILL.md"
  [ "$(fm_val "$f" name)" = "$s" ] && pass "$s: name matches dir" || fail "$s: frontmatter name != dir"
  [ -n "$(fm_val "$f" description)" ] && pass "$s: has description" || fail "$s: missing description"
  [ -n "$(fm_val "$f" argument-hint)" ] && pass "$s: has argument-hint" || fail "$s: missing argument-hint"
done
for a in $AGENTS; do
  f=".claude/agents/$a.md"
  [ "$(fm_val "$f" name)" = "$a" ] && pass "$a: name matches file" || fail "$a: frontmatter name != file"
  [ -n "$(fm_val "$f" description)" ] && pass "$a: has description" || fail "$a: missing description"
  [ -n "$(fm_val "$f" tools)" ] && pass "$a: has tools" || fail "$a: missing tools"
  want=$(expected_model "$a"); got=$(fm_val "$f" model)
  [ "$got" = "$want" ] && pass "$a: model=$got" || fail "$a: model is '$got', expected '$want'"
done
# tool allowlists: only senior-engineer may write
for a in $AGENTS; do
  f=".claude/agents/$a.md"; tools=$(fm_val "$f" tools)
  if [ "$a" = "senior-engineer" ]; then
    echo "$tools" | grep -q "Edit" && pass "senior-engineer has Edit/Write" || fail "senior-engineer should have Edit/Write"
  else
    echo "$tools" | grep -qE "Edit|Write" && fail "$a should NOT have Edit/Write (read-only role)" || pass "$a is read-only"
  fi
done
assert_has .claude/agents/senior-engineer.md "isolation: worktree" "isolation: worktree"

# ── Layer 1d: reference convention ───────────────────────────────────
sect "Reference convention (bare internal, namespaced external)"
if grep -rn "workflow:" .claude/skills .claude/agents >/dev/null 2>&1; then
  grep -rn "workflow:" .claude/skills .claude/agents; fail "stray 'workflow:' prefix in .claude/ (internal refs must be bare)"
else
  pass "no 'workflow:' prefixes in .claude/ (bare-name convention holds)"
fi
assert_has .claude/skills/work/SKILL.md "/soundcheck:security-review" "external soundcheck ref intact"
assert_has .claude/agents/senior-engineer.md "/soundcheck:pr-review" "external soundcheck ref intact"

# ── Layer 2: content invariants (from CLAUDE.md) ─────────────────────
sect "Content invariants"
# senior-engineer discipline
se=.claude/agents/senior-engineer.md
assert_has "$se" "Do NOT merge" "engineer: do-not-merge rule"
assert_has "$se" ".claude/worktrees/" "engineer: worktree guard"
assert_has "$se" "git rev-parse --show-toplevel" "engineer: contamination check"

# architect merge discipline
ar=.claude/agents/architect.md
assert_has "$ar" "gh pr merge" "architect: normal merge path"
grep -qiE 'never .{0,3}--admin|--admin.{0,20}never' "$ar" && pass "$ar: forbids --admin" || fail "$ar: no explicit --admin prohibition"
assert_absent "$ar" 'gh pr merge[^\n]*--admin' "architect: never invokes an --admin merge"

# work skill
wk=.claude/skills/work/SKILL.md
assert_has "$wk" "soundcheck:security-review" "work: runs soundcheck"
assert_has "$wk" "HELD" "work: Critical/High hold rule"
assert_has "$wk" "--show-toplevel" "work: worktree hardening line"
assert_has "$wk" "general-purpose" "work: stale-persona fallback"
assert_has "$wk" "/deploy" "work: auto-advances to /deploy"

# plan-sprint: tracker fallbacks, ADRs, all panelists named
ps=.claude/skills/plan-sprint/SKILL.md
assert_has "$ps" "tracker.json" "plan-sprint: tracker config"
assert_has "$ps" "sprint-backlog.md" "plan-sprint: markdown-backlog fallback"
assert_has "$ps" "docs/adr/" "plan-sprint: ADR write"
assert_has "$ps" "/work" "plan-sprint: auto-advances to /work"
for p in product-manager product-designer devops-engineer data-engineer; do
  assert_has "$ps" "$p" "plan-sprint: names $p"
done

# deploy: human gate + tag immutability + tag-trigger detection
dp=.claude/skills/deploy/SKILL.md
grep -qiE 'explicit (human )?(confirmation|"go"|go)' "$dp" && pass "deploy: explicit human gate" || fail "deploy: no explicit human-gate wording"
assert_has "$dp" "on: push: tags" "deploy: tag-trigger detection"
grep -qiE 'never (move|re-push|force)' "$dp" && pass "deploy: tag-immutability rule" || fail "deploy: no tag-immutability wording"

# idea: brief + adr + handoff
id=.claude/skills/idea/SKILL.md
assert_has "$id" "idea-architect" "idea: dispatches idea-architect"
assert_has "$id" "docs/ideas/" "idea: writes brief to docs/ideas/"
assert_has "$id" "/plan-sprint" "idea: hands off to plan-sprint"

# panel agents share the same ticket-draft block
sect "Ticket-draft block (shared by panelists)"
BLOCK="TITLE: PROBLEM: USER VALUE: PROPOSAL: ACCEPTANCE CRITERIA: PRIORITY: CONSTRAINT NOTE: OPEN QUESTIONS:"
for p in $PANELISTS; do
  f=".claude/agents/$p.md"; ok=1
  for field in TITLE PROBLEM PROPOSAL PRIORITY; do grep -qF "$field:" "$f" || ok=0; done
  grep -qF "USER VALUE:" "$f" || ok=0
  grep -qF "ACCEPTANCE CRITERIA:" "$f" || ok=0
  grep -qF "CONSTRAINT NOTE:" "$f" || ok=0
  grep -qF "OPEN QUESTIONS:" "$f" || ok=0
  [ "$ok" = 1 ] && pass "$p emits the shared ticket-draft block" || fail "$p is missing ticket-draft fields"
done

# ── Optional: claude plugin validate (if the CLI is present) ─────────
sect "claude plugin validate"
if have claude; then
  if claude plugin validate . >/tmp/wf_validate.$$ 2>&1; then pass "claude plugin validate passed"; else fail "claude plugin validate failed:"; cat /tmp/wf_validate.$$; fi
  rm -f /tmp/wf_validate.$$
else
  printf '  \033[33mskip\033[0m claude CLI not on PATH (run locally before release)\n'
fi

# ── Result ───────────────────────────────────────────────────────────
printf '\n'
if [ "$fails" -eq 0 ]; then
  printf '\033[32mAll checks passed.\033[0m\n'; exit 0
else
  printf '\033[31m%d check(s) failed.\033[0m\n' "$fails"; exit 1
fi
