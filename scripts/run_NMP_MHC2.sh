#!/usr/bin/env bash
# run_NMP_MHC2.sh — NetMHC2pan 4.3 parallel runner (MHC-II)
# Usage: bash run_NMP_MHC2.sh <PROTEOME_KEY>
# Example: bash run_NMP_MHC2.sh Lbra
# Called by end2end.sh. Requires proteomes.tsv and alleles_mhc2.txt.
set -euo pipefail

IMAGE="netmhc2pan:4.3"
TOOL="/work/netMHCIIpan-4.3/netMHCIIpan"
RDIR="/work/netMHCIIpan-4.3"

SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/scripts}"
DATA_IN="${DATA_IN:-/data/in/proteomes}"
DATA_OUT="${DATA_OUT:-/data/out/peptidome}"

PROTEOME_TABLE="$SCRIPTS_DIR/proteomes.tsv"
ALLELES_FILE_IN="$SCRIPTS_DIR/alleles_mhc2.txt"

MHC="MHC2"
PROG="netmhc2pan_4.3"
LEN="15"
INPTYPE="0"
USE_BA="1"
EXTRA_FLAGS=""
MAX_PARALLEL="6"

if [[ $# -ne 1 ]]; then
  echo "Usage: bash $(basename "$0") <PROTEOME_KEY>" >&2
  exit 1
fi

PROTEOME_KEY="$1"

# Validar requisitos
[[ -f "$PROTEOME_TABLE" ]] || { echo "ERROR: missing $PROTEOME_TABLE" >&2; exit 1; }
[[ -f "$ALLELES_FILE_IN" ]] || { echo "ERROR: missing $ALLELES_FILE_IN" >&2; exit 1; }
command -v docker &>/dev/null || { echo "ERROR: docker not found" >&2; exit 1; }

row="$(awk -F'\t' -v k="$PROTEOME_KEY" '$1==k {print $0}' "$PROTEOME_TABLE")"
[[ -n "$row" ]] || { echo "ERROR: proteome key not found: $PROTEOME_KEY" >&2; exit 1; }

IFS=$'\t' read -r PROTEOME INPUT_MODE IN_FASTA_FILE PREFIX_BASE <<< "$row"
PREFIX="${PREFIX_BASE}_mhc2"

mapfile -t ALLELES < <(grep -Ev '^\s*$|^\s*#' "$ALLELES_FILE_IN")
[[ "${#ALLELES[@]}" -gt 0 ]] || { echo "ERROR: no alleles found" >&2; exit 1; }

case "$INPUT_MODE" in
  clean)    IN_FASTA="$DATA_IN/clean/${IN_FASTA_FILE}" ;;
  original) IN_FASTA="$DATA_IN/${IN_FASTA_FILE}" ;;
  *)
    echo "ERROR: INPUT_MODE must be clean or original" >&2
    exit 1
    ;;
esac

[[ -f "$IN_FASTA" ]] || { echo "ERROR: Input FASTA not found: $IN_FASTA" >&2; exit 1; }

BASE_OUT="$DATA_OUT/prediction/${PROTEOME}/${MHC}/${PROG}"
mkdir -p "$BASE_OUT" "$BASE_OUT/_trash"

# Generar RUN_ID único con lock
COUNTER="${BASE_OUT}/.next_run_id"
{
  flock -n 200 || { echo "ERROR: another instance running" >&2; exit 1; }
  RUN_ID="$(cat "$COUNTER" 2>/dev/null || echo 1)"
  echo "$((RUN_ID+1))" > "$COUNTER"
} 200>"${COUNTER}.lock"
RUN_PAD="$(printf "%03d" "$RUN_ID")"

RUNDIR="${BASE_OUT}/run_${RUN_PAD}"
mkdir -p "$RUNDIR"/_trash "$RUNDIR"/raw "$RUNDIR"/err \
         "$RUNDIR"/alleles "$RUNDIR"/meta "$RUNDIR"/logs "$RUNDIR"/cp

echo "RUN FOLDER: $RUNDIR"

# Construir FLAGS
FLAGS=()
FLAGS+=("-inptype" "$INPTYPE")
FLAGS+=("-length" "$LEN")
[[ "$USE_BA" == "1" ]] && FLAGS+=("-BA")
[[ -n "$EXTRA_FLAGS" ]] && FLAGS+=(${EXTRA_FLAGS})

FLAGS_STR="$(printf " %q" "${FLAGS[@]}")"
FLAGS_STR="${FLAGS_STR# }"

# Metadatos
RUN_WHAT="${RUNDIR}/WHAT.txt"
{
  echo "WHAT: NetMHCIIpan 4.3 parallel run (MHC-II)"
  echo "run_id:        run_${RUN_PAD}"
  echo "proteome:      ${PROTEOME}"
  echo "mhc:           ${MHC}"
  echo "program:       ${PROG}"
  echo "docker_image:  ${IMAGE}"
  echo "input_fasta:   ${IN_FASTA}"
  echo "input_mode:    ${INPUT_MODE}"
  echo "alleles_n:     ${#ALLELES[@]}"
  echo "peptide_len:   ${LEN}"
  echo "inptype:       ${INPTYPE}"
  echo "flags:         ${FLAGS_STR}"
  echo "parallel_jobs: ${MAX_PARALLEL}"
  echo "prefix:        ${PREFIX}"
  echo "alleles_src:   ${ALLELES_FILE_IN}"
  echo "note:          raw/ and err/ are predictor outputs; cp/ is reserved for clean/parse."
} > "$RUN_WHAT"

TS_UTC="$(date -u +%Y%m%d_%H%M%S)"
META_FILE="${RUNDIR}/meta/run.meta.txt"
{
  echo "run_id:       run_${RUN_PAD}"
  echo "timestamp:    ${TS_UTC} (UTC)"
  echo "image:        ${IMAGE}"
  echo "tool:         ${TOOL}"
  echo "rdir:         ${RDIR}"
  echo "proteome:     ${PROTEOME}"
  echo "input_fasta:  ${IN_FASTA}"
  echo "input_mode:   ${INPUT_MODE}"
  echo "alleles_n:    ${#ALLELES[@]}"
  echo "length:       ${LEN}"
  echo "inptype:      ${INPTYPE}"
  echo "use_BA:       ${USE_BA}"
  echo "extra_flags:  ${EXTRA_FLAGS}"
  echo "flags:        ${FLAGS_STR}"
  echo "max_parallel: ${MAX_PARALLEL}"
  echo "prefix:       ${PREFIX}"
  echo "host:         $(hostname)"
  echo "user:         $(id -u):$(id -g)"
} > "$META_FILE"

ALLELE_FILE="${RUNDIR}/alleles/alleles.txt"
printf "%s\n" "${ALLELES[@]}" > "$ALLELE_FILE"

RUNLOG="${RUNDIR}/logs/runner.log"

# Trap para Ctrl+C
trap 'echo "Interrupted at $(date -u)" >> "$RUNLOG"; wait 2>/dev/null || true; exit 1' INT TERM

echo "START $(date -u)" | tee -a "$RUNLOG"
echo "RUN: run_${RUN_PAD}" | tee -a "$RUNLOG"
echo "FLAGS: ${FLAGS_STR}" | tee -a "$RUNLOG"

sanitize_for_filename() {
  local safe
  safe="$(echo "$1" | sed -E 's/[^A-Za-z0-9._-]+/_/g')"
  [[ -n "$safe" ]] || safe="unknown"
  echo "$safe"
}

declare -A JOB_PIDS

run_one_allele() {
  local allele="$1"
  local label out err exitcode=0
  label="$(sanitize_for_filename "$allele")"

  out="${RUNDIR}/raw/${PREFIX}.${label}.len${LEN}.out"
  err="${RUNDIR}/err/${PREFIX}.${label}.len${LEN}.err"

  # Saltar si ya completado (busca línea de header)
  if [[ -f "$out" && -f "$err" ]] && grep -q "^# Rank" "$out" 2>/dev/null; then
    echo "SKIP: $allele (already completed)" | tee -a "$RUNLOG"
    return 0
  fi

  echo "START: $allele $(date -u)" | tee -a "$RUNLOG"

  docker run --rm --user "$(id -u):$(id -g)" \
    -v "$DATA_IN:$DATA_IN:ro" \
    -v "$DATA_OUT:$DATA_OUT" \
    "$IMAGE" \
    bash -lc "
      set -euo pipefail
      export TMPDIR=/tmp
      '$TOOL' -rdir '$RDIR' \
        -f '$IN_FASTA' \
        -a '$allele' \
        ${FLAGS_STR} \
        > '$out' 2> '$err'
    " || exitcode=$?

  if [[ $exitcode -ne 0 ]]; then
    echo "ERROR: $allele failed with exit code $exitcode" | tee -a "$RUNLOG"
    return $exitcode
  fi

  echo "DONE: $allele $(date -u)" | tee -a "$RUNLOG"
}

wait_for_slot() {
  while [[ "$(jobs -rp | wc -l)" -ge "$MAX_PARALLEL" ]]; do
    sleep 1
  done
}

for allele in "${ALLELES[@]}"; do
  wait_for_slot
  run_one_allele "$allele" &
  JOB_PIDS[$!]="$allele"
done

# Esperar y capturar fallos
FAILED=0
for pid in "${!JOB_PIDS[@]}"; do
  if ! wait "$pid" 2>/dev/null; then
    echo "FAILED: ${JOB_PIDS[$pid]}" | tee -a "$RUNLOG"
    ((FAILED++))
  fi
done

if [[ $FAILED -gt 0 ]]; then
  echo "FAILED: $FAILED alleles" | tee -a "$RUNLOG"
  exit 1
fi

echo "DONE $(date -u)" | tee -a "$RUNLOG"
echo "✓ All alleles completed"
echo "  RAW outputs:  ${RUNDIR}/raw"
echo "  ERR outputs:  ${RUNDIR}/err"
echo "  META:         ${RUNDIR}/meta"
echo "  RUNDIR:       $RUNDIR"