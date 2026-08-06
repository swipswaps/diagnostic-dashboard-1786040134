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
