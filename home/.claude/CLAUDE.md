# Global Claude Code Preferences

## Git commits and pull requests

- Never include co-author information (e.g. `Co-Authored-By: Claude...`) in commit messages, PR titles, or PR descriptions.
- Commit messages must be a single line: `TICKET-ID: Short description` (e.g. `SDCD-1234: Fix go fmt`). No brackets around the ticket ID, no multi-line body, no file names or implementation details.
- Branch name should be raul.perezclavero/<short-desc>:
    - The <short-desc> part should contain the jira ticket ID we are working on. If no context about any jira ticket, simply say NO-TICKET-... and the rest of the description a very very brief desc of the changes done.

## Diffs

When running inside a VSCode/Cursor terminal (or any IDE with a `code` or `cursor` CLI available), show diffs visually using `code --diff` or `cursor --diff` instead of plain text in the terminal.

## Go

- After editing any Go files, run `go fmt` on the modified files to ensure correct formatting.
- When working in a repo that uses Bazel (e.g. dd-source), use the appropriate Bazel tooling instead of raw `go` commands:
  - Run tests with `:all` target wildcard (not `...`).
  - After adding/removing `.go` imports, run Gazelle: `bzl run //:gazelle -- update <dir>`
  - Use the `running-bzl` agent to run Bazel commands.
- In repos that don't use Bazel (e.g. dd-go), use standard `go` tooling.