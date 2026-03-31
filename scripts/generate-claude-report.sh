#!/bin/bash
# Weekly Claude Code insights report generator
# Runs every Monday at 8am via LaunchAgent

set -e

NOTABOT="$HOME/.claude/plugins/linkedin-plugins/linkedin-plugins/productivity/send-to-slack/scripts/notabot"

on_error() {
  local exit_code=$?
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: script failed (exit $exit_code)" >> "$HOME/.claude/usage-data/launchagent-report.log"
  "$NOTABOT" send -c "@schew" -m "❌ *claude-report LaunchAgent failed* (exit $exit_code) — check \`~/.claude/usage-data/launchagent-report.log\`" > /dev/null 2>&1 || true
}
trap on_error ERR

# Environment setup (LaunchAgent has minimal PATH)
export HOME="/Users/schew"
export VOLTA_HOME="$HOME/.volta"
export PATH="$HOME/.volta/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPORT_SRC="$HOME/.claude/usage-data/report.html"
REPO_DIR="$HOME/Documents/Github/claude-report"
DATE=$(date +%Y-%m-%d)
LOG_FILE="$HOME/.claude/usage-data/launchagent-report.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

log "--- Starting weekly insights report ---"

# Re-run the insights analysis to regenerate report.html
log "Running claude -p /insights..."
cd "$HOME/Documents"
"$HOME/.volta/bin/claude" --dangerously-skip-permissions -p "/insights" >> "$LOG_FILE" 2>&1 || {
  log "ERROR: claude -p /insights failed"
  exit 1
}

# Verify report exists
if [ ! -f "$REPORT_SRC" ]; then
  log "ERROR: report.html not found at $REPORT_SRC"
  exit 1
fi

# Copy report into the repo
cp "$REPORT_SRC" "$REPO_DIR/report-$DATE.html"
cp "$REPORT_SRC" "$REPO_DIR/report-latest.html"
log "Copied report to $REPO_DIR/report-$DATE.html"

# Generate index.html and archive.html
python3 << PYEOF
import re, os, glob

repo = "$REPO_DIR"
date_str = "$DATE"

# --- index.html: inject "All Reports" banner into report-latest.html ---
with open(os.path.join(repo, "report-latest.html")) as f:
    content = f.read()

banner = """<div style="position:fixed;top:20px;right:24px;z-index:9999;">
  <a href="archive.html" style="display:inline-flex;align-items:center;gap:6px;background:white;color:#334155;font-family:'Inter',-apple-system,sans-serif;font-size:13px;font-weight:500;text-decoration:none;padding:8px 14px;border-radius:20px;border:1px solid #e2e8f0;box-shadow:0 2px 8px rgba(0,0,0,0.08);transition:box-shadow 0.15s;" onmouseover="this.style.boxShadow='0 4px 12px rgba(0,0,0,0.12)'" onmouseout="this.style.boxShadow='0 2px 8px rgba(0,0,0,0.08)'">
    All Reports &rarr;
  </a>
</div>"""

content = content.replace("<body>", "<body>" + banner, 1)
with open(os.path.join(repo, "index.html"), "w") as f:
    f.write(content)

# --- archive.html: list all reports newest first ---
reports = sorted(
    glob.glob(os.path.join(repo, "report-20*.html")),
    reverse=True
)

def format_range(date_str):
    from datetime import datetime, timedelta
    end = datetime.strptime(date_str, "%Y-%m-%d")
    start = end - timedelta(days=6)
    if start.year == end.year and start.month == end.month:
        return f"{start.strftime('%b %-d')}–{end.strftime('%-d, %Y')}"
    elif start.year == end.year:
        return f"{start.strftime('%b %-d')} – {end.strftime('%b %-d, %Y')}"
    else:
        return f"{start.strftime('%b %-d, %Y')} – {end.strftime('%b %-d, %Y')}"

rows = ""
for i, path in enumerate(reports):
    fname = os.path.basename(path)
    d = fname.replace("report-", "").replace(".html", "")
    label = format_range(d)
    badge = '<span style="font-size:11px;font-weight:600;background:#f0fdf4;color:#16a34a;padding:2px 8px;border-radius:10px;margin-left:8px;">Latest</span>' if i == 0 else ""
    rows += f'''<li>
      <a href="{fname}" style="color:#0f172a;text-decoration:none;font-weight:500;font-size:15px;">{label}{badge}</a>
    </li>'''

archive_html = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Claude Code Insights — All Reports</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{ font-family: 'Inter', -apple-system, sans-serif; background: #f8fafc; color: #334155; padding: 48px 24px; }}
    .container {{ max-width: 600px; margin: 0 auto; }}
    .back {{ display: inline-flex; align-items: center; gap: 6px; color: #64748b; text-decoration: none; font-size: 14px; margin-bottom: 40px; }}
    .back:hover {{ color: #334155; }}
    h1 {{ font-size: 28px; font-weight: 700; color: #0f172a; margin-bottom: 6px; }}
    .subtitle {{ color: #64748b; font-size: 14px; margin-bottom: 36px; }}
    ul {{ list-style: none; border: 1px solid #e2e8f0; border-radius: 12px; background: white; overflow: hidden; }}
    li {{ padding: 16px 20px; border-bottom: 1px solid #f1f5f9; }}
    li:last-child {{ border-bottom: none; }}
    li:hover {{ background: #f8fafc; }}
    a {{ color: #0f172a; text-decoration: none; }}
  </style>
</head>
<body>
  <div class="container">
    <a href="index.html" class="back">← Latest Report</a>
    <h1>All Reports</h1>
    <p class="subtitle">Weekly Claude Code usage insights, generated every Monday</p>
    <ul>
      {rows}
    </ul>
  </div>
</body>
</html>"""

with open(os.path.join(repo, "archive.html"), "w") as f:
    f.write(archive_html)

print("Generated index.html and archive.html")
PYEOF

log "Generated index.html and archive.html"

# Commit and push
cd "$REPO_DIR"

# Use gh CLI token for authenticated push in LaunchAgent context
GH_TOKEN=$(gh auth token --user subsscsl 2>/dev/null)
if [ -n "$GH_TOKEN" ]; then
  git remote set-url origin "https://subsscsl:${GH_TOKEN}@github.com/subsscsl/claude-report.git"
fi

git add "report-$DATE.html" report-latest.html index.html archive.html
git diff --staged --quiet && { log "No changes to commit (report unchanged)"; exit 0; }

git -c user.name="subsscsl" -c user.email="subsscsl@users.noreply.github.com" \
  commit -m "Weekly insights report $DATE"
git push origin main

log "Done. Pushed report-$DATE.html to subsscsl/claude-report"
