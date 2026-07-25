---
name: plan-sprint
description: Plan a product sprint with a repo-tailored agent panel (architect always; PM / designer / devops chosen from the repo), then cut the resulting tickets into this repo's issue tracker. Use when the user says "/plan-sprint", "plan the next sprint", "what should we build next", or wants product improvements scoped into tracker issues. Surveys the existing backlog first to avoid duplicates; creates tickets only after the user approves the plan.
argument-hint: "[theme / goal — or blank for open-ended.  optional: -- panel: pm,designer,devops]"
---

# /plan-sprint — repo-tailored panel → tracker tickets

Run a planning panel **tailored to this repo** and turn its output into tracker issues.
You (the main loop) own all tracker I/O, the human approval gate, and the ADR writes;
this plugin's agents (`architect`, `product-manager`,
`product-designer`, `devops-engineer`, `data-engineer`) do the
product / design / infra / data / feasibility thinking.

## Operating principle — autonomy

The panel agents work **without stopping to ask the user**. They resolve open questions
from the repo's docs, `CLAUDE.md`, ADRs, and the existing backlog, and produce a
*complete* plan with assumptions stated inline. The one deliberate human gate is step 4
(approve before tickets are cut) — a product call, not a mid-run question. If the agents
surface a real architectural unknown, the architect notes it needs a recorded decision;
after approval you write it up as an ADR (step 4), rather than blocking the plan.

## 1. Gather context (you, before fan-out)

- **Resolve the tracker** for this repo, in order: explicit arg → `.claude/tracker.json`
  (e.g. `{ "linearTeam": "...", "linearProject": "..." }`) or a tracker section in
  `CLAUDE.md` → infer from repo name via the Linear MCP → else GitHub Issues via `gh`
  (the repo already uses `gh` for PRs) → else **no tracker**: plan to emit the sprint as
  a markdown backlog file (`docs/sprint-backlog.md`) and say so. State your choice in one
  line and proceed (autonomy — don't ask).
- Read `CLAUDE.md`, the `README`, and any product/market/research/roadmap docs in the
  repo. `git log --oneline -30` for recent direction.
- **Classify the repo for panel selection (step 2):** skim the top-level tree and the
  manifests (`package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, Terraform/Helm/K8s
  manifests, `Dockerfile`, `.github/workflows/`). This tells you whether the repo is a
  user-facing product, a library/CLI, or infra/ops.
- **Detect the release mechanism:** look for a semver-tag-triggered workflow under
  `.github/workflows/` (`on: push: tags:`), existing `git tag`s, or a `CHANGELOG`. Note
  whether this repo releases via **tagged merge to main** (the mechanism `/deploy`
  expects) — you'll act on this in step 3.
- **Survey the backlog** so the panel doesn't re-propose existing work: list the open
  (non-completed) issues in the resolved tracker; capture titles + states.
- The theme is the argument; if blank, the theme is "what should we ship next to move
  the needle for our target customer / operator?"

## 2. Choose the panel, then fan out

**Select the panel from the repo — do NOT always spin up the full trio.** The main loop
picks; there is no classifier agent. Cap the panel at **3 agents** to keep synthesis
tractable, and always state the chosen panel in one line before fan-out
(e.g. "Panel: architect + devops-engineer — infra repo, no UI").

- **Always:** `architect` in PLAN mode — the feasibility gate for every repo.
- **Then pick 1–2 more** from the roster using the step-1 signals:
  - `product-manager` — the README describes a user-facing product/service;
    there's a customer, pricing, or competitive framing.
  - `product-designer` — a front-end exists (`ui/`, `app/`, `web/`, a JS
    framework in `package.json`, design tokens) or the work is user-visible surfaces.
  - `devops-engineer` — the repo is primarily infra / ops / tooling: Terraform,
    Helm/K8s manifests, Dockerfiles + registries, CI/CD-as-the-product, or a CLI/library
    with no UI.
  - `data-engineer` — the repo is primarily data / analytics / ML: ETL/ELT
    pipelines, a warehouse/lakehouse schema, dbt/Airflow/Spark/Dagster, feature/vector
    stores, or model training/serving code.
- **Edge rules:** infra-only repo → architect + devops (no PM, no designer). Data/ML repo
  → architect + data-engineer (+ PM if there's a user-facing product on top). Library/CLI
  → architect + PM (users are developers) unless purely internal, then architect + devops.
  If genuinely ambiguous, default to architect + PM + designer.
- **Override:** honor an explicit `-- panel: pm,designer,devops` argument verbatim
  (architect is always included on top).

Spawn the chosen agents **in parallel (single message)**, giving each the theme, the
product/infra context you gathered, and the open-backlog titles (to dedupe). The PM
returns 3–6 prioritized ticket drafts; the designer works UX/states/copy/a11y for the
promising items; the devops engineer returns reliability/toil/cost/release-engineering
tickets; the data engineer returns data-quality/pipeline/schema/ML-lifecycle tickets; the
architect returns a feasibility + sequencing assessment and a hard filter on anything the
repo's constraints make impossible. (All panelists emit the same ticket-draft format.)

## 3. Synthesize the plan (you)

Merge the panel's output into one sprint plan. For each surviving item produce a
ready-to-cut ticket: **Title** (imperative, specific); **Description** (Markdown: Problem
· Proposal · Acceptance criteria · Design notes · Technical notes & sequencing ·
Constraint note); **Priority**, rough **size** (S/M/L), suggested **labels**, and
**blocked-by** links between the new tickets where the architect found dependencies. Drop
anything the architect flagged as impossible under the repo's constraints and say so
explicitly (these become "market against" notes, not tickets).

**Release model:** sequence the sprint so it ends in a shippable, tagged release
(`/deploy` cuts a semver tag onto main). **If step 1 found the repo does NOT
release via tagged merge to main**, add ONE optional suggested ticket to the plan —
"Adopt tagged-merge-to-main releases (wires up `/deploy`)" — as a suggestion the
user can drop, never a silent assumption.

## 4. Approval gate → write ADRs → create tickets

Present the full plan to the user as a numbered list (title · priority · size ·
one-line summary) plus the build order, and call out the panel you used and any suggested
release-model ticket. **Do not create anything yet.**

After the user approves (they may edit/drop/reorder first):

1. **Record ADRs.** For any item the architect flagged as "needs a recorded decision"
   that the approved plan settles, write an ADR into `docs/adr/` (match the repo's
   existing format/numbering; create `docs/adr/0001-<slug>.md` if the repo keeps none
   yet). Large architectural decisions live in the repo, not just the tracker.
2. **Create the tickets** in the resolved tracker in dependency order, setting title,
   description, priority, labels, and blocked-by relations per the sequencing. File
   tickets with unmet dependencies in a backlog/blocked status and the unblocked ones in
   the ready status so `/work` can pick them up. (No tracker → write
   `docs/sprint-backlog.md` instead and say so.)

Report back the recorded ADRs, the created ticket ids, and the recommended pickup order.

## 5. Auto-advance to `/work`

Once the tickets exist (i.e. the user approved in step 4 and they've been created), the
cycle continues automatically: **invoke `/work`** to build the ready tickets — no manual
re-invoke needed. The human checkpoint for this phase was the step-4 approval; building the
approved tickets is the natural next step, and `/work` runs its own soundcheck + green-only
merge rails, then hands to `/deploy` (which keeps its release gate). Skip the handoff only
if the user asked to stop at ticket creation, or if step 4 produced no tickets (e.g. no
tracker → markdown backlog only).

## Guardrails
- Creating tracker tickets is outward-facing and bulk — always gate behind the explicit
  approval in step 4; never auto-create from raw panel output.
- Tailor the panel to the repo — an infra repo should not get a product designer, and a
  UI product should not be planned by devops alone.
- The agents must not invent work the repo's constraints can't support; catch any that
  slip through in synthesis.
- Keep the sprint small and shippable — prefer 3–5 sharp tickets over a backlog dump.
