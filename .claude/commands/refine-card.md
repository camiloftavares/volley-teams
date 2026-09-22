---
description: Promote a Backlog item to Ready — a quick confirm-and-promote when it's already complete (e.g. from plan-card.md), or a full grooming pass when it isn't
argument-hint: [issue-number-or-url]
---

# Refine Card Workflow

The single gate before `development-card.md` will touch a card. Every Backlog item goes through this, but not every item needs the same amount of work here — a card `plan-card.md` already fully specified should be a quick check and a status flip; a card typed up by hand or dropped in from a triage meeting needs the real grooming pass.

> Tool names below (`mcp__github__*`) are illustrative — confirm the exact tool names your GitHub MCP server exposes for Issues and Projects v2 field reads/writes, and swap them in. Same template and field schema as `plan-card.md` / `development-card.md` — see the plan doc.

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

**IF** an issue number or URL is given as `$ARGUMENTS`, use it directly.

**ELSE** list the Project's Backlog-status items and ask which one to groom:

```
mcp__github__list_issues(owner="{OWNER}", repo="{REPO}", state="open")
mcp__github__get_project_item_fields(owner="{OWNER}", project_number="{PROJECT_NUMBER}", issue_number={N})
```

filtered down to Status = Backlog.

## Step 1 – Fetch the card fresh

```
mcp__github__get_issue(owner="{OWNER}", repo="{REPO}", issue_number={N})
mcp__github__get_project_item_fields(owner="{OWNER}", project_number="{PROJECT_NUMBER}", issue_number={N})
```

**Gate check — IF Status is not `Backlog`:** stop and say so (name the current Status). There's nothing for this command to do — `Ready` and beyond has already been through this gate, and anything earlier isn't this command's job.

## Step 2 – Assess completeness against the template

Check the body and fields for:

- **Problem** — is it clear who this is for and what's wrong or missing?
- **Acceptance Criteria** — concrete and testable ("X does Y when Z"), not vague ("improve X")?
- **Technical Notes** — present, or reasonably absent for a small/obvious card?
- **Out of Scope** — addressed if there's a real adjacent-scope risk?
- **Definition of Done** — present?
- **Type / Priority / Size** — set on the Project item?
- **Design** — if the card is UI-facing: a real Figma link in Technical Notes counts as complete; a leftover `Design: pending` flag does not — that's an unresolved gap, not a done item.

This assessment decides which path below to take. Most `plan-card.md`-created cards land in the fast path; most hand-created or triage-sourced cards land in the full-groom path — but judge the actual card in front of you, not its likely origin.

## Step 3a – Fast path: card is already complete

Show a short summary (Problem in one line, the Acceptance Criteria list, current Type/Priority/Size) and ask a single confirmation: does this look right to promote to Ready? Don't re-ask questions the card already answers.

**IF confirmed:** skip to Step 5 with no body changes needed.

**IF the user spots a gap during that quick look — including a lingering `Design: pending` flag:** drop into Step 3b for that gap only — don't restart a full interrogation over one missing detail. For a pending design specifically, the fix usually isn't a question to answer here at all: offer to run `design-card.md` on this issue now, or confirm the card genuinely doesn't need one after all (and drop the flag if so).

## Step 3b – Full-groom path: card has real gaps

Fill gaps by asking the user directly, in conversation — this path is interactive by design, not autonomous:

- Missing or vague Problem → ask what's wrong and for whom.
- Missing or vague Acceptance Criteria → propose a draft set from the Problem statement and confirm/adjust, rather than asking fully open-ended.
- Missing Type / Priority / Size → ask for each, or propose a value (grep the repo for relevant modules first if that helps size it) and confirm.
- Out of Scope → ask only if there's a real adjacent-scope risk worth writing down.

Draft the completed sections and confirm the full result with the user before writing anything back.

## Step 4 – Write back and set fields

**IF Step 3b changed anything**, update the Issue body (merge into what's already good — don't blow away content that was already fine):

```
mcp__github__update_issue(owner="{OWNER}", repo="{REPO}", issue_number={N}, body="{UPDATED_BODY}")
```

Set or confirm the Project fields:

```
mcp__github__update_project_item_field(owner="{OWNER}", project_number="{PROJECT_NUMBER}", issue_number={N}, field="Type", value="{TYPE}")
mcp__github__update_project_item_field(owner="{OWNER}", project_number="{PROJECT_NUMBER}", issue_number={N}, field="Priority", value="{PRIORITY}")
mcp__github__update_project_item_field(owner="{OWNER}", project_number="{PROJECT_NUMBER}", issue_number={N}, field="Size", value="{SIZE}")
```

## Step 5 – Promote to Ready

```
mcp__github__update_project_item_field(owner="{OWNER}", project_number="{PROJECT_NUMBER}", issue_number={N}, field="Status", value="Ready")
```

## Step 6 – Confirm back

Report: issue number, title, which path was taken (quick promote vs. full groom), and the fields set. This is the point where `development-card.md` can pick the card up with zero further questions — say that explicitly so it's clear the card is actually ready, not just marked ready.
