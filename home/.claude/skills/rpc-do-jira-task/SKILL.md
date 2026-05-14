---
name: rpc-do-jira-task
description: Bootstrap and run a JIRA-driven engineering task end-to-end. Reads the ticket, sets up workspace folder, tmux session and per-repo git worktrees, then guides explore → plan → test (TDD) → implement → commit/PR. Never commits or pushes unless explicitly asked.
---

# rpc-do-jira-task

Take a JIRA ticket and bootstrap the full working environment for it (folder, tmux session, git worktrees), then walk the user through the implementation flow.

## Invocation

The skill is invoked as `/rpc-do-jira-task [JIRA-ID]`.

- If `JIRA-ID` is provided → fetch it via the Atlassian MCP and proceed.
- If `JIRA-ID` is missing → engage the user:
  1. Ask for a short description of the work.
  2. Ask which JIRA project / issue type / components apply.
  3. Create the issue via `mcp__atlassian__createJiraIssue`.
  4. Use the returned ID and title from then on.

Do not proceed without a real JIRA ID.

## Canonical task slug

For a ticket `<JIRA-ID>` (e.g. `SDCD-2541`) and a derived `<short-desc>` (e.g. `cd-vis-scaffolding`), define:

```
TASK_SLUG = <JIRA-ID>-<short-desc>     e.g. SDCD-2541-cd-vis-scaffolding
```

The same slug is reused everywhere for consistency:

| Where               | Value                                  |
| ------------------- | -------------------------------------- |
| Workspace folder    | `$HOME/w/<TASK_SLUG>`                  |
| tmux session name   | `<TASK_SLUG>`                          |
| Worktree dir        | `$HOME/dd/<repo>-<TASK_SLUG>`          |
| Git branch          | `raul.perezclavero/<TASK_SLUG>`        |

`<short-desc>` is derived from the JIRA title: lowercase, words joined with `-`, drop articles/filler, keep it short (~3–5 tokens). Confirm the slug with the user the first time you compute it.

## Step-by-step flow

### 1. Resolve the JIRA ticket

- Fetch the ticket via `mcp__atlassian__getJiraIssue` (or create it if missing — see Invocation).
- Print a concise summary: title, status, assignee, priority, components, and the rendered description.
- Ask the user: **"Anything else I should know before we start?"** Wait for an answer before moving on.

### 2. Resolve the workspace folder

- Search `$HOME/w` for any folder whose name **contains** `<JIRA-ID>` (e.g. `ls -d $HOME/w/*<JIRA-ID>* 2>/dev/null`).
- If a match exists → reuse it. Its existing name wins over a freshly-derived `<short-desc>` (avoids drift). Set `TASK_SLUG` = basename of that folder.
- If no match → derive `<short-desc>` from the title, confirm with the user, then `mkdir -p $HOME/w/<TASK_SLUG>`.
- `cd` into the folder.

### 3. Rename the tmux session

- Detect tmux via the `$TMUX` env var.
- If set and the current session name differs from `<TASK_SLUG>`:
  ```
  tmux rename-session <TASK_SLUG>
  ```
- If `$TMUX` is unset → skip silently. Do not start a new tmux session.

### 4. Determine the target repo(s)

- Infer candidate repos from the ticket text (title, description, components, "affects" hints).
- Repos live under `$HOME/dd/` (e.g. `dd-go`, `dd-source`, `k8s-resources`, `web-ui`, `logs-backend`). Other locations are possible — fall back to asking when unsure.
- Present the inferred list to the user and ask for confirmation/corrections **before** touching anything on disk.

### 5. Update each target repo

For each confirmed `<repo>`:

1. `cd $HOME/dd/<repo>`
2. `git main` — user's alias that switches to `main` or `master` as appropriate.
3. `git pull`

If a step fails (uncommitted changes, conflicts, etc.), stop and surface it. Do **not** stash, reset, or discard work to "fix" it.

### 6. Create a worktree per repo

For each `<repo>`:

```
git worktree add ../<repo>-<TASK_SLUG> -b raul.perezclavero/<TASK_SLUG>
```

- Worktree path: `$HOME/dd/<repo>-<TASK_SLUG>` (sibling of the repo).
- Branch name: `raul.perezclavero/<TASK_SLUG>`.
- If the worktree path already exists → reuse it; verify the branch matches. If branch differs, surface and ask.
- If the branch already exists locally or upstream → use `git worktree add ../<repo>-<TASK_SLUG> raul.perezclavero/<TASK_SLUG>` (no `-b`).

### 7. Create (or update) the VS Code workspace file

Create `$HOME/w/<TASK_SLUG>/<TASK_SLUG>.code-workspace` if it doesn't exist yet. Also create or refresh it mid-task if you notice it is missing.

The file must include, in order:

1. The workspace folder itself: `$HOME/w/<TASK_SLUG>`
2. One entry per worktree: `$HOME/dd/<repo>-<TASK_SLUG>`

Template (replace variables, use absolute paths):

```json
{
  "folders": [
    { "path": "~/w/<TASK_SLUG>" },
    { "path": "~/dd/<repo>-<TASK_SLUG>" }
  ],
  "settings": {}
}
```

- If there are **multiple repos**, add one `folders` entry per worktree after the workspace folder entry.
- If the file already exists and a new repo/worktree is added later, **update** the file to include the new path.
- After writing the file, print the path so the user can open it directly: `open ~/w/<TASK_SLUG>/<TASK_SLUG>.code-workspace` (or suggest `cursor ~/w/<TASK_SLUG>/<TASK_SLUG>.code-workspace` if in a Cursor session).

### 8. Hand off to the implementation flow

After setup, walk the user through:

1. **Explore** — read the relevant code, share a short map of what's relevant.
2. **Plan** — propose a plan, get explicit user agreement before writing code.
3. **Test (TDD)** — write failing tests first whenever feasible. If TDD doesn't fit a step, say so and why.
4. **Implement** — make the tests pass.
5. **Commit / PR** — only when the user explicitly asks. See rules below.

## Hard rules

- **No commits, no pushes, no PRs unless the user explicitly asks.** Even after green tests, stop and wait.
- **Commit message format** (when asked): single line `<JIRA-ID>: <short description>`. No co-author trailers. No multi-line body. No file lists.
- **Branch naming** is fixed: `raul.perezclavero/<TASK_SLUG>`. Never invent variations.
- **Go**: after editing `.go` files, run `go fmt` on the changed files. In Bazel-using repos (e.g. `dd-source`):
  - Use Bazel tooling instead of raw `go` (use the `running-bzl` agent for Bazel commands).
  - Use the `:all` target wildcard for tests, not `...`.
  - After import changes: `bzl run //:gazelle -- update <dir>`.
- **Diffs**: when running inside a VSCode/Cursor terminal, prefer `code --diff` / `cursor --diff` over plain text dumps.

## Integrating to staging

When the user asks to integrate changes to staging:

1. Identify the affected service(s):
   - First, look at the PR's labels. PRs are often auto-tagged with `changes:<service>`-style labels by CI. Read them with:
     ```
     gh pr view <pr> --json labels
     ```
   - If labels are missing or ambiguous, propose the service(s) you'd guess from the diff and **ask the user** to confirm or correct.
2. Post a PR comment per service:
   ```
   gh pr comment <pr> --body "/integrate -dfs <service-name>"
   ```
3. A single PR may span multiple services — post one comment per service unless the user says otherwise.

## Engaging the user

These are explicit interaction points; don't skip them:

- After fetching the ticket → "Anything else I should know?"
- Before creating folders / worktrees / branches → confirm the derived slug.
- Before starting implementation → confirm the plan.
- Before any commit, push, or PR → ask explicitly.
- Whenever inferring services or repos → present the guess and ask, don't assume silently.
