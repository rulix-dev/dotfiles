# Global Claude Code Preferences

## Git commits and pull requests

- Never include co-author information (e.g. `Co-Authored-By: Claude...`) or the `Environment: Datadog workspace` trailer in commit messages, PR titles, or PR descriptions.
- Commit messages must be a single line in Conventional Commits style: `<type>(<service>): <short description>` (e.g. `fix(dora-intake): handle nil intake payload`). `<type>` is `feat`, `fix`, `hillclimb`, `refactor`, `perf`, `test`, `docs`, `chore`, `ci`, `build`… Omit `(<service>)` entirely when the change is not tied to a service (e.g. a library). The description says what that commit does. No ticket/incident reference, no multi-line body, no file names or implementation details.
- PR titles follow the same format, with the reference right after the colon: `<type>(<service>): [<JIRA-KEY>] <description>` for JIRA work, `[INCIDENT-<n>]` for incident work. Pages and no-ticket work get no reference in the title (`<type>(<service>): <description>`); a page is referenced in the PR description instead.
- Branch name should be raul.perezclavero/<short-desc>:
    - The <short-desc> part should contain the jira ticket ID we are working on. If no context about any jira ticket, simply say NO-TICKET-... and the rest of the description a very very brief desc of the changes done.
- Generally, avoid committing or pushing changes without explicit approval from user

## Diffs

When running inside a VSCode/Cursor terminal (or any IDE with a `code` or `cursor` CLI available), show diffs visually using `code --diff` or `cursor --diff` instead of plain text in the terminal.

## Go

- After editing any Go files, run `go fmt` on the modified files to ensure correct formatting.
- When working in a repo that uses Bazel (e.g. dd-source), use the appropriate Bazel tooling instead of raw `go` commands:
  - Run tests with `:all` target wildcard (not `...`).
  - After adding/removing `.go` imports, run Gazelle: `bzl run //:gazelle -- update <dir>`
  - Use the `running-bzl` agent to run Bazel commands.
- In repos that don't use Bazel (e.g. dd-go), use standard `go` tooling.