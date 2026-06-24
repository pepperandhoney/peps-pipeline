# cp_parse_NMP_MHC1_4.2.awk — NetMHCpan 4.2 output parser (MHC-I, EL+BA)
# Usage: awk -v dataset="Lbra_mhc1" -v out="file.tsv" -f cp_parse_NMP_MHC1_4.2.awk file.cleanout
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

    Pos     = a[idx["Pos"]]
    MHC     = a[idx["MHC"]]
    Peptide = a[idx["Peptide"]]

    # Optional columns in MHC-I output
    Core     = ("Core"     in idx) ? a[idx["Core"]]     : "NA"
    Of       = ("Of"       in idx) ? a[idx["Of"]]       : "NA"
    Identity = ("Identity" in idx) ? a[idx["Identity"]] : "NA"

    # Keep your normalization (remove ":" if present)
    gsub(/:/, "", MHC)

    # Defaults
    Score_EL = Rank_EL = Score_BA = Rank_BA = Aff = Exp_Bind = "NA"
    BindLevel = "NA"

    # MHC-I EL columns are named Score and %Rank
    if ("Score"   in idx) Score_EL = a[idx["Score"]]
    if ("%Rank"   in idx) Rank_EL  = a[idx["%Rank"]]

    # BA columns
    if ("Score_BA"  in idx) Score_BA = a[idx["Score_BA"]]
    if ("%Rank_BA"  in idx) Rank_BA  = a[idx["%Rank_BA"]]
    if ("Aff(nM)"   in idx) Aff      = a[idx["Aff(nM)"]]

    # BindLevel: scan from right (captures "<=SB" or "<=WB")
    for (i = n; i >= 1; i--) {
        if (a[i] ~ /(SB|WB)/) {
            BindLevel = a[i]
            gsub(/[<= ]/, "", BindLevel)
            break
        }
    }

    print dataset "\t" Pos "\t" MHC "\t" Peptide "\t" Core "\t" Of "\t" \
          Identity "\t" Score_EL "\t" Rank_EL "\t" \
          Score_BA "\t" Rank_BA "\t" Aff "\t" Exp_Bind "\t" BindLevel >> out
}
