# claude-report

Weekly Claude Code insights reports published to `subsscsl/claude-report`.

## How reports are generated

Reports are generated automatically every **Monday at noon** by a macOS LaunchAgent (`com.schew.claude-report`) that runs `~/.claude/scripts/generate-claude-report.sh`.

A backup of that script lives at `scripts/generate-claude-report.sh` in this repo.

### What the script does
1. Runs `claude -p /insights` to regenerate `~/.claude/usage-data/report.html`
2. Copies the output to `report-YYYY-MM-DD.html` and `report-latest.html`
3. Regenerates `index.html` (latest report + archive link) and `archive.html` (all reports)
4. Commits and pushes to `subsscsl/claude-report`

### Failure notification
If any step fails, the script sends a Slack DM to `@schew` with the exit code. Check `~/.claude/usage-data/launchagent-report.log` for details.

### LaunchAgent logs
- stdout: `~/.claude/usage-data/launchagent-report.log`
- stderr: `~/.claude/usage-data/launchagent-report-error.log`

### Diagnosing a missed report
```bash
# Check last exit code (127 = command not found, 1 = script error)
launchctl list | grep claude-report

# Check the log
cat ~/.claude/usage-data/launchagent-report.log | tail -30
```
