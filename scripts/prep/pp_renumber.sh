#!/usr/bin/env bash
# pp_renumber.sh — give every protein a short identifier that survives truncation
#
# WHY THIS EXISTS
#   NetMHCpan and NetMHCIIpan truncate the FASTA identifier to 15 characters and
#   replace dots with underscores. An accession such as
#
#       >AIN95104.1 kinesin MCAK-like, putative [Leishmania panamensis]
#
#   comes back as AIN95104_1_MCAK. Reconstructing the original from that is
#   unreliable, and for gene-style identifiers it is impossible:
#   LbrM.01.2.000040 and LbrM.01.2.000041 are 16 characters and both truncate to
#   LbrM_01_2_00004, so two different proteins become one.
#
#   This script replaces every header with a fixed-width identifier that fits,
#   and writes a dictionary so nothing is lost:
#
#       LPANP000001  ->  AIN95104.1  ->  kinesin MCAK-like, putative
#
#   Format: 4-character prefix + "P" + 6 digits = 11 characters, four to spare.
#
# USAGE
#   bash pp_renumber.sh <PREFIX> <INPUT_FASTA> [OUT_DIR]
#
#   bash pp_renumber.sh LAET /data/in/proteomes/clean/LAET.clean.faa
#
# OUTPUT
#   <OUT_DIR>/<PREFIX>.faa           renamed FASTA, ready for prediction
#   <OUT_DIR>/<PREFIX>.iddict.tsv    new_id, original_id, prefix, description
#   <OUT_DIR>/iddict_global.tsv      every dictionary, rebuilt from scratch
set -euo pipefail

_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_d" != "/" && ! -f "$_d/lib/peps_common.sh" ]]; do _d="$(dirname "$_d")"; done
[[ -f "$_d/lib/peps_common.sh" ]] || { echo "ERROR: lib/peps_common.sh not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$_d/lib/peps_common.sh"

PREFIX="${1:-}"
IN_FASTA="${2:-}"
OUT_DIR="${3:-$PEPS_DATA_IN/renamed}"

if [[ -z "$PREFIX" || -z "$IN_FASTA" ]]; then
  echo "Usage: bash $(basename "$0") <PREFIX> <INPUT_FASTA> [OUT_DIR]" >&2
  exit 1
fi

# Exactly four characters, so every identifier has the same width and a
# dictionary lookup is never ambiguous.
[[ "$PREFIX" =~ ^[A-Z0-9]{4}$ ]] \
  || peps_die "prefix must be exactly 4 uppercase alphanumeric characters: $PREFIX"
peps_require_file "$IN_FASTA"
[[ -s "$IN_FASTA" ]] || peps_die "input FASTA is empty: $IN_FASTA"

mkdir -p "$OUT_DIR"
OUT_FASTA="$OUT_DIR/$PREFIX.faa"
OUT_DICT="$OUT_DIR/$PREFIX.iddict.tsv"
GLOBAL_DICT="$OUT_DIR/iddict_global.tsv"

peps_log "renumber  prefix=$PREFIX"
peps_log "          input=$IN_FASTA"
peps_log "          output=$OUT_FASTA"

printf 'new_id\toriginal_id\tprefix\tdescription\n' > "$OUT_DICT"

N="$(awk -v prefix="$PREFIX" -v dict="$OUT_DICT" -v fasta="$OUT_FASTA" '
BEGIN { n = 0 }
/^>/ {
    n++
    id = sprintf("%sP%06d", prefix, n)

    header = substr($0, 2)
    split(header, parts, " ")
    original = parts[1]

    desc = header
    sub(/^[^ ]+[ ]*/, "", desc)
    if (desc == "") desc = "-"
    gsub(/\t/, " ", desc)

    print id "\t" original "\t" prefix "\t" desc >> dict
    print ">" id > fasta
    next
}
{ print > fasta }
END { print n }
' "$IN_FASTA")"

# Rebuild the global dictionary from every per-proteome file, so re-running one
# proteome never leaves a stale duplicate behind.
{
  printf 'new_id\toriginal_id\tprefix\tdescription\n'
  for d in "$OUT_DIR"/*.iddict.tsv; do
    [[ -s "$d" ]] && tail -n +2 "$d"
  done
} > "$GLOBAL_DICT.tmp"
mv "$GLOBAL_DICT.tmp" "$GLOBAL_DICT"

MAXLEN="$(awk -F'\t' 'NR>1 {if (length($1) > m) m = length($1)} END {print m+0}' "$OUT_DICT")"
NDUP="$(awk -F'\t' 'NR>1 {print $1}' "$OUT_DICT" | sort | uniq -d | wc -l)"
NFASTA="$(grep -c '^>' "$OUT_FASTA")"
NGLOB=$(( $(wc -l < "$GLOBAL_DICT") - 1 ))

echo "  proteins renamed  : $N"
echo "  headers in FASTA  : $NFASTA"
echo "  max id length     : $MAXLEN  (the predictors truncate at 15)"
echo "  duplicate ids     : $NDUP"
echo "  dictionary        : $OUT_DICT"
echo "  global dictionary : $GLOBAL_DICT ($NGLOB entries)"

[[ "$MAXLEN" -le 15 ]]   || peps_die "identifiers exceed 15 characters"
[[ "$NDUP" -eq 0 ]]      || peps_die "duplicate identifiers generated"
[[ "$N" -eq "$NFASTA" ]] || peps_die "dictionary and FASTA disagree on the protein count"

peps_log "renumber OK"
