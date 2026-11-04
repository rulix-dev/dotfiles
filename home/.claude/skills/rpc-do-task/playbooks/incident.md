# Playbook: incident (`incident`)

Help with a Datadog incident: understand where it stands, reconstruct the
timeline, find the cause, and produce the fix, follow-ups and write-ups the user
asks for. Use `playbooks/investigate.md` for tools, method and `NOTES.md`.

## 1. Snapshot (always first)

Refresh and show:
- title, **severity**, **state** (active / stable / resolved), customer impact;
- roles (commander, responders) and the user's role, if any;
- start / detection / mitigation / resolution times;
- impacted services and teams, linked monitors/pages;
- the latest updates and open threads in the incident Slack channel.

If the incident is **active**, focus on what helps mitigation now (evidence for
the responders, candidate causes, rollback candidates); root-cause depth comes
after.

## 2. Timeline

Reconstruct a UTC timeline in `NOTES.md` from the Datadog incident timeline,
the Slack channel, monitor/alert events, deploys and config changes. Mark each
entry's source. Flag gaps (e.g. "impact start unknown").

## 3. Investigate

Follow `playbooks/investigate.md` → *Method*, scoped to the impacted services
and window. Keep the hypotheses table current and tell the user after each
loop what changed.

## 4. Conclude

- Trigger, root cause and contributing factors (technical and process);
- impact quantified (who/what/how long);
- what detected it and how detection could be faster;
- open questions.

## 5. Deliverables — each one on request, through the Action plan gate

- **Status update** for the incident channel: draft (current state, what we
  know, next steps, ETA if any) → post only after explicit approval
  (`external` ⚠️).
- **Postmortem input**: draft sections (summary, timeline, root cause,
  contributing factors, what went well/badly, action items) in
  `$HOME/w/<TASK_SLUG>/POSTMORTEM.md`; publishing it anywhere is `external`.
- **Follow-up tickets**: draft each JIRA issue → create only after approval;
  link them in `HANDOFF.md`.
- **Code fix**: add the repo (`rpc-handoff-task` → *Add a repo to an existing
  task*) → `playbooks/implement.md`.
- **Monitor/alerting improvements**: as in `playbooks/investigate.md`.

## Rules

- Never change incident fields (severity, state, roles, impact, timeline)
  unless the user explicitly asks and approves the exact change.
- Don't speak for the incident commander; drafts are for the user to post.

Record decisions in the `HANDOFF.md` Log. When the incident is resolved and the
follow-ups are handled, suggest `/rpc-wrapup-task <TASK_ID>`.
