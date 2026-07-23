---
name: idea
description: Turn a rough idea into a decision-complete design brief before it becomes a sprint. Spins up a deep planning architect (on fable) that researches best practices, compares real approaches, challenges the idea's assumptions, and recommends the simplest thing that works — then hands the brief off to /plan-sprint for ticketing. Use when the user says "/idea", "I have an idea", "think this through", "help me scope this out", or wants a solid plan before committing to build.
argument-hint: "[your idea / rough concept]"
---

# /idea — a rough idea → a solid, decision-complete brief

This is the front of the loop. Before work gets scoped into a sprint, one idea gets
*thought all the way through*: researched, stress-tested, and reduced to the simplest
shape that actually solves the problem. You (the main loop) frame the idea and own the
write-down; the `idea-architect` agent (deep planning, on fable) does the thinking. The
output is a brief solid enough that `/plan-sprint` can scope it without re-deciding
anything load-bearing.

## Operating principle — collaborative, not autonomous

Unlike `/work`, this skill is a **dialogue**. It's the user's idea, and the goal is a plan
they trust. So: think hard, present the brief, and *iterate with the user* before writing
anything down. The one thing the architect must not do is hedge — it makes the real design
decisions and defends them; the user is refining a concrete plan, not answering a
questionnaire.

## 1. Frame the idea + gather context (you, before the architect)

- Capture the idea from the argument. If it's a one-liner, restate what you understand it
  to mean in a sentence and proceed (don't interrogate the user — that's the architect's
  job to resolve from the repo).
- Read `CLAUDE.md`, the `README`, and any relevant product/architecture docs and
  `docs/adr/` so the brief is grounded in *this* repo's reality, constraints, and
  direction. `git log --oneline -20` for recent context.
- Note the release model (this framework assumes a **tagged merge to `main`**) so the
  plan lands shippable.

## 2. Spin up the deep planning architect

Dispatch one **`idea-architect`** agent with the framed idea + the context you gathered.
It researches best practices and prior art (WebSearch), lays out **2–3 genuinely different
approaches**, challenges the idea's assumptions, recommends the simplest approach that
works, resolves the load-bearing decisions, and returns a decision-complete brief. It
writes no files and cuts no tickets — it returns the brief to you.

(If the `idea-architect` agent isn't available — e.g. running outside the plugin — fall
back to a general planning agent with the same brief and the same "research, compare
approaches, challenge assumptions, be decision-complete, bias to simplicity" instructions.)

## 3. Present the brief and iterate (the human loop)

Show the user the brief — lead with the **recommended approach and why**, the **key
decisions**, and anything the architect **pushed back on** (assumptions that don't hold, a
simpler thing to build instead). Then work with them: if they disagree or add constraints,
re-run or refine with the architect until the plan is one they'd stake the sprint on. This
back-and-forth *is* the value of the skill; don't rush to write-down.

## 4. Write it down + hand off to `/plan-sprint`

Once the user is happy:
- **Save the brief** to `docs/ideas/<slug>.md` (create `docs/ideas/` if absent) so it's
  durable and `/plan-sprint` can read it as context.
- **Record ADRs.** Any load-bearing decision the brief settles gets an ADR in `docs/adr/`
  (match the repo's existing format/numbering; create `docs/adr/0001-<slug>.md` if the
  repo keeps none yet). Big decisions live in the repo, not just a brief.
- **Offer the handoff:** ask whether to run `/plan-sprint` now with the brief's
  `HANDOFF TO PLAN-SPRINT` framing as the theme. If yes, invoke it; if not, tell the user
  the brief is saved and `/plan-sprint <theme>` will pick it up later.

## Guardrails
- `/idea` produces a **brief and ADRs — no tickets, no code.** Ticketing is `/plan-sprint`;
  building is `/work`. Keep the stages separate.
- Bias to **simplicity**: the best outcome is often a smaller build than the idea proposed,
  or a well-argued "don't build this." Surface that plainly rather than dressing up a
  faithful plan for the wrong thing.
- Don't skip the human loop — this is the one skill in the set that's meant to be
  collaborative. Write the brief down only once the user is satisfied.
