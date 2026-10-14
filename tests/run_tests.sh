#!/usr/bin/env bash
# run_tests.sh — the whole pipeline except prediction itself
#
#   bash tests/run_tests.sh
#
# Docker is not needed. A small Python stand-in produces output shaped like
# NetMHCpan's, including the two behaviours the pipeline exists to work around:
# identifiers truncated to 15 characters, and dots turned into underscores.
#
# Covered: the library, the registry, renumbering, the truncation collision and
# its fix, both parsers, merging, QC (passing and failing), and the annotation
# round trip.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d -t peps_tests_XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { printf '  \033[32mok\033[0m   %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; FAIL=$((FAIL+1)); }
head2() { printf '\n\033[1m%s\033[0m\n' "$1"; }

check() { # check DESC EXPECTED ACTUAL
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi
}

export PEPS_DATA_IN="$TMP/in/proteomes"
export PEPS_DATA_OUT="$TMP/out"
export PEPS_CONFIG="$TMP/configs"
mkdir -p "$PEPS_DATA_IN" "$PEPS_DATA_OUT" "$PEPS_CONFIG"
cp "$ROOT/configs/lengths.conf" "$PEPS_CONFIG/" 2>/dev/null || true

# ---------------------------------------------------------------------------
head2 "1. Syntax"
# ---------------------------------------------------------------------------
while IFS= read -r f; do
  if bash -n "$f" 2>/dev/null; then ok "bash -n $(basename "$f")"
  else bad "bash -n $(basename "$f")" "$(bash -n "$f" 2>&1 | head -1)"; fi
done < <(find "$ROOT/lib" "$ROOT/scripts" -name '*.sh' | sort)

# ---------------------------------------------------------------------------
head2 "2. Library"
# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
source "$ROOT/lib/peps_common.sh"
[[ "$PEPS_ROOT" == "$ROOT" ]] && ok "PEPS_ROOT resolves to the repository root" \
                              || bad "PEPS_ROOT" "got $PEPS_ROOT"

check "peps_sanitize strips colons" "HLA-A02_01" "$(peps_sanitize 'HLA-A02:01')"
check "peps_lengths MHC1 default"   "9"          "$(peps_lengths MHC1)"
check "peps_lengths MHC2 default"   "15"         "$(peps_lengths MHC2)"
check "PEPS_LENGTHS_MHC1 overrides" "8 9 10"     "$(PEPS_LENGTHS_MHC1='8 9 10' peps_lengths MHC1)"
check "comma lists are accepted"    "8 9 10"     "$(PEPS_LENGTHS_MHC1='8,9,10' peps_lengths MHC1)"

peps_mode_config MHC1; check "mode MHC1 program" "netmhcpan_4.2"  "$PROG"
peps_mode_config MHC2; check "mode MHC2 program" "netmhc2pan_4.3" "$PROG"
( peps_mode_config MHC9 ) 2>/dev/null && bad "an unknown mode must fail" || ok "an unknown mode fails"

# ---------------------------------------------------------------------------
head2 "3. Registry"
# ---------------------------------------------------------------------------
printf 'key\torganism\tinput_mode\tfasta_file\tprefix\n' >  "$PEPS_CONFIG/proteomes.tsv"
printf 'TEST\ttestorg\trenamed\tTEST.faa\tTEST\n'        >> "$PEPS_CONFIG/proteomes.tsv"
printf 'DRIFT\ttestorg\trenamed\tDRIFT.faa\tOTHER\n'     >> "$PEPS_CONFIG/proteomes.tsv"
export PEPS_REGISTRY="$PEPS_CONFIG/proteomes.tsv"

peps_registry_row TEST && check "registry reads the organism" "testorg" "$PROTEOME_ORGANISM" \
                       || bad "registry row for TEST"
check "registry reads the prefix" "TEST" "$PROTEOME_PREFIX"
( peps_registry_row NOPE ) && bad "an absent key must fail" || ok "an absent key fails"
check "registry lists keys" "TEST DRIFT" "$(peps_registry_keys testorg | tr '\n' ' ' | sed 's/ $//')"
if peps_registry_row DRIFT 2>"$TMP/drift.err" >/dev/null; then :; fi
grep -q 'differ' "$TMP/drift.err" \
  && ok "a key/prefix mismatch is reported" || bad "a key/prefix mismatch should warn"

# ---------------------------------------------------------------------------
head2 "4. Renumbering and the truncation collision"
# ---------------------------------------------------------------------------
# Identifiers in the LbrM style: 16 characters, which is one over the limit.
cat > "$PEPS_DATA_IN/collide.faa" <<'EOF'
>LbrM.01.2.000040 protein forty [Leishmania braziliensis]
MAKGKRSADAKSSQKRQKKVLRDNIRGITRGCVRRMARRGGVKRISSEVY
>LbrM.01.2.000041 protein forty-one [Leishmania braziliensis]
MSISSLPLEGLTAIADFFDSASVPLAFTSVSPAGRVAGELAAFACPAHCY
>LbrM.01.2.000042 protein forty-two [Leishmania braziliensis]
MPRTYSEALQNAVKDLRSRGQAPSVAEIRKALGLSSTSTVHHHLKTLEAK
EOF

python3 "$HERE/fake_netmhc.py" --fasta "$PEPS_DATA_IN/collide.faa" \
        --allele HLA-A02:01 --length 9 --mode MHC1 --truncate > "$TMP/collide.out" 2>/dev/null
N_IDS="$(awk '/^ *[0-9]+ /{print $10}' "$TMP/collide.out" | sort -u | wc -l)"
check "three proteins collapse to one truncated identifier" "1" "$N_IDS"

bash "$ROOT/scripts/prep/pp_prepare.sh" TEST "$PEPS_DATA_IN/collide.faa" >/dev/null 2>&1
[[ -s "$PEPS_DATA_IN/renamed/TEST.faa" ]] && ok "pp_prepare writes the renamed FASTA" \
                                          || bad "pp_prepare did not write the renamed FASTA"
[[ -s "$PEPS_DATA_IN/renamed/TEST.iddict.tsv" ]] && ok "pp_prepare writes the dictionary" \
                                                 || bad "pp_prepare did not write the dictionary"

MAXW="$(awk -F'\t' 'NR>1 {if (length($1)>m) m=length($1)} END {print m+0}' "$PEPS_DATA_IN/renamed/TEST.iddict.tsv")"
[[ "$MAXW" -le 15 ]] && ok "identifiers fit in 15 characters (max $MAXW)" \
                     || bad "identifiers exceed 15 characters" "max $MAXW"

python3 "$HERE/fake_netmhc.py" --fasta "$PEPS_DATA_IN/renamed/TEST.faa" \
        --allele HLA-A02:01 --length 9 --mode MHC1 --truncate > "$TMP/fixed.out" 2>/dev/null
N_IDS2="$(awk '/^ *[0-9]+ /{print $10}' "$TMP/fixed.out" | sort -u | wc -l)"
check "after renumbering the three stay distinct" "3" "$N_IDS2"

# ---------------------------------------------------------------------------
head2 "5. Parsers"
# ---------------------------------------------------------------------------
run_parse() { # run_parse MODE OUTFILE TSV
  awk -v mode="$1" -v clean="$TMP/c.cleanout" -v meta="$TMP/c.meta" \
      -f "$ROOT/scripts/parse/cp_cleanout.awk" "$2"
  local p="cp_parse_NMP_MHC1_4.2.awk"; [[ "$1" == "MHC2" ]] && p="cp_parse_NMP_MHC2_4.3.awk"
  awk -v dataset=test -v out="$3" -f "$ROOT/scripts/parse/$p" "$TMP/c.cleanout"
}

run_parse MHC1 "$TMP/fixed.out" "$TMP/p1.tsv"
check "the class I header has 16 columns" "16" "$(head -1 "$TMP/p1.tsv" | awk -F'\t' '{print NF}')"
check "MHC keeps the colon"     "HLA-A02:01" "$(awk -F'\t' 'NR==2{print $3}' "$TMP/p1.tsv")"
check "MHC_key drops the colon" "HLA-A0201"  "$(awk -F'\t' 'NR==2{print $4}' "$TMP/p1.tsv")"
check "Pep_Len matches the peptide" "9"      "$(awk -F'\t' 'NR==2{print $6}' "$TMP/p1.tsv")"
NA_EL="$(awk -F'\t' 'NR>1 && $11=="NA"' "$TMP/p1.tsv" | wc -l)"
check "%Rank_EL is never NA (4.1/4.2 spelling)" "0" "$NA_EL"

# The 4.0 spelling must still parse: this is the regression v2 shipped with.
sed 's/Score_EL %Rank_EL/   Score    %Rank/' "$TMP/fixed.out" > "$TMP/old.out"
run_parse MHC1 "$TMP/old.out" "$TMP/p_old.tsv"
NA_OLD="$(awk -F'\t' 'NR>1 && $11=="NA"' "$TMP/p_old.tsv" | wc -l)"
check "%Rank_EL is never NA (4.0 spelling)" "0" "$NA_OLD"

python3 "$HERE/fake_netmhc.py" --fasta "$PEPS_DATA_IN/renamed/TEST.faa" \
        --allele DRB1_0701 --length 15 --mode MHC2 > "$TMP/m2.out" 2>/dev/null
run_parse MHC2 "$TMP/m2.out" "$TMP/p2.tsv"
check "both parsers emit the same header" \
      "$(head -1 "$TMP/p1.tsv")" "$(head -1 "$TMP/p2.tsv")"
check "class II peptide length" "15" "$(awk -F'\t' 'NR==2{print $6}' "$TMP/p2.tsv")"

BL="$(awk -F'\t' 'NR>1 && ($16=="SB" || $16=="WB")' "$TMP/p1.tsv" | wc -l)"
[[ "$BL" -gt 0 ]] && ok "BindLevel is recovered ($BL rows)" || bad "BindLevel never parsed"

# ---------------------------------------------------------------------------
head2 "6. Merge and QC"
# ---------------------------------------------------------------------------
RD="$PEPS_DATA_OUT/testorg/prediction/TEST/MHC1/netmhcpan_4.2/run_001"
mkdir -p "$RD"/{raw,err,alleles,meta,logs} "$RD"/cp/{cleanout,parse,merged,meta}
printf 'HLA-A02:01\nHLA-A03:01\n' > "$RD/alleles/alleles.txt"
{ echo "input_fasta:  $PEPS_DATA_IN/renamed/TEST.faa"
  echo "lengths:      9"
  echo "alleles_n:    2"
  echo "prefix:       TEST"; } > "$RD/meta/run.meta.txt"

for A in HLA-A02:01 HLA-A03:01; do
  L="$(peps_sanitize "$A")"
  python3 "$HERE/fake_netmhc.py" --fasta "$PEPS_DATA_IN/renamed/TEST.faa" \
          --allele "$A" --length 9 --mode MHC1 > "$RD/raw/TEST_mhc1.$L.len9.out" 2>/dev/null
done

bash "$ROOT/scripts/parse/run_cleanparse.sh" "$RD" MHC1 >/dev/null 2>&1
MERGED="$RD/cp/merged/merged_mhc1.tsv"
[[ -s "$MERGED" ]] && ok "the merged TSV is produced" || bad "no merged TSV"
check "the merged TSV has two alleles" "2" \
      "$(awk -F'\t' 'NR>1{print $3}' "$MERGED" | sort -u | wc -l | tr -d ' ')"

bash "$ROOT/scripts/parse/cp_qc.sh" "$RD" MHC1 >/dev/null 2>&1
check "QC passes on a complete run" "0" "$?"
grep -q 'completeness  : 100%' "$RD/cp/meta/cleanparse.qc.txt" \
  && ok "QC reports 100% completeness" || bad "QC did not report 100%"

# An incomplete run must be caught — this is what v2's "SKIPPED" could not do.
cp -r "$RD" "${RD}_broken"
rm -f "${RD}_broken"/cp/parse/*HLA-A03*.tsv "${RD}_broken"/cp/merged/*.tsv
bash "$ROOT/scripts/parse/cp_mergetsv.sh" "${RD}_broken/cp/parse" \
     "${RD}_broken/cp/merged/merged_mhc1.tsv" >/dev/null 2>&1
bash "$ROOT/scripts/parse/cp_qc.sh" "${RD}_broken" MHC1 >/dev/null 2>&1
check "QC fails on an incomplete run" "2" "$?"

# ---------------------------------------------------------------------------
head2 "7. Annotation round trip"
# ---------------------------------------------------------------------------
DICT="$PEPS_DATA_IN/renamed/iddict_global.tsv"
DICT="$DICT" bash "$ROOT/scripts/prep/pp_annotate.sh" "$MERGED" "$TMP/ann.tsv" >/dev/null 2>&1
[[ -s "$TMP/ann.tsv" ]] && ok "pp_annotate writes its output" || bad "pp_annotate produced nothing"

UNRESOLVED="$(awk -F'\t' 'NR>1 && $(NF-1)=="NA"' "$TMP/ann.tsv" | wc -l)"
check "every row resolves to an accession" "0" "$UNRESOLVED"
grep -q 'LbrM.01.2.00004' "$TMP/ann.tsv" \
  && ok "the original accession is recovered in full" \
  || bad "the original accession was not recovered"
check "the three accessions are distinguishable again" "3" \
      "$(awk -F'\t' 'NR>1{print $(NF-1)}' "$TMP/ann.tsv" | sort -u | wc -l | tr -d ' ')"

# ---------------------------------------------------------------------------
head2 "8. Massive mode"
# ---------------------------------------------------------------------------
JOBS_OUT="$(DRY_RUN=1 PEPS_ALLELES_MHC1="$RD/alleles/alleles.txt" PEPS_LENGTHS_MHC1='8 9' \
            bash "$ROOT/scripts/predict/hive.sh" MHC1 testorg 2 2>/dev/null)"
check "hive builds the right number of jobs" "jobs : 8" \
      "$(printf '%s' "$JOBS_OUT" | grep -m1 'jobs ' | tr -s ' ' | sed 's/^ //')"
printf '%s' "$JOBS_OUT" | grep -q 'DRY RUN' && ok "hive honours DRY_RUN" || bad "hive ignored DRY_RUN"

BEE_OUT="$(DRY_RUN=1 FORCE=1 bash "$ROOT/scripts/predict/bee.sh" MHC1 TEST HLA-A02:01 9 "$RD" 2>/dev/null)"
printf '%s' "$BEE_OUT" | grep -q -- '-l 9' && ok "bee builds the class I command" \
                                           || bad "bee's class I command is wrong" "$BEE_OUT"
BEE2="$(DRY_RUN=1 FORCE=1 bash "$ROOT/scripts/predict/bee.sh" MHC2 TEST DRB1_0701 15 "$RD" 2>/dev/null)"
printf '%s' "$BEE2" | grep -q -- '-length 15' && ok "bee builds the class II command" \
                                              || bad "bee's class II command is wrong" "$BEE2"

# ---------------------------------------------------------------------------
printf '\n\033[1mResult\033[0m\n'
printf '  passed: %d\n  failed: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
