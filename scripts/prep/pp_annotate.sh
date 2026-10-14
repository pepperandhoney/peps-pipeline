#!/usr/bin/env bash
# pp_annotate.sh — put the original accessions back into a parsed table
#
# Prediction runs on short identifiers (LAETP000001) so that nothing is lost to
# the predictors' 15-character truncation. This script joins them back against
# the dictionary pp_renumber.sh wrote, appending two columns:
#
#       original_id    the accession as it appeared in the source FASTA
#       description    the rest of the original header
#
# end2end.sh calls this automatically after parsing. v2 shipped the script but
# never invoked it, so merged tables kept only the short identifiers and the
# accession had to be restored by hand.
#
# USAGE
#   bash pp_annotate.sh <INPUT_TSV> [OUTPUT_TSV] [ID_COLUMN]
#
#   bash pp_annotate.sh merged_mhc1.tsv
#   bash pp_annotate.sh candidates.tsv annotated.tsv protein_id
#
#   The default identifier column is "Identity", which is what the parsers emit.
#   The default output is <input>_annotated.tsv.
#
# ENVIRONMENT
#   DICT=...   dictionary to join against
#              (default: $PEPS_DATA_IN/renamed/iddict_global.tsv)
set -euo pipefail

_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_d" != "/" && ! -f "$_d/lib/peps_common.sh" ]]; do _d="$(dirname "$_d")"; done
[[ -f "$_d/lib/peps_common.sh" ]] || { echo "ERROR: lib/peps_common.sh not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$_d/lib/peps_common.sh"

IN="${1:-}"
OUT="${2:-}"
IDCOL="${3:-Identity}"
DICT="${DICT:-$PEPS_IDDICT}"

if [[ -z "$IN" ]]; then
  echo "Usage: bash $(basename "$0") <INPUT_TSV> [OUTPUT_TSV] [ID_COLUMN]" >&2
  exit 1
fi
peps_require_file "$IN"
[[ -s "$DICT" ]] || peps_die "dictionary not found: $DICT
       Set DICT=... or run pp_prepare.sh first."

OUT="${OUT:-${IN%.tsv}_annotated.tsv}"

awk -F'\t' -v OFS='\t' -v dict="$DICT" -v idcol="$IDCOL" '
BEGIN {
    getline < dict                       # discard the dictionary header
    while ((getline line < dict) > 0) {
        split(line, d, "\t")
        ORIG[d[1]] = d[2]
        DESC[d[1]] = d[4]
    }
    close(dict)
}
NR == 1 {
    for (i = 1; i <= NF; i++) if ($i == idcol) col = i
    if (!col) {
        print "ERROR: column not found in input: " idcol > "/dev/stderr"
        exit 1
    }
    print $0, "original_id", "description"
    next
}
{
    id = $col
    print $0, (id in ORIG ? ORIG[id] : "NA"), (id in DESC ? DESC[id] : "NA")
}
' "$IN" > "$OUT"

TOTAL=$(( $(wc -l < "$OUT") - 1 ))
MATCHED=$(awk -F'\t' 'NR>1 && $(NF-1) != "NA"' "$OUT" | wc -l)
PCT=0; [[ "$TOTAL" -gt 0 ]] && PCT=$(( MATCHED * 100 / TOTAL ))

echo "  input      : $IN"
echo "  dictionary : $DICT"
echo "  output     : $OUT"
echo "  rows       : $TOTAL"
echo "  resolved   : $MATCHED  (${PCT}%)"

if [[ "$MATCHED" -lt "$TOTAL" ]]; then
  peps_warn "$((TOTAL - MATCHED)) rows did not resolve."
  peps_warn "The dictionary may not cover this proteome, or the run used a"
  peps_warn "FASTA whose headers were never renumbered."
fi
