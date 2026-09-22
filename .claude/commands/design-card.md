---
description: Check a card for an existing Figma design; if there isn't one, generate candidate screens from its Acceptance Criteria, review them with you, then link the result back to the Issue
argument-hint: [issue-number-or-url]
---

# Design Card Workflow

Separate from `plan-card.md` on purpose: writing a spec is a fast, conversational loop; designing screens is a visual one you need to actually look at and iterate on. Keeping them apart means planning a card never has to stall waiting on design, and a card with no UI at all (an API change, a chore) never goes through this at all.

> Tool names below (`mcp__figma__*`, `mcp__github__*`) are illustrative — confirm what your Figma MCP server and GitHub MCP server actually expose and swap them in. If your Claude Code setup has the Figma skills (`figma-use`, `figma-create-new-file`, `figma-generate-design`, `figma-design-to-code`) available, load the relevant one before the matching tool call below — each of those is a mandatory prerequisite for its tool in that skill set, not optional context.

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

## Step 0 – Resolve the target

**IF** an issue number or URL is given as `$ARGUMENTS`, use it directly. **ELSE** ask which card to design for.

## Step 1 – Fetch the card

```
mcp__github__get_issue(owner="{OWNER}", repo="{REPO}", issue_number={N})
```

Pull Problem, Acceptance Criteria, and Technical Notes — this is what the screens need to satisfy. If Acceptance Criteria are missing or too vague to design against, stop and say the card needs a `refine-card.md` or `plan-card.md` pass first; don't design against a guess.

## Step 2 – Check for an existing Figma link

Look in Technical Notes (and the rest of the body) for a `figma.com/design/...` link.

**IF found:** fetch it for context rather than assuming it's still accurate:

```
mcp__figma__get_metadata(fileKey="{FILE_KEY}", nodeId="{NODE_ID}")
mcp__figma__get_design_context(fileKey="{FILE_KEY}", nodeId="{NODE_ID}")
```

Show a short summary and ask whether it already covers the current Acceptance Criteria, or needs updating. If it needs updating, treat Step 4 below as edits to this file/node rather than a new one. If it's already good, skip to Step 6 — nothing to write back, it's already linked.

**IF not found:** continue to Step 3.

## Step 3 – Pick a destination file

Ask whether the new screens belong in an existing Figma file (ask for it, or check recent files if your Figma MCP exposes that) or need a new one.

**IF a new file:** load the `figma-create-new-file` skill first, then:

```
mcp__figma__create_new_file(editorType="design", fileName="{CARD_TITLE}")
```

## Step 4 – Generate the screens

Load the `figma-generate-design` skill first — it discovers existing design-system components, variables and styles (from Code Connect files, existing screens, or a library search) before building anything, so the output uses real tokens and components instead of hardcoded one-off values.

Translate the Acceptance Criteria into screens/states: each criterion that implies something visible (a new view, an empty/loading/error state, a modal, a changed layout) becomes a section to build. Assemble incrementally, section by section:

```
mcp__figma__use_figma(...)
```

(load the `figma-use` skill first — required before any `use_figma` call, per that skill's own instructions.)

## Step 5 – Review with the user

**STOP here and show what was built** — a screenshot or the file link — before treating it as done. This is the one step in the whole card lifecycle that's genuinely visual; don't try to collapse it into a yes/no text confirmation like the other commands' approval gates.

Loop on feedback: adjust via `use_figma`, re-show, repeat until approved. Don't guess at "close enough" — ask.

## Step 6 – Link it back to the card

On approval (or if Step 2 found an already-good existing design), write the Figma link into the Issue's Technical Notes — merge it in, don't replace what's already there:

```
mcp__github__update_issue(owner="{OWNER}", repo="{REPO}", issue_number={N}, body="{UPDATED_BODY_WITH_FIGMA_LINK}")
```

This is what makes it automatic downstream: `refine-card.md`'s completeness check and `development-card.md`'s Step 1.5 both look for a Figma link in Technical Notes, so once it's here neither of them has to ask again.

## Step 7 – Confirm back

Report: issue number, the Figma file/frame link, and a one-line summary of what was built or updated.
