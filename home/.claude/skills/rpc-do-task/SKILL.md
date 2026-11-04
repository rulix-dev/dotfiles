---
name: rpc-do-task
description: Do the work of a task inside the environment bootstrapped by rpc-handoff-task — implement a JIRA ticket (explore → plan → TDD → implement), review a GitHub PR (orientation, your own comments, automated multi-agent review, draft GitHub review), or investigate a Datadog page or incident (triage → evidence → root cause → mitigation/fix/follow-ups). Resolves the task from an ID, URL, sentence or the current directory; asks when invoked without arguments. Autonomous for read-only work, one confirmation gate before any change (explicit per-action approval for external or destructive ones). Never commits, pushes, comments or posts unless explicitly asked.
---

# rpc-do-task

Do the actual work of a task whose environment already exists. Environment
setup (folder, tmux, worktrees, agent session, `HANDOFF.md`) is owned by
**`rpc-handoff-task`**; closing the task is **`rpc-wrapup-task`**.

**First, read `~/.claude/skills/rpc-handoff-task/CONVENTIONS.md`** (task
types, input detection, naming, `HANDOFF.md`, interaction contract, harness
notes).

## Invocation

`/rpc-do-task [anything]` — an ID, URL, `TASK_SLUG` or sentence, e.g.
`/rpc-do-task SDCD-2541`, `/rpc-do-task dd-go#20122`,
`/rpc-do-task incident-57516`, `/rpc-do-task` (from inside the task folder).

Resolution order:

1. **Argument given** → classify it (CONVENTIONS §2), then resolve the existing
   task (CONVENTIONS §3 *Resolving an existing task*).
2. **No argument, cwd inside a task** (`$HOME/w/<TASK_SLUG>/…` or a worktree
   listed in a manifest) → that task. State which one you picked.
3. **No argument, elsewhere** → list active tasks (`status: active` manifests
   and legacy folders — no `HANDOFF.md`, or one without front matter — most
   recently modified first) and ask which one (structured question tool; top 3
   as options, free text for anything else).

A PR link may be a task's own *work PR* rather than something to review —
check it as described in CONVENTIONS §2 *Work PRs*.

If the task has **no environment yet**, stop and propose
`/rpc-handoff-task <input>` first. Don't create assets ad hoc here.

## Step-by-step

### 0. Verify the environment

From `HANDOFF.md` (or the legacy folder conventions):
- the workspace folder exists;
- every worktree in `repos:` exists (compare with `realpath`) and is on its
  recorded `branch` (work types) or detached at the expected ref (`pr-review`);
- report anything missing or unexpected. To add a missing/new repo, follow
  `rpc-handoff-task` → *Add a repo to an existing task* (same conventions and
  plan gate) — never improvise paths or branch names.

Legacy task → offer to write a `HANDOFF.md` (plan gate: `create`), or to
prepend front matter to an existing one without touching its body (`modify`).

### 1. Load and refresh the context

- Read `HANDOFF.md` (+ `NOTES.md` / `REVIEW.md` / `context/` if present).
- Refresh the source to catch changes since the handoff (read-only): JIRA
  status/comments, PR head SHA/new commits/reviews/CI, monitor state, incident
  state/timeline, new Slack thread messages.
- Print a concise summary: what the task is, what changed since the handoff,
  current state of the assets.
- Ask: **"Anything else I should know before we start?"** and wait.

### 2. Follow the playbook for the task type

Read and follow the matching playbook (only the one you need):

| `TASK_TYPE`       | Playbook                                                      |
| ----------------- | ------------------------------------------------------------- |
| `jira`, `adhoc`   | `~/.claude/skills/rpc-do-task/playbooks/implement.md`          |
| `pr-review`       | `~/.claude/skills/rpc-do-task/playbooks/pr-review.md`          |
| `page`            | `~/.claude/skills/rpc-do-task/playbooks/page.md`               |
| `incident`        | `~/.claude/skills/rpc-do-task/playbooks/incident.md`           |

`page` and `incident` share `playbooks/investigate.md` (observability toolkit
and evidence standard); when they turn into a code fix they continue with
`playbooks/implement.md`.

### 3. Keep the manifest current

Scratch writes, no gate needed (CONVENTIONS §6.4):
- append decisions, findings and results to **Log** in `HANDOFF.md`;
- keep `repos:`, `jira:` and `prs:` (work PRs) in the front matter current;
- investigation notes go to `NOTES.md`, review drafts to `REVIEW.md`.

## Hard rules

- **Interaction contract** (CONVENTIONS §6): autonomous for read-only work, one
  **Action plan** gate before changes, iterate on *Adjust*, per-action approval
  for `external` ⚠️ and `destructive` ⛔ rows.
- **No commits, pushes, PRs, GitHub comments/reviews, Slack messages, JIRA
  changes or Datadog changes unless the user explicitly asks** — even after
  green tests or a finished review. Draft first, show it, then wait.
- **Datadog workspace**: commits/pushes and the `create-and-push-commit`
  conflict with the commit rules — CONVENTIONS §4 (ask before the first commit).
- **Commit format / branch naming**: CONVENTIONS §4.
- **Go / Bazel / diffs**: global `CLAUDE.md` rules (`go fmt`; in Bazel repos use
  the `running-bzl` agent, `:all` targets and Gazelle after import changes;
  `code --diff`/`cursor --diff` inside an IDE terminal).
- **Production is read-only for the agent**: propose rollbacks, restarts,
  scaling, flag flips or monitor mutes for the human to execute.

## Engaging the user

Explicit interaction points — don't skip them:
- after loading the context → "Anything else I should know?";
- before implementing or applying any change → the plan gate;
- before any commit, push, PR, comment, message or ticket change → explicit ask;
- whenever you infer services, repos or root causes → present the guess and the
  evidence, don't assume silently.

## When the work is done

Run **`/rpc-wrapup-task <TASK_ID>`** once the outcome is final (PRs merged,
review finished, page/incident resolved) to review consistency, handle
follow-ups/JIRA and clean up the environment.

## Relationship to the other rpc-* skills

- **`rpc-handoff-task`** — ensure the assets exist, capture context, stage a
  waiting agent session. Bootstrap only.
- **`rpc-do-task`** (this skill) — do the work inside that environment.
- **`rpc-wrapup-task`** — close the task: outcome/consistency review, JIRA and
  follow-ups, worktree/branch/tmux cleanup.
