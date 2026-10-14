# cp_parse_NMP_MHC2_4.3.awk — NetMHCIIpan output parser (MHC-II, EL + BA)
#
# Usage:
#   awk -v dataset="LAET_mhc2" -v out="file.tsv" -f cp_parse_NMP_MHC2_4.3.awk file.cleanout
#
# Called by run_cleanparse.sh.
#
# OUTPUT COLUMNS
#   Identical to the class I parser, so the two merged tables stack and any
#   downstream code reads both with one schema:
#
#   dataset Pos MHC MHC_key Peptide Pep_Len Core Of Identity
#   Score_EL %Rank_EL Score_BA %Rank_BA Aff(nM) Exp_Bind BindLevel
#
# CHANGES FROM v2
#
#   1. The allele is kept verbatim in MHC; the punctuation-free form is MHC_key.
#      v2 stripped colons, which breaks joins against IEDB and published allele
#      tables. Class II names such as HLA-DPA10103-DPB10401 have no colons to
#      begin with, but DRB1*04:01 style input does, so both forms are kept for
#      the same reason as in class I.
#
#   2. Pep_Len is emitted, which multilength campaigns need to separate
#      12- through 21-mers inside a single merged file.
#
#   3. Optional columns are read defensively with `in idx` rather than assumed
#      present. v2 addressed Core, Of and Identity unconditionally; a run
#      without them produced empty fields that shifted nothing but looked
#      indistinguishable from real data.

function trim(s) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    return s
}

BEGIN {
    if (out == "")     out = "parsed.tsv"
    if (dataset == "") dataset = "NA"

    print "dataset\tPos\tMHC\tMHC_key\tPeptide\tPep_Len\tCore\tOf\tIdentity\t" \
          "Score_EL\t%Rank_EL\tScore_BA\t%Rank_BA\tAff(nM)\tExp_Bind\tBindLevel" > out

    rows = 0
}

/^[[:space:]]*Pos[[:space:]]+/ {
    line = trim($0)
    gsub(/[ ]+/, "\t", line)
    nH = split(line, H, "\t")

    delete idx
    for (i = 1; i <= nH; i++) idx[H[i]] = i

    if (!("Pos" in idx) || !("MHC" in idx) || !("Peptide" in idx)) {
        print "ERROR: header lacks Pos, MHC or Peptide" > "/dev/stderr"
        exit 1
    }
    header_seen = 1
    next
}

/^[[:space:]]*[0-9]+[[:space:]]+/ {
    if (!header_seen) {
        print "ERROR: data row before any header line" > "/dev/stderr"
        exit 1
    }

    line = trim($0)
    gsub(/[ ]+/, "\t", line)
    n = split(line, a, "\t")

    Pos     = a[idx["Pos"]]
    MHC     = a[idx["MHC"]]
    Peptide = a[idx["Peptide"]]

    MHC_key = MHC
    gsub(/[:*]/, "", MHC_key)

    Core     = ("Core"     in idx) ? a[idx["Core"]]     : "NA"
    Of       = ("Of"       in idx) ? a[idx["Of"]]       : "NA"
    Identity = ("Identity" in idx) ? a[idx["Identity"]] : "NA"

    Score_EL = Rank_EL = Score_BA = Rank_BA = Aff = Exp_Bind = "NA"
    BindLevel = "NA"

    if      ("Score_EL" in idx) Score_EL = a[idx["Score_EL"]]
    else if ("Score"    in idx) Score_EL = a[idx["Score"]]

    if      ("%Rank_EL" in idx) Rank_EL = a[idx["%Rank_EL"]]
    else if ("%Rank"    in idx) Rank_EL = a[idx["%Rank"]]

    if ("Score_BA" in idx) Score_BA = a[idx["Score_BA"]]
    if ("%Rank_BA" in idx) Rank_BA  = a[idx["%Rank_BA"]]
    if ("Aff(nM)"  in idx) Aff      = a[idx["Aff(nM)"]]
    if ("Exp_Bind" in idx) Exp_Bind = a[idx["Exp_Bind"]]

    for (i = n; i >= 1; i--) {
        if (a[i] ~ /(SB|WB)$/ || a[i] ~ /(Strong|Weak)$/) {
            BindLevel = a[i]
            gsub(/[<= ]/, "", BindLevel)
            break
        }
    }

    print dataset "\t" Pos "\t" MHC "\t" MHC_key "\t" Peptide "\t" length(Peptide) \
          "\t" Core "\t" Of "\t" Identity "\t" Score_EL "\t" Rank_EL "\t" \
          Score_BA "\t" Rank_BA "\t" Aff "\t" Exp_Bind "\t" BindLevel >> out
    rows++
}

END {
    if (rows == 0)
        print "WARNING: no data rows parsed from " FILENAME > "/dev/stderr"
}
