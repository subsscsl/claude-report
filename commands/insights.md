# Weekly Copilot CLI Insights Report

Generate a **comprehensive, data-driven** weekly usage insights report from the Copilot CLI session store. The goal is parity with the old Claude Code insights reports: not just descriptive stats, but **actionable, copy-pasteable recommendations grounded in the actual session content**. A good report is ~60–75 KB of HTML; a thin descriptive-only report is a regression.

## Instructions

### 1. Query the local session store

Query `~/.copilot/session-store.db` using `sqlite3` via bash. Gather data for the past 7 days (or all data if fewer than 7 days exist).

**Sessions overview:**
```sql
SELECT count(*) as total_sessions,
       count(DISTINCT repository) as repos,
       count(DISTINCT date(created_at)) as active_days
FROM sessions
WHERE created_at > datetime('now', '-7 days');
```

**Sessions by repository:**
```sql
SELECT repository, count(*) as session_count,
       group_concat(DISTINCT summary) as summaries
FROM sessions
WHERE created_at > datetime('now', '-7 days')
GROUP BY repository ORDER BY session_count DESC;
```

**Conversation volume:**
```sql
SELECT count(*) as total_turns,
       count(DISTINCT t.session_id) as sessions_with_turns
FROM turns t
JOIN sessions s ON t.session_id = s.id
WHERE s.created_at > datetime('now', '-7 days');
```

**Files touched:**
```sql
SELECT file_path, tool_name, count(*) as times
FROM session_files sf
JOIN sessions s ON sf.session_id = s.id
WHERE s.created_at > datetime('now', '-7 days')
GROUP BY file_path, tool_name ORDER BY times DESC LIMIT 20;
```

**Commits and PRs:**
```sql
SELECT ref_type, count(*) as count
FROM session_refs sr
JOIN sessions s ON sr.session_id = s.id
WHERE s.created_at > datetime('now', '-7 days')
GROUP BY ref_type;
```

**Activity by hour (from turn timestamps):**
```sql
SELECT cast(strftime('%H', timestamp) as integer) as hour, count(*) as turns
FROM turns t
JOIN sessions s ON t.session_id = s.id
WHERE s.created_at > datetime('now', '-7 days')
GROUP BY hour ORDER BY hour;
```

**Session summaries for narrative:**
```sql
SELECT repository, summary, created_at
FROM sessions
WHERE created_at > datetime('now', '-7 days') AND summary IS NOT NULL
ORDER BY created_at;
```

### 2. Deep-dive the actual conversation content (REQUIRED — this is what makes the report good)

The descriptive stats above are necessary but **not sufficient**. The three highest-value sections (Features to Try, New Ways to Use, Where Things Went Wrong) all depend on reading the real `turns` content to detect **friction patterns** and **repeated workflows**. Do not skip this.

**Pull user messages to detect friction + repetition:**
```sql
SELECT s.repository, t.session_id, t.turn_index,
       substr(t.user_message, 1, 400) as msg
FROM turns t
JOIN sessions s ON t.session_id = s.id
WHERE s.created_at > datetime('now', '-7 days')
  AND t.user_message IS NOT NULL
ORDER BY t.session_id, t.turn_index;
```

**Analyze the results for:**
- **Friction signals** — user corrections ("no, that's wrong", "actually", "I told you", "don't do X", "that's not what I meant"), repeated re-prompts, permission/sandbox failures, platform errors (macOS `grep -P`, TCC, VPN/push failures), abandoned sessions (no summary, very few turns).
- **Repeated workflows** — the same pipeline/skill run many times across sessions (e.g. meeting-notes, deploys, reflect). Count how many sessions each represents — these counts are the justification for every recommendation.
- **Cluster** friction into 2–4 named categories, each with a count and 1–3 concrete example quotes.

Also query the **cloud session store** via the `session_store_sql` tool for richer signal when available (last 7 days only, always time-filtered):
- Total input/output tokens (`events` where `usage_model IS NOT NULL`)
- Tool execution counts (`events` where `type = 'tool.execution_complete'`)
- Model usage breakdown
- `turns.user_message ILIKE` patterns for corrections — but only within session_ids already in window (never an unfiltered scan).

### 3. Generate the HTML report with ALL of these sections

The report MUST include every section below. Sections 6–8 are the differentiated, high-value content — never omit them. If data is thin for a section, say so briefly but still render the section.

1. **At a Glance** — golden highlight box. 2–3 sentence narrative of the week: what you worked on, key wins, notable patterns.
2. **What You Worked On** — project areas as cards, each with session count + brief description.
3. **How You Use Copilot CLI** — stats row (sessions, turns, active days, repos, + tokens if available) and an hour-of-day histogram with a one-line peak-activity callout.
4. **Impressive Things You Did** — 2–4 green "big win" cards highlighting notable accomplishments (complex tasks, commits, PRs, migrations) drawn from session summaries.
5. **Where Things Went Wrong** — the 2–4 friction categories from step 2, each as a red card: title, one-line description, count, and a bulleted list of real example quotes. Be specific and honest, not generic.
6. **Copilot CLI Features to Try** — TWO parts:
   - **Suggested `copilot-instructions.md` Additions** — a blue card containing copy-pasteable instruction snippets, each derived from a friction pattern in step 2. Each item: a `<code>` block with the exact text to paste, plus a "why" line citing the friction count (e.g. "4 sessions failed because…"). Include a "Copy All Checked" button and per-item checkboxes/copy affordance. Target 3–6 items.
   - **Hooks** — feature cards suggesting Copilot CLI lifecycle hooks (e.g. pre-commit lint/type-check, post-edit validation, sessionStart sync) tailored to the observed friction, each with a "why for you" line tied to the data.
7. **New Ways to Use Copilot CLI** — 2–3 blue "pattern" cards. Each proposes a concrete workflow improvement (automation, headless/cron, file-watcher, batching) justified by usage data (e.g. "17/37 sessions were the same pipeline…"), and includes a copy-pasteable prompt the user can drop straight into Copilot CLI to set it up.
8. **On the Horizon** — a short forward-looking note: 1–3 upcoming/underused Copilot CLI capabilities relevant to this user's patterns (e.g. background agents, subagents, MCP integrations they haven't leveraged). Keep it light but present.

**Terminology:** This is Copilot CLI, not Claude Code. Say "copilot-instructions.md" (not CLAUDE.md), "Copilot CLI", "hooks at `~/.copilot/hooks/`". Copy-paste prompts should be phrased for Copilot CLI.

### 4. Add a sticky top nav / table-of-contents

Render an anchor-linked nav (`.nav-toc`) with a chip per section so the long report is navigable. Give each `<h2>` an `id`.

### 5. Style the report using this design system

- Font: Inter (Google Fonts), fallback system sans-serif. Background `#f8fafc`, text `#334155`, headings `#0f172a`. Max-width 800px container, centered, `padding: 48px 24px`.
- **Headings:** h1 32px/700; h2 20px/600 with `margin-top: 48px`.
- **Nav TOC:** white card, `1px solid #e2e8f0`, rounded; chips `background:#f1f5f9`, `font-size:12px`, hover `#e2e8f0`.
- **Stats row:** flex, top/bottom `1px solid #e2e8f0`; each stat large value (`24px/700 #0f172a`) + small uppercase label (`11px #64748b`).
- **At-a-glance:** golden gradient `#fef3c7`→`#fde68a`, border `#f59e0b`, rounded 12px; title `#92400e`, body `#78350f`.
- **Project area cards / narrative:** white, `1px solid #e2e8f0`, rounded 8px.
- **Big wins:** `background:#f0fdf4`, `border:1px solid #bbf7d0`, title `#166534`, body `#15803d`.
- **Friction cards:** `background:#fef2f2`, `border:1px solid #fca5a5`, title `#991b1b`, body `#7f1d1d`; examples as a `<ul>`.
- **copilot-instructions.md suggestion card:** `background:#eff6ff`, `border:1px solid #bfdbfe`, h3 `#1e40af`. Each item: a `.cmd-code` monospace white block (`12px`, `1px solid #bfdbfe`, `white-space:pre-wrap`) with the paste text, a checkbox, and a `.cmd-why` grey rationale line. A `.copy-all-btn` (`background:#2563eb`, white, turns green `#16a34a` + "Copied!" on click).
- **Feature cards** (hooks): `background:#f0fdf4`, `border:1px solid #86efac`. **Pattern cards** (new ways): `background:#f0f9ff`, `border:1px solid #7dd3fc`. Each pattern card embeds a copy-pasteable prompt block with its own copy button.
- Include a small `<script>` implementing the copy buttons: "Copy All Checked" concatenates checked items' code text to the clipboard; per-block copy buttons copy their block; show a transient "Copied!" state.

### 6. Write & output

- Write the report to `~/.copilot/usage-data/report.html`.
- Output the file path when done.
- If the session store has very little data (< 3 sessions), note this at the top, render what's available, and still produce valid HTML with all section headers present. Do **not** drop sections 6–8 just because data is thin — instead, base their suggestions on whatever friction/patterns are visible plus sensible defaults for this user's known workflows.
