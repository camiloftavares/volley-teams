---
description: Fetch a GitHub Issue's card details from the Project board, confirm it's scoped, and drive a TDD implementation plan through Plan Mode
argument-hint: [issue-number-or-url]
---

# Develop Card Workflow

Implements one backlog card end to end: fetch the spec from GitHub, confirm it's ready, plan the work as TDD, get your approval, then build it — writing progress back to the Issue itself instead of any local file.

> Tool names below (`mcp__github__*`, `mcp__figma__*`) are illustrative. Before relying on this file, confirm the exact tool names your GitHub MCP server exposes (Issues, and separately Projects v2 — Projects v2 is GraphQL-only and tool names vary more across server versions) and swap them in.

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

## Step 0 – Gather required input

**STOP and ask if not provided:** a GitHub Issue number or URL.

- Number format: `123` or `#123`
- URL format: `https://github.com/{owner}/{repo}/issues/123` — extract the issue number from the URL path; if `{owner}/{repo}` isn't the current repo, confirm before proceeding.

## Step 1 – Pull the card fresh from GitHub

**IMPORTANT:** Use GitHub MCP tools, not raw HTTP — auth and rate limiting are handled by the MCP server.

```
mcp__github__get_issue(owner="{OWNER}", repo="{REPO}", issue_number={N})
```

Also pull its Project (v2) field values (Status, Priority, Size, Type) and any existing comments (for resuming a card already in progress):

```
mcp__github__get_project_item_fields(owner="{OWNER}", project_number={PROJECT_NUMBER}, issue_number={N})
mcp__github__list_issue_comments(owner="{OWNER}", repo="{REPO}", issue_number={N})
```

**Gate check — IF Status is not `Ready` (and not already `In Progress`, i.e. a resume):** stop here. Report the current Status and say the card needs to go through `refine-card.md` first. Do not draft a plan against an ungroomed card.

Parse the body against the standard template:

- **Problem**
- **Acceptance Criteria** — reformat as a numbered checklist if not already one
- **Technical Notes**
- **Out of Scope**
- **Definition of Done**

**IF Acceptance Criteria is missing or empty, THEN stop and surface that** rather than inventing scope.

**IF this is a resume** (Status already `In Progress`, prior comments exist): read the progress comments to see which acceptance criteria are already checked off, and treat those as done — don't redo them.

Once the card passes the gate, flip Status to `In Progress` immediately, before any code changes:

```
mcp__github__update_project_item_field(owner="{OWNER}", project_number={PROJECT_NUMBER}, issue_number={N}, field="Status", value="In Progress")
```

## Step 1.5 – Fetch Figma design context (only if a link is present)

**Gate check — IF Technical Notes contains a leftover `Design: pending` flag** (set by `plan-card.md`, never resolved): stop, same as a missing Acceptance Criteria. Say the card needs a `design-card.md` pass first — don't implement a UI-facing card against a guess.

**IF** the Issue body contains a Figma link (`https://www.figma.com/design/{fileKey}/{fileName}?node-id={nodeId}`), **AND** a Figma MCP tool is available in this session, **THEN** fetch design context. **Otherwise skip this step entirely** — no design link, or no Figma connector, both just mean proceed to Step 2 with no design context.

Parse the URL for `fileKey` and `nodeId` (hyphens to colons: `858-381716` → `858:381716`).

**Get metadata first**, since a linked frame is often a whole screen when only one section is relevant:

```
mcp__figma__get_metadata(fileKey="{FILE_KEY}", nodeId="{NODE_ID}")
```

From the metadata, identify the child node(s) that actually match the Acceptance Criteria (by name — skip generic containers, headers, footers). Fetch only those:

```
mcp__figma__get_design_context(fileKey="{FILE_KEY}", nodeId="{RELEVANT_CHILD_NODE_ID}")
```

Extract: layout/structure, states (hover/active/disabled/loading/error), responsive variants, design tokens, assets to pull in. **IF** the link is inaccessible, note that and proceed on Acceptance Criteria alone.

## Step 2 – Confirm base branch

This repo branches everything off the default branch — no epic/parent branches to check.

```bash
git fetch origin --prune
git symbolic-ref refs/remotes/origin/HEAD
```

Base branch = the default branch the command above resolves to (typically `main`). Planned feature branch name: `{N}-short-description` (e.g. `142-cart-loyalty-offers`).

## Step 3 – Review the Issue and the codebase, propose a strict-TDD implementation plan

Translate each acceptance criterion into concrete tasks: validations, flows, data contracts, edge cases.

Inspect the repo itself to find the layers this change touches — don't assume a stack; look at how the existing code is organized (UI/views, state/business logic, models, API/service calls, routing, config/flags) and search for the modules each acceptance criterion is most likely to touch:

```
Grep(pattern="{RELEVANT_TERM}", path="{REPO_ROOT}")
```

For **each acceptance criterion**, plan it as strict TDD:

1. Write a failing test that encodes that criterion
2. Implement the minimum change to make it pass
3. Refactor

Also note:
- New assets needed (copy, icons, translations)
- Risks and edge cases — open questions for you, not silently resolved

**STOP and present the plan** — do this through Plan Mode: lay out the plan referencing each acceptance criterion by number, and wait for approval before touching any files.

## Step 4 – Deliverable summary (part of the Plan Mode proposal)

1. **Issue** — number and title
2. **Key findings** — notable constraints, dependencies, anything Out of Scope that's adjacent to the work
3. **Base branch** — confirmed default branch and planned feature branch name
4. **TDD plan** — task breakdown per acceptance criterion, file targets, test-first sequence
5. **Open questions** — anything needing your input before or during implementation

**WAIT for approval.**

## Step 5 – After approval: branch and implement

```bash
git checkout -b {N}-short-description origin/{BASE_BRANCH}
```

Work through the acceptance criteria in order, strict TDD per criterion. After each criterion is checked off, post a short progress comment on the Issue (not a local file) so the board reflects reality mid-session:

```
mcp__github__add_issue_comment(owner="{OWNER}", repo="{REPO}", issue_number={N}, body="- [x] {criterion} — done in {commit-or-file}")
```

This is also what makes the card resumable: if this workflow is re-run on the same issue number later, Step 1 re-fetches these comments and picks up where it left off, rather than reopening a saved file.

## Step 6 – Close out

Once every acceptance criterion is checked off:

1. Run this repo's normal test/lint gates.
2. Commit.
3. Open a PR that references the Issue:

```
mcp__github__create_pull_request(owner="{OWNER}", repo="{REPO}", head="{N}-short-description", base="{BASE_BRANCH}", title="...", body="Closes #{N}\n\n...")
```

4. Flip Status to `In Review`:

```
mcp__github__update_project_item_field(owner="{OWNER}", project_number={PROJECT_NUMBER}, issue_number={N}, field="Status", value="In Review")
```

5. Leave a closing comment on the Issue summarizing what was done against each acceptance criterion.
