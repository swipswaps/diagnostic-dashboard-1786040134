#!/usr/bin/env bash
# ============================================================================
# build_repo_here.sh – Build the repo from scratch in the current directory.
# ============================================================================

set -o pipefail

OWNER="swipswaps"
REPO="diagnostic-dashboard-1786040134"
PAGES_URL="https://$OWNER.github.io/$REPO"

echo "=== BUILD REPO FROM SCRATCH ==="
echo "Working directory: $(pwd)"

# ----------------------------------------------------------------------
# 1. Generate all files (overwrite any existing).
# ----------------------------------------------------------------------
echo "Generating files..."

# app.py
cat > app.py <<'PYEOF'
#!/usr/bin/env python3
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
chmod +x app.py

# requirements.txt
cat > requirements.txt <<'REQEOF'
Flask==2.3.3
REQEOF

# Dockerfile
cat > Dockerfile <<'DOCEOF'
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

# docker-compose.yml
cat > docker-compose.yml <<'COMEOF'
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

# docs/ folder
mkdir -p docs/static
cat > docs/index.html <<'HTMLEOF'
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

cat > docs/static/style.css <<'CSSEOF'
body { font-family: sans-serif; margin: 2em; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ccc; padding: 0.5em; text-align: left; }
th { background: #f0f0f0; }
CSSEOF

# .nojekyll
touch docs/.nojekyll

# workflow
mkdir -p .github/workflows
cat > .github/workflows/pages.yml <<'YAMLEOF'
name: Deploy Pages

on:
  push:
    branches: [ main ]

permissions:
  pages: write
  id-token: write

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
# 2. Initialize git and push.
# ----------------------------------------------------------------------
echo "Initializing git..."
if [ ! -d ".git" ]; then
    git init
    git remote add origin "https://github.com/$OWNER/$REPO.git"
else
    echo "Git repo already exists."
fi

git add .
git commit -m "Initial commit: diagnostic dashboard" || echo "No changes"
git push -u origin main || { echo "❌ Push failed. Check remote and permissions."; exit 1; }

# ----------------------------------------------------------------------
# 3. Enable Pages with legacy build type.
# ----------------------------------------------------------------------
echo "Enabling Pages with legacy build type..."
gh api -X POST "repos/$OWNER/$REPO/pages" \
    --input - <<< '{"source":{"branch":"main","path":"/docs"},"build_type":"legacy"}' 2>&1 | jq '.'

# ----------------------------------------------------------------------
# 4. Trigger a build and monitor.
# ----------------------------------------------------------------------
echo "Triggering build..."
gh api -X POST "repos/$OWNER/$REPO/pages/builds" 2>&1 | jq '.'

echo "Monitoring build status (checking every 10s)..."
MAX_ATTEMPTS=30
ATTEMPT=0
BUILD_STATUS=""
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    BUILD_STATUS=$(gh api "repos/$OWNER/$REPO/pages" | jq -r '.status // "unknown"')
    echo "[$(date -u +%H:%M:%S)] Attempt $ATTEMPT – Status: $BUILD_STATUS"
    if [ "$BUILD_STATUS" = "built" ]; then
        echo "✅ Build succeeded!"
        break
    elif [ "$BUILD_STATUS" = "errored" ]; then
        echo "❌ Build failed. Fetching error..."
        gh api "repos/$OWNER/$REPO/pages/builds" | jq '.[0].error'
        break
    fi
    sleep 10
done

# ----------------------------------------------------------------------
# 5. Fetch build logs.
# ----------------------------------------------------------------------
echo "Fetching Pages build logs..."
gh api "repos/$OWNER/$REPO/pages/builds" | jq '.'

# ----------------------------------------------------------------------
# 6. Save diagnostics and push.
# ----------------------------------------------------------------------
LOG_FILE="diagnostics/build_$(date -u +%Y%m%d%H%M%S).txt"
gh api "repos/$OWNER/$REPO/pages" > "$LOG_FILE"
git add "$LOG_FILE"
git commit -m "Add build diagnostics" || echo "No changes"
git push origin main

RAW_LINK="https://raw.githubusercontent.com/$OWNER/$REPO/main/$LOG_FILE"
echo
echo "=== RAW LOG LINK ==="
echo "$RAW_LINK"

# ----------------------------------------------------------------------
# 7. Final status.
# ----------------------------------------------------------------------
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PAGES_URL")
echo "Pages status: $BUILD_STATUS"
echo "HTTP: $HTTP_CODE"
if [ "$BUILD_STATUS" = "built" ] && [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Site is live!"
    xdg-open "$PAGES_URL" 2>/dev/null
else
    echo "❌ Site not live. Check the logs above."
fi

echo "=== BUILD REPO COMPLETE ==="
