---
name: deploy
description: Cut a release / ship merged work to prod for whatever repo you're in. Assumes the framework default — a tagged merge to main — but detects the repo's actual mechanism, computes the next version from conventional commits, verifies the branch + pipeline are healthy, then (after explicit human confirmation) triggers the release, watches it, and confirms the roll. Runs at the end of /work; also use for "/deploy", "cut a release", "ship it", "push to prod".
argument-hint: "[explicit version e.g. v1.4.0  |  bump e.g. patch|minor|major  |  blank = auto from conventional commits]"
---

# /deploy — cut a release and ship merged work

Merging to the default branch does not necessarily deploy anything. This framework's
**default assumption is a tagged merge to main** — a semver tag pushed to the default
branch that triggers release automation. This skill ships what's merged, verifying that
assumption and honoring the repo's actual mechanism if it differs. Everything up to the
release trigger is autonomous preflight; the trigger itself (a pushed tag, a prod deploy)
is the one irreversible, outward-facing step, so it is gated on an explicit human "go".

## Operating principle — one human gate

Discovery, preflight, and version selection are done autonomously. The actual
release trigger is the point of no return — published tags are immutable and a
prod deploy reaches real users — so gate it on an explicit human confirmation,
unless the user gave a standing "just ship / auto-deploy" instruction this session.

## 1. Confirm how THIS repo releases (default: tagged merge to main)

The expected mechanism is a **tagged merge to main** — a semver tag on the default branch
triggering release automation. Confirm it first, then fall back to detection:
- release automation under `.github/workflows/` — a workflow with `on: push: tags:`
  is the tagged-merge-to-main signal; also a `release`/`publish`/`deploy` job;
- a release/deploy section in `CLAUDE.md` / `AGENTS.md` / `README` / `CONTRIBUTING`;
- version history: `git tag`, `gh release list`, a `CHANGELOG`;
- a non-tag deploy entry point: `Makefile` target, `scripts/deploy*`, `package.json`
  scripts, a `fly.toml`/`vercel.json`/`Dockerfile`+registry, etc.

State the mechanism you found in one line. If the repo ships some other way, **ship it
that way** — the default is a preference, not a straitjacket. **If the repo has NO release
mechanism at all**, propose adopting tagged-merge-to-main (tag → CI release job), note it
for `/plan-sprint` to formalize, and **stop rather than guess** — deploying the
wrong way is expensive and hard to undo.

## 2. Preflight

- On the release branch (usually the default), working tree clean, synced with the
  remote (`git fetch`; `git status`).
- Last release: `git describe --tags --abbrev=0` and/or `gh release list`.
- **What would ship:** `git log <last>..HEAD --oneline`. If empty, **nothing to
  release — stop and say so.**
- **Is the branch green?** Check the head commit's required checks (`gh pr checks`
  on the last merge, or `gh run list`). Don't ship a red branch.
- **Is the release pipeline itself healthy?** If the last release run failed, read
  *why* (`gh run view <id> --log-failed`) and surface it. **Don't cut a new release
  onto a known-broken pipeline** — fix it (land the fix on the release branch
  first, since the pipeline runs from the released commit), or hand it back.

## 3. Choose the version (semver from conventional commits)

Scan commit subjects since the last release and compute the bump (state it + why):
`feat` → **minor**; `fix`/`perf`/`refactor`/`chore`/`docs`/`ci`/`build` → **patch**;
a `!` or `BREAKING CHANGE` → **major** (pre-1.0, treat breaking as **minor**). An
explicit argument (a full version, or `patch|minor|major`) overrides. If the
computed version already exists, bump to the next free one — never reuse or move an
existing version.

## 4. Human gate — THEN release

Present concisely: the **computed version**, the **commits grouped by type**
(feat / fix / other), and the **release mechanism + target**. Then **ask for
explicit confirmation to trigger the release.** Proceed only on an unambiguous yes
(or a standing auto-deploy instruction). This is the point of no return.

## 5. Trigger + monitor

Release the repo's way — for the tagged-merge-to-main default, `git tag vX.Y.Z && git push
origin vX.Y.Z`; otherwise the repo's deploy script/command. (Push the tag only — never
force-push, never move an existing tag.) Watch it to completion (`gh run watch <id>`, or
the script's output).
- **On failure:** report the failing job/step. If the mechanism is
  immutable-tag-based, do **NOT** retry the same version — fix forward and cut the
  **next** version.
- **On success:** report the release URL / published artifacts. If the repo's
  changelog is auto-generated from PR titles, the release notes are the changelog.

## 6. Confirm the roll (best-effort)

If the repo auto-deploys (a GitOps controller, a deploy job, a PaaS) and you have
access, confirm the target advanced to the new version — **release/version/rollout
state only, never product or user data.** Otherwise say the release built and note
what's responsible for rolling it out.

## Guardrails

- **The release trigger is outward-facing and irreversible** — always gate it on
  explicit human confirmation (§4). Never auto-trigger without a clear go or a
  standing auto-deploy instruction.
- **Never move, re-push, or force an existing version tag** (published tags are
  immutable). A broken release is fixed by a **new** version, never a retag.
- **Never force a red pipeline through** — fix it and land the fix on the release
  branch *first* (the pipeline runs from the released commit).
- **Don't modify a separate prod/infra repo** — flag any change needed there
  (GitOps config, infra, secrets) as a human follow-up; this skill releases the
  current repo only.
- Read only release/rollout state — never product/user data.
