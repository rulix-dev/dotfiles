---
name: rpc-handoff-task
description: Bootstrap an isolated working environment for a task and stage a dedicated agent session that waits for instructions. Works for a JIRA ticket, a GitHub PR to review (URL or repo + number), a Datadog page (Slack message link, page URL or monitor URL) or a Datadog incident (incident URL or Slack incident channel ID), plus ad-hoc tasks. Parses a free-form prompt (asks when invoked without arguments or when something is unclear), gathers context into HANDOFF.md, and — after one confirmation gate — creates the workspace folder, tmux session, git worktrees (detached at the PR head for reviews), VS Code workspace and a Claude Code or pi session. Bootstrap only; the work itself is rpc-do-task. Never destructive.
---

# rpc-handoff-task

Set up everything needed to work on a task in isolation, write down what is
known about it, and leave a fresh agent session waiting in tmux. This skill
**only ensures the assets exist and captures context**; the work happens in
`rpc-do-task`, and the cleanup in `rpc-wrapup-task`.

**First, read `~/.claude/skills/rpc-handoff-task/CONVENTIONS.md`** (task
types, input detection, naming, `HANDOFF.md`, interaction contract, harness
notes). Everything below builds on it.

## Invocation

`/rpc-handoff-task [anything]` — the argument can be an ID, a URL, or a
sentence in Spanish or English:

- `/rpc-handoff-task SDCD-2541`
- `/rpc-handoff-task https://github.com/ddoghq/dd-go/pull/20122`
- `/rpc-handoff-task revisa dd-source#4651`
- `/rpc-handoff-task mira este page https://dd.enterprise.slack.com/archives/C0…/p1784…`
- `/rpc-handoff-task https://app.datadoghq.com/incidents/57516`
- `/rpc-handoff-task C07ABCDE123` (incident channel)

**Without arguments**, ask (structured question tool) what to work on:

1. *What kind of task?* — JIRA ticket · PR review · Datadog page · Datadog
   incident (free text covers "something else" → `adhoc`).
2. *Identifier?* — the ID/URL/Slack link for that type (free text). For JIRA,
   offer "create a new ticket" as an option.

With arguments, classify per CONVENTIONS §2 and only ask what remains unclear.

## Hard rules

- **Non-destructive.** Never delete, reset, stash, overwrite or force-recreate
  anything. Existing assets are reused. Never touch the repo's main checkout
  (CONVENTIONS §4).
- **Surface partial state.** If some assets exist and others don't, say so
  explicitly in the plan.
- **One plan gate** (CONVENTIONS §6) before writing anything outside the scratch
  area. The slug, the repos and the agent (Claude Code / pi) are confirmed in
  that gate.
- **External actions** (e.g. creating a JIRA ticket) are separate `external`
  rows in the plan and need explicit approval.
- **No work here.** Stop once the environment is ready and the agent session is
  waiting. No code changes, no review comments, no analysis beyond what is
  needed to name the task and brief the next session.

## Flow

### 1. Classify the input

Apply CONVENTIONS §2. Result: `TASK_TYPE` plus the raw identifiers (ticket key,
`owner/repo` + PR number, Slack channel + ts, incident id, monitor id, …).

### 2. Resolve the source (read-only)

Gather what is needed to name the task, pick repos and brief the next session.
Save raw captures you'll want later under the scratch `context/` folder once it
exists (step 6); until then keep them in memory.

**`jira`**
- Fetch with Atlassian `getJiraIssue`: title, status, assignee, priority,
  components, labels, epic, links, rendered description, recent comments.
- Ticket doesn't exist yet → ask for the **epic** and a short description; the
  creation (`createJiraIssue`) is an `external` action: present it as a mini
  plan, create only after approval, then continue with the returned key.

**`pr-review`**
- `gh pr view <n> --repo <owner>/<repo> --json number,title,url,author,state,isDraft,baseRefName,headRefName,headRefOid,headRepositoryOwner,isCrossRepository,labels,additions,deletions,changedFiles,reviewDecision,body,files`
  (`files` stops at 100 entries; when `changedFiles` is larger, list them with
  `gh api --paginate repos/<owner>/<repo>/pulls/<n>/files --jq '.[] | "\(.additions)\t\(.deletions)\t\(.filename)"'`).
- `gh pr checks <n> --repo <owner>/<repo>` (CI status) and existing reviews
  (`gh api --paginate repos/<owner>/<repo>/pulls/<n>/reviews`).
- Linked ticket: look for a JIRA key in title, body or head branch.
- If the PR is merged/closed, say so and ask whether to continue.

**`page`** — follow the trail to the monitor. No Datadog MCP tool reads an
On-Call page, and the paging API only has write endpoints, so the path goes
through Slack and the monitor:
1. **Slack link** → `slack_read_thread(channel, parent_ts)` (CONVENTIONS §2 for
   the ts). The Datadog bot's parent attachment has `Page #<n>: <title>`, the
   page URL, "Triggered by <monitor link>", *Status*, *Urgency*, *Team*,
   *Responder* and the rendered monitor message (runbook, dashboards). Its
   first reply, "Page triggered by … Monitor #<id>", links the monitor with
   `group=` (triggering group), `event_id` and `link_event_ts` (trigger time).
   Later replies: notifications, "acknowledged by", "automatically resolved",
   then the human discussion.
2. **Page URL or "Page #<n>" only** → search Slack for the page number
   (`slack_search_public` with `keywords: ["<n>"]`, `include_bots: true`) and
   continue as in 1. Nothing found (or a UUID page URL, which has no number to
   search) → ask for the Slack link, the `Page #N`, or the monitor link.
3. **Monitor** → `search_datadog_monitors(query: "id:<id>", include_tags:
   ["service*", "team*", "env*"])`: name, type, query, thresholds, message,
   notifications, status, creator, tags (tags only come back with
   `include_tags`).
4. **Alert events** →
   `search_datadog_events(query: "source:alert (@monitor_id:<id> OR monitor_id:<id>)", from: <trigger − 2h>, to: <trigger + 1h>)`
   (trigger = `link_event_ts`; the tool defaults to the last hour, so always
   pass the window), then a 7-day window for the trigger/recover history.
   Events carry priority and group tags; monitors managed as code carry
   `terraform_repo:` / `terraform_path:` tags (where the definition lives).
5. Note the trigger time, triggering group, current state, who acknowledged,
   and whether an incident was declared (an incident-triggered page says
   "Created from incident IR-<n>" → treat as `incident`).

**`incident`**
1. Get the public id: from the URL (`/incidents/<n>`), from `IR-<n>`, or from
   the Slack channel — `slack_read_channel(<id>, limit: 1)` prints
   `Channel: #incident-<n> (<id>)`; `slack_search_channels(["incident-<n>"],
   include_archived: true)` also returns the topic (severity, state,
   commander, incident link).
2. `get_datadog_incident(<n>, include_timeline: true)`: title, severity,
   state, customer impact, created/detected/resolved, users, `custom_fields`
   (slug `IR-<n>`, services, teams, datacenter, products impacted, summary,
   root cause…) and the timeline (it mirrors the Slack channel).
   `custom_fields.services` is often empty — derive services from teams,
   title, timeline links and referenced monitors.
3. The incident doesn't expose its Slack channel: find `#incident-<n>` with
   `slack_search_channels` and `include_archived: true` (channels are archived
   after resolution; private/security incidents may need
   `channel_types: private_channel`, or ask). Read recent messages
   (`slack_read_channel`) and busy threads (`slack_read_thread`).

**`adhoc`** — take the description as given; ask for the repo(s) if code is
involved.

**Service → repo** (`page`/`incident`):
`search_datadog_entities(entity_type: "service", query: "name:<service>", fields: ["owner", "links", "contacts"])`
→ `links[]` entries with `type: repo` point to
`github.com/<org>/<repo>/tree/<branch>/<path>` (repo, branch and the service's
directory). Prefer the link named after the service or "Source" over
Helm/k8s ones. Map `<repo>` to `$HOME/dd/<repo>`.

### 3. Determine the repos

- `pr-review`: the PR's repo — fixed.
- `jira`/`adhoc`: infer from the ticket text (title, description, components,
  "affects" hints).
- `page`/`incident`: the candidate repos from step 2 are **optional** rows in
  the plan (default: include only if one repo is clearly implicated; the rest
  can be added later).

Repos live under `$HOME/dd/` (`dd-go`, `dd-source`, `k8s-resources`, `web-ui`,
`logs-backend`, …). Other locations are possible — ask when unsure. If a repo
isn't cloned, offer the clone as a `create` row
(`gh repo clone <owner>/<repo> "$HOME/dd/<repo>"`; owner per CONVENTIONS §2 —
normally `ddoghq`).

### 4. Compute names and check existing assets (read-only)

- Resolve an existing task first (CONVENTIONS §3 *Resolving an existing task*);
  its folder name wins. Otherwise derive `<short-desc>` and the `TASK_SLUG`.
- For each asset, check whether it exists:
  - folder: `test -d "$HOME/w/<TASK_SLUG>"`; manifest: `test -f …/HANDOFF.md`
  - tmux: `tmux has-session -t "=w/<TASK_SLUG>" 2>/dev/null`; if alive, is an
    agent already running in **any** of its windows?
    `tmux list-panes -s -t "=w/<TASK_SLUG>" -F '#{window_index}.#{pane_index} #{pane_current_command}'`
    (an agent shows up as `claude`, `pi` or `node`; a free pane as `zsh`/`bash`)
  - worktrees: `git -C "$HOME/dd/<repo>" worktree list --porcelain` (compare
    with `realpath`) — right branch/ref?
  - branch: `git -C "$HOME/dd/<repo>" rev-parse --verify --quiet refs/heads/<branch>`
    and `git -C "$HOME/dd/<repo>" ls-remote --heads origin <branch>`
  - `pr-review`: if the PR head branch is already checked out somewhere (main
    checkout, or your own work worktree), **note it — don't reuse it**; the
    detached review worktree is created anyway (CONVENTIONS §4).
  - `page` with a fallback ID (`page-<monitor-id>`, `page-<date>`) that matches
    an existing task: same task only if `sources:`/`slack.thread_ts` match —
    otherwise ask: reuse, or a new slug with a `-2` suffix (CONVENTIONS §3).

### 5. Plan gate

Print a brief summary of the task (type, id, title, 3–5 lines of context),
then the **Action plan** (CONVENTIONS §6) with one row per asset, e.g.:

| # | Action                    | Target                                               | Kind     | Reversible |
| - | ------------------------- | ---------------------------------------------------- | -------- | ---------- |
| 1 | Workspace folder          | `$HOME/w/pr-review-dd-source-59188`                  | create   | yes        |
| 2 | HANDOFF.md + `context/`   | `$HOME/w/pr-review-dd-source-59188/`                 | create   | yes        |
| 3 | Fetch PR head             | `refs/pr-review/59188` in `dd-source`                | create   | yes        |
| 4 | Worktree (detached, no hooks) | `$HOME/dd/pr-review-dd-source-59188` @ `a1b2c3d` | create   | yes        |
| 5 | VS Code workspace         | `…/pr-review-dd-source-59188.code-workspace`         | create   | yes        |
| 6 | tmux session              | `w/pr-review-dd-source-59188`                        | reuse    | —          |
| 7 | Agent session (Claude)    | `pr-review-dd-source-59188` in tmux                  | create   | yes        |

Ask in the same round (structured question tool): **Proceed / Adjust /
Cancel**, and — if not obvious — the agent to launch: **Claude Code
(default)** or **pi**. Iterate on *Adjust* until approved.

### 6. Execute (in this order, skipping what already exists)

1. **Folder**: `mkdir -p "$HOME/w/<TASK_SLUG>/context"`.
2. **Captures**: save useful raw data under `context/` (e.g.
   `context/jira.md`, `context/pr.json`, `context/monitor.json`,
   `context/incident.json`, `context/slack-thread.md`).
3. **tmux session** (detached, never kill or rename an existing one):
   ```bash
   tmux has-session -t "=w/<TASK_SLUG>" 2>/dev/null \
     || tmux new-session -d -s "w/<TASK_SLUG>" -c "$HOME/w/<TASK_SLUG>"
   ```
4. **Worktrees** — per repo, with the exact commands in CONVENTIONS §4:
   - work types: `fetch origin <main>`, then attach the existing branch, track
     it from `origin`, or create it `--no-track` from `origin/<main>`
     (branch name per CONVENTIONS §3);
   - `pr-review`: fetch `refs/pull/<n>/head` into `refs/pr-review/<n>`, then
     `-c core.hooksPath=/dev/null worktree add --detach "$HOME/dd/<TASK_SLUG>" refs/pr-review/<n>`,
     then verify `HEAD == headRefOid`;
   - existing worktree path → reuse; verify its branch/ref matches, otherwise
     stop and ask;
   - any failure → stop and surface it; never work around it destructively.
5. **VS Code workspace** `$HOME/w/<TASK_SLUG>/<TASK_SLUG>.code-workspace`
   (create, or add missing folders to an existing one). Use **relative paths**
   (VS Code doesn't expand `${env:HOME}` in `folders[].path`, but resolves
   paths relative to the file):
   ```json
   {
     "folders": [
       { "path": "." },
       { "path": "../../dd/<repo>-<TASK_SLUG>" }
     ],
     "settings": {}
   }
   ```
   For `pr-review` the second entry is `../../dd/<TASK_SLUG>`.
6. **`HANDOFF.md`** following CONVENTIONS §5: front matter with every known
   field, then Summary, *Context gathered (verify it — don't trust it)*, Open
   questions, Suggested angles, Environment table, *What to do* ("Nothing yet —
   wait for the user's instructions"), and Log. Type-specific content:
   - `jira`: ticket fields and description, acceptance criteria, first code
     pointers you found.
   - `pr-review`: purpose, size, files grouped by area, CI state, existing
     reviews, linked ticket, areas that deserve attention.
   - `page`: monitor definition + link, trigger time and groups, current
     state, Slack thread highlights, suspected services/repos, first
     investigation angles.
   - `incident`: severity/state/roles, timeline so far, impact, impacted
     services, open threads in the channel, investigation angles.
   Write plain `key: value` lines (no template `# …` comments). If a
   `HANDOFF.md` already exists, never overwrite it. With front matter:
   fill empty fields, append to lists and to **Log** (a conflicting non-empty
   value → ask). Without front matter (legacy): prepend the front-matter block
   and append a `## Log` section; keep the existing body untouched.
7. **Agent session** — only if no agent is already running in any window of
   the tmux session (step 4). Target a pane by id: a free shell in a window
   named `agent`, else a new `agent` window. Run it as **one** command (shell
   variables don't survive between tool calls; a bare `=w/<TASK_SLUG>` is not a
   valid pane target):
   ```bash
   P=$(tmux list-panes -s -t "=w/<TASK_SLUG>" -F '#{window_name} #{pane_current_command} #{pane_id}' \
         | awk '$1=="agent" && ($2=="zsh"||$2=="bash") {print $3; exit}')
   [ -n "$P" ] || P=$(tmux new-window -d -P -F '#{pane_id}' -t "=w/<TASK_SLUG>:" -n agent -c "$HOME/w/<TASK_SLUG>")
   # Claude Code (default) — one-line first message, no single quotes inside it
   tmux send-keys -t "$P" 'cd "$HOME/w/<TASK_SLUG>" && claude --name "<TASK_SLUG>" "You are the dedicated session for task <TASK_SLUG> (<TASK_TYPE>). Read ./HANDOFF.md now. The environment is already bootstrapped: do not re-create assets. Reply with a 5-line summary of the task, then wait for my instructions. When I ask you to work on it, use the rpc-do-task skill."' Enter
   ```
   For pi, the same with the launch command
   `cd "$HOME/w/<TASK_SLUG>" && pi --session-id "<TASK_SLUG>" --name "<TASK_SLUG>" "<same message>"`
   (`--session-id` creates the session, or resumes it if it already exists).
   If a Claude Code session named `<TASK_SLUG>` already exists for this folder
   (a `"customTitle":"<TASK_SLUG>"` match in
   `~/.claude/projects/<folder path with / and . replaced by ->/*.jsonl`),
   resume it instead: `claude_session "$HOME/w/<TASK_SLUG>" "<TASK_SLUG>"`.

### 7. Report

A result table (created / reused / skipped / failed), plus:
- the workspace file to open: `cursor "$HOME/w/<TASK_SLUG>/<TASK_SLUG>.code-workspace"`
  (or `code`; for a cross-repository/fork PR recommend `code`, whose Workspace
  Trust opens untrusted code in Restricted Mode);
- the tmux session to attach: `tmux attach -t "w/<TASK_SLUG>"`;
- that the agent session `<TASK_SLUG>` (Claude Code or pi) is waiting for
  instructions, and that the work flow is `/rpc-do-task`.

## Add a repo to an existing task

Used when a task needs another worktree mid-flight (typically a `page` or
`incident` that turned into a code fix; `rpc-do-task` sends you here). Resolve
the task from its `HANDOFF.md`, then run steps 3–6 for the new repo only:
for `page`/`incident`, first offer to create or link a JIRA ticket (it goes
into the branch name, CONVENTIONS §3) → plan gate → fetch + worktree → add the
folder to the `.code-workspace` → add the repo (with its `branch`) to `repos:`
in the manifest and a Log line. Don't launch another agent session.

## Relationship to the other rpc-* skills

- **`rpc-handoff-task`** (this skill) — ensure the assets exist, capture
  context in `HANDOFF.md`, stage a waiting agent session. Bootstrap only.
- **`rpc-do-task`** — do the work inside that environment (implement, review,
  investigate, fix).
- **`rpc-wrapup-task`** — close the task: consistency/outcome review, JIRA or
  follow-ups, cleanup of worktrees/branches/tmux.
