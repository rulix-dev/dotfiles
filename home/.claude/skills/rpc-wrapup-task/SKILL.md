---
name: rpc-wrapup-task
description: Close out tasks created by rpc-handoff-task once their outcome is final — JIRA/ad-hoc tasks with merged PRs, finished PR reviews, resolved Datadog pages and incidents. Reviews consistency and outcome per type (JIRA vs PR vs diff, review posted and PR state, follow-ups for pages/incidents), proposes JIRA updates/transitions and follow-ups, and cleans up worktrees, branches, review refs and tmux sessions. Targeted (any ID/URL/slug, or the current task folder) or discovery mode (no argument - scans all task workspaces and worktrees and shows which are ready). Every external or destructive action needs explicit per-action confirmation. Works even if the task's tmux or agent session is dead.
---

# rpc-wrapup-task

Close tasks whose outcome is final. Runs in the **current session**; the
task's tmux or agent session doesn't need to be alive.

**First, read `~/.claude/skills/rpc-handoff-task/CONVENTIONS.md`** (task
types, naming, `HANDOFF.md`, interaction contract, harness notes).

## Invocation

`/rpc-wrapup-task [anything]`

- **Argument given** (ticket key, PR URL/shorthand — a task's work PR or a
  reviewed PR, see CONVENTIONS §2 *Work PRs* —, incident/page link,
  `TASK_ID` or `TASK_SLUG`) → **targeted mode** for that task.
- **No argument** → **discovery mode**: scan, show the candidates table, and
  ask which task(s) to wrap up (structured question tool; if cwd is inside a
  task, offer it as the recommended option). Each selected task then runs the
  targeted flow, one at a time.

## Hard rules

- **Never delete the workspace folder** `$HOME/w/<TASK_SLUG>` — it keeps
  `HANDOFF.md`, notes and history.
- **Never force**: no `git worktree remove --force`; `git branch -D` only after
  the checks in step 6d **and** a separate explicit confirmation.
- **Never edit or transition JIRA, post to Slack/GitHub, or change Datadog**
  without showing the exact change first and getting approval for that action.
  Never delete a pending GitHub review — that's the user's call, in the UI.
- **Only clean up what the task owns**: worktrees, branches and refs recorded
  in its `repos:` (or found by the legacy naming rules). Never the main
  checkout or another task's worktree.
- **Dead tmux / agent sessions are not errors** — report "already gone".
- **Action table first, execute later**: nothing is executed until the user
  has approved it (CONVENTIONS §6: `destructive` ⛔ and `external` ⚠️ rows are
  confirmed per action; "all" shortcuts only when the user says so).

---

## Discovery mode

### DS-1. Collect candidates

Use `find` (the shell may be zsh, where unmatched globs abort commands).

1. **Manifests**:
   `find "$HOME/w" -mindepth 2 -maxdepth 2 -name HANDOFF.md` — for each file
   whose first line is `---`, read the front matter (`task_type`, `task_id`,
   `status`, `repos:`, `pr`, `prs`, `jira`, …). Skip `status: done` unless it
   still has worktrees left over.
2. **Legacy tasks**: folders in `$HOME/w` whose `HANDOFF.md` is missing or has
   no front matter, and whose names match the CONVENTIONS §3 legacy patterns
   (`<KEY>-<n>-…`, `incident-<n>-…`, `pr-review-<repo>-<n>`, `NO-TICKET-…`).
3. **Orphan worktrees**: for each repo under `$HOME/dd/` with extra worktrees
   (`git -C <repo> worktree list --porcelain`), any worktree on a
   `raul.perezclavero/*` branch, or a detached one whose basename is
   `pr-review-<repo>-<n>` (porcelain shows only `detached` + the HEAD sha; you
   can also compare the sha with
   `git -C <repo> for-each-ref --format='%(objectname) %(refname)' refs/pr-review/`),
   that no task above claims.

Folders with no task-like name, no manifest and no worktree (e.g. scratch
folders) are listed separately as "not managed" and left alone.

### DS-2. Gather status (read-only)

Per task:

| Field                | How |
| -------------------- | --- |
| Worktrees + state    | exist? `git -C <wt> status --porcelain` (clean?), branch/ref |
| Remote               | `git -C <wt> remote get-url origin` → `<owner>/<repo>` |
| Work PRs             | for each `repos[].branch` (legacy: `raul.perezclavero/<TASK_SLUG>`): `gh pr list --repo <owner>/<repo> --head <branch> --state all --json number,title,state,url,mergedAt`; plus the `prs:` entries |
| Reviewed PR          | `pr-review`: `gh pr view <n> --repo <owner>/<repo> --json state,mergedAt,closedAt` + your review state (step 4) |
| Page                 | `page`: current monitor state (Datadog MCP) |
| Incident             | `incident`: current incident state (Datadog MCP) |
| tmux                 | `tmux has-session -t "=w/<TASK_SLUG>" 2>/dev/null` → ALIVE / DEAD |

### DS-3. Classify

| Status          | `jira` / `adhoc`            | `pr-review`                       | `page`                                         | `incident`                                     |
| --------------- | --------------------------- | --------------------------------- | ---------------------------------------------- | ---------------------------------------------- |
| 🟢 ready        | all work PRs merged         | PR merged or closed               | monitor OK and no open fix PRs                 | incident resolved and no open fix PRs          |
| 🟡 partial      | some PRs still open         | PR open, your review submitted    | monitor OK, fix PRs open / follow-ups pending  | resolved, follow-ups/PRs open                  |
| 🔴 in progress  | no PRs / all open           | PR open, no review submitted yet  | still alerting                                 | active or stable                               |
| ⚪ unknown      | no PRs, clean, old          | PR not found                      | monitor not found                              | incident not found                             |

### DS-4. Present and ask

```
#  TASK_SLUG                              Type       Worktrees               PRs / state          tmux   Status
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
1  SDCD-2545-cd-vis-worker-cc-enricher     jira       dd-source ✓ clean       #465140 merged       DEAD   🟢 ready
2  pr-review-dd-source-59188               pr-review  dd-source ✓ detached    #59188 merged        DEAD   🟢 ready
3  incident-57516-cc-enricher-killswitch   incident   dd-source ✓ clean       resolved · #1234 open ALIVE 🟡 partial
4  page-9540074-dora-intake-lag            page       —                       monitor ALERT        ALIVE  🔴 in progress
```

Ask which tasks to wrap up (numbers, or "all ready" for every 🟢). Run the
targeted flow for each selected task **sequentially**, so the user reviews
each report and confirms actions per task.

---

## Targeted mode flow

### 1. Resolve the task

Resolve per CONVENTIONS §3 (manifest lookup → folder name → legacy patterns;
ask if several match). No match → stop: the task was never set up or is
already fully cleaned. Read `HANDOFF.md` (plus `NOTES.md`, `REVIEW.md`,
`POSTMORTEM.md` if present) and refresh the source (JIRA / PR / monitor /
incident).

### 2. Discover associated PRs

- **Work PRs** (all types except pure reviews): for every worktree in `repos:`
  use its recorded `branch` (legacy: `raul.perezclavero/<TASK_SLUG>`, worktrees
  found per CONVENTIONS §3):
  `gh pr list --repo <owner>/<repo> --head "<branch>" --state all --json number,title,state,url,mergedAt,headRefOid`,
  plus the PRs listed in `prs:`. Classify: merged ✓ · open ⏳ (warn: "PR #N is
  still open — wrap up anyway?") · closed unmerged ✗.
- **Reviewed PR** (`pr-review`): the PR in `pr:`.
- No PRs found where you expected some → ask for the repo(s)/PR numbers before
  continuing. Older tasks may only have **pre-migration PRs** in the old
  `DataDog` org, which can't be queried (CONVENTIONS §2): ask the user for the
  outcome instead of classifying the task as in progress, and don't offer
  `branch -D` (there is no PR head to compare with).

### 3. Current-state report (read-only)

```
Asset                                              Status
──────────────────────────────────────────────────────────────────────────────
Task  incident-57516-cc-enricher-killswitch         incident · HANDOFF.md ✓
Incident 57516                                      resolved (SEV-2) · postmortem draft
tmux  w/incident-57516-cc-enricher-killswitch       DEAD
Agent session  incident-57516-cc-enricher-killswitch resumable (claude_session / pi --session-id)
Worktree  $HOME/dd/dd-source-incident-57516-…        EXISTS — clean · 2 ignored files (.env.local, notes/)
Local branch  raul.perezclavero/NO-TICKET-incident-… EXISTS in dd-source (tip == PR head)
PR #1234 (ddoghq/dd-source)                         merged ✓ 2026-07-12
Review ref  refs/pr-review/59188                    (pr-review only)
```

Checks per worktree and branch:
- uncommitted changes: `git -C <wt> status --porcelain` (must be empty);
- **ignored files**, which `git worktree remove` deletes without warning:
  `git -C <wt> status --porcelain --ignored=matching | grep '^!!'` — build and
  dependency output (`node_modules/`, `bazel-*`, `.pnp.*`, `.yarn/cache`,
  `dist/`) is fine; list anything else;
- **detached worktrees** (reviews): commits reachable from nothing else would
  be lost —
  `git -C <wt> log --oneline HEAD --not --branches --tags --remotes --glob='refs/pr-review/*' | head -20`
  (empty means nothing is lost; don't use `--not --all`, which includes HEAD
  itself and always prints nothing). Run it before deleting the review ref;
- **local branch vs PR head**: fetch the PR head first so it exists locally
  (`git -C "$HOME/dd/<repo>" fetch origin "refs/pull/<n>/head"`, FETCH_HEAD
  only), then compare `git -C "$HOME/dd/<repo>" rev-parse <branch>` with the
  PR's `headRefOid`; if they differ, show both directions:
  `log --oneline <headRefOid>..<branch>` (local-only commits) and
  `log --oneline <branch>..<headRefOid>` (e.g. GitHub "Update branch" commits);
- tmux: alive/dead, and what runs in it:
  `tmux list-panes -s -t "=w/<TASK_SLUG>" -F '#{window_index}.#{pane_index} #{pane_current_command} #{pane_current_path}'`.

### 4. Outcome review (per type)

Produce a written report and wait for acknowledgement before step 5.

**`jira` / `adhoc` — Consistency report** across (1) the JIRA description (or
the ad-hoc description in `HANDOFF.md`), (2) each merged PR's title/body
(`gh pr view <n> --repo <owner>/<repo> --json title,body`), and (3) its
file-level diff stat
(`gh api --paginate repos/<owner>/<repo>/pulls/<n>/files --jq '.[] | "\(.additions)+ \(.deletions)- \(.filename)"'`):
- ✅ **Consistent** — what aligns (brief).
- ⚠️ **Discrepancies** — scope creep, described-but-missing features, wrong
  names/types/approach, anything misleading for a future reader.
- 📝 **Proposed JIRA changes** — ready-to-apply edits. The implementation is the
  source of truth. If the ticket is already accurate, say so.

**`pr-review` — Review outcome**:
- PR final state (merged/closed/open) and when.
- Your review: submitted? state? **Pending review left behind?**
  (`gh api --paginate repos/<owner>/<repo>/pulls/<n>/reviews --jq '.[] | select(.state=="PENDING") | .id'`)
  → warn; submitting or discarding it is the user's call, in the GitHub UI.
- Your comments: addressed / unresolved — compare `REVIEW.md` → **Posted** with
  the review threads' `isResolved`/`isOutdated` (GraphQL query in
  `rpc-do-task/playbooks/pr-review.md` §2).
- Follow-ups worth a ticket (e.g. deferred "should-fix" items).

**`page` — Outcome**:
- Monitor state now and since when; any re-trigger after the fix?
- Conclusion from `NOTES.md` (classification, cause, confidence).
- Follow-ups: fix PRs (merged?), monitor tuning done?, JIRA tickets created?
- Proposed: final Slack thread summary (draft), missing follow-up tickets.

**`incident` — Outcome**:
- Incident state (resolved?), postmortem status.
- Timeline/conclusion from `NOTES.md`; action items and their tickets.
- Fix PRs merged?
- Proposed: final channel summary / postmortem contributions (drafts),
  missing follow-up tickets.

### 5. Action table — confirm each action

```
#   Action                                              Kind            Detail
─────────────────────────────────────────────────────────────────────────────────────────────
1   Update JIRA description                             external ⚠️     [exact proposed text/diff]
2   Transition JIRA → Done / In-Production              external ⚠️     [available transitions]
3   Create follow-up JIRA ticket(s)                     external ⚠️     [drafts]
4   Post final summary (Slack thread / channel)         external ⚠️     [draft message]
5   Remove worktree  <path from repos:>                 destructive ⛔  git worktree remove [+ ignored files it deletes; deferred if this session runs in it]
6   Delete local branch <repos[].branch> in <repo>      destructive ⛔  git branch -d
7   Delete review ref  refs/pr-review/<n> in <repo>     destructive ⛔  git update-ref -d
8   Mark task done in HANDOFF.md                        modify          status: done + wrap-up summary
9   Kill tmux session  w/<TASK_SLUG>                    destructive ⛔  tmux kill-session [only if ALIVE; panes listed]
```

Include only the rows that apply to the task type. Show a clear warning for
⛔ rows. Default to per-action y/n; offer "y to all non-destructive" and "y to
all" shortcuts, but don't assume them.

### 6. Execute the approved actions, in order

#### 6a. JIRA description (if approved)
Show the exact final text, then Atlassian `editJiraIssue` (`description`).

#### 6b. JIRA transition (if approved)
Atlassian `getTransitionsForJiraIssue` → show them, recommend the closest to
Done / In Production / Closed, confirm the exact name → `transitionJiraIssue`.

#### 6c. Follow-up tickets / Slack summary (if approved)
Create each approved ticket (`createJiraIssue`, link it with `createIssueLink`
when relevant) and post each approved message exactly as shown (Slack MCP,
in the right thread/channel). Record links in `HANDOFF.md`.

#### 6d. Worktrees, branches, refs (if approved, one by one)
1. **Worktree**: if this agent's working directory is inside `<wt>` (compare
   `realpath "$PWD"` with `realpath "<wt>"` as a prefix), don't remove it from
   this session: finish the other actions, then tell the user to run
   `git -C "$HOME/dd/<repo>" worktree remove "<wt>"` (and the approved branch
   deletion) after exiting. Also warn if a tmux pane's `pane_current_path`
   (step 3) is inside `<wt>`. Otherwise re-run the step-3 checks. Skip and
   report if there are uncommitted changes. Ignored files beyond build/dependency output, or
   unreachable commits in a detached worktree → remove only after a separate
   explicit ⛔ confirmation that names them. Then, from the main repo:
   `git -C "$HOME/dd/<repo>" worktree remove "<wt>"`. Any error → report and
   skip (never `--force`).
2. **Local branch** (the recorded `repos[].branch`):
   `git -C "$HOME/dd/<repo>" branch -d "<branch>"`. `-d` refuses unmerged
   branches — which is normal after a **squash merge**. If it refuses: show the
   step-3 evidence (tip == the merged PR's `headRefOid`, no local-only
   commits) and offer `-D` as a **separate** explicit confirmation; otherwise
   skip.
3. **Review ref** (`pr-review`): `git -C "$HOME/dd/<repo>" update-ref -d refs/pr-review/<n>`.

#### 6e. Manifest (if approved)
Set `status: done` in the front matter and append a **Wrap-up** section to
`HANDOFF.md`: date, outcome, PRs, tickets, what was cleaned up. Legacy task:
prepend a minimal front matter (with `status: done`) and append the Wrap-up
section; never rewrite the existing body.

#### 6f. tmux (if approved and ALIVE) — always last
If this agent runs inside that session
(`[ -n "$TMUX" ] && [ "$(tmux display-message -p -t "$TMUX_PANE" '#S')" = "w/<TASK_SLUG>" ]`),
don't kill it: finish the report, then tell the user to run
`tmux kill-session -t "=w/<TASK_SLUG>"` after exiting. Otherwise
`tmux kill-session -t "=w/<TASK_SLUG>"`. Already dead → "session already gone".

### 7. Final report

```
Action                              Result
──────────────────────────────────────────────────────
JIRA description updated            ✓ done
JIRA transitioned → Done            ✓ done
Worktree dd-source-… removed        ✓ done
Branch deleted (dd-source)          skipped (user declined)
Review ref deleted                  n/a
HANDOFF.md                          status: done
tmux session                        kill it after exiting (this agent runs in it)
Workspace folder                    kept at $HOME/w/<TASK_SLUG>
```

Call out anything skipped or failed and suggest next steps.

## Session recovery note

A dead tmux session (e.g. after a restart) is expected. To look at the task's
agent session before wrapping up (optional):
- Claude Code: `claude_session "$HOME/w/<TASK_SLUG>" "<TASK_SLUG>"` (or
  `claude --resume` and pick it);
- pi: `cd "$HOME/w/<TASK_SLUG>" && pi --session-id "<TASK_SLUG>"`.

## Relationship to the other rpc-* skills

- **`rpc-handoff-task`** — bootstrap the environment and capture context.
- **`rpc-do-task`** — do the work inside that environment.
- **`rpc-wrapup-task`** (this skill) — close the loop: outcome review, JIRA and
  follow-ups, cleanup.
