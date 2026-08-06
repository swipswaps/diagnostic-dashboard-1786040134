#!/usr/bin/env python3
import os, sys, sqlite3, json, datetime
from flask import Flask, request, jsonify, render_template
from flask_cors import CORS
CORS(app)
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
