# Playbook: PR review (`pr-review`)

The user reviews the code themselves with the agent's help: orientation first,
then their own reading and comments, then (on request) an automated review.
Everything converges into a draft in `REVIEW.md`; publishing it to GitHub is an
`external` action that needs explicit approval.

Variables: `<owner>/<repo>`, `<n>`, worktree `WT=$HOME/dd/<TASK_SLUG>`,
`<base>` (PR base branch), review ref `refs/pr-review/<n>`. Always pass
`--repo <owner>/<repo>` to `gh`.

## 1. Sync the worktree with the PR

- Compare `git -C "$WT" rev-parse HEAD` with the PR's current `headRefOid`
  (`gh pr view <n> --repo <owner>/<repo> --json headRefOid,baseRefName,state,isDraft,mergedAt`;
  `<base>` = `baseRefName`, a bare branch name).
- PR updated since the handoff → re-run the fetch (CONVENTIONS §4), show the new
  commits with `git -C "$WT" log --oneline HEAD..refs/pr-review/<n>` (the review
  worktree's HEAD — never the main checkout's), and propose the refresh
  (`-c core.hooksPath=/dev/null checkout --detach`). Refresh only if
  `git -C "$WT" status --porcelain` is empty; never discard local changes.
- PR merged/closed → say so and ask whether to continue.
- Diff range for everything below (re-fetch `origin/<base>` first):
  `MB=$(git -C "$WT" merge-base HEAD origin/<base>)` → `git -C "$WT" diff "$MB"...HEAD`.
  This matches GitHub's view for an open PR. For a **merged** PR the head is
  already part of `origin/<base>`, so use the parent of the merge instead:
  `M=$(git -C "$WT" rev-list --ancestry-path --first-parent HEAD..origin/<base> | tail -1)`
  then `MB=$(git -C "$WT" merge-base HEAD "$M^1")`; fallback:
  `MB=$(git -C "$WT" merge-base HEAD "$(gh pr view <n> --repo <owner>/<repo> --json baseRefOid --jq .baseRefOid)")`.
  When in doubt, `gh pr diff <n> --repo <owner>/<repo>` is GitHub's own diff.

## 2. Orientation brief

Give the user a map before they read:
- **Purpose**: what the PR claims to do (title/body, linked ticket) in 2–3 lines.
- **Size and shape**: files changed grouped by area/package, additions/deletions,
  generated vs hand-written files, tests touched (`gh api --paginate
  repos/<owner>/<repo>/pulls/<n>/files` when there are more than 100 files).
- **Signals**: CI state (`gh pr checks <n> --repo <owner>/<repo>`), draft
  status, existing reviews, and review threads with their resolved/outdated
  state (the REST comments API has no resolved flag — use GraphQL):
  ```bash
  gh api graphql -F owner=<owner> -F repo=<repo> -F n=<n> -f query='
    query($owner:String!,$repo:String!,$n:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$n){
      reviewThreads(first:100){nodes{isResolved isOutdated path line
        comments(first:3){nodes{author{login} body url}}}}}}}'
  ```
- **Where to look first**: the riskiest hunks (concurrency, error handling,
  data migrations, API/contract changes, security-sensitive code, missing tests).
- **How to open it**: `cursor "$HOME/w/<TASK_SLUG>/<TASK_SLUG>.code-workspace"`
  (or `code`; for a cross-repository PR prefer `code`, whose Workspace Trust
  keeps untrusted code in Restricted Mode). Jump to a location with
  `code -g "$WT/<path>:<line>"` / `cursor -g …`. Per-file diff:
  `git -C "$WT" diff "$MB"...HEAD -- <path>`.

`REVIEW.md`: if it doesn't exist, create it (scratch write) with the skeleton
from §7. If it exists, **never recreate or overwrite it** — it holds the
user's comments and the Posted log; add a `## Round <k> — @ <short sha>`
section instead, and check **Posted** before offering to publish again.

## 3. Human review loop

While the user reads:
- answer questions about the code (read the worktree, trace callers, check
  history with `git log -p`/`git blame`, compare with `origin/<base>`);
- when the user dictates a comment ("comenta en foo.go:42 que…"), add it to
  `REVIEW.md` as a draft inline comment, **marked `source: you`**, and
  normalize the wording only if asked;
- running the PR's tests or builds executes its code with your credentials:
  do it only when the user asks or confirms the exact command (plan gate).
  If `isCrossRepository` is true, or the repo is public and the author is
  outside the org, say so and recommend against it. Never run
  `yarn`/`npm install`, `go generate` or `make` in the review worktree unless
  asked.

## 4. Automated review — when the user asks ("haz una review automática")

1. **Scope**: the diff range from §1, with full-file context from `$WT`.
2. **Run the review**:
   - **Claude Code**: use the built-in `code-review` skill on the PR (or on
     the `$MB...HEAD` range in `$WT`), at the effort level the user asks for.
     Optionally add specialised review agents that are available in the
     session for lenses it doesn't cover well (language-specific reviewers,
     test coverage, error handling) — run them in parallel on the same range.
   - **pi**: call `subagents_enable`, then launch one `subagent` per lens in
     parallel (correctness, error handling, tests, plus language-specific
     ones), using the definitions of the review agents of the installed Claude
     plugins as instructions when they exist (under each plugin's
     `installPath`, CONVENTIONS §7).
   Tell every reviewer/agent: repo path `$WT`, base `$MB`, PR purpose, the
   files in scope, and to report `file:line`, severity and a concrete failure
   scenario for each finding.
3. **Verify every finding** yourself against the code before keeping it: try
   to refute it (is the path reachable? is it handled elsewhere? is it
   pre-existing and untouched by this PR?). Drop false positives and
   out-of-scope nits; keep pre-existing issues only if the PR makes them worse.
4. **Deduplicate and rank**: `blocking` · `should-fix` · `nit` · `question` ·
   `praise`. Merge with the user's own comments (never drop or rewrite those
   silently).
5. **Write it to `REVIEW.md`** and present: findings table first, then the
   draft inline comments and the draft summary.

## 5. Iterate, then (only on request) publish

Iterate on the draft until the user is happy (edit/drop/add, tone, severity).
Publishing is `external` ⚠️ — show the exact payload and ask:

- **(a) Pending review (recommended)** — created on GitHub but visible only to
  the user; they submit it from the GitHub UI.
- **(b) Submit now as `COMMENT`.**
- **`APPROVE` / `REQUEST_CHANGES` only if the user explicitly asks for it.**

Before posting:
- a user can only have **one pending review per PR** — check with
  `gh api --paginate repos/<owner>/<repo>/pulls/<n>/reviews --jq '.[] | select(.state=="PENDING") | .id'`.
  If one exists, don't touch it: show its comments
  (`gh api --paginate repos/<owner>/<repo>/pulls/<n>/reviews/<id>/comments`)
  and let the user submit or discard it in the GitHub UI (or fold its
  comments into this draft) before posting;
- every inline comment must target a line that exists **in the PR diff**
  (validate against `gh pr diff <n> --repo <owner>/<repo>`; use the new-file
  line number with `side: RIGHT`, or `side: LEFT` for removed lines). Comments
  that don't map to a diff line move into the summary body;
- pin `commit_id` to the head SHA you reviewed; if the PR moved since, say so;
- keep internal context out: check `gh repo view <owner>/<repo> --json visibility`
  (CONVENTIONS §4 *Public repos*).

Post by writing the payload to `$HOME/w/<TASK_SLUG>/context/review-payload.json`:

```json
{
  "commit_id": "<headRefOid reviewed>",
  "body": "<summary>",
  "event": "COMMENT",
  "comments": [
    { "path": "pkg/foo/bar.go", "line": 42, "side": "RIGHT", "body": "<comment>" },
    { "path": "pkg/foo/baz.go", "start_line": 10, "line": 14, "side": "RIGHT", "body": "<multi-line comment>" }
  ]
}
```

(omit `"event"` for option (a) — the review stays `PENDING`), then:

```bash
gh api --method POST "repos/<owner>/<repo>/pulls/<n>/reviews" \
  --input "$HOME/w/<TASK_SLUG>/context/review-payload.json"
```

Record the review id/URL and state under **Posted** in `REVIEW.md` and in the
`HANDOFF.md` Log. Replies to existing threads
(`gh api --method POST repos/<owner>/<repo>/pulls/<n>/comments/<comment_id>/replies -f body=…`)
follow the same gate.

## 6. Own PR

If the PR author is the user (`gh api user --jq .login`), offer the choice:
post the findings as a self-review, or fix them directly. Fixes happen in the
work worktree of the task that owns the branch (see the related worktree noted
in `HANDOFF.md`, or `/rpc-do-task <that task>`) with `playbooks/implement.md` —
never commit on the detached review worktree.

**Rules**
- The review worktree is **read-only**: no commits, no pushes to the PR branch.
- Never resolve/dismiss other people's threads or reviews, and never delete a
  pending review.
- Keep internal context (Slack, incidents) out of GitHub comments unless the
  user explicitly includes it.

## 7. `REVIEW.md` skeleton

```markdown
# Review — <owner>/<repo>#<n> @ <short head sha>

## Draft summary (review body)

## Findings
| # | Severity | File:line | Finding | Source | Status |
| - | -------- | --------- | ------- | ------ | ------ |
|   |          |           |         | you / auto:<agent> | keep / drop / posted |

## Draft inline comments
### C1 — `path/to/file.go:42` (RIGHT)
<comment body>

## Questions for the author

## Posted
- <date> — review <id> (<PENDING|COMMENT|…>), <k> inline comments
```
