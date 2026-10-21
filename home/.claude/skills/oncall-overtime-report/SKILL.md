---
name: oncall-overtime-report
description: Build an on-call overtime (intervention) report in a Google Sheet from Datadog On-Call pages. Collects pages that fired outside working hours (09:00-18:00) for an on-call week, applies the overlap/30-minute-gap aggregation policy from the Datadog Global On-Call Policy - Spain Supplement, and writes a day-grouped tab with per-day and per-week totals plus the recovery-days calculation. Use when the user asks for an on-call overtime report, intervention hours, recovery days, pages outside working hours, or says /oncall-overtime-report.
---

# On-Call Overtime Report

Builds the intervention report used to declare on-call overtime and claim recovery days.

Policy source: [Datadog Global On-Call Policy - Spain Supplement](https://docs.google.com/document/d/1vWRWqPr6mtdzTfyVU385BjRvxcg7hHkOiSg3CnOpS4c/edit).
Key clauses this skill implements:
- Working hours are **09:00 to 18:00**. Only time outside that window counts.
- "You should only declare **one intervention per day**. You need to aggregate all intervention periods and round the number to the highest figure." (Example in the doc: three pages totalling 45 min on one day is declared as 1 hour.)
- Intervention compensation is **time in lieu at 175%** of the intervention's duration.

## Inputs

| Input | Default |
|---|---|
| Google Sheet | **Ask the user if not supplied.** Accepts a full URL or a bare spreadsheet ID. |
| Period | Current on-call week: **Monday 09:00 → following Monday 09:00**, local time (Europe/Madrid). |
| Slack channel (page source) | `#sw-delivery-oncall` (`C0BA1NTCB2Q`) |
| Responder filter | The current user only. Resolve their name once, then drop pages answered by anyone else. |

If the user gives an explicit period ("last week", a date range), use that instead. Resolve "current week" from the real current date — compute it, never assume.

## Step 1 — Resolve the period

```bash
date                                   # current local time + timezone
date -j -f "%Y-%m-%d %H:%M:%S" "<monday> 09:00:00" +%s
```

Confirm the resolved window back to the user in one line before writing anything.

## Step 2 — Collect the pages

The On-Call list endpoint (`/api/v2/on-call/pages`) **ignores `filter[team]`** and returns all 10,000 pages in the org, so it cannot be used to scope by team. Use the Slack channel as the scope instead, then resolve each page through the API.

1. Read the channel over the window (paginate; `limit` is 100 per call):

   `slack_read_channel(channel_id="C0BA1NTCB2Q", oldest=<epoch>, latest=<epoch>, response_format="concise")`

   Double-check the `oldest` epoch you pass — an off-by-one-window mistake here silently truncates the report.

2. Extract every `app.datadoghq.com/on-call/pages/<id>` link. Note that pages **forwarded by a person** (rather than posted by the Datadog bot) still count; their link may be missing from the concise dump, so re-read those messages in `detailed` format if a human message looks like a forward.

3. Resolve each page through the API, which is the **only** source of truth for times:

```bash
dd-auth --domain app.datadoghq.com -- bash -c '
for id in <IDS>; do
  curl -s -H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY" \
    "https://api.datadoghq.com/api/v2/on-call/pages/$id?include=responders"
  echo
done'
```

Fields: `attributes.created_at` (trigger), `attributes.closed_at` (resolved), `attributes.status`,
and the responder name from `included[]` where `type == "users"`, matched against
`data.relationships.responders.data[].id`.

**Never use the Slack message timestamp.** It lags the page by seconds and Slack never carries a resolution time at all.

## Step 3 — Filter and assign to days

Apply in this order:

1. **Responder** — keep only pages where the current user is a responder.
2. **Outside working hours** — keep only pages whose **trigger** time has `hour < 9 or hour >= 18`.
3. **Day assignment** — each page belongs to the day its **`closed_at`** falls on, not its trigger day.
4. **Period membership** — also decided by `closed_at`. A page triggered before the window but closed inside it belongs to this report; one triggered inside but closed after the window belongs to the next one. State explicitly in the summary when either happens.
5. **Still open** — a page with no `closed_at` has no day, so it cannot be placed. List these separately under a `PENDING` heading below the totals, with no minutes, and tell the user they must be re-run once closed.

Known edge cases the user has accepted — apply the rules literally and flag them in the summary rather than inventing special handling:
- A page crossing midnight (e.g. 23:30 → 00:15) lands on the following day, so its minutes round into that day.
- Two pages where one crosses midnight and another closes before it will overlap across the day boundary and be counted as overlapping.

## Step 4 — The aggregation policy

Round every timestamp down to the minute (seconds to zero) before any arithmetic.

Pages are treated as **one continuous intervention block** when either:
- they **overlap** (a page starts before the previous one ended), or
- the **gap between them is under 30 minutes** — a sub-30-minute break is not a real disconnection, so the gap itself counts as worked time.

A gap of exactly 30 minutes or more starts a new block.

Each row's `Minutes (ADJ)` is therefore the **new** time that page contributes, measured from whichever is later: its own start, or the latest end seen so far. A page wholly inside an earlier one contributes 0 — which means "added no interruption time", **not** "was not real work". Keep the column header explicit so nobody misreads a 0.

Summing `Minutes (ADJ)` over a day gives that day's true interruption time.

**This requires rows sorted by `Started` ascending.** The user generates these reports with assistant help, so that ordering is guaranteed — but if a late page is ever inserted mid-table, re-sort before trusting the column.

## Step 5 — Prepare the tab

Tab name: **`ON-CALL-REPORT-TMP`**.

- **If it exists** — ask the user for permission before clearing it, then overwrite the old range with empty values (there is no delete-range tool; write blanks over at least the previous extent).
- **If it does not exist** — *the user has to create it.* The Google Workspace MCP tools cannot add a tab to an existing spreadsheet (`create_spreadsheet` makes a whole new document, and there is no `add_sheet`). Tell the user plainly, and suggest they duplicate an existing report tab and rename it so it inherits the frozen row/column, column widths and date formats; then continue once they confirm. Do not silently write somewhere else.

Check what exists with `get_spreadsheet_metadata` first.

## Step 6 — Write the tab

Layout — one header row, then per day: the page rows, a blank row, a subtotal row.

| Col | Header | Content |
|---|---|---|
| A | `Day` | `MONDAY 19th` style label, **bold**, only on the first row of each day's block |
| B | `Page` | `=HYPERLINK("<url>","Page #<id>: <title>")` |
| C | `Source` | `#sw-delivery-oncall` |
| D | `Started` | trigger, `DATE_TIME` pattern `M/d/yyyy H:mm:ss` |
| E | `Resolved` | `closed_at`, same format; empty if still open |
| F | `Minutes (NET)` | `=ROUND((E2-D2)*1440)` — this page's own duration |
| G | `Minutes (ADJ)` | overlap/gap-adjusted contribution (formula below) |
| H | | spacer, left empty |
| I | `Day Minutes` | subtotal row only |
| J | `Day Rounded` | subtotal row only |
| K | `Day Hours` | subtotal row only |

Earlier hand-made tabs carried duplicate `Intervention Start` / `Intervention End` columns because the user did the overlap maths manually. The formulas replace that, so **do not recreate those columns.**

General rule: never write a literal copy of a value that already exists in another cell — reference it (`=E5`).

### Minutes (ADJ) formula

First data row (row 2) has nothing before it:

```
=ROUND((E2-D2)*1440)
```

Every later row `r`:

```
=IF((D{r}-MAX($E$2:E{r-1}))*1440<30,
    MAX(0, ROUND((E{r}-MAX($E$2:E{r-1}))*1440)),
    ROUND((E{r}-D{r})*1440))
```

`MAX($E$2:E{r-1})` is the latest end seen so far; the half-anchored range grows as it is filled down. Leave `F` and `G` **empty** on rows with no `Resolved` — a formula against an empty end date returns a large negative number and poisons the `SUM`.

### Per-day subtotal row

```
I = =SUM(G<first>:G<last>)      the day's aggregated minutes
J = =CEILING(I<row>,60)         rounded up to the whole hour (policy: "round to the highest figure")
K = =J<row>/60                  hours
```

### Week total

Below the last day's block, a `TOTAL WEEK` row:

```
J = =SUM(<each day's J cell>)   total minutes rounded to hours
K = =SUM(<each day's K cell>)   total hours
```

Rounding is applied **per day and never to the week**, because the policy declares one intervention per day. Summing already-rounded days is intentional.

### Recovery days

Below the week total, a two-cell labelled block:

```
A: Dias Totales
B: =<week total K cell>/8*1.75
```

8-hour working day, 175% time-in-lieu per the policy. Report it as a decimal (whole days plus fraction).

The MCP tools cannot create a **native Sheets Table object** or a named range, so this is written as a labelled block. Tell the user, and mention they can select the two cells and use *Insert → Table* / *Data → Named ranges* to name it `Dias Totales` if they want the real object.

### Formatting

- `format_sheet_cells` on `D:E` of the data rows: `number_format_type=DATE_TIME`, `number_format_pattern=M/d/yyyy H:mm:ss`
- Bold column `A` and the `Source` header, matching the existing tabs
- Dates are written as `M/D/YYYY H:MM:SS` strings and parsed by the sheet's `en_US` locale

**Reset the numeric columns when reusing a tab.** Cell formatting survives overwriting the values, so a tab that previously held a different layout keeps its old `numberFormat` under the new content. The usual symptom is `Minutes (NET)` / `Minutes (ADJ)` rendering as dates, because those columns used to hold `Intervention Start` / `Intervention End`. After writing, always run:

```
format_sheet_cells(range="'<TAB>'!$F$2:$K$<last>", number_format_type="NUMBER")
```

Pass **no** `number_format_pattern` — that resets to the locale default. An explicit pattern like `0.##` leaves a trailing separator (`18.`) on whole numbers.

Equally, re-apply the `DATE_TIME` format to `D:E` over the **new** row extent rather than assuming the old one covered it, and remember the previous content may have been shorter or longer than the current report.

Links go in as `=HYPERLINK(...)` because the tools cannot write text with an embedded `textFormat.link`. Mention this: the cell is a formula, and pasting column B as values-only converts it to the older style if the user prefers.

## Step 7 — Verify and report back

Re-read the written range and check it against the computed numbers before telling the user it is done. Then report:

- The resolved period and the page count
- Per-day: aggregated minutes → rounded → hours
- Week total and `Dias Totales`
- **The gap between the naive per-page sum and the adjusted total**, so the user can see what the overlap policy removed
- Any pages excluded (wrong responder, inside working hours, closed outside the window) and any still open

## Pitfalls

- Report times in **Europe/Madrid**, and watch the CEST/CET switch when a period spans late October.
- `closed_at` is when the page was *closed*, which for a monitor that auto-resolved is when the alert cleared and for a manual close is when the user clicked. The user has accepted this as the basis for the report.
- Do not fabricate a resolution time for an open page.
- The channel is private; if `slack_search_channels` returns nothing, search with `channel_types="public_channel,private_channel"`.
