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
