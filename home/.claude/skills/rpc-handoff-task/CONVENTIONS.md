# rpc-* task conventions

Shared by **`rpc-handoff-task`**, **`rpc-do-task`** and **`rpc-wrapup-task`**.
This file is the single source of truth for task types, input detection,
naming, the `HANDOFF.md` manifest and the interaction contract. The skills
reference it; they do not redefine these rules.

Path: `~/.claude/skills/rpc-handoff-task/CONVENTIONS.md`.

---

## 1. Task types

| `TASK_TYPE` | What it is                                                   | Typical deliverable                                   |
| ----------- | ------------------------------------------------------------ | ----------------------------------------------------- |
| `jira`      | A JIRA ticket to investigate and/or implement                | Code change → PR(s)                                   |
| `pr-review` | A GitHub PR to review (someone else's or your own)           | Review findings → (optionally) GitHub review comments |
| `page`      | A Datadog On-Call page / monitor alert                       | Triage + root cause → mitigation / fix / monitor tune |
| `incident`  | A Datadog incident                                           | Timeline + root cause → fix / follow-ups / postmortem |
| `adhoc`     | Anything else (no ticket, or a non-JIRA ticket like `ZD-…`)  | Whatever the user asks                                |

---

## 2. Input detection

The user may write in Spanish or English, paste a URL, an ID, or a sentence
("revisa la PR 1234 de dd-go", "mira este page <slack link>"). Extract every
identifier you can, then classify with the **first matching rule**:

| #  | Pattern (examples)                                                                                     | `TASK_TYPE`              |
| -- | ------------------------------------------------------------------------------------------------------ | ------------------------ |
| 0  | An existing `TASK_SLUG` or `TASK_ID` (`SDCD-2541-cd-vis-scaffolding`, `pr-review-dd-source-59188`, `page-9540074`, `NO-TICKET-…`) — see §3 *Resolving an existing task* | that task's type |
| 1  | GitHub PR URL `https://github.com/<owner>/<repo>/pull/<n>`                                               | `pr-review` (see *Work PRs* below) |
| 2  | `<owner>/<repo>#<n>`, `<repo>#<n>`, or "PR"/"pull request" + a number + a repo name (`dd-go 12345`)      | `pr-review` (see *Work PRs* below) |
| 3  | JIRA URL `https://datadoghq.atlassian.net/browse/<KEY>-<n>` (or `…?selectedIssue=<KEY>-<n>`)             | `jira`                   |
| 4  | Datadog incident URL `https://<dd-site>/incidents/<n>` (also `/incidents/<n>/pages`, `?from_related_incident=<n>`) | `incident`   |
| 5  | Incident references `IR-<n>`, `incident-<n>`, `#incident-<n>`, "incident/incidente <n>" — **checked before rule 11** | `incident`   |
| 6  | On-Call page URL `https://<dd-site>/on-call/pages/<n>`, `…/on-call/pages/<uuid>`, `…/on-call/pages?…page-identifier=<n>` | `page`       |
| 7  | "Page #<n>" / "page <n>" (a 6+ digit page number)                                                        | `page` (resolve like a page URL) |
| 8  | Monitor URL `https://<dd-site>/monitors/<id>[?…]` or any link with `link_monitor_id=<id>`                | `page`                   |
| 9  | Slack permalink `https://dd.slack.com/archives/<CHANNEL>/p<16 digits>` (host may also be `dd.enterprise.slack.com`) | read it → see below |
| 10 | Bare Slack channel ID (`C…`/`G…`, 9–11 uppercase alphanumerics)                                          | read it → usually `incident` |
| 11 | Bare ticket key `[A-Z][A-Z0-9]+-[0-9]+` (`SDCD-1234`)                                                    | `jira` (fallback: `adhoc`) |
| 12 | Keywords only: review/revisa/PR → `pr-review`; page/paged/alerta/monitor → `page`; incident/incidente → `incident` | ask for the identifier |

`<dd-site>` is any Datadog site host (`app.datadoghq.com`, `us3.datadoghq.com`,
`us5.datadoghq.com`, `app.datadoghq.eu`, `ap1.datadoghq.com`, custom
subdomains like `<org>.datadoghq.com`, or `support-admin.*.prod.dog`). Useful
extractions: monitor id `(?:/monitors/|link_monitor_id=)(\d+)`; page number
`/on-call/pages/(\d+)` or `page-identifier=(\d+)`; incident id
`/incidents/(\d+)`, `IR-(\d+)`, `incident-(\d+)`.

**Work PRs (rules 1–2, in `rpc-do-task` and `rpc-wrapup-task` only).** A PR
link may be the *work PR* of an existing task rather than a PR to review. Get
its head branch (`gh pr view <n> --repo <owner>/<repo> --json headRefName,title`);
if a manifest lists that branch or PR (§3 lookup on `branch:`/`prs:`), it is
that task. Legacy tasks record neither, so next strip `raul.perezclavero/` from
the branch and run the §3 folder lookup with the rest (`jira`/`adhoc`/legacy
branches are `raul.perezclavero/<TASK_SLUG>`; for `page`/`incident` also try it
without the leading `<KEY>-<n>-` or `NO-TICKET-`), then with any JIRA key found
in the branch or title. Only if nothing matches is it a `pr-review`.

**Slack permalinks (rules 9–10).** `…/archives/<CHANNEL>/p<10 digits><6 digits>`
→ message `ts` = `<10 digits>.<6 digits>` (`p1790628115045089` →
`1790628115.045089`). If the URL has `?thread_ts=<ts>`, the link points to a
**reply** and `thread_ts` is the parent: read the thread with the parent ts.
Read the message + thread (and, for a bare channel ID, the channel: its name
and topic), then decide:
- channel `#incident-<n>` (the Datadog bot's topic links the incident) →
  `incident` with id `<n>`; a page "created from incident IR-<n>" is also an
  `incident`;
- a Datadog bot attachment `Page #<n>: <title>` with "Triggered by … a
  monitor", or a monitor notification `Triggered: <title> (…monitors/<id>…)`
  → `page`;
- otherwise (e.g. a teammate's "paged again, see <link>") apply rules 1–8 to
  every URL in the message and in its thread parent; ask only if none match.

If a Slack read fails (`channel_not_found`: private or not joined), ask the
user to paste the message text or the page/monitor link.

**Ticket keys (rule 11).** Fetch the key from JIRA. If JIRA has no such issue
(e.g. `ZD-2981177` is a Zendesk ticket, not JIRA), ask; if the user confirms it
is not JIRA, use `adhoc` with that key as `TASK_ID`.

**GitHub owner.** Datadog repos moved from the `DataDog` GitHub org to
**`ddoghq`** (`gh … --repo DataDog/dd-go` no longer resolves). Always take
`<owner>/<repo>` from the local clone's remote —
`git -C "$HOME/dd/<repo>" remote get-url origin` →
`git@ddoghq.github.com:ddoghq/dd-go.git` → `ddoghq/dd-go`. No local clone →
default to `ddoghq`, and ask when unsure. Always pass `--repo <owner>/<repo>`
to `gh`: agent sessions run from `$HOME/w/<TASK_SLUG>`, which is not a git
repo.

**PR numbers did not move with the repos**: ddoghq repos restarted their
numbering and the old org can't be queried, so a pasted
`github.com/DataDog/<repo>/pull/<n>` link is a pre-migration PR — **never
reuse `<n>` in ddoghq** (it is missing or an unrelated PR). Find the ddoghq PR
by head branch or title (`gh pr list --repo ddoghq/<repo> --state all --head <branch>`
or `--search "<JIRA key or title words>"`) or ask for the ddoghq link; if there
is none, say the PR only exists in the old org. Always show the resolved PR's
title and author before building assets or posting anything.

If after this pass the type or a required identifier is still unknown, **ask**
(see §6). Never guess an ID.

---

## 3. Canonical names

`<short-desc>` is derived from the title (ticket summary, PR title, monitor
name, incident title): lowercase ASCII, words joined with `-`, drop
articles/filler, ~3–5 tokens (`cd-vis-scaffolding`). The user confirms it as
part of the handoff plan.

| `TASK_TYPE` | `TASK_ID` (lookup key)          | `TASK_SLUG`                        | Example `TASK_SLUG`                      |
| ----------- | ------------------------------- | ---------------------------------- | ---------------------------------------- |
| `jira`      | `<KEY>-<n>`                     | `<TASK_ID>-<short-desc>`           | `SDCD-2541-cd-vis-scaffolding`           |
| `pr-review` | `pr-review-<repo>-<n>`          | `<TASK_ID>` (no desc)              | `pr-review-dd-source-59188`              |
| `page`      | `page-<page-number>`            | `<TASK_ID>-<short-desc>`           | `page-9540074-dora-intake-lag`           |
| `incident`  | `incident-<public-id>`          | `<TASK_ID>-<short-desc>`           | `incident-57516-cc-enricher-killswitch`  |
| `adhoc`     | `NO-TICKET` or external key     | `<TASK_ID>-<short-desc>`           | `NO-TICKET-dora-resizable-columns`       |

`page` IDs: prefer the On-Call page number (`Page #9540074`); for a plain
monitor alert with no page, use `page-<monitor-id>`; with neither,
`page-<YYYYMMDD>`. The manifest records all of them (§5). These fallback IDs
are not unique: an existing task only counts as the same one if its `sources:`
or `slack.thread_ts` match the new input — otherwise ask whether to reuse it or
create a new slug with a `-2` (`-3`, …) suffix.

Derived assets — identical for every type unless noted:

| Asset                  | Value                                                                      |
| ---------------------- | -------------------------------------------------------------------------- |
| Workspace folder       | `$HOME/w/<TASK_SLUG>`                                                      |
| Manifest               | `$HOME/w/<TASK_SLUG>/HANDOFF.md` (§5)                                      |
| Raw context captures   | `$HOME/w/<TASK_SLUG>/context/`                                             |
| Working notes          | `$HOME/w/<TASK_SLUG>/NOTES.md` (investigations) · `REVIEW.md` (PR reviews) |
| tmux session           | `w/<TASK_SLUG>`                                                            |
| Agent session name     | `<TASK_SLUG>` (Claude Code or pi, §7)                                      |
| VS Code workspace      | `$HOME/w/<TASK_SLUG>/<TASK_SLUG>.code-workspace`                           |
| Worktree (work types)  | `$HOME/dd/<repo>-<TASK_SLUG>` — one per repo                               |
| Worktree (`pr-review`) | `$HOME/dd/<TASK_SLUG>` — the slug already contains the repo                |
| Branch (`jira`, `adhoc`) | `raul.perezclavero/<TASK_SLUG>`, new, from the tip of `origin/<main>`    |
| Branch (`page`, `incident` fixes) | `raul.perezclavero/<TICKET>-<TASK_SLUG>` — `<TICKET>` = the linked JIRA key, else `NO-TICKET` (the global `CLAUDE.md` wants a ticket or `NO-TICKET` in branch names) |
| Branch (`pr-review`)   | none — the worktree is **detached** at the PR head (§4)                    |

"Work types" = `jira`, `adhoc`, and `page`/`incident` once a code fix is needed.
`page`/`incident` start without worktrees unless a candidate repo is already
clear; repos can be added later (see `rpc-handoff-task` → *Add a repo to an
existing task*). The branch actually used is always recorded in the manifest
(`repos[].branch`) — read it from there instead of recomputing it.

### Resolving an existing task

Look up by every identifier you extracted (`TASK_ID`, ticket key, PR, monitor
id, page number, incident id, pasted URL), in this order. Use `find`, not
`ls` with globs: the shell is often zsh, where a glob that matches nothing
aborts the whole command.

1. Manifests (front-matter fields and list items; tolerates trailing `# …`
   comments, and a numeric ID must follow a separator so `59188` doesn't match
   `#159188`):
   ```bash
   find "$HOME/w" -mindepth 2 -maxdepth 2 -name HANDOFF.md -exec grep -l -E \
     '^(task_id|task_slug|jira|pr|monitor_id|page_number|incident_id): *"?<ID>"?( +#.*)? *$|^ *(- |branch: |worktree: )"?([^ ]*[/#=:-])?<ID>"?( +#.*)? *$' {} +
   ```
   Escape ERE metacharacters in `<ID>` (`.`, `?`, `+`) when it is a pasted
   URL, or search by the IDs extracted from it.
2. Folder names:
   ```bash
   find "$HOME/w" -mindepth 1 -maxdepth 1 -type d \( -name '*<ID>' -o -name '*<ID>-*' \)
   ```
   (the `-*` form keeps `SDCD-123` from matching `SDCD-1234`).

An existing folder's name **wins** over a freshly derived slug. More than one
match (e.g. `SDCD-2992-g1-spark-validation` and `SDCD-2992-otel-ai-impact-scope`)
→ ask which one. From inside a task (cwd under `$HOME/w/<TASK_SLUG>` or inside
a worktree listed in a manifest), that task is the default.

**Legacy workspaces** — created by the old `rpc-*-jira-task` skills — have
either no `HANDOFF.md` or a `HANDOFF.md` **without front matter** (its first
line is not exactly `---`). Infer the type from the folder name —
`<KEY>-<n>-…` → `jira` (or `adhoc` if JIRA doesn't know the key, e.g. `ZD-…`),
`incident-<n>-…` → `incident`, `pr-review-<repo>-<n>` → `pr-review`,
`NO-TICKET-…` → `adhoc` — and find worktrees with
`find "$HOME/dd/" -mindepth 1 -maxdepth 1 \( -name '*-<TASK_SLUG>' -o -name '<TASK_SLUG>' \)`
(trailing slash: `$HOME/dd` may be a symlink). To upgrade a legacy task,
**prepend** a front-matter block (and append a `## Log` section if missing) —
never rewrite the existing body. That is a *modify* action (§6).

---

## 4. Environment facts and git rules

- **`$HOME/dd` may be a symlink** (Datadog workspaces: `$HOME/dd` →
  `$HOME/go/src/github.com/DataDog`). `git worktree list` prints physical
  paths; compare paths with `realpath`, not string equality.
- **Main branch** of a repo — `<main>` is the bare branch name:
  `git -C "$HOME/dd/<repo>" symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##'`
  (→ `main`, `master` or `prod`). If unset, check which of those exists with
  `git -C "$HOME/dd/<repo>" ls-remote --heads origin main master prod`.
- **Never touch the main checkout.** Other sessions (and other people's
  branches) may be checked out in `$HOME/dd/<repo>`. Do not `checkout`, `pull`,
  `stash` or `reset` it, and don't read its working tree as "the code" (it may
  be on any branch). Only `git fetch`, then use remote-tracking refs: branch
  from them, or read code from git objects
  (`git -C "$HOME/dd/<repo>" show origin/<main>:<path>`, `git grep … origin/<main>`).
- **New work branch + worktree** (`<branch>` per §3):
  ```bash
  git -C "$HOME/dd/<repo>" fetch origin <main>
  # branch already exists locally → attach it
  git -C "$HOME/dd/<repo>" worktree add "$HOME/dd/<repo>-<TASK_SLUG>" "<branch>"
  # branch exists only on origin (pushed from another machine) → track it
  git -C "$HOME/dd/<repo>" fetch origin "<branch>"
  git -C "$HOME/dd/<repo>" worktree add --track -b "<branch>" "$HOME/dd/<repo>-<TASK_SLUG>" "origin/<branch>"
  # new branch → from the tip of origin/<main>, without tracking it
  # (tracking origin/prod is a push footgun; set the upstream on first push)
  git -C "$HOME/dd/<repo>" worktree add --no-track -b "<branch>" "$HOME/dd/<repo>-<TASK_SLUG>" "origin/<main>"
  ```
  Check which case applies with
  `git -C "$HOME/dd/<repo>" rev-parse --verify --quiet "refs/heads/<branch>"` and
  `git -C "$HOME/dd/<repo>" ls-remote --heads origin "<branch>"`.
- **PR review worktree** — detached (works for fork PRs, leaves no local
  branch), always created fresh, and **with git hooks disabled** (a relative
  `core.hooksPath` such as web-ui's `.husky` would run `yarn install` or the
  PR's own hook scripts, i.e. unreviewed code):
  ```bash
  git -C "$HOME/dd/<repo>" fetch origin "+refs/pull/<n>/head:refs/pr-review/<n>" "<base>"
  git -C "$HOME/dd/<repo>" -c core.hooksPath=/dev/null \
    worktree add --detach "$HOME/dd/<TASK_SLUG>" "refs/pr-review/<n>"
  ```
  Verify `git -C "$HOME/dd/<TASK_SLUG>" rev-parse HEAD` equals the PR's
  `headRefOid`. Refresh after new pushes: re-run the fetch, then — only if the
  worktree is clean —
  `git -C "$HOME/dd/<TASK_SLUG>" -c core.hooksPath=/dev/null checkout --detach refs/pr-review/<n>`.
  Diff base: `git -C <worktree> merge-base HEAD origin/<base>` (for a merged
  PR see `rpc-do-task` → `playbooks/pr-review.md`). If the PR's head branch
  is already checked out elsewhere (the main checkout, or another task's work
  worktree for your own PR), **still create the detached review worktree** — it
  doesn't conflict — and never record someone else's checkout in `repos:`;
  mention the other task's worktree in the HANDOFF body as a related worktree.
  Installing dependencies, building or running tests in a review worktree runs
  the PR's code: that is a separate, confirmed action.
- **Datadog workspace** (`IN_WORKSPACE=1`): the workspace asks for commits and
  pushes to go through the `create-and-push-commit` skill (workspaces plugin).
  Its template **conflicts with the commit rules below and with the global
  `CLAUDE.md`**: it adds a body plus `Environment: Datadog workspace` and
  `Co-Authored-By: Claude …` trailers, and its re-signing path runs
  `git reset --hard` in the worktree. Before the first commit of a task, point
  the conflict out and let the user choose the approach; never run that path
  on a dirty worktree. Its `OWNER_REPO` sed doesn't parse
  `git@ddoghq.github.com:…` remotes — set `OWNER_REPO=<owner>/<repo>` (§2)
  yourself.
- **Go / Bazel / diffs**: follow the global `CLAUDE.md` rules (`go fmt`, Bazel
  `:all`, Gazelle, `running-bzl` agent, `code --diff`/`cursor --diff`).

### Commits, branches and PRs

- Commit message: one line, `<type>(<service>): <short description>`
  (Conventional Commits: `feat`, `fix`, `hillclimb`, `refactor`, `test`,
  `chore`…; drop `(<service>)` when not tied to a service, e.g. a library),
  describing what that commit does. **No ticket or incident reference**, no
  `Co-Authored-By` or `Environment:` trailers, no body. `<service>`: the PR's
  `changes:<service>`
  label or the Software Catalog service; ask when unsure.
- PR title: same format, with the reference after the colon —
  `jira` (and `adhoc` with an external key) → `<type>(<service>): [<KEY>] <description>`;
  `incident` → `[INCIDENT-<n>]`; `page` and `NO-TICKET` → no reference
  (link the page, and the incident/ticket, in the PR description). Public
  repos: no `[INCIDENT-<n>]` either (see below).
- For `page`/`incident` fixes, offer to create or link a JIRA ticket before
  creating the branch (an *external* action, §6); it goes into the branch name.
- Branch: exactly as in §3. Never invent variations.
- **Public repos**: before writing a PR description, commit message or review
  comment, check `gh repo view <owner>/<repo> --json visibility`. For `PUBLIC`
  repos (e.g. `datadog-agent`, `integrations-core`), never include internal
  links, Slack excerpts, incident/page details or customer data.

---

## 5. `HANDOFF.md` — the task manifest

Written by `rpc-handoff-task`, read by `rpc-do-task` and `rpc-wrapup-task`,
kept current as the task evolves. YAML front matter (machine-readable, one key
per line so it can be grepped; the file's first line is exactly `---`) + a
human-readable body. Paths are written as `$HOME/…` (never `~`), so they can
be used as-is inside double-quoted shell commands.

```markdown
---
task_type: pr-review            # jira | pr-review | page | incident | adhoc
task_id: pr-review-dd-source-59188
task_slug: pr-review-dd-source-59188
title: "Add retry to DORA intake client"
status: active                  # active | done
agent: claude                   # claude | pi
created: 2026-09-29
sources:                        # every URL/ID the task came from
  - https://github.com/ddoghq/dd-source/pull/59188
jira: SDCD-1234                 # linked ticket, if any
pr: ddoghq/dd-source#59188      # pr-review only: the PR under review
prs:                            # work PRs opened by this task
  - ddoghq/dd-go#239466
page_number: 9540074            # page only (On-Call "Page #N"), if any
monitor_id: 294586644           # page (and incidents triggered by a monitor)
monitor_group: "datacenter:us1.prod.dog,service:foo"   # triggering group, if known
incident_id: 57516              # incident only (IR-57516)
slack:                          # page/incident: where the conversation lives
  channel: C0123456789
  thread_ts: "1784126564.295089"
repos:
  - name: dd-source
    github: ddoghq/dd-source
    worktree: $HOME/dd/pr-review-dd-source-59188
    branch: null                # work types: the branch from §3
    ref: refs/pr-review/59188   # pr-review only
    base: main                  # bare branch name (<main> / PR baseRefName)
    started_at: 2ae6609ed63f    # commit the worktree was created at
---

# <TASK_ID> — <title>

Handoff prepared <date> by `rpc-handoff-task`.
**Your environment is already bootstrapped — do not re-create assets.**

## Summary
<what this is about, in one paragraph>

## Context gathered (verify it — don't trust it)
<type-specific facts with links: ticket body, PR metadata, monitor query and
state transitions, incident timeline, Slack thread highlights, code pointers>

## Open questions
## Suggested angles / next steps
## Environment
<table: TASK_SLUG, folder, tmux, agent session, worktrees, branches/refs, base
commit, related worktrees owned by other tasks>

## What to do
Nothing yet — wait for the user's instructions. Work flow: `/rpc-do-task`.

## Log
- <date> handoff: created …
```

Rules:
- The `# …` comments above document the template: **don't copy them** into
  real manifests (one plain `key: value` per line keeps the §3 lookup simple).
- Keep secrets out of it. Internal data (Slack excerpts, incident details) is
  fine in `$HOME/w/…`, but **never copy these files into a repo or PR**.
- Update front matter by filling empty fields, appending to lists (`sources`,
  `prs`, `repos`) and changing `status`. **Never silently change a non-empty
  value** — a conflicting value means ask.
- `rpc-do-task` appends key decisions/results to **Log** and keeps `repos:` and
  `prs:` current; `rpc-wrapup-task` sets `status: done` and appends the
  wrap-up summary.

---

## 6. Interaction contract (all three skills)

The user wants the agent to run **autonomously for everything read-only**, and
to **stop at one clear confirmation gate before acting** — iterating on the
proposal as many times as needed.

1. **Parse first.** With arguments, infer everything you can (§2) and resolve
   it with read-only calls before asking anything.
2. **No arguments → ask**, except `rpc-do-task` run from inside a task (cwd
   under `$HOME/w/<TASK_SLUG>` or a manifest worktree): it uses that task and
   says so. Otherwise present the options with the structured question tool
   (§7): task type and identifier, or — for `do`/`wrapup` — the discovered
   existing tasks (recommended option first; the current task, if any, is the
   recommended option for `wrapup`).
3. **Ask only what is still unclear**, batched (≤ 4 questions per round), with
   a recommended option first. Don't ask what you can look up.
4. **Read-only work needs no confirmation**: MCP reads, `gh … view/list/diff`,
   `gh api` GETs, `git fetch`/`log`/`diff`, `find`, reading files. Neither do
   **scratch writes** in the task's own folder (`HANDOFF.md` Log, `NOTES.md`,
   `REVIEW.md`, `POSTMORTEM.md`, `context/`) — but they only create missing
   files, append, or update their own sections: **never overwrite an existing
   file as a whole**.
5. **Plan gate before any other write.** Present an **Action plan** table:

   | # | Action | Target | Kind | Reversible |
   | - | ------ | ------ | ---- | ---------- |

   `Kind` is one of:
   - `create` — new local asset (folder, worktree, branch, tmux, file);
   - `modify` — change to existing local state (code edits, config);
   - `external` ⚠️ — visible to others: GitHub (comments, reviews, pushes, PRs,
     labels), Slack messages, JIRA (create/edit/transition/comment), Datadog
     (monitors, incidents, notebooks), Confluence;
   - `destructive` ⛔ — deletes or discards something: worktree removal, branch
     or ref deletion, killing a tmux session, overwriting files.

   Then ask **Proceed / Adjust / Cancel**. On *Adjust*, revise and show the
   plan again. Code edits inside the task's own worktree that follow an
   already-approved implementation plan don't need a new gate per edit.
   Running a PR's code (tests, builds, installs in a review worktree) is a
   `modify` row of its own, because it executes unreviewed code.
6. **`external` and `destructive` actions are listed one per row** and
   highlighted. `destructive` ones need **per-action** confirmation (y/n),
   unless the user explicitly approves "all". An approval covers only the
   actions shown — anything new needs a new gate.
7. **Report after executing**: a result table (done / skipped / failed + why)
   and the suggested next step.
8. **Never, without explicit approval in this conversation**: commit, push,
   open/update a PR, post GitHub comments or reviews, send Slack messages,
   create/edit/transition JIRA issues, change Datadog monitors/incidents.
   Read-only phases must not call write tools "just to look" (e.g. Datadog
   `update_datadog_incident`, the On-Call paging API — it only has write
   endpoints —, Slack send/reaction tools). **Never ever**: `--force` worktree
   removal, `git reset --hard`, `git stash`, `git checkout -- <file>`,
   `rm -rf` of task assets, deleting `$HOME/w/<TASK_SLUG>`, switching the
   global kubectl context (`kubectl config use-context`/`set-context` — pass
   `--context` instead), executing production-changing operations (rollbacks,
   scaling, restarts, feature-flag flips) — propose them for the human to run.
9. **Proposals are drafts.** Findings, review comments, fixes, Slack updates
   and JIRA text are shown in full before they are applied, and revised until
   the user is happy.

---

## 7. Harness notes (Claude Code and pi)

These skills are loaded by Claude Code (`~/.claude/skills`) and by pi (via the
`skills` setting in `~/.pi/agent/settings.json`). Refer to tools by what they
do, then use the local name:

| Capability                | Claude Code                                          | pi                                                                |
| ------------------------- | ---------------------------------------------------- | ----------------------------------------------------------------- |
| Structured questions      | `AskUserQuestion`                                    | `ask_user_question` (`@juicesharp/rpiv-ask-user-question`)        |
| MCP tools                 | `mcp__<server>__<tool>` (load via `ToolSearch`)      | `<server>_<tool>` when the server has `directTools`, otherwise through the `mcp` proxy tool |
| Subagents                 | `Agent` tool (e.g. `pr-review-toolkit:*` agents)     | `subagent` tool (`pi-subagents`; call `subagents_enable` first), giving it the Claude agent's definition file as instructions. Bridged `/<plugin>:agent:<name>` prompt templates can only be typed by the user |
| Invoke a skill            | `/<skill> <args>`                                    | `/skill:<skill> <args>` (args are appended; no `$ARGUMENTS`)       |
| Start a session           | `claude --name "<TASK_SLUG>" "<first message>"`      | `pi --session-id "<TASK_SLUG>" --name "<TASK_SLUG>" "<first message>"` |
| Resume it                 | `claude_session "$HOME/w/<TASK_SLUG>" "<TASK_SLUG>"` | `cd "$HOME/w/<TASK_SLUG>" && pi --session-id "<TASK_SLUG>"` (sessions are per directory) |

If no structured-question tool is available, print numbered options and wait.
Launch agent sessions from the workspace folder `$HOME/w/<TASK_SLUG>`, not from
a repo: a repo-level `.mcp.json` overrides same-named MCP servers (e.g. the
Atlassian OAuth "issuer mismatch" in pi).

Claude plugin definitions live under each plugin's `installPath`
(`jq -r '.plugins["<plugin>@<marketplace>"][0].installPath' ~/.claude/plugins/installed_plugins.json`),
e.g. `…/agents/code-reviewer.md` for `pr-review-toolkit`. In pi, the
workspaces plugin's skills (e.g. `create-and-push-commit`) are bridged by the
dotfiles config.

MCP servers used here: **Atlassian** (JIRA/Confluence), **Datadog**
(monitors, incidents, logs, metrics, traces, events, catalog), **Slack**
(messages, threads, channels), plus `gh` for GitHub. Server names and enabled
toolsets come from the local config, not from these skills: discover them from
the available tools instead of assuming names. If several Datadog servers are
configured (one per site), use the one matching the site of the task's URLs,
defaulting to US1. For the Datadog MCP, do its skill discovery first
(`load_datadog_skill` + `list_datadog_skills`) as its server instructions
require. When a tool is missing, say which toolset provides it and use the
closest alternative.
