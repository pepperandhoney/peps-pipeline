#!/usr/bin/env bash
# gs_backupbucket.sh — Sync /data and scripts to GCS backup bucket
# Usage: bash gs_backupbucket.sh
# Called by end2end.sh after each prediction run.
set -euo pipefail
export LC_ALL=C

BUCKET="${BUCKET:-gs://vm1-peps-backup}"
LOG="${LOG:-$HOME/gs-backup.log}"

mkdir -p "$(dirname "$LOG")"
command -v gsutil >/dev/null || { echo "ERROR: gsutil not found" >&2; exit 1; }

echo "===== Backup started: $(date) =====" >> "$LOG"

gsutil -m rsync -r \
  -x '.*\/\._.*|.*\/tmp\/.*' \
  /data "$BUCKET/data" >> "$LOG" 2>&1 || echo "WARNING: /data backup failed at $(date)" >> "$LOG"

gsutil -m rsync -r \
  "$HOME/scripts" "$BUCKET/home_scripts" >> "$LOG" 2>&1 || echo "WARNING: scripts backup failed at $(date)" >> "$LOG"

echo "===== Backup finished: $(date) =====" >> "$LOG"

exit 0