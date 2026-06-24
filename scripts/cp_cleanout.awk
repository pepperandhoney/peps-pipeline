#!/usr/bin/awk -f
# cp_cleanout.awk — Clean raw NetMHCpan/NetMHCIIpan output
# Usage: awk -v mode=MHC1 -v clean="file.cleanout" -v meta="file_meta.txt" -f cp_cleanout.awk file.out
# Called by run_cleanparse.sh. Universal for MHC1 and MHC2.

BEGIN {
    header_seen = 0
    if (mode != "MHC1" && mode != "MHC2") {
        print "ERROR: mode must be MHC1 or MHC2" > "/dev/stderr"
        exit 1
    }
    if (clean == "") clean = "clean.out"
    if (meta  == "") meta  = "metadata.txt"
}

function trim(s) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    return s
}

# MHC-II metadata (run-level, from commented header)
mode == "MHC2" && /^#[[:space:]]*(NetMHCIIpan version|Input is|Peptide length|Prediction Mode|Threshold|Allele:|HLA-.*Distance to training data)/ {
    line = $0
    sub(/^#[[:space:]]*/, "", line)
    print trim(line) > meta
    next
}

# Garbage removal
/^[[:space:]]*$/            { next }
/^[[:space:]]*-{3,}/        { next }
/^nohup:/                   { next }
/^[[:space:]]*#/            { next }

# Header (keep once)
/^[[:space:]]*Pos[[:space:]]+/ {
    if (!header_seen) {
        print $0 > clean
        header_seen = 1
    }
    next
}

# MHC-I metadata (protein-centric)
mode == "MHC1" && /^[[:space:]]*Protein/ {
    print trim($0) > meta
    next
}

# Data rows
/^[[:space:]]*[0-9]+[[:space:]]+/ {
    print $0 > clean
    next
}

# Ignore everything else
{ next }