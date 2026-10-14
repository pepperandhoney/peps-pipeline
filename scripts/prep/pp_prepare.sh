#!/usr/bin/env bash
# pp_prepare.sh — clean a proteome and renumber it, in one step
#
# The two things that must happen before any prediction:
#
#   1. cleaning     strip gaps, drop sequences shorter than MINLEN or containing
#                   a non-standard residue (X, B, Z, J, U, O, *)
#   2. renumbering  replace headers with identifiers that survive the predictors'
#                   15-character truncation (see pp_renumber.sh)
#
# Dropping a whole protein because of one X is deliberate: the predictors treat
# unknown residues inconsistently, and a protein with an unresolved position is
# not a reliable source of candidate peptides. The count of what was removed is
# printed, and any peptide expected from a dropped protein will be missing from
# the universe downstream -- worth checking when a benchmark expects specific
# peptides to be present.
#
# USAGE
#   bash pp_prepare.sh <PREFIX> <RAW_FASTA> [MINLEN]
#
#   bash pp_prepare.sh LAET /data/in/proteomes/TriTrypDB-67_LaethiopicaL147.fasta
#   bash pp_prepare.sh INF1 /data/in/proteomes/influenza_PR8.faa 8
#
# OUTPUT
#   $PEPS_DATA_IN/clean/<PREFIX>.clean.faa
#   $PEPS_DATA_IN/renamed/<PREFIX>.faa
#   $PEPS_DATA_IN/renamed/<PREFIX>.iddict.tsv
#
# Cleaning uses seqkit when available and an awk implementation of the same two
# rules otherwise.
set -euo pipefail

_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_d" != "/" && ! -f "$_d/lib/peps_common.sh" ]]; do _d="$(dirname "$_d")"; done
[[ -f "$_d/lib/peps_common.sh" ]] || { echo "ERROR: lib/peps_common.sh not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$_d/lib/peps_common.sh"

PREFIX="${1:-}"
RAW="${2:-}"
MINLEN="${3:-8}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$PREFIX" || -z "$RAW" ]]; then
  echo "Usage: bash $(basename "$0") <PREFIX> <RAW_FASTA> [MINLEN]" >&2
  exit 1
fi
peps_require_file "$RAW"
[[ "$PREFIX" =~ ^[A-Z0-9]{4}$ ]] \
  || peps_die "prefix must be exactly 4 uppercase alphanumeric characters: $PREFIX"

CLEAN_DIR="$PEPS_DATA_IN/clean"
RENAMED_DIR="$PEPS_DATA_IN/renamed"
mkdir -p "$CLEAN_DIR" "$RENAMED_DIR"
CLEAN="$CLEAN_DIR/$PREFIX.clean.faa"

peps_section "PREPARE  $PREFIX"
echo "  raw      : $RAW"
echo "  min len  : $MINLEN"
echo ""

# --- 1. clean --------------------------------------------------------------
peps_log "[1/2] cleaning"
if command -v seqkit >/dev/null 2>&1; then
  seqkit seq -g -m "$MINLEN" "$RAW" 2>/dev/null | seqkit grep -s -v -p "X" > "$CLEAN" 2>/dev/null
  echo "        using seqkit"
else
  awk -v minlen="$MINLEN" '
    function flush_rec() {
      if (hdr != "" && length(seq) >= minlen && seq !~ /[XBZJUO*]/)
        print hdr "\n" seq
    }
    /^>/ { flush_rec(); hdr = $0; seq = ""; next }
    { gsub(/[ \t\r\n-]/, ""); seq = seq toupper($0) }
    END { flush_rec() }
  ' "$RAW" > "$CLEAN"
  echo "        using awk (seqkit not installed)"
fi

N_RAW="$(grep -c '^>' "$RAW" || true)"
N_CLEAN="$(grep -c '^>' "$CLEAN" || true)"
echo "        $N_RAW -> $N_CLEAN proteins  ($((N_RAW - N_CLEAN)) removed)"
[[ "$N_CLEAN" -gt 0 ]] || peps_die "cleaning removed every sequence; check MINLEN and the input"
echo ""

# --- 2. renumber -----------------------------------------------------------
peps_log "[2/2] renumbering"
bash "$HERE/pp_renumber.sh" "$PREFIX" "$CLEAN" "$RENAMED_DIR"

echo ""
echo "Add this row to $PEPS_REGISTRY if it is not there yet:"
printf '  %s\t<organism>\trenamed\t%s.faa\t%s\n' "$PREFIX" "$PREFIX" "$PREFIX"
