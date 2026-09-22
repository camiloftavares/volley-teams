---
description: Turn a rough idea or set of notes into a fully-specified GitHub Issue in Backlog, asking only for what's missing, so refine-card.md's later pass is a quick promotion rather than a re-interrogation
argument-hint: [rough description, or leave blank and answer the prompt]
---

# Plan Card Workflow

Creates one new backlog item and lands it in `Backlog` — same as any other card, `refine-card.md` is still the one thing that promotes it to `Ready`. What's different is how little `refine-card.md` should have to do when it gets there: this command front-loads every question it would otherwise have to ask, so its pass on a plan-card.md-created item should be a quick check-and-promote, not a re-interrogation.

> Tool names below (`mcp__github__*`) are illustrative — confirm the exact tool names your GitHub MCP server exposes for Issues and for Projects v2 (item creation + field writes; Projects v2 is GraphQL-only) and swap them in. Same template and field schema as `refine-card.md` / `development-card.md` — see the plan doc.

## Resolve owner, repo, and Project (every run)

Do this first — every step below assumes `{OWNER}`, `{REPO}` and `{PROJECT_NUMBER}` are already known, not hand-typed into this file.

1. **Owner/repo** — derive from git, don't hardcode it:

```bash
git remote get-url origin
```

Parse `{OWNER}/{REPO}` out of the result (handles both `https://github.com/{owner}/{repo}.git` and `git@github.com:{owner}/{repo}.git`).

2. **Project number** — check for `.claude/backlog-config.json` at the repo root:

```json
{"owner": "{OWNER}", "repo": "{REPO}", "project_number": {PROJECT_NUMBER}}
```

**IF** it exists, use its `project_number` and move on.

**IF** it doesn't exist (first run of any of these four commands in this repo): look up Projects linked to this repo/owner via GitHub MCP. **IF** exactly one is linked, confirm with the user ("Use Project #{N} — '{title}' — for this?") rather than assuming silently. **IF** none or more than one, ask directly for the Project number or URL.

Either way, once resolved, write `.claude/backlog-config.json` with the values above — a one-time cost. Every later run of any of the four commands reads it off disk, so this never gets asked again unless the file is deleted or the repo switches Projects.

## Step 0 – Take whatever you're given, as-is

Accept `$ARGUMENTS` as freeform input: a rough idea, bullet notes, a pasted paragraph, a link. No required shape — shaping it is this command's job, not a precondition for running it.

**IF** `$ARGUMENTS` is empty, **THEN** ask: "What are we building?" and take the raw answer as the starting material.

## Step 1 – Map what's already there onto the spec template

From the input, attempt to draft:

- **Problem** — who this is for, what's wrong or missing
- **Acceptance Criteria** — as concrete, testable outcomes (not yet finalized — draft candidates even from a vague ask)
- **Technical Notes** — anything the user already mentioned (constraints, related code, prior art)
- **Out of Scope** — only if something adjacent was explicitly excluded
- **Type** — Feature / Bug / Chore / Spike, if inferable

**Don't invent specifics that weren't said.** Anything genuinely unstated is a gap for Step 2, not a guess to paper over.

Optionally, ground the draft in the actual codebase before asking questions — a quick search surfaces better questions than asking blind:

```
Grep(pattern="{RELEVANT_TERM}", path="{REPO_ROOT}")
```

Use hits to sharpen Technical Notes, flag likely affected files, and inform a Size estimate.

## Step 1.5 – Check for a Figma design

**IF** what you were given includes a Figma link, fetch it for context — same as `development-card.md`'s own design step — so the draft below is grounded in the real screens, not a guess:

```
mcp__figma__get_metadata(fileKey="{FILE_KEY}", nodeId="{NODE_ID}")
mcp__figma__get_design_context(fileKey="{FILE_KEY}", nodeId="{RELEVANT_CHILD_NODE_ID}")
```

**IF no Figma link was given and this card involves anything visible or UI-facing**, don't generate one here — that's a longer, visual back-and-forth that belongs in `design-card.md`, not this fast Q&A loop. Just ask whether the card needs a design. If yes, note it in Technical Notes: `Design: pending - run design-card.md on this issue`, so `refine-card.md` and `development-card.md` both know to expect one later. If the card is backend/API/chore work with nothing to design, skip this step entirely — don't ask.

## Step 2 – Ask only what's missing

Check the draft against what `development-card.md` requires to run unattended:

- Is the **Problem** statement actually clear, or still vague?
- Are the **Acceptance Criteria** testable and observable — not "improve X" but "X does Y when Z"? If none exist yet, propose a draft set from the Problem statement and confirm/adjust with the user rather than asking open-ended.
- **Type** — if not inferable, ask.
- **Out of Scope** — ask explicitly only if there's a real adjacent-scope risk (e.g. "should this also cover Y, or is that a separate card?"). Skip this question if scope is already unambiguous.
- **Priority** and **Size** — ask for a gut call, or propose one from the Technical Notes findings and confirm.
- **Design** — if the card is UI-facing, is a Figma link already attached, or is it flagged `Design: pending` from Step 1.5? Don't let a UI-facing card go to Backlog with neither.

Ask in one pass, covering only the actual gaps — never re-ask anything already given in Step 0. Prefer short, answerable questions (a pick from a few options for Type/Priority/Size; free text only for the Problem/AC gaps that need real explanation).

**STOP here if the answers leave any Acceptance Criteria still vague** — loop back with a sharper follow-up rather than accepting a fuzzy one. This is the one gate standing between "fully specified" and "development-card.md has to guess."

## Step 3 – Draft the full Issue and create it

Assemble the complete body, same template `refine-card.md` and `development-card.md` expect:

```markdown
## Problem
...

## Acceptance Criteria
- [ ] ...
- [ ] ...

## Technical Notes
...

## Out of Scope
...

## Definition of Done
...
```

Also decide: a title, and the Project field values (**Type**, **Priority**, **Size**, **Status = Backlog**) — proposing your own best call for Priority/Size when the user hasn't given one (Step 2 already asked for anything that was a real gap; don't re-ask here).

**No approval gate by default** — go straight to Step 4 and create it. Step 2's stop-if-AC-is-vague check is what keeps a bad draft from reaching this point, so once you're here the draft is good enough to write. Show the full draft (title, body, fields) in the same message that reports the created Issue, so the user sees exactly what got written — not before, as a thing to approve.

Exception: if the user has asked to review before creation (in this run, or as a standing preference), honor that instead — stop and show the draft, same as before.

## Step 4 – Create it

```
mcp__github__create_issue(owner="{OWNER}", repo="{REPO}", title="{TITLE}", body="{DRAFTED_BODY}")
```

Add it to the Project and set its fields:

```
mcp__github__add_project_item(owner="{OWNER}", project_number="{PROJECT_NUMBER}", content_id="{ISSUE_NODE_ID}")
mcp__github__update_project_item_field(owner="{OWNER}", project_number="{PROJECT_NUMBER}", issue_number={N}, field="Status", value="Backlog")
mcp__github__update_project_item_field(owner="{OWNER}", project_number="{PROJECT_NUMBER}", issue_number={N}, field="Type", value="{TYPE}")
mcp__github__update_project_item_field(owner="{OWNER}", project_number="{PROJECT_NUMBER}", issue_number={N}, field="Priority", value="{PRIORITY}")
mcp__github__update_project_item_field(owner="{OWNER}", project_number="{PROJECT_NUMBER}", issue_number={N}, field="Size", value="{SIZE}")
```

Report back: issue number, link, and the fields set on it. Mention that it's ready for a `refine-card.md` pass whenever you want it promoted to `Ready` — since everything's already filled in, that pass should just confirm and flip the status, not redo the work.

**IF this card was flagged `Design: pending`:** ask whether to hand off to `design-card.md` right now, on this issue number, while the context is fresh — or leave it for later. Either answer is fine; this is a courtesy offer, not a requirement to chain commands.

## Step 5 – Offer to do another

Planning sessions usually produce more than one card. After confirming the created Issue, ask if there's another item to plan — if so, go back to Step 0 with a clean slate rather than carrying over context from the last card.
