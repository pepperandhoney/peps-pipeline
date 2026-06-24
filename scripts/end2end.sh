#!/usr/bin/env bash
# end2end.sh — Per-proteome coordinator (MHC-I and MHC-II)
# Usage: bash end2end.sh <MHC1|MHC2> <PROTEOME_KEY>
# Example: bash end2end.sh MHC1 Lbra
# Called by queue.sh. Runs prediction → parsing → GCS backup → cleanup.
set -euo pipefail

SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/scripts}"
DATA_OUT="${DATA_OUT:-/data/out/peptidome/prediction}"

MODE="${1:-}"
PROTEOME="${2:-}"

if [[ -z "$MODE" || -z "$PROTEOME" ]]; then
  echo "Usage: bash $(basename "$0") <MHC1|MHC2> <PROTEOME_KEY>" >&2
  exit 1
fi

MODE="$(echo "$MODE" | tr '[:lower:]' '[:upper:]')"

case "$MODE" in
  MHC1)
    RUNNER="$SCRIPTS_DIR/run_NMP_MHC1.sh"
    PROG="netmhcpan_4.2"
    MHC_DIR="MHC1"
    LEN="9"
    ;;
  MHC2)
    RUNNER="$SCRIPTS_DIR/run_NMP_MHC2.sh"
    PROG="netmhc2pan_4.3"
    MHC_DIR="MHC2"
    LEN="15"
    ;;
  *)
    echo "ERROR: mode must be MHC1 or MHC2" >&2
    exit 1
    ;;
esac

# Verificar que archivos/scripts existen
for file in "$SCRIPTS_DIR/proteomes.tsv" "$RUNNER" \
            "$SCRIPTS_DIR/run_cleanparse.sh" \
            "$SCRIPTS_DIR/gs_backupbucket.sh" \
            "$SCRIPTS_DIR/gs_cleandisk.sh"; do
  if [[ ! -f "$file" ]]; then
    echo "ERROR: missing file $file" >&2
    exit 1
  fi
done

# Validar que proteoma existe en la tabla
if ! grep -q "^${PROTEOME}\t" "$SCRIPTS_DIR/proteomes.tsv"; then
  echo "ERROR: proteome not found in proteomes.tsv: $PROTEOME" >&2
  exit 1
fi

BASE_OUT="$DATA_OUT/$PROTEOME/$MHC_DIR/$PROG"

echo "Running $MODE for $PROTEOME..."
bash "$RUNNER" "$PROTEOME"

# Buscar el último directorio run_*
RUNDIR="$(ls -d "$BASE_OUT"/run_* 2>/dev/null | sort | tail -n 1 || true)"

if [[ -z "$RUNDIR" ]]; then
  echo "ERROR: could not find run dir in $BASE_OUT" >&2
  exit 1
fi

echo "Parsing $RUNDIR..."
bash "$SCRIPTS_DIR/run_cleanparse.sh" "$RUNDIR" "$MODE" "$LEN"

echo "Backing up..."
bash "$SCRIPTS_DIR/gs_backupbucket.sh"

echo "Cleaning disk..."
bash "$SCRIPTS_DIR/gs_cleandisk.sh" "$RUNDIR"

echo "Done: $RUNDIR"