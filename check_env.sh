#!/usr/bin/env bash
export DB_PATH="${DB_PATH:-./diagnostics.db}"
for var in DB_PATH; do
    if [ -z "${!var}" ]; then
        echo "ERROR: $var is empty after export" >&2
        exit 1
    fi
done
echo "✅ Environment variables set: DB_PATH=$DB_PATH"
