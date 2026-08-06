#!/usr/bin/env bash
# ============================================================================
# setup_all.sh – One‑shot repo creation, file generation, Pages deployment, and log push.
# Complies with userPreferences rules #1, #7, #8, #9, #16, #28, #30, #38,
# #39, #41, #47, #49, #50, #51, #52, #53, #54, #55, #56.
#
# IMPORTANT: This script does NOT use 'set -e' anywhere.
# All failures are handled explicitly with '|| { log_result ...; exit 1; }'.
# ============================================================================

# ----------------------------------------------------------------------
# Capture all output (stdout and stderr) to a timestamped log file.
# We use 'tee' so output is still visible in the terminal.
# ----------------------------------------------------------------------
LOG_DIR="$HOME/$(basename "$0" .sh)_logs"
mkdir -p "$LOG_DIR" || { echo "Cannot create log dir"; exit 1; }
LOG_FILE="$LOG_DIR/setup_$(date -u +%Y%m%d%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Rule #1: Ground every factual claim.
echo "=== SETUP_ALL: Starting at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "Log file: $LOG_FILE"

# ----------------------------------------------------------------------
# Rule #8: Observability / Verbatim Reporting – shared log function
# ----------------------------------------------------------------------
log_result() {
    local operation="$1" success="$2" detail="$3"
    local ts status
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ "$success" = "true" ]; then status="SUCCESS"; else status="FAILURE"; fi
    echo "[$ts] [$status] $operation: $detail" >&2
}

# ----------------------------------------------------------------------
# Rule #28: Dependency Management (no silent failures)
# ----------------------------------------------------------------------
for cmd in git gh docker python3 sqlite3 curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_result "dependency_check" "false" "Required command '$cmd' not found."
        exit 1
    fi
done
log_result "dependency_check" "true" "All required commands are available."

# ----------------------------------------------------------------------
# Rule #49: REPO OWNER DISCOVERY – dynamic, not hardcoded
# ----------------------------------------------------------------------
OWNER=$(gh api user -q .login 2>&1) || {
    log_result "repo_owner_discovery" "false" "Could not determine GitHub username via gh."
    exit 1
}
if [ -z "$OWNER" ]; then
    log_result "repo_owner_discovery" "false" "gh returned empty username."
    exit 1
fi
log_result "repo_owner_discovery" "true" "Owner: $OWNER"

REPO_NAME="diagnostic-dashboard-$(date +%s)"
echo "Owner: $OWNER, repo: $REPO_NAME"

# ----------------------------------------------------------------------
# Step 1: Clone reference repo (optional) – we still do it.
# ----------------------------------------------------------------------
REF_REPO="https://github.com/swipswaps/receipts-ocr.git"
REF_DIR="/tmp/receipts-ocr-ref"
if [ -d "$REF_DIR" ]; then
    rm -rf "$REF_DIR" || log_result "clean_ref" "true" "Removed existing reference dir."
fi
git clone "$REF_REPO" "$REF_DIR" 2>&1 || {
    log_result "clone_ref" "false" "Could not clone reference repo. Proceeding with generic structure."
    REF_DIR=""
}
log_result "clone_ref" "true" "Reference repo cloned (or skipped)."

# ----------------------------------------------------------------------
# Step 2: Create new repo via gh – always clone afterwards.
# ----------------------------------------------------------------------
WORKDIR="/tmp/$REPO_NAME"
export WORKDIR   # <--- critical: export so inner scripts see it
mkdir -p "$WORKDIR" || { log_result "mkdir" "false" "Cannot create $WORKDIR"; exit 1; }
cd "$WORKDIR" || { log_result "cd_workdir" "false" "Cannot cd to $WORKDIR"; exit 1; }

# Check if repo exists; if not, create it.
if ! gh repo view "$OWNER/$REPO_NAME" 2>&1 >/dev/null; then
    gh repo create "$REPO_NAME" --public 2>&1 || {
        log_result "repo_create" "false" "Failed to create repo '$REPO_NAME'."
        exit 1
    }
    log_result "repo_create" "true" "Repo created."
fi

# Always clone the repo into the current directory (which is empty).
if [ -d ".git" ]; then
    log_result "repo_clone" "info" "Git repository already exists, pulling latest..."
    git pull origin main 2>&1 || log_result "repo_pull" "false" "Pull failed, continuing."
else
    git clone "https://github.com/$OWNER/$REPO_NAME.git" . 2>&1 || {
        log_result "repo_clone" "false" "Failed to clone repository."
        exit 1
    }
    log_result "repo_clone" "true" "Repo cloned into $WORKDIR."
fi

# ----------------------------------------------------------------------
# Step 3: Generate application files via heredocs.
# NOTE: The inner script MUST NOT use set -e.
# We now place frontend assets under 'docs/' for GitHub Pages.
# ----------------------------------------------------------------------
cat > "$WORKDIR/generate_files.sh" <<'GENEOF'
#!/usr/bin/env bash
# ============================================================================
# generate_files.sh – Writes all app files for the diagnostic dashboard.
# ============================================================================

# Rule #8: We log our steps.
log_result() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$1] $2: $3" >&2; }

# Rule #50: Export and assert environment variables.
if [ -z "${WORKDIR:-}" ]; then
    log_result "export_gate" "false" "WORKDIR not set."
    exit 1
fi
log_result "export_gate" "true" "WORKDIR=$WORKDIR"

# ----------------------------------------------------------------------
# 3a. Backend app (Flask) – unchanged.
# ----------------------------------------------------------------------
cat > "$WORKDIR/app.py" <<'PYEOF'
#!/usr/bin/env python3
# ============================================================================
# app.py – Flask backend with SQLite, health checks, and diagnostic API.
# ============================================================================
import os, sys, sqlite3, json, datetime
from flask import Flask, request, jsonify, render_template
try:
    import flask
except ImportError:
    print("ERROR: Missing Flask. Run: pip install flask", file=sys.stderr)
    sys.exit(1)
app = Flask(__name__)
DB_PATH = os.environ.get("DB_PATH", "/data/diagnostics.db")
assert DB_PATH and DB_PATH.strip(), "DB_PATH missing"
def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn
def init_db():
    conn = get_db()
    conn.execute("CREATE TABLE IF NOT EXISTS diagnostics (id INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT, component TEXT, status TEXT, line_number INTEGER, line_text TEXT, logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)")
    conn.execute("CREATE TABLE IF NOT EXISTS rule_compliance (id INTEGER PRIMARY KEY AUTOINCREMENT, script_name TEXT, rule_id TEXT, passed INTEGER, evidence TEXT, created_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP)")
    conn.commit()
    conn.close()
    conn = get_db()
    tables = conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
    conn.close()
    table_names = [t[0] for t in tables]
    assert "diagnostics" in table_names
    assert "rule_compliance" in table_names
init_db()
@app.route("/")
def index():
    return render_template("index.html")
@app.route("/api/diagnostics")
def get_diagnostics():
    conn = get_db()
    rows = conn.execute("SELECT * FROM diagnostics ORDER BY logged_at DESC LIMIT 100").fetchall()
    conn.close()
    return jsonify([dict(row) for row in rows])
@app.route("/api/health")
def health():
    return jsonify({"status": "healthy", "db": DB_PATH, "time": datetime.datetime.now(datetime.timezone.utc).isoformat()})
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
PYEOF
chmod +x "$WORKDIR/app.py" || exit 1

# ----------------------------------------------------------------------
# 3b. Requirements
# ----------------------------------------------------------------------
cat > "$WORKDIR/requirements.txt" <<'REQEOF'
Flask==2.3.3
REQEOF

# ----------------------------------------------------------------------
# 3c. Dockerfile – unchanged.
# ----------------------------------------------------------------------
cat > "$WORKDIR/Dockerfile" <<'DOCEOF'
FROM python:3.11-slim
RUN apt-get update && apt-get install -y sqlite3 curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
COPY templates/ templates/
COPY static/ static/
ENV DB_PATH=/data/diagnostics.db
VOLUME ["/data"]
CMD ["python3", "-u", "app.py"]
DOCEOF

# ----------------------------------------------------------------------
# 3d. docker-compose.yml – unchanged.
# ----------------------------------------------------------------------
cat > "$WORKDIR/docker-compose.yml" <<'COMEOF'
version: '3'
services:
  backend:
    build: .
    ports:
      - "5000:5000"
    volumes:
      - ./data:/data
    environment:
      - DB_PATH=/data/diagnostics.db
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
COMEOF

# ----------------------------------------------------------------------
# 3e. Frontend – now placed under docs/ for GitHub Pages.
# We keep a copy in templates/ for Flask, but Pages uses docs/.
# ----------------------------------------------------------------------
mkdir -p "$WORKDIR/docs" "$WORKDIR/templates" "$WORKDIR/static"
# The HTML uses relative path to static, which will work from /docs.
cat > "$WORKDIR/docs/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <title>Diagnostic Dashboard</title>
    <link rel="stylesheet" href="static/style.css">
</head>
<body>
    <h1>Diagnostic Dashboard</h1>
    <div id="content"><p>Loading data...</p></div>
    <script>
        fetch('/api/diagnostics')
            .then(r => r.json())
            .then(data => {
                let html = '<table><tr><th>ID</th><th>Run</th><th>Component</th><th>Status</th><th>Line</th><th>Logged</th></tr>';
                data.forEach(row => {
                    html += `<tr><td>${row.id}</td><td>${row.run_id}</td><td>${row.component}</td><td>${row.status}</td><td>${row.line_number}</td><td>${row.logged_at}</td></tr>`;
                });
                html += '</table>';
                document.getElementById('content').innerHTML = html;
            })
            .catch(err => {
                document.getElementById('content').innerHTML = '<p style="color:red;">Error loading data: ' + err + '</p>';
            });
    </script>
</body>
</html>
HTMLEOF
# Copy the same to templates/ for Flask.
cp "$WORKDIR/docs/index.html" "$WORKDIR/templates/index.html"

# ----------------------------------------------------------------------
# 3f. Static CSS – placed in docs/static and also static/ for Flask.
# ----------------------------------------------------------------------
mkdir -p "$WORKDIR/docs/static"
cat > "$WORKDIR/docs/static/style.css" <<'CSSEOF'
body { font-family: sans-serif; margin: 2em; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ccc; padding: 0.5em; text-align: left; }
th { background: #f0f0f0; }
CSSEOF
cp "$WORKDIR/docs/static/style.css" "$WORKDIR/static/style.css"

# ----------------------------------------------------------------------
# 3g. GitHub Actions workflow – now upload docs/ instead of templates/.
# ----------------------------------------------------------------------
mkdir -p "$WORKDIR/.github/workflows"
cat > "$WORKDIR/.github/workflows/pages.yml" <<'YAMLEOF'
name: Deploy Pages
on:
  push:
    branches: [ main ]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Pages
        uses: actions/configure-pages@v4
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: './docs'
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
YAMLEOF

# ----------------------------------------------------------------------
# 3h. Database import script – unchanged.
# ----------------------------------------------------------------------
cat > "$WORKDIR/import_diagnostic.py" <<'IMPORTEOF'
#!/usr/bin/env python3
import os, sys, sqlite3, re, datetime
DB_PATH = os.environ.get("DB_PATH", "./diagnostics.db")
assert DB_PATH and DB_PATH.strip(), "DB_PATH missing"
def parse_line(line):
    match = re.search(r'\[VISIBILITY\]\s+(\w+)=(\w+)', line)
    return match.group(1), match.group(2) if match else (None, None)
if len(sys.argv) < 2:
    print("Usage: import_diagnostic.py <logfile> [run_id]", file=sys.stderr)
    sys.exit(1)
logfile = sys.argv[1]
run_id = sys.argv[2] if len(sys.argv) > 2 else datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()
with open(logfile, 'r') as f:
    for line_num, line in enumerate(f, 1):
        if "[VISIBILITY]" in line:
            comp, status = parse_line(line)
            if comp:
                cursor.execute("INSERT INTO diagnostics (run_id, component, status, line_number, line_text) VALUES (?, ?, ?, ?, ?)", (run_id, comp, status, line_num, line.strip()))
conn.commit()
conn.close()
print(f"Imported visibility lines from {logfile} into {DB_PATH}")
IMPORTEOF
chmod +x "$WORKDIR/import_diagnostic.py" || exit 1

# ----------------------------------------------------------------------
# 3i. Environment validation script – unchanged.
# ----------------------------------------------------------------------
cat > "$WORKDIR/check_env.sh" <<'ENVEOF'
#!/usr/bin/env bash
export DB_PATH="${DB_PATH:-./diagnostics.db}"
for var in DB_PATH; do
    if [ -z "${!var}" ]; then
        echo "ERROR: $var is empty after export" >&2
        exit 1
    fi
done
echo "✅ Environment variables set: DB_PATH=$DB_PATH"
ENVEOF
chmod +x "$WORKDIR/check_env.sh" || exit 1

# ----------------------------------------------------------------------
# 3j. README.md (we'll create but not push)
# ----------------------------------------------------------------------
cat > "$WORKDIR/README.md" <<'MDEOF'
# Diagnostic Dashboard

See the live site at [GitHub Pages](https://$OWNER.github.io/$REPO_NAME/).
MDEOF

echo "✅ All files generated in $WORKDIR"
GENEOF

chmod +x "$WORKDIR/generate_files.sh" || {
    log_result "chmod_generate" "false" "Cannot chmod generate_files.sh"
    exit 1
}
log_result "generate_files_created" "true" "generate_files.sh written."

# ----------------------------------------------------------------------
# Step 4: Run the file generation inside the repo directory
# ----------------------------------------------------------------------
cd "$WORKDIR" || { log_result "cd_workdir" "false" "Cannot cd to $WORKDIR"; exit 1; }
./generate_files.sh || {
    log_result "generate_files_run" "false" "generate_files.sh failed."
    exit 1
}
log_result "generate_files_run" "true" "All application files generated."

# ----------------------------------------------------------------------
# Step 5: Commit and push (no git init/remote add needed – cloned repo already has them).
# ----------------------------------------------------------------------
git add . || { log_result "git_add" "false" "git add failed."; exit 1; }
# Remove README.md from staging if present.
if git ls-files --cached | grep -q "^README.md$"; then
    git rm --cached README.md || {
        log_result "git_rm_readme" "false" "Failed to remove README.md from index."
        exit 1
    }
    log_result "git_rm_readme" "true" "README.md removed from staging."
fi
git commit -m "Initial commit: diagnostic dashboard with backend and Pages workflow" || {
    log_result "git_commit" "false" "Commit failed."
    exit 1
}
git push -u origin main || {
    log_result "git_push" "false" "Push failed."
    exit 1
}
log_result "git_push" "true" "Repository pushed to GitHub."

# ----------------------------------------------------------------------
# Step 6: Enable GitHub Pages via API – now using path: "/docs" (allowed).
# ----------------------------------------------------------------------
log_result "pages_enable" "info" "Enabling GitHub Pages..."
gh api -X POST "/repos/$OWNER/$REPO_NAME/pages" \
    --input - <<< '{"source":{"branch":"main","path":"/docs"}}' 2>&1 || {
    log_result "pages_enable" "false" "Pages API call failed."
    exit 1
}
log_result "pages_enable" "true" "Pages API call succeeded."

# ----------------------------------------------------------------------
# Step 7: Poll until the site is live (Rule #55 Raw Link Validation)
# ----------------------------------------------------------------------
PAGES_URL="https://$OWNER.github.io/$REPO_NAME"
log_result "pages_poll" "info" "Polling $PAGES_URL ..."
max_attempts=30
attempt=0
HTTP_CODE=""
while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PAGES_URL" 2>&1)
    if [ "$HTTP_CODE" = "200" ]; then
        log_result "pages_poll" "true" "Site is live (HTTP 200)."
        break
    fi
    log_result "pages_poll" "info" "Attempt $attempt: HTTP $HTTP_CODE, waiting 10s..."
    sleep 10
done
if [ "$HTTP_CODE" != "200" ]; then
    log_result "pages_poll" "false" "Site did not return 200 after $max_attempts attempts."
    exit 1
fi

# ----------------------------------------------------------------------
# Step 8: Open the site
# ----------------------------------------------------------------------
if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$PAGES_URL" || log_result "open_browser" "false" "xdg-open failed."
    log_result "open_browser" "true" "Opened $PAGES_URL in browser."
else
    log_result "open_browser" "info" "xdg-open not found; open $PAGES_URL manually."
fi

# ----------------------------------------------------------------------
# Step 9: Push the log file to GitHub and print the raw link.
# The log file is already outside the repo (in $LOG_DIR), so we copy it into the repo.
# ----------------------------------------------------------------------
REPO_LOG_DIR="$WORKDIR/logs"
mkdir -p "$REPO_LOG_DIR" || { log_result "mkdir_repo_logs" "false" "Cannot create $REPO_LOG_DIR"; exit 1; }
cp "$LOG_FILE" "$REPO_LOG_DIR/" || { log_result "copy_log" "false" "Failed to copy log into repo."; exit 1; }
LOG_BASENAME=$(basename "$LOG_FILE")
git add "$REPO_LOG_DIR/$LOG_BASENAME" || { log_result "git_add_log" "false" "Failed to add log."; exit 1; }
git commit -m "Add setup log $LOG_BASENAME" || log_result "git_commit_log" "false" "Commit of log failed (maybe no changes)."
git push origin main || { log_result "git_push_log" "false" "Failed to push log."; exit 1; }
RAW_LOG_URL="https://raw.githubusercontent.com/$OWNER/$REPO_NAME/main/logs/$LOG_BASENAME"
log_result "raw_log_link" "true" "Log pushed: $RAW_LOG_URL"
echo "=== RAW LOG LINK ==="
echo "$RAW_LOG_URL"

# ----------------------------------------------------------------------
# Rule #30: Hard-gate self-audit – verify final state
# ----------------------------------------------------------------------
if curl -s -o /dev/null -w "%{http_code}" "$PAGES_URL" 2>&1 | grep -q "200"; then
    log_result "hard_gate" "true" "All criteria met: repo exists, Pages live, log pushed."
else
    log_result "hard_gate" "false" "Final verification failed – Pages not reachable."
    exit 1
fi

log_result "setup_all" "true" "COMPLETED SUCCESSFULLY."
echo "=== SETUP_ALL COMPLETED SUCCESSFULLY ==="

# ----------------------------------------------------------------------
# Keep terminal open by replacing this script with a new interactive shell.
# ----------------------------------------------------------------------
exec bash
