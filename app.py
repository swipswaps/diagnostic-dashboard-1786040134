#!/usr/bin/env python3
# ============================================================================
# app.py – Diagnostic dashboard backend with working routes.
# ============================================================================

import os
import sys
import sqlite3
import json
import datetime
from flask import Flask, jsonify, render_template
from flask_cors import CORS

app = Flask(__name__, static_folder='../frontend/dist', static_url_path='/static')
CORS(app)

# ----------------------------------------------------------------------
# Database configuration (Rule #50: environment variable export gate)
# ----------------------------------------------------------------------
DB_PATH = os.environ.get("DB_PATH", "./diagnostics.db")
print(f"Using database: {DB_PATH}")

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn

def init_db():
    conn = get_db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS diagnostics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id TEXT,
            component TEXT,
            status TEXT,
            line_number INTEGER,
            line_text TEXT,
            logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS rule_compliance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            script_name TEXT,
            rule_id TEXT,
            passed INTEGER,
            evidence TEXT,
            created_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    conn.close()
    print("✅ Database initialized/verified.")

init_db()

# ----------------------------------------------------------------------
# Routes
# ----------------------------------------------------------------------

@app.route("/")
def index():
    try:
        return app.send_static_file('index.html')
    except:
        return jsonify({"message": "Frontend not built. Run 'npm run build' in frontend/"}), 200

@app.route("/api/diagnostics")
def get_diagnostics():
    try:
        conn = get_db()
        rows = conn.execute("SELECT * FROM diagnostics ORDER BY logged_at DESC LIMIT 100").fetchall()
        conn.close()
        result = [dict(row) for row in rows]
        print(f"Returning {len(result)} rows")
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/debug")
def debug():
    try:
        conn = get_db()
        count = conn.execute("SELECT COUNT(*) FROM diagnostics").fetchone()[0]
        conn.close()
        return jsonify({"db_path": DB_PATH, "count": count, "status": "ok"})
    except Exception as e:
        return jsonify({"db_path": DB_PATH, "error": str(e), "status": "error"}), 500

@app.route("/api/health")
def health():
    try:
        conn = get_db()
        conn.execute("SELECT 1")
        conn.close()
        return jsonify({
            "status": "healthy",
            "db": DB_PATH,
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()
        })
    except Exception as e:
        return jsonify({"status": "unhealthy", "error": str(e)}), 503

# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------
if __name__ == "__main__":
    print(f"Starting backend with DB_PATH={DB_PATH}")
    app.run(host="0.0.0.0", port=5001, debug=False, threaded=True)
