# Playbook: implement (`jira`, `adhoc`, and fixes from `page`/`incident`)

Explore → plan → test (TDD) → implement → verify → (on request) commit/PR →
(on request) integrate to staging. Work only inside the task's worktree(s).

## 1. Explore

- Read the relevant code in the worktree(s); share a short map of what matters
  for the task (entry points, data flow, tests that already cover it).
- For fixes coming from a `page`/`incident`: start from the evidence in
  `NOTES.md` (failing code path, error messages, offending change) and confirm
  it in the code before planning.

## 2. Plan

- Propose a plan: the change, files to touch, tests to add, risks, rollout
  notes (flags, backfills, staging).
- **Get explicit agreement** before writing code (Action plan gate). Iterate on
  *Adjust*.

## 3. Test first (TDD)

- Write failing tests first whenever feasible and show them failing. If TDD
  doesn't fit a step (config, wiring, generated code), say so and why.

## 4. Implement

- Make the tests pass with the smallest change that matches the plan and the
  surrounding code style.
- Go: `go fmt` changed files; Bazel repos (e.g. `dd-source`): `running-bzl`
  agent, `:all` target wildcard, Gazelle after import changes.

## 5. Verify and present

- Run the relevant tests/linters and report the actual results (paste failures).
- Show the diff (`code --diff` / `cursor --diff` in an IDE terminal, otherwise
  `git -C <worktree> diff --stat` + key hunks).
- Log the outcome in `HANDOFF.md`.

## 6. Commit / PR — only when the user explicitly asks

- Commit message: one line `<type>(<service>): <short description>`, no
  ticket reference; PR title adds `[<KEY>]` / `[INCIDENT-<n>]` after the colon
  (CONVENTIONS §4).
- Datadog workspace → `create-and-push-commit`, whose template conflicts with
  the one-line format: settle the approach with the user first (CONVENTIONS §4).
- Set the upstream on first push (a new branch was created `--no-track`).
- PR description: what/why/how-tested; link the ticket. Check the repo's
  visibility first (`gh repo view <owner>/<repo> --json visibility`): in a
  `PUBLIC` repo, no internal links, incident/page details or Slack excerpts;
  in private repos, link the incident/page when relevant but still no Slack
  excerpts. Add the PR to `prs:` in `HANDOFF.md`.

## 7. Integrate to staging — only when asked

1. Identify the affected service(s):
   - PR labels first (CI often adds `changes:<service>`):
     `gh pr view <pr> --repo <owner>/<repo> --json labels`
   - Missing/ambiguous → propose the service(s) you'd guess from the diff and
     **ask** the user to confirm or correct.
2. Post one PR comment per service (`external` — confirm the list first):
   ```bash
   gh pr comment <pr> --repo <owner>/<repo> --body "/integrate -dfs <service-name>"
   ```
3. A single PR may span multiple services — one comment per service unless the
   user says otherwise.
