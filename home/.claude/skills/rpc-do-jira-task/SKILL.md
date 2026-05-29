---
name: rpc-do-jira-task
description: Implement a JIRA-driven engineering task inside an already-bootstrapped environment — explore → plan → test (TDD) → implement → commit/PR. Assumes the workspace folder, tmux session, branch and worktrees already exist (created by rpc-handoff-jira-task); if they don't, it points you there first. Never commits or pushes unless explicitly asked.
---

# rpc-do-jira-task

Take a JIRA ticket whose working environment is already set up and walk through
the implementation flow. **Environment setup (folder, tmux session, Claude
session, branch, worktrees, VS Code workspace) is owned by
`rpc-handoff-jira-task`** — this skill does the actual work.

## Invocation

The skill is invoked as `/rpc-do-jira-task [JIRA-ID]`.

- If `JIRA-ID` is provided → fetch it via the Atlassian MCP and proceed.
- If `JIRA-ID` is missing → ask for it (or create the ticket via
  `mcp__atlassian__createJiraIssue` if it doesn't exist yet), then proceed.

Do not proceed without a real JIRA ID.

## Canonical task slug

This skill reuses the canonical `TASK_SLUG` and the paths/branch derived from
it. **The authoritative definition lives in `rpc-handoff-jira-task`** (the
"Canonical task slug" table); do not redefine it here. As a reminder:

```
TASK_SLUG = <JIRA-ID>-<short-desc>   →  folder $HOME/w/<TASK_SLUG>,
worktree $HOME/dd/<repo>-<TASK_SLUG>, branch raul.perezclavero/<TASK_SLUG>
```

Resolve `TASK_SLUG` from the existing workspace folder:
`ls -d $HOME/w/*<JIRA-ID>* 2>/dev/null` → its basename is the slug. If there is more than one match, ask the user to choose. If there are no matches, stop and run
`/rpc-handoff-jira-task <JIRA-ID>` first to bootstrap the environment, then come back here.

## 0. Verify the environment exists

Before implementing, confirm the assets are in place:

- Workspace folder `$HOME/w/<TASK_SLUG>` exists.
- A worktree `$HOME/dd/<repo>-<TASK_SLUG>` exists on branch
  `raul.perezclavero/<TASK_SLUG>`.

If any of these are **missing**, stop and run **`/rpc-handoff-jira-task
<JIRA-ID>`** first to bootstrap the environment, then come back. Do not
re-create assets ad hoc here.

## Step-by-step flow

### 1. Resolve the JIRA ticket

- Fetch the ticket via `mcp__atlassian__getJiraIssue`.
- Print a concise summary: title, status, assignee, priority, components, and
  the rendered description.
- Ask the user: **"Anything else I should know before we start?"** Wait for an
  answer before moving on.

### 2. Explore

- Read the relevant code in the worktree(s); share a short map of what's
  relevant to the ticket.

### 3. Plan

- Propose a plan and get **explicit user agreement** before writing any code.

### 4. Test (TDD)

- Write failing tests first whenever feasible. If TDD doesn't fit a step, say so and why.

### 5. Implement

- Make the tests pass.

### 6. Commit / PR

- Only when the user explicitly asks. See Hard rules below.

## Hard rules

- **No commits, no pushes, no PRs unless the user explicitly asks.** Even after
  green tests, stop and wait.
- **Commit message format** (when asked): single line `<JIRA-ID>: <short
  description>`. No co-author trailers. No multi-line body. No file lists.
- **Branch naming** is fixed: `raul.perezclavero/<TASK_SLUG>`. Never invent
  variations.
- **Go**: after editing `.go` files, run `go fmt` on the changed files. In
  Bazel-using repos (e.g. `dd-source`):
  - Use Bazel tooling instead of raw `go` (use the `running-bzl` agent for
    Bazel commands).
  - Use the `:all` target wildcard for tests, not `...`.
  - After import changes: `bzl run //:gazelle -- update <dir>`.
- **Diffs**: when running inside a VSCode/Cursor terminal, prefer `code --diff`
  / `cursor --diff` over plain text dumps.

## Integrating to staging

When the user asks to integrate changes to staging:

1. Identify the affected service(s):
   - First, look at the PR's labels. PRs are often auto-tagged with
     `changes:<service>`-style labels by CI. Read them with:
     ```
     gh pr view <pr> --json labels
     ```
   - If labels are missing or ambiguous, propose the service(s) you'd guess from
     the diff and **ask the user** to confirm or correct.
2. Post a PR comment per service:
   ```
   gh pr comment <pr> --body "/integrate -dfs <service-name>"
   ```
3. A single PR may span multiple services — post one comment per service unless
   the user says otherwise.

## Engaging the user

These are explicit interaction points; don't skip them:

- After fetching the ticket → "Anything else I should know?"
- Before starting implementation → confirm the plan.
- Before any commit, push, or PR → ask explicitly.
- Whenever inferring services or repos → present the guess and ask, don't assume
  silently.

## Relationship to `rpc-handoff-jira-task`

- **`rpc-handoff-jira-task`** = ensure the working assets exist (folder, tmux
  session, Claude session, branch, worktrees, VS Code workspace) and stage a
  waiting session. Bootstrap only.
- **`rpc-do-jira-task`** (this skill) = implement the task inside that
  already-bootstrapped environment.
