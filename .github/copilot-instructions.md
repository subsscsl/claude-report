# claude-report

Weekly Copilot CLI insights reports published to `subsscsl/claude-report`.

**Live site:** [subsscsl.github.io/claude-report](https://subsscsl.github.io/claude-report/)

## How reports are generated

Reports are generated automatically every **Monday at noon** by a macOS LaunchAgent (`com.schew.claude-report`) that runs `~/.copilot/scripts/generate-claude-report.sh`.

A backup of that script lives at `scripts/generate-claude-report.sh` in this repo.

The custom `/insights` command that defines the report's structure and sections is backed up at `commands/insights.md`. **This file is the single source of report quality** — it specifies all 8 sections (At a Glance, What You Worked On, How You Use Copilot CLI, Impressive Things, Where Things Went Wrong, Features to Try with copy-paste `copilot-instructions.md` additions + Hooks, New Ways to Use, On the Horizon) and the design system. It is NOT a symlink and is easy to lose during tooling migrations — keep this backup in sync.

### What the script does
1. Detects available CLI (`copilot` preferred, `claude` fallback)
2. Runs `/insights` to regenerate `~/.copilot/usage-data/report.html` — the custom `/insights` command lives at `~/.copilot/commands/insights.md` and queries the local session store (`~/.copilot/session-store.db`)
3. Runs `/schew-insights-triage` for friction analysis (non-fatal if it fails)
4. Copies the output to `report-YYYY-MM-DD.html` and `report-latest.html`
5. Regenerates `index.html` (latest report + archive link) and `archive.html` (all reports)
6. Commits and pushes to `subsscsl/claude-report` using `gh` credential helper (no embedded tokens)

### Failure handling
If any step fails, the error is logged to `~/.copilot/usage-data/launchagent-report.log`.

### LaunchAgent logs
- stdout: `~/.copilot/usage-data/launchagent-report.log` (auto-rotated at 5000 lines)
- stderr: `~/.copilot/usage-data/launchagent-report-error.log`

### Diagnosing a missed report
```bash
# Check last exit code (127 = command not found, 1 = script error)
launchctl list | grep claude-report

# Check the log
cat ~/.copilot/usage-data/launchagent-report.log | tail -30
```

### Syncing the script backup
The live script is at `~/.copilot/scripts/generate-claude-report.sh`. To sync:
```bash
cp scripts/generate-claude-report.sh ~/.copilot/scripts/generate-claude-report.sh
```

### Syncing the /insights command backup
The live command is at `~/.copilot/commands/insights.md`. To restore or sync:
```bash
cp commands/insights.md ~/.copilot/commands/insights.md   # restore into Copilot CLI
cp ~/.copilot/commands/insights.md commands/insights.md   # back up edits
```
If a future report looks thin (missing the Features to Try / New Ways / On the Horizon sections), the live command was likely overwritten — restore it from this backup.
