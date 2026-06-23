---
name: rpc-wrapup-jira-task
description: Close out completed JIRA tasks after PR(s) are merged — consistency review (JIRA vs PR vs implementation), JIRA transition to Done/In-Production, and worktree/branch cleanup. Two modes: targeted (provide a JIRA-ID) or discovery (scan $HOME/dd for all worktrees and surface which ones are ready to clean up). All destructive actions require explicit per-action user confirmation. Works even if the task's tmux or Claude session is dead.
---

# rpc-wrapup-jira-task

Wrap up completed JIRA tasks once their PR(s) are merged. This skill runs in
the **current session** — it does not require the task's tmux or Claude session
to be alive.

Two modes:
- **Targeted** — `/rpc-wrapup-jira-task SDCD-XXXX`: wrap up one specific task.
- **Discovery** — `/rpc-wrapup-jira-task` (no argument): scan `$HOME/dd` for all
  known worktrees, check their PR status, and surface which ones are ready to
  clean up.

## Invocation

`/rpc-wrapup-jira-task [JIRA-ID]`

- **With JIRA-ID** → targeted mode: wrap up that specific task (see
  [Targeted mode flow](#targeted-mode-flow)).
- **Without JIRA-ID** → discovery mode: scan all worktrees and present a
  candidates table (see [Discovery mode](#discovery-mode)). From the table the
  user picks which task(s) to wrap up; each selected task then runs the targeted
  flow.

## Discovery mode

When invoked without a JIRA-ID, scan `$HOME/dd` for worktree directories and
build a full picture of outstanding tasks.

### DS-1. Find worktree candidates

List everything in `$HOME/dd` whose name contains a JIRA-ID-like segment
(`<REPO>-<PROJECT>-<NUMBER>-<desc>`, e.g. `dd-go-SDCD-2546-ukv-enrich-deployments`):

```bash
ls -d $HOME/dd/*-[A-Z]*-[0-9]* 2>/dev/null
```

This matches the convention `<repo>-<TASK_SLUG>` where TASK_SLUG starts with a
JIRA project key and number.

Exclude the known bare repos (`dd-go`, `dd-source`, `k8s-resources`, `web-ui`,
`logs-backend`, etc.) — they never contain a JIRA-ID in their names.

### DS-2. Verify each candidate is a git worktree

```bash
git -C <candidate> rev-parse --git-dir 2>/dev/null
```

If this fails, the directory is not a git repo — skip it with a note.

### DS-3. Gather per-worktree metadata

For each confirmed worktree:

| Field | Command |
|---|---|
| Current branch | `git -C <wt> rev-parse --abbrev-ref HEAD` |
| Working tree clean? | `git -C <wt> status --porcelain` (empty = clean) |
| Remote (org/repo) | `git -C <wt> remote get-url origin` → parse `DataDog/<repo>` |
| TASK_SLUG | extracted from the directory name (strip leading `<repo>-`) |
| JIRA-ID | extracted from TASK_SLUG (first `<PROJECT>-<NUMBER>` segment) |
| Workspace folder | `ls -d $HOME/w/*<JIRA-ID>* 2>/dev/null` → exists? |
| tmux session | `tmux has-session -t "=w/<TASK_SLUG>" 2>/dev/null` → ALIVE/DEAD |

### DS-4. Discover PRs for each worktree

```bash
gh pr list \
  --head "<branch>" \
  --state all \
  --json number,title,state,url,mergedAt \
  --repo <org>/<repo>
```

Classify:
- All PRs merged → 🟢 **ready to wrapup**
- Some open, some merged → 🟡 **partially done**
- No PRs at all / all open → 🔴 **in progress**
- Branch has no PRs and is clean → ⚪ **unknown / abandoned?**

### DS-5. Present the discovery table

Print one row per discovered worktree, grouped by TASK_SLUG:

```
#   TASK_SLUG                                Worktree               Branch    PRs              Status
─────────────────────────────────────────────────────────────────────────────────────────────────────────
1   SDCD-2545-cd-vis-worker-cc-enricher      dd-source  ✓ clean     merged    #465140 merged   🟢 ready
2   SDCD-2632-pr-ci-test-sessions-dur        k8s-res    ✓ clean     merged    #162937 open     🟡 partial
3   SDCD-2546-ukv-enrich-deployments         dd-go      ✓ clean     merged    #239466 merged   🟢 ready
4   SDCD-2547-dora-query-ci-allowlist        dd-source  ✓ clean     current   (none)           🔴 in progress
```

Also show for each: workspace folder exists? (`$HOME/w/<TASK_SLUG>`), tmux
session alive?

### DS-6. Let the user choose

Ask: **"Which tasks do you want to wrap up? (enter numbers, comma-separated, or
'all ready' to process all 🟢 tasks)"**

For each selected task, run the full **Targeted mode flow** (steps 1–7 below)
in sequence. Do not batch — run one task at a time so the user can review the
consistency report and confirm actions per task.

---

## Targeted mode flow

> Used directly when a JIRA-ID is provided, or as the per-task step after
> discovery mode selection.

## Canonical task slug

Resolved the same way as `rpc-do-jira-task`:
```
ls -d $HOME/w/*<JIRA-ID>* 2>/dev/null
```
The basename of the matching folder is the `TASK_SLUG`. If no match exists,
stop — the workspace was never set up or was already fully cleaned up.

If multiple matches exist, ask the user to choose.

## Hard rules

- **Never delete the workspace folder** `$HOME/w/<TASK_SLUG>`. It holds the
  `HANDOFF.md` and historical context; leave it in place.
- **Never force-remove** a worktree (`--force`) or force-delete a branch (`-D`).
  If the safe check fails (dirty worktree, unmerged branch), surface the error
  and skip that action.
- **Never edit the JIRA description** without showing the exact proposed diff first.
- **Never transition the JIRA ticket** without showing available transitions and
  confirming the specific one.
- **Dead tmux/Claude sessions are not errors.** If the tmux session is gone
  (e.g. after a machine restart), note it as "already clean" and move on.
- **All destructive actions require explicit per-action confirmation.** Present
  the full action table first; execute only what the user approves.

## Step-by-step flow

### 1. Resolve TASK_SLUG and fetch the JIRA ticket

```
TASK_SLUG=$(basename $(ls -d $HOME/w/*<JIRA-ID>* 2>/dev/null | head -1))
```

Fetch the ticket via `mcp__atlassian__getJiraIssue`. Print: title, current
status, assignee, description (truncated if long).

### 2. Discover associated PRs

For every worktree `$HOME/dd/*<JIRA-ID>*`:

1. Extract the GitHub repo:
   ```
   git -C <worktree> remote get-url origin
   # e.g. git@github.com:DataDog/dd-go.git → DataDog/dd-go
   ```

2. Look up PRs from this branch in that repo:
   ```
   gh pr list \
     --head "raul.perezclavero/<TASK_SLUG>" \
     --state all \
     --json number,title,state,url,mergedAt \
     --repo <org>/<repo>
   ```

3. Classify each PR:
   - `merged` ✓ — ready for wrapup
   - `open` ⏳ — warn: "PR #N is still open — are you sure you want to wrap up now?"
   - `closed` (not merged) ✗ — note it

If **no PRs are found at all**, ask the user to confirm the repo(s) and PR
numbers manually before continuing.

### 3. Current-state report (read-only, no actions yet)

Print a status table covering every relevant asset. Example:

```
Asset                                         Status
────────────────────────────────────────────────────────────────────────
JIRA SDCD-XXXX                                In Progress
tmux  w/<TASK_SLUG>                           DEAD (not running)
Claude session  <TASK_SLUG>                   unknown (resumable with: claude --resume --name <TASK_SLUG>)
Worktree  $HOME/dd/dd-go-<TASK_SLUG>          EXISTS — clean, branch merged upstream
Worktree  $HOME/dd/dd-source-<TASK_SLUG>      EXISTS — clean, branch merged upstream
Local branch  raul.perezclavero/<TASK_SLUG>   EXISTS in dd-go (local only)
Local branch  raul.perezclavero/<TASK_SLUG>   EXISTS in dd-source (local only)
PR #12345  (DataDog/dd-go)                    merged ✓  2026-06-20
PR #67890  (DataDog/dd-source)                merged ✓  2026-06-21
```

For each worktree, check cleanliness:
```
git -C <worktree> status --porcelain
```

For the tmux session:
```
tmux has-session -t "=w/<TASK_SLUG>" 2>/dev/null && echo ALIVE || echo DEAD
```

### 4. Consistency review

Read the three sources and produce a written **Consistency Report**:

1. **JIRA description** — from the ticket fetched in step 1.
2. **PR title + body** — for each merged PR:
   ```
   gh pr view <number> --json title,body --repo <org>/<repo>
   ```
3. **Implementation diff summary** — for each merged PR:
   ```
   gh pr diff <number> --repo <org>/<repo> --stat
   ```
   (file-level stat only; no need to read every line)

Produce a **Consistency Report** with three sections:

**✅ Consistent** — what aligns well across JIRA, PR descriptions, and the
actual diff (mention briefly, don't over-explain).

**⚠️ Discrepancies** — things that diverge:
- Scope creep in the implementation (more was done than stated).
- Features described in JIRA/PR but absent from the diff.
- Incorrect types, field names, or approach descriptions.
- Anything a future reader would find misleading.

**📝 Proposed JIRA changes** — concrete, ready-to-apply edits to the JIRA
description. The **implementation is the source of truth**; the JIRA should
reflect what was actually built. If the JIRA is already accurate, say so
explicitly.

Present the full Consistency Report to the user and wait for acknowledgement
before proceeding.

### 5. Action table — confirm each action individually

Present the full list of proposed actions. The user confirms each one (y/n)
before anything is executed. Do not execute anything yet.

```
#   Action                                            Detail
────────────────────────────────────────────────────────────────────────────
1   Update JIRA description                           [show proposed diff]
2   Transition JIRA → Done / In-Production            [show available transitions]
3   Remove worktree  $HOME/dd/<repo1>-<TASK_SLUG>     git worktree remove
4   Remove worktree  $HOME/dd/<repo2>-<TASK_SLUG>     git worktree remove
5   Delete local branch in <repo1>                    git branch -d raul.perezclavero/<TASK_SLUG>
6   Delete local branch in <repo2>                    git branch -d raul.perezclavero/<TASK_SLUG>
7   Kill tmux session  w/<TASK_SLUG>                  tmux kill-session  [only if ALIVE]
```

Actions 3–7 are destructive; show a clear warning. Actions 1–2 are reversible
but still require confirmation.

Ask the user to go through each action (y/n). You may also offer "y to all
non-destructive" and "y to all" shortcuts, but default to per-action.

### 6. Execute confirmed actions in order

#### 6a — Update JIRA description (if confirmed)

Show the exact proposed description text (full replacement or diff). Use
`mcp__atlassian__editJiraIssue` with the updated `description` field.

#### 6b — Transition JIRA (if confirmed)

Fetch available transitions:
```
mcp__atlassian__getTransitionsForJiraIssue
```

Display them and recommend the one closest to "Done" / "In Production" /
"Closed". Ask the user to confirm the exact transition name before executing:
```
mcp__atlassian__transitionJiraIssue
```

#### 6c — Remove worktrees (if confirmed, one by one)

For each worktree:
1. Pre-check cleanliness:
   ```
   git -C <worktree> status --porcelain
   ```
   If not clean → skip, show error, do not remove.
2. Remove:
   ```
   cd $HOME/dd/<repo> && git worktree remove "$HOME/dd/<repo>-<TASK_SLUG>"
   ```
   If this fails for any reason, show the error and skip.

#### 6d — Delete local branches (if confirmed, one per repo)

```
cd $HOME/dd/<repo> && git branch -d "raul.perezclavero/<TASK_SLUG>"
```

`-d` is intentional (safe): git refuses to delete an unmerged branch. If it
fails, show the message and ask the user whether to skip or force (`-D`).

#### 6e — Kill tmux session (if confirmed and ALIVE)

```
tmux kill-session -t "w/<TASK_SLUG>"
```

If the session is already dead, print "session already gone — nothing to do."

### 7. Final report

Print a summary table of what was done vs skipped vs failed:

```
Action                          Result
──────────────────────────────────────────────────
JIRA description updated        ✓ done
JIRA transitioned → Done        ✓ done
Worktree dd-go-... removed      ✓ done
Worktree dd-source-... removed  ✓ done
Branch deleted (dd-go)          ✓ done
Branch deleted (dd-source)      skipped (user declined)
tmux session killed             already dead
Workspace folder                kept at $HOME/w/<TASK_SLUG>
```

If anything was skipped or failed, call it out clearly and suggest next steps.

## Session recovery note

If the task's **tmux session** is dead (machine restart), that is expected and
not an error — the cleanup steps above do not require it.

If you want to **resume the task's Claude session** to check its state before
wrapping up, you can do so from any terminal:
```
claude --resume --name "<TASK_SLUG>"
```
This is optional and informational — `rpc-wrapup-jira-task` does not require it.

## Relationship to the other rpc-* skills

- **`rpc-handoff-jira-task`** = bootstrap the working environment (folder, tmux,
  Claude session, branch, worktrees).
- **`rpc-do-jira-task`** = implement the task inside that environment.
- **`rpc-wrapup-jira-task`** (this skill) = close the loop once PRs are merged:
  consistency review, JIRA transition, and cleanup.
