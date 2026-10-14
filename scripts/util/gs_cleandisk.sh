#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
# usage:
#   bash gs_cleandisk.sh /path/to/run_###
# Environment:
#   DRY_RUN=1    -> only print actions, do not delete
#   TRASH_MODE=1 -> move removed dirs to _trash/clean_TIMESTAMP instead of deleting

RUNDIR="${1:-}"
if [[ -z "$RUNDIR" ]]; then
  echo "Usage: bash $(basename "$0") <RUNDIR>" >&2
  exit 1
fi
if [[ ! -d "$RUNDIR" ]]; then
  echo "ERROR: RUNDIR not found: $RUNDIR" >&2
  exit 1
fi
if [[ ! -d "$RUNDIR/cp" ]]; then
  echo "ERROR: cp/ not found in $RUNDIR" >&2
  exit 1
fi

# Normalize to absolute path when possible
if command -v readlink >/dev/null 2>&1; then
  RUNDIR="$(readlink -f "$RUNDIR")"
fi

# Refuse dangerous targets
case "$RUNDIR" in
  /|""|"$HOME"|/root)
    echo "Refusing to operate on unsafe target: $RUNDIR" >&2
    exit 1
    ;;
esac

DRY_RUN="${DRY_RUN:-0}"
TRASH_MODE="${TRASH_MODE:-0}"
TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"
TRASHDIR="$RUNDIR/_trash/clean_$TIMESTAMP"

echo "Cleaning: $RUNDIR"

for rel in raw err cp/cleanout; do
  p="$RUNDIR/$rel"
  if [[ -e "$p" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      echo "[DRY-RUN] Would remove: $p"
      continue
    fi

    if [[ "$TRASH_MODE" == "1" ]]; then
      mkdir -p "$TRASHDIR"
      echo "Moving $p -> $TRASHDIR/"
      mv -- "$p" "$TRASHDIR/"
    else
      echo "Removing $p"
      rm -rf -- "$p"
    fi
  else
    echo "Not found, skipping: $p"
  fi
done

echo "Done."
