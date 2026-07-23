# Testing

This plugin's risk splits cleanly in two, and so does its testing:

- **Structural drift** (renames, namespace typos, roster/model mismatches, a dependency
  that won't auto-resolve) — cheap and deterministic. Caught by `tests/validate.sh`, which
  runs in CI on every push.
- **Behavioral** (does the right panel spin up? do engineers stay in their worktree and not
  self-merge? does the tracker fall back correctly?) — expensive and nondeterministic. Not
  automated. Covered by the manual checklist below, run once before each release (~30 min).

No test framework, no LLM-in-CI, no eval harness — that would cost more than the plugin.

## Automated: `tests/validate.sh`

```
./tests/validate.sh          # bash + jq + grep; exits nonzero on any failure
```

Checks manifests, structure, frontmatter (incl. the per-role `model:` tiers and tight tool
allowlists), the bare-name reference convention, and the load-bearing content invariants
from `CLAUDE.md` (engineer worktree guard + no-self-merge, architect never `--admin`, the
soundcheck pass, tracker fallbacks, the shared ticket-draft block). It also runs
`claude plugin validate` when the CLI is on PATH. Run it before every commit; CI runs it too.

## Manual: pre-release behavioral checklist

Run from a session with the working copy loaded — either you're editing in this repo (its
`.claude/` auto-loads project-scoped) or `claude --plugin-dir ~/dev/workflow`.

Keep 3–4 **tiny throwaway fixture repos** outside this repo (e.g. `~/dev/wf-fixtures/`).
Each needs only a `README.md` describing the product plus the marker file(s) below —
nothing real.

| Fixture | Marker files | Expected `/plan-sprint` panel |
| --- | --- | --- |
| web app | `package.json`, an `app/` or `web/` dir | architect + product-manager + product-designer |
| infra | `main.tf` (or `helm/`, `k8s/`) | architect + devops-engineer (no designer) |
| data | `dbt_project.yml` (or `dags/`) | architect + data-engineer |
| library/CLI | a bare `Cargo.toml` or `go.mod`, no UI | architect + product-manager |

### 1. Panel selection (`/plan-sprint`) — highest value
In each fixture, run `/plan-sprint` and check **only** the one-line `Panel: …` announcement
against the table. **Stop at the approval gate — never approve**, so no tickets are cut.

### 2. Tracker fallback (`/plan-sprint`)
- In a fixture with no Linear config and no `gh` remote → it announces the
  `docs/sprint-backlog.md` fallback.
- In a `gh`-enabled fixture without Linear → it announces GitHub Issues via `gh`.
Stop at the gate.

### 3. `/idea`
Give `/idea` a one-line concept in any fixture. Confirm it: dispatches the `idea-architect`
(runs on **fable**), returns a brief with **2–3 compared approaches + a recommendation**,
and stops to discuss before writing anything. Don't approve the write-down.

### 4. `/work` rehearsal
On a real-but-safe repo (or a scratch fork) with one trivial ready ticket:
- the engineer's result shows a worktree path under `.claude/worktrees/`;
- it opened a PR and **stopped** (PR open, unmerged, no auto-merge enabled);
- `/soundcheck:security-review` visibly ran **from the main loop**;
- if you let the architect proceed, the merge is a normal `--squash` — grep the transcript
  for `--admin` and confirm it's **absent**.

### 5. `/deploy` dry gate
On a repo with unreleased commits, run `/deploy` and answer **no** at the gate. Confirm the
mechanism was detected and the version computed correctly, and that `git tag --list` is
unchanged. (The human gate *is* the dry-run — nothing irreversible fires before it.)

### 6. Dependency auto-install (once per release)
Into a clean profile: `/plugin marketplace add thejefflarson/workflow` → install `workflow`
→ confirm **soundcheck auto-installs** at the pinned `ref`.

## Not worth testing

Ticket/brief prose quality, ADR wording, the agents' judgment, the "intellectual lineage"
sections — these are steered by prompts, not verified by assertions. Don't snapshot skill
text (every intentional edit would break it); the targeted substring checks in
`validate.sh` cover only the load-bearing lines. Don't mock Linear/`gh`/git — the
integration surface is Claude Code itself, which can't be meaningfully mocked. Soundcheck
has its own tests; here we only assert the reference and the pin exist.
