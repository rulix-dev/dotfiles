# Playbook: page (`page`)

Understand a Datadog page (usually a monitor alert), decide whether it is real,
find the cause, and propose mitigation, fix or monitor tuning. Use
`playbooks/investigate.md` for tools, method and `NOTES.md`.

## 1. Situation first (always)

Before any deep dive, answer and show:
- **Is it still firing?** Current monitor state (Alert / Warn / OK / No Data),
  per group when the `alerting` toolset is available, since when, how many
  groups (otherwise infer groups from the latest alert/recover events).
- **Is someone on it?** Page acknowledged/resolved, who is active in the Slack
  thread, whether an incident was declared (if yes, suggest switching to an
  `incident` task or linking it).
- **Impact right now**: customer-facing or internal, which env/region.

If it is still firing and the user is on-call, **mitigation comes first**:
propose the quickest safe mitigation (for the human to run) before root-cause
work.

## 2. Understand the monitor

- Definition: type, query, thresholds (alert/warn/recovery), evaluation window,
  no-data behaviour, group-by, notification message, runbook links, tags,
  owner team.
- History: how often it has triggered recently (flapping? recurring daily?),
  typical value vs threshold. This decides between "real problem" and "noisy
  monitor".
- Record the monitor link, trigger time and triggering groups at the top of
  `NOTES.md`.

## 3. Investigate

Follow `playbooks/investigate.md` → *Method*, scoped to the triggering groups
and the trigger window. Typical first loop for a page:
1. plot the monitored metric/query around the trigger (± 1–2 h, then 7 d);
2. errors/logs for the service+env in that window;
3. changes right before (deploys, config, flags, dependency incidents);
4. saturation/restarts of the underlying infra.

Narrate after each loop; keep `NOTES.md` current.

## 4. Conclude

Present a short verdict:
- **Classification**: real problem · expected/transient · noisy monitor ·
  upstream/dependency · unknown (with what's missing).
- **Cause** (trigger and root cause), **impact**, **current state**.
- **Confidence** and the evidence links.

## 5. Propose actions (Action plan gate)

From `playbooks/investigate.md` → *Turning findings into actions*: mitigation
(human-executed), code fix, monitor tuning, follow-up JIRA ticket, and a Slack
thread update. For the Slack update, draft a concise message (status, cause,
next steps, links) and post only after explicit approval, replying **in the
page thread** (`thread_ts` from `HANDOFF.md`).

Record the decisions in the `HANDOFF.md` Log. When nothing else is pending,
suggest `/rpc-wrapup-task <TASK_ID>`.
