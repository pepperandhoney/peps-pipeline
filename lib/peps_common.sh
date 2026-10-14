#!/usr/bin/env bash
# peps_common.sh — shared foundation for every peps-pipeline script
#
# Source it from any script, at any depth, with:
#
#     source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/peps_common.sh"
#
# or, more robustly, by searching upwards:
#
#     _d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#     while [[ "$_d" != "/" && ! -f "$_d/lib/peps_common.sh" ]]; do _d="$(dirname "$_d")"; done
#     source "$_d/lib/peps_common.sh"
#
# WHAT IT PROVIDES
#   Paths            PEPS_ROOT, PEPS_LIB, PEPS_SCRIPTS, PEPS_CONFIG,
#                    PEPS_DATA_IN, PEPS_DATA_OUT
#   Logging          peps_log, peps_warn, peps_die, peps_section
#   Validation       peps_require_cmd, peps_require_file, peps_require_dir
#   Registry         peps_registry_row, peps_registry_keys, peps_fasta_path
#   Mode config      peps_mode_config, peps_lengths
#   Run directories  peps_next_run_id, peps_init_rundir, peps_find_rundir
#   Misc             peps_sanitize, peps_utc
#
# Every value can be overridden from the environment before sourcing, so the
# pipeline runs unchanged on a laptop, a VM or inside CI.
# ---------------------------------------------------------------------------

# Guard against double sourcing.
[[ -n "${PEPS_COMMON_LOADED:-}" ]] && return 0
PEPS_COMMON_LOADED=1

export LC_ALL=C

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# Resolve the repository root from this file's own location: lib/ is always
# one level below the root, so nothing depends on the caller's directory.
_peps_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEPS_ROOT="${PEPS_ROOT:-$(cd "$_peps_lib_dir/.." && pwd)}"
PEPS_LIB="$_peps_lib_dir"
PEPS_SCRIPTS="${PEPS_SCRIPTS:-$PEPS_ROOT/scripts}"
PEPS_CONFIG="${PEPS_CONFIG:-$PEPS_ROOT/configs}"

# Data lives outside the repository.
PEPS_DATA_IN="${PEPS_DATA_IN:-/data/in/proteomes}"
PEPS_DATA_OUT="${PEPS_DATA_OUT:-/data/out}"

PEPS_REGISTRY="${PEPS_REGISTRY:-$PEPS_CONFIG/proteomes.tsv}"
PEPS_SOURCES="${PEPS_SOURCES:-$PEPS_CONFIG/proteome_sources.tsv}"
PEPS_IDDICT="${PEPS_IDDICT:-$PEPS_DATA_IN/renamed/iddict_global.tsv}"

export PEPS_ROOT PEPS_LIB PEPS_SCRIPTS PEPS_CONFIG
export PEPS_DATA_IN PEPS_DATA_OUT PEPS_REGISTRY PEPS_SOURCES PEPS_IDDICT

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

peps_utc() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

peps_log()     { printf '[%s] %s\n'      "$(peps_utc)" "$*"; }
peps_warn()    { printf '[%s] WARN: %s\n' "$(peps_utc)" "$*" >&2; }
peps_die()     { printf '[%s] ERROR: %s\n' "$(peps_utc)" "$*" >&2; exit 1; }
peps_section() { printf '\n=== %s ===\n' "$*"; }

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

peps_require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || peps_die "required command not found: $c"
  done
}

peps_require_file() {
  for f in "$@"; do
    [[ -f "$f" ]] || peps_die "required file not found: $f"
  done
}

peps_require_dir() {
  for d in "$@"; do
    [[ -d "$d" ]] || peps_die "required directory not found: $d"
  done
}

# Make a string safe to use inside a filename.
peps_sanitize() {
  local s
  s="$(printf '%s' "$1" | sed -E 's/[^A-Za-z0-9._-]+/_/g')"
  printf '%s' "${s:-unknown}"
}

# ---------------------------------------------------------------------------
# Proteome registry
#
# configs/proteomes.tsv has five tab-separated columns and one header line:
#
#     key   organism   input_mode   fasta_file   prefix
#
# The key and the prefix must be the same string. v1 allowed them to drift and
# the same proteome ended up labelled three different ways.
# ---------------------------------------------------------------------------

# peps_registry_row KEY
# Sets PROTEOME_KEY, PROTEOME_ORGANISM, PROTEOME_INPUT_MODE,
# PROTEOME_FASTA_FILE, PROTEOME_PREFIX. Returns non-zero when the key is absent.
peps_registry_row() {
  local key="${1:?peps_registry_row: provide a key}"
  peps_require_file "$PEPS_REGISTRY"

  local row
  row="$(awk -F'\t' -v k="$key" 'NR>1 && $1==k {print; exit}' "$PEPS_REGISTRY")"
  [[ -n "$row" ]] || return 1

  IFS=$'\t' read -r PROTEOME_KEY PROTEOME_ORGANISM PROTEOME_INPUT_MODE \
                   PROTEOME_FASTA_FILE PROTEOME_PREFIX <<< "$row"

  [[ -n "$PROTEOME_ORGANISM"   ]] || peps_die "registry: empty organism for $key"
  [[ -n "$PROTEOME_INPUT_MODE" ]] || peps_die "registry: empty input_mode for $key"
  [[ -n "$PROTEOME_FASTA_FILE" ]] || peps_die "registry: empty fasta_file for $key"
  [[ -n "$PROTEOME_PREFIX"     ]] || peps_die "registry: empty prefix for $key"

  if [[ "$PROTEOME_KEY" != "$PROTEOME_PREFIX" ]]; then
    peps_warn "registry: key ($PROTEOME_KEY) and prefix ($PROTEOME_PREFIX) differ."
    peps_warn "          This is what produced inconsistent dataset labels in v1."
  fi
  return 0
}

# peps_registry_keys [ORGANISM]
# Prints every key, or only those of one organism.
peps_registry_keys() {
  local filter="${1:-}"
  peps_require_file "$PEPS_REGISTRY"
  awk -F'\t' -v f="$filter" '
    NR==1 || $1 ~ /^#/ || $1=="" {next}
    f=="" || $2==f {print $1}' "$PEPS_REGISTRY"
}

# peps_registry_organisms
peps_registry_organisms() {
  peps_require_file "$PEPS_REGISTRY"
  awk -F'\t' 'NR>1 && $1 !~ /^#/ && $2!="" {print $2}' "$PEPS_REGISTRY" | sort -u
}

# peps_fasta_path INPUT_MODE FASTA_FILE
# Resolves the FASTA according to the input mode and warns when the headers
# have not been renumbered, because NetMHCpan truncates them to 15 characters.
peps_fasta_path() {
  local mode="${1:?}" file="${2:?}" path
  case "$mode" in
    renamed)  path="$PEPS_DATA_IN/renamed/$file" ;;
    clean)    path="$PEPS_DATA_IN/clean/$file" ;;
    original) path="$PEPS_DATA_IN/$file" ;;
    *) peps_die "input_mode must be renamed, clean or original (got: $mode)" ;;
  esac
  if [[ "$mode" != "renamed" ]]; then
    peps_warn "input_mode is '$mode', not 'renamed'."
    peps_warn "         NetMHCpan truncates headers to 15 characters and replaces"
    peps_warn "         dots with underscores, so the protein of origin may not be"
    peps_warn "         recoverable. Run pp_prepare.sh unless this is intentional."
  fi
  printf '%s' "$path"
}

# ---------------------------------------------------------------------------
# Mode configuration
#
# One place that knows what MHC1 and MHC2 mean. Adding a predictor version is
# a change here and nowhere else.
# ---------------------------------------------------------------------------

# peps_mode_config MODE
# Sets MODE, MHC_DIR, PROG, IMAGE, TOOL, RDIR, ALLELES_FILE, DEFAULT_LENGTHS.
peps_mode_config() {
  local mode
  mode="$(printf '%s' "${1:?peps_mode_config: provide MHC1 or MHC2}" | tr '[:lower:]' '[:upper:]')"
  case "$mode" in
    MHC1)
      MODE="MHC1"
      MHC_DIR="MHC1"
      PROG="${PEPS_PROG_MHC1:-netmhcpan_4.2}"
      IMAGE="${PEPS_IMAGE_MHC1:-netmhcpan:4.2}"
      TOOL="${PEPS_TOOL_MHC1:-/work/netMHCpan-4.2/netMHCpan}"
      RDIR=""
      ALLELES_FILE="${PEPS_ALLELES_MHC1:-$PEPS_CONFIG/alleles_mhc1.txt}"
      DEFAULT_LENGTHS="9"
      ;;
    MHC2)
      MODE="MHC2"
      MHC_DIR="MHC2"
      PROG="${PEPS_PROG_MHC2:-netmhc2pan_4.3}"
      IMAGE="${PEPS_IMAGE_MHC2:-netmhc2pan:4.3}"
      TOOL="${PEPS_TOOL_MHC2:-/work/netMHCIIpan-4.3/netMHCIIpan}"
      RDIR="${PEPS_RDIR_MHC2:-/work/netMHCIIpan-4.3}"
      ALLELES_FILE="${PEPS_ALLELES_MHC2:-$PEPS_CONFIG/alleles_mhc2.txt}"
      DEFAULT_LENGTHS="15"
      ;;
    *) peps_die "mode must be MHC1 or MHC2 (got: $1)" ;;
  esac
}

# peps_lengths MODE
# Prints the whitespace-separated list of peptide lengths for a mode.
#
# Precedence, highest first:
#   1. PEPS_LENGTHS            (applies to whichever mode is running)
#   2. PEPS_LENGTHS_MHC1 / _MHC2
#   3. configs/lengths.conf
#   4. the mode default (9 for class I, 15 for class II)
#
# v1 and v2 hard-coded a single length in three different files. Running the
# multilength campaigns the immunopeptidome benchmark needs meant editing all
# of them, which is how bee.sh ended up with a length list missing 15.
peps_lengths() {
  local mode conf var val
  mode="$(printf '%s' "${1:?peps_lengths: provide MHC1 or MHC2}" | tr '[:lower:]' '[:upper:]')"

  if [[ -n "${PEPS_LENGTHS:-}" ]]; then
    printf '%s' "${PEPS_LENGTHS//,/ }"; return 0
  fi

  var="PEPS_LENGTHS_${mode}"
  val="${!var:-}"
  if [[ -n "$val" ]]; then
    printf '%s' "${val//,/ }"; return 0
  fi

  conf="${PEPS_LENGTHS_CONF:-$PEPS_CONFIG/lengths.conf}"
  if [[ -f "$conf" ]]; then
    val="$(awk -F'=' -v k="${mode}_LENGTHS" '
      $0 ~ /^[[:space:]]*#/ {next}
      {gsub(/[[:space:]"]/,"")}
      $1==k {print $2; exit}' "$conf")"
    if [[ -n "$val" ]]; then
      printf '%s' "${val//,/ }"; return 0
    fi
  fi

  peps_mode_config "$mode"
  printf '%s' "$DEFAULT_LENGTHS"
}

# peps_read_alleles FILE  — prints one allele per line, comments and blanks removed
peps_read_alleles() {
  local f="${1:?}"
  peps_require_file "$f"
  grep -Ev '^[[:space:]]*$|^[[:space:]]*#' "$f"
}

# ---------------------------------------------------------------------------
# Run directories
#
# Layout:  $PEPS_DATA_OUT/<organism>/prediction/<key>/<MHC1|MHC2>/<prog>/run_NNN
# Runs are numbered and never overwritten.
# ---------------------------------------------------------------------------

# peps_base_out ORGANISM KEY MHC_DIR PROG
peps_base_out() {
  printf '%s/%s/prediction/%s/%s/%s' \
    "$PEPS_DATA_OUT" "${1:?}" "${2:?}" "${3:?}" "${4:?}"
}

# peps_next_run_id BASE_OUT  — atomically allocates the next run number
peps_next_run_id() {
  local base="${1:?}" counter run_id
  mkdir -p "$base"
  counter="$base/.next_run_id"
  {
    flock -w 30 200 || peps_die "could not lock $counter (another run in progress?)"
    run_id="$(cat "$counter" 2>/dev/null || echo 1)"
    [[ "$run_id" =~ ^[0-9]+$ ]] || run_id=1
    echo "$((run_id + 1))" > "$counter"
  } 200>"${counter}.lock"
  printf '%03d' "$run_id"
}

# peps_init_rundir BASE_OUT RUN_PAD  — creates the subdirectories, prints the path
peps_init_rundir() {
  local base="${1:?}" pad="${2:?}" rundir
  rundir="$base/run_$pad"
  mkdir -p "$rundir"/{raw,err,alleles,meta,logs,_trash} \
           "$rundir"/cp/{cleanout,parse,merged,meta}
  printf '%s' "$rundir"
}

# peps_find_rundir BASE_OUT  — newest existing run directory
peps_find_rundir() {
  local base="${1:?}"
  ls -d "$base"/run_* 2>/dev/null | sort | tail -n 1
}

# peps_write_meta RUNDIR KEY=VALUE...
peps_write_meta() {
  local rundir="${1:?}"; shift
  local f="$rundir/meta/run.meta.txt"
  mkdir -p "$(dirname "$f")"
  : > "$f"
  printf '%s\n' "$@" >> "$f"
  printf 'host:         %s\n' "$(hostname)" >> "$f"
  printf 'user:         %s\n' "$(id -u):$(id -g)" >> "$f"
  printf 'pipeline:     peps-pipeline v3\n' >> "$f"
  if command -v git >/dev/null 2>&1 && git -C "$PEPS_ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
    printf 'commit:       %s\n' "$(git -C "$PEPS_ROOT" rev-parse --short HEAD)" >> "$f"
  fi
  printf '%s' "$f"
}

# peps_out_basename PREFIX ALLELE LEN  — canonical name for one prediction file
peps_out_basename() {
  printf '%s.%s.len%s' "${1:?}" "$(peps_sanitize "${2:?}")" "${3:?}"
}

# ---------------------------------------------------------------------------
# Self-check: sourcing this file must not leave the shell in a broken state.
# ---------------------------------------------------------------------------
: "${PEPS_ROOT:?peps_common.sh: could not resolve PEPS_ROOT}"
