# cp_parse_NMP_MHC1_4.2.awk — NetMHCpan output parser (MHC-I, EL + BA)
#
# Usage:
#   awk -v dataset="LAET_mhc1" -v out="file.tsv" -f cp_parse_NMP_MHC1_4.2.awk file.cleanout
#
# Called by run_cleanparse.sh.
#
# OUTPUT COLUMNS
#   dataset Pos MHC MHC_key Peptide Pep_Len Core Of Identity
#   Score_EL %Rank_EL Score_BA %Rank_BA Aff(nM) Exp_Bind BindLevel
#
# CHANGES FROM v2
#
#   1. The eluted-ligand columns are found under either name.
#      v2 looked only for "Score" and "%Rank", which is the NetMHCpan 4.0
#      spelling. Run with -BA, versions 4.1 and 4.2 emit "Score_EL" and
#      "%Rank_EL" instead, and every EL value came through as NA -- silently,
#      because NA is also what a genuinely absent column produces.
#
#   2. The allele is kept verbatim in MHC, and the punctuation-free form moves
#      to MHC_key.
#      v2 ran gsub(/:/, "", MHC), turning HLA-A02:01 into HLA-A0201. That makes
#      joins against IEDB, AFND and published allele tables fail, since those
#      all carry the colon. Both forms are now emitted: MHC to join outwards,
#      MHC_key for filenames and for continuity with v1 and v2 output.
#
#   3. Pep_Len is emitted.
#      With multilength campaigns one merged TSV holds 8- through 14-mers, and
#      length is needed to split them again. Deriving it from the sequence is
#      trivial but doing it here means every consumer agrees.
#
#   4. Exp_Bind is read when present. v2 declared the column and never filled it.

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

# ---------------------------------------------------------------------------
# Header: map column names to positions.
# Column order differs between versions and between -BA and plain runs, so
# nothing may be addressed positionally.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Data rows
# ---------------------------------------------------------------------------
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

    # 4.1 / 4.2 spelling first, then the 4.0 spelling.
    if      ("Score_EL" in idx) Score_EL = a[idx["Score_EL"]]
    else if ("Score"    in idx) Score_EL = a[idx["Score"]]

    if      ("%Rank_EL" in idx) Rank_EL = a[idx["%Rank_EL"]]
    else if ("%Rank"    in idx) Rank_EL = a[idx["%Rank"]]

    if ("Score_BA" in idx) Score_BA = a[idx["Score_BA"]]
    if ("%Rank_BA" in idx) Rank_BA  = a[idx["%Rank_BA"]]
    if ("Aff(nM)"  in idx) Aff      = a[idx["Aff(nM)"]]
    if ("Exp_Bind" in idx) Exp_Bind = a[idx["Exp_Bind"]]

    # BindLevel sits in a trailing "<= SB" or "<= WB" field with no header, so
    # it is found by scanning from the right.
    for (i = n; i >= 1; i--) {
        if (a[i] ~ /(SB|WB)$/) {
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
    else if (el_warned == 0 && Rank_EL == "NA")
        print "WARNING: %Rank_EL is NA on the last row of " FILENAME \
              " — check the header names" > "/dev/stderr"
}
