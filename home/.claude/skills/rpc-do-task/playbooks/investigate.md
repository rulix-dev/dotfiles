# Investigation toolkit (shared by `page` and `incident`)

How to investigate production behaviour with evidence. Used by
`playbooks/page.md` and `playbooks/incident.md`.

## Principles

- **Evidence over intuition.** Every claim in `NOTES.md` links to the query,
  URL or command that shows it (Datadog link, log query, trace ID, commit SHA,
  Slack permalink). Mark anything unproven as a hypothesis.
- **Read-only.** Query freely; never mutate production, monitors, incidents or
  dashboards. Creating a Datadog notebook to share findings is `external` —
  only on request.
- **Time-box and narrate.** Work in short loops (question → query → finding)
  and tell the user what you learned after each loop, especially if the
  alert is still firing.
- **Scope to the right env/org/datacenter.** Monitors often cover several
  `env`/`datacenter` groups; confirm which ones triggered and query those.

## Setup

1. Datadog MCP skill discovery first (its server instructions require it):
   `load_datadog_skill` for the domain you need (e.g. `datadog/monitors`,
   `datadog/logs`, `datadog/traces`, `datadog/incidents`) **and**
   `list_datadog_skills` with a keyword query; load what matches.
2. Pick the **window**: from ~1 h before the trigger/impact start to now (or to
   recovery). Widen to days/weeks when checking whether the behaviour is new.
3. Collect the **coordinates**: `service`, `env`, `datacenter`/`region`,
   `team`, host/pod/cluster, monitor group tags, endpoint/resource names.

## Tool map (Datadog MCP unless noted)

| Question                                   | Where to look                                                                 |
| ------------------------------------------ | ----------------------------------------------------------------------------- |
| What exactly alerted?                      | `search_datadog_monitors(query: "id:<id>", include_tags: [...])` — definition, status, message, tags; per-group states with `search_datadog_monitor_groups` (needs the `alerting` toolset) |
| How often does it fire? Flapping?          | `search_datadog_events(query: "source:alert (@monitor_id:<id> OR monitor_id:<id>)")` over days/weeks; counts with `aggregate_events`; monitor edits with `source:monitor_audit_event` |
| Is it real or noise?                       | The monitored metric itself around the thresholds (`get_datadog_metric`), vs. its history |
| Error messages / failing code paths        | `search_datadog_logs`, `analyze_datadog_logs` (patterns, counts by tag)        |
| Latency / errors per endpoint, dependency  | `search_datadog_spans`, `aggregate_spans`, `get_datadog_trace`                  |
| What changed right before?                 | `search_datadog_events(query: "source:change_tracking …")` (deploys, config, flags), `search_dora_events` (deployments), `get_change_stories` if the toolset exposes it; `gh pr list --repo <owner>/<repo> --search "merged:>=<date>"`, `git log --since` |
| Infra saturation / restarts                | `get_datadog_metric` / `search_datadog_metrics` (CPU, memory, restarts, lag), `search_datadog_hosts`, `kubectl --context <ctx> get/describe/logs` (read-only; pass `--context`, never switch the global context) |
| Who owns it / which repo / blast radius    | `search_datadog_entities` (Software Catalog: owner, `links` of `type: repo`, contacts; relationships `current_oncalls`, `monitors`, upstream/downstream services) |
| Where is the monitor defined?              | Alert event tags `terraform_repo:` / `terraform_path:` (monitors as code); otherwise the UI (`creator` shows who/what manages it) |
| Related incidents / prior occurrences      | `search_datadog_incidents`; Slack search for the monitor name / error string   |
| Existing dashboards / notebooks            | `search_datadog_dashboards`, `search_datadog_notebooks`                         |

Some tools depend on the Datadog MCP toolsets enabled in the client
(`?toolsets=` on the server URL; `core` is the default). If a tool you need is
missing, say which toolset provides it and use the closest alternative
(deploys: `source:change_tracking` events; overall monitor state:
`search_datadog_monitors`).

## Method

1. **Confirm the symptom** with the raw signal (metric/log/trace), not just the
   alert text. Quantify: when it started, peak, current value, blast radius
   (orgs/customers/regions/endpoints affected).
2. **Correlate with change**: deploys, config/flag changes, traffic shifts,
   dependency incidents in the same window.
3. **Form hypotheses** and test each one with a query that could falsify it.
   Keep a table in `NOTES.md`:

   | # | Hypothesis | Evidence for | Evidence against | Confidence |
   | - | ---------- | ------------ | ---------------- | ---------- |

4. **Reach the code** when the evidence points there: find the failing path, the
   commit that introduced it, and its PR. Read it in the task worktree if there
   is one; otherwise from git objects — never from the main checkout's working
   tree, which may be on any branch: `git -C "$HOME/dd/<repo>" fetch origin <main>`,
   then `git -C "$HOME/dd/<repo>" grep -n '<pattern>' origin/<main> -- <path>`,
   `… show origin/<main>:<path>`, `… blame origin/<main> -- <path>`,
   `… log -S'<string>' origin/<main> -- <path>`. Prefer the deployed commit
   when a `version`/`git.commit.sha` tag is known (`git show <sha>:<path>`).
   For deeper work, add a worktree (`rpc-handoff-task` → *Add a repo to an
   existing task*).
5. **Conclude**: trigger vs root cause vs contributing factors, impact, whether
   it's resolved, and what would prevent recurrence.

## `NOTES.md` layout

```markdown
# <TASK_ID> — investigation notes

## Status (keep current)
<one paragraph: what we know now, what is still open>

## Timeline (UTC)
| Time | Event | Source |

## Findings
- <finding> — <link/query>

## Hypotheses
| # | Hypothesis | For | Against | Confidence |

## Conclusion
## Proposed actions
```

## Turning findings into actions

Present them as an **Action plan** (CONVENTIONS §6); typical rows:

- **Mitigation** (for the human to execute): rollback, restart, scale, flag
  flip, mute/downtime. Give the exact command/UI path; the agent does not run
  them.
- **Code fix**: add the repo to the task (`rpc-handoff-task` → *Add a repo to
  an existing task*), then `playbooks/implement.md`.
- **Monitor tuning**: threshold/window/recovery/no-data/notification changes.
  If the monitor is managed as code (`terraform_repo:`/`terraform_path:` tags,
  or a `creator` like "Terraform …"), change it in that repo (code-fix path);
  otherwise draft the exact change for the user to apply in the UI.
- **Follow-up ticket**: draft the JIRA issue (title, description, links,
  epic/labels) → `external` ⚠️.
- **Slack update**: draft the message for the thread/channel → `external` ⚠️.
- **Notebook**: summarize evidence in a Datadog notebook → `external` ⚠️.
