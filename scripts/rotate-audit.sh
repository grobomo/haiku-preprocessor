#!/bin/bash
# Rotate analysis.log files in preprocessor instance directories.
# Runs daily via cron. Keeps rotated files 14 days.
#
# Install: crontab -e → 3 3 * * * /path/to/rotate-audit.sh
#
# Rotates any analysis.log over 5MB, prunes rotated files older than 14 days.

PREPROCESSORS_DIR="${HOME}/.claude/hooks/preprocessors"
MAX_BYTES=$((5 * 1024 * 1024))
RETAIN_DAYS=14

if [ ! -d "$PREPROCESSORS_DIR" ]; then
  exit 0
fi

for instance_dir in "$PREPROCESSORS_DIR"/*/; do
  [ -d "$instance_dir" ] || continue
  log_file="${instance_dir}analysis.log"

  if [ -f "$log_file" ]; then
    size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
    if [ "$size" -gt "$MAX_BYTES" ]; then
      mv "$log_file" "${log_file%.log}-$(date +%Y-%m-%d).log"
    fi
  fi

  # Prune old rotated logs
  find "$instance_dir" -name 'analysis-*.log' -mtime +${RETAIN_DAYS} -delete 2>/dev/null
done
