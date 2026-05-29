---
name: rpc-handoff-jira-task
description: Kick off a JIRA-driven task by ensuring all working assets exist — JIRA ticket, workspace folder, tmux session, a dedicated Claude session, and per-repo git worktrees — then hand context to that Claude session and have it wait for instructions. Bootstrap only; it does NOT implement the task (that is rpc-do-jira-task). Never destructive.
---

# rpc-handoff-jira-task

Bootstrap the full working environment for a JIRA ticket so that a fresh Claude
session is ready and waiting to do the work. This skill **only ensures the
assets exist**; the implementation flow lives in `rpc-do-jira-task`.

## Invocation

The skill is invoked as `/rpc-handoff-jira-task [JIRA-ID]`.

- If `JIRA-ID` is provided → fetch it via the Atlassian MCP and proceed.
- If `JIRA-ID` is missing → engage the user:
  1. Ask for the JIRA task ID.
  2. If it doesn't exist yet, ask for the **epic** and a short description of
     the work.
  3. Create the issue via `mcp__atlassian__createJiraIssue` under that epic.
  4. Use the returned ID and title from then on.

Do not proceed past step 1 (the slug) without a real JIRA ID.

## Canonical task slug — the single source of truth

For a ticket `<JIRA-ID>` (e.g. `SDCD-2541`) and a derived `<short-desc>` (e.g.
`cd-vis-scaffolding`), define:

```
TASK_SLUG = <JIRA-ID>-<short-desc>     e.g. SDCD-2541-cd-vis-scaffolding
```

The same slug is reused everywhere for consistency. **This table is the
authoritative definition; `rpc-do-jira-task` references it rather than
redefining it.**

| Where               | Value                                  |
| ------------------- | -------------------------------------- |
| Workspace folder    | `$HOME/w/<TASK_SLUG>`                  |
| tmux session name   | `w/<TASK_SLUG>`                        |
| Claude session name | `<TASK_SLUG>`                          |
| Worktree dir        | `$HOME/dd/<repo>-<TASK_SLUG>`          |
| Git branch          | `raul.perezclavero/<TASK_SLUG>`        |

`<short-desc>` is derived from the JIRA title: lowercase, words joined with
`-`, drop articles/filler, keep it short (~3–5 tokens). **Confirm the slug with
the user** before creating anything on disk.

If a folder matching `$HOME/w/*<JIRA-ID>*` already exists, its name wins over a
freshly-derived `<short-desc>` (avoids drift): set `TASK_SLUG` = basename of
that folder.

## Hard rules

- **Non-destructive.** Never delete, reset, stash, overwrite, or force-recreate
  anything. If an asset exists, reuse it.
- **Surface partial state.** If some assets exist and others don't (ticket,
  folder, tmux session, Claude session, branch, worktree), report it to the
  user explicitly.
- **Plan table first.** Before touching disk, present a create/reuse table (see
  below) for every asset and confirm the slug.
- **Branch naming** is fixed: `raul.perezclavero/<TASK_SLUG>`. Never invent
  variations.
- **Branch/worktree start point**: always branch from the tip of the repo's
  main branch (`main`/`master`/`prod`). Fetch/pull it first.
- **No implementation here.** This skill stops once the environment is ready and
  the spawned Claude session is waiting. The actual work is `rpc-do-jira-task`.

## Plan table

Before creating anything, print a table covering each asset and whether it will
be **created** or **reused**, e.g.:

| Asset             | Path / name                              | Action  |
| ----------------- | ---------------------------------------- | ------- |
| JIRA ticket       | `SDCD-2541`                              | reuse   |
| Workspace folder  | `$HOME/w/SDCD-2541-cd-vis-scaffolding`   | create  |
| tmux session      | `w/SDCD-2541-cd-vis-scaffolding`         | create  |
| Claude session    | `SDCD-2541-cd-vis-scaffolding`           | create  |
| Repo branch       | `raul.perezclavero/SDCD-2541-...`        | create  |
| Worktree          | `$HOME/dd/dd-go-SDCD-2541-...`           | create  |
| VS Code workspace | `<workspace>/<TASK_SLUG>.code-workspace` | create  |

## Step-by-step flow

### 1. Resolve the JIRA ticket

- Fetch via `mcp__atlassian__getJiraIssue` (or create it — see Invocation).
- Print a concise summary: title, status, assignee, priority, components, and
  the rendered description.

### 2. Confirm the slug, then ensure the workspace folder

- Search `$HOME/w` for a folder containing `<JIRA-ID>`:
  `ls -d $HOME/w/*<JIRA-ID>* 2>/dev/null`. If found, reuse that name.
- Otherwise derive `<short-desc>`, **confirm `TASK_SLUG` with the user**, then:
  ```
  mkdir -p "$HOME/w/<TASK_SLUG>"
  ```

### 3. Ensure the tmux session

The session is named `w/<TASK_SLUG>` and starts in the workspace folder. Create
it detached if it doesn't already exist (do not kill or rename an existing one):

```
tmux has-session -t "=w/<TASK_SLUG>" 2>/dev/null \
  || tmux new-session -d -s "w/<TASK_SLUG>" -c "$HOME/w/<TASK_SLUG>"
```

### 4. Determine the target repo(s)

- Infer candidate repos from the ticket text (title, description, components,
  "affects" hints).
- Repos live under `$HOME/dd/` (e.g. `dd-go`, `dd-source`, `k8s-resources`,
  `web-ui`, `logs-backend`). Other locations are possible — ask when unsure.
- Present the inferred list and ask for confirmation **before** touching disk.

### 5. Update each target repo's main branch

For each confirmed `<repo>`:

1. `cd $HOME/dd/<repo>`
2. `git main` — user's alias that switches to `main`/`master` as appropriate.
3. `git pull` (or `git fetch` for the main branch).

If a step fails (uncommitted changes, conflicts, etc.), **stop and surface it**.
Do not stash, reset, or discard work.

### 6. Ensure a branch + worktree per repo

For each `<repo>`, from the tip of the freshly-pulled main branch:

```
git worktree add ../<repo>-<TASK_SLUG> -b raul.perezclavero/<TASK_SLUG>
```

- Worktree path: `$HOME/dd/<repo>-<TASK_SLUG>` (sibling of the repo).
- If the worktree path already exists → reuse it; verify its branch matches. If
  the branch differs, surface and ask.
- If the branch already exists locally or upstream → omit `-b`:
  ```
  git worktree add ../<repo>-<TASK_SLUG> raul.perezclavero/<TASK_SLUG>
  ```

### 7. Ensure the VS Code workspace file (portable)

Create `$HOME/w/<TASK_SLUG>/<TASK_SLUG>.code-workspace` if it doesn't exist (or
refresh it when a repo/worktree is added later).

**Use relative paths — portable, no hardcoded home directory.** VS Code does not
support env-var substitution (`${env:HOME}`) in `folders[].path`, but it does
resolve paths relative to the workspace file's own directory. Since the file
lives in `$HOME/w/<TASK_SLUG>/` and worktrees live in `$HOME/dd/...`:

- `.` → the workspace folder itself (`$HOME/w/<TASK_SLUG>`)
- `../../dd/<repo>-<TASK_SLUG>` → `$HOME/dd/<repo>-<TASK_SLUG>`

Template (one `folders` entry per worktree after the workspace folder):

```json
{
  "folders": [
    { "path": "." },
    { "path": "../../dd/<repo>-<TASK_SLUG>" }
  ],
  "settings": {}
}
```

After writing, print the path so the user can open it directly, e.g.
`cursor "$HOME/w/<TASK_SLUG>/<TASK_SLUG>.code-workspace"` (or `code`/`open`).

### 8. Hand off to the waiting Claude session

Launch a Claude session named `<TASK_SLUG>` inside the tmux session and feed it
the task context, instructing it to **wait for the user's instructions**.

1. Start Claude in the tmux session (named via `--name`):
   ```
   tmux send-keys -t "w/<TASK_SLUG>" 'cd "$HOME/w/<TASK_SLUG>" && claude --name "<TASK_SLUG>"' Enter
   ```
2. Once it has booted, send the context as its first message, then `Enter`:
   ```
   tmux send-keys -t "w/<TASK_SLUG>" '<context message>' Enter
   ```

The context message should tell the new session:
- The JIRA ticket ID, title, and a one-paragraph summary of the work.
- The `TASK_SLUG`, workspace folder, worktree path(s), and branch.
- That the implementation flow is `rpc-do-jira-task` (it can `/rpc-do-jira-task
  <JIRA-ID>`), and that **its environment is already bootstrapped** — it should
  skip re-creating assets.
- An explicit instruction: **do nothing yet — wait for the user's
  instructions.**

### 9. Report completion

Tell the user the handoff is complete: which assets were created vs reused, the
workspace file path, the tmux session name, and that the Claude session
`<TASK_SLUG>` is up and waiting in tmux for their instructions.

## Relationship to `rpc-do-jira-task`

- **`rpc-handoff-jira-task`** (this skill) = ensure the assets exist and stage a
  waiting session. Bootstrap only.
- **`rpc-do-jira-task`** = implement the task (explore → plan → TDD →
  implement → commit/PR) inside that already-bootstrapped environment.
