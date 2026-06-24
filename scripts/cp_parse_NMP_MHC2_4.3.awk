# cp_parse_NMP_MHC2_4.3.awk — NetMHC2pan 4.3 output parser (MHC-II, EL+BA)
# Usage: awk -v dataset="Lbra_mhc2" -v out="file.tsv" -f cp_parse_NMP_MHC2_4.3.awk file.cleanout
# Called by run_cleanparse.sh.

function trim(s) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    return s
}

BEGIN {
    if (out == "") out = "parsed.tsv"
    if (dataset == "") dataset = "NA"

    header = "dataset\tPos\tMHC\tPeptide\tCore\tOf\tIdentity\t" \
             "Score_EL\t%Rank_EL\tScore_BA\t%Rank_BA\tAff(nM)\tExp_Bind\tBindLevel"

    print header > out
}

# ------------------------------------------------------------
# Read table header and map column names -> positions
# ------------------------------------------------------------
/^[[:space:]]*Pos[[:space:]]+/ {
    line = trim($0)
    gsub(/[ ]+/, "\t", line)
    nH = split(line, H, "\t")

    delete idx
    for (i = 1; i <= nH; i++) {
        idx[H[i]] = i
    }
    if (idx["Pos"] == "" || idx["MHC"] == "" || idx["Peptide"] == "") {
        print "ERROR: missing required header column Pos, MHC or Peptide" > "/dev/stderr"
        exit 1
    }
    next
}

# ------------------------------------------------------------
# Parse data rows
# ------------------------------------------------------------
/^[[:space:]]*[0-9]+[[:space:]]+/ {
    line = trim($0)
    gsub(/[ ]+/, "\t", line)
    n = split(line, a, "\t")

    Pos      = a[idx["Pos"]]
    MHC      = a[idx["MHC"]]
    Peptide  = a[idx["Peptide"]]
    Core     = a[idx["Core"]]
    Of       = a[idx["Of"]]
    Identity = a[idx["Identity"]]

    gsub(/:/, "", MHC)

    # Defaults
    Score_EL = Rank_EL = Score_BA = Rank_BA = Aff = Exp_Bind = "NA"
    BindLevel = "NA"

    if ("Score_EL"  in idx) Score_EL = a[idx["Score_EL"]]
    if ("%Rank_EL"  in idx) Rank_EL  = a[idx["%Rank_EL"]]
    if ("Score_BA"  in idx) Score_BA = a[idx["Score_BA"]]
    if ("%Rank_BA"  in idx) Rank_BA  = a[idx["%Rank_BA"]]
    if ("Aff(nM)"   in idx) Aff      = a[idx["Aff(nM)"]]
    if ("Exp_Bind"  in idx) Exp_Bind = a[idx["Exp_Bind"]]

    # BindLevel: scan from right
    for (i = n; i >= 1; i--) {
        if (a[i] ~ /(SB|WB|Weak|Strong)/) {
            BindLevel = a[i]
            gsub(/[<= ]/, "", BindLevel)
            break
        }
    }

    print dataset "\t" Pos "\t" MHC "\t" Peptide "\t" Core "\t" Of "\t" \
          Identity "\t" Score_EL "\t" Rank_EL "\t" \
          Score_BA "\t" Rank_BA "\t" Aff "\t" Exp_Bind "\t" BindLevel >> out
}

