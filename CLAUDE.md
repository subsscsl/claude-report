# claude-report

Weekly Copilot CLI insights reports published to `subsscsl/claude-report`.

**Live site:** [subsscsl.github.io/claude-report](https://subsscsl.github.io/claude-report/)

## How reports are generated

Reports are generated automatically every **Monday at noon** by a macOS LaunchAgent (`com.schew.claude-report`) that runs `~/.claude/scripts/generate-claude-report.sh`.

A backup of that script lives at `scripts/generate-claude-report.sh` in this repo.

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
The live script is at `~/.claude/scripts/generate-claude-report.sh`. To sync:
```bash
cp scripts/generate-claude-report.sh ~/.claude/scripts/generate-claude-report.sh
```
