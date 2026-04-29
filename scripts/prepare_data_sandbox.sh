#!/bin/bash
set -euo pipefail

## ============================================================
## FinnGen RX - Convert source files to Parquet
## ============================================================

## input file paths
# get these from file to avoid showing paths in repo
source /finngen/shared_nfs/Resources/fganalysis/R14/file_locations_r14.txt

# "stem" function: given a full path, strip extension to get base name
stem() {
   local base
   base=$(basename "$1" )
   # strip known double extensions
   base="${base%.gz}"
   base="${base%.parquet}"
   base="${base%.txt}"
   base="${base%.csv}"
   base="${base%.tsv}"
   echo "$base"
}

# set output file basenames
out_pheno="$(stem "$in_pheno")"
out_labs="$(stem "$in_labs")"
out_minimum="$(stem "$in_minimum")"
out_cov_pheno="$(stem "$in_cov_pheno")"
out_endpoint="$(stem "$in_endpoint")_longformat"
out_vnr="$(stem "$in_vnr")"
out_anthrop="$(stem "$in_anthrop")_dedup_fixbp"
out_drug_events="$(stem "$in_drug_events").simple"

## shared DuckDB helper function
# Usage: run_duckdb <R-code-string>
# Runs a block of R code via Rscript (more robust than R -- slave).
run_duckdb () {
   Rscript --vanilla - <<EOF
library(duckdb)
conn <- duckdb::dbConnect(duckdb::duckdb(), ":memory:")
on.exit(duckdb::dbDisconnect(conn, shutdown = TRUE))
$1
EOF
}

# Common COPY options - ZSTD level 3 gives ~20-30% better compression
# than Snappy with negligible read-speed cost for FinnGen-style data.
PARQUET_OPTS="FORMAT PARQUET, CODEC 'ZSTD', COMPRESSION_LEVEL 3, ROW_GROUP_SIZE 500000"

## ============================================================
## 1. Service sector (phenotypes) - partitioned by SOURCE
## ============================================================
echo -e "\n[1/8] Phenotypes - service sector detailed longitudinal"
run_duckdb "
DBI::dbExecute(conn, \"
   COPY (
      SELECT * FROM read_csv('${in_pheno}', delim='\t', nullstr='NA')
   )
   TO '${out_pheno}.parquet'
   (${PARQUET_OPTS}, PARTITION_BY (SOURCE))
\")
"

## ============================================================
## 2. Kanta labs (already parquet - just copy)
## ============================================================
echo -e "\n[2/8] Kanta labs (copy)"
cp -v "${in_labs}" "${out_labs}.parquet"

## ============================================================
## 3. Minimum extended phenotypes
## ============================================================
echo -e "\n[3/8] Minimum extended"
run_duckdb "
DBI::dbExecute(conn, \"
   COPY (
      SELECT * FROM read_csv('${in_minimum}', delim='\t', nullstr='NA')
   )
   TO '${out_minimum}.parquet
   (${PARQUET_OPTS} )
\")
"

## ============================================================
## 4. Covariates + phenotypes
## ============================================================
echo -e "\n[4/8] Covariates + phenotypes"
run_duckdb "
DBI::dbExecute(conn, \"
   COPY (
      SELECT * FROM read_csv('${in_cov_pheno}', delim='\t', nullstr='NA' )
   )
   TO '${out_cov_pheno}.parquet'
   (${PARQUET_OPTS})
\")
"

## ============================================================
## 5. Endpoints: wide -> long -> parquet
## ============================================================
echo -e "\n[5/8] Wide endpoints to long format"
# /dev/stdin doesn't work here because Rscript -- vanilla - already consumes stdin
# for the heredoc. Write awk output to a named temp file instead.
tmp_endpoint=$(mktemp --suffix =.txt.gz)
trap 'rm -f "${tmp_endpoint}"' EXIT

zcat "${in_endpoint}" | awk '
   BEGIN {OFS="\t"; print "FINNGENID\tCOLUMN\tVALUE\tFU_AGE\tAPPROX_EVENT_DAY\tNEVT" }
   NR==1 {
      for (i=1; i<=NF; i++) {
         c[i]=$i; d[$i]=i
         if ($i != "FINNGENID" && $i != "BL_AGE" && $i != "BL_YEAR" && 
             $i != "AGE_AT_DEATH_OR_END_OF_FOLLOWUP" && $i != "SEX" && 
             $i !~ /_FU_AGE$/ && $i !~ /_APPROX_EVENT_DAY$/ && $i !~ /_NEVT$/) {
            p[i]++
         }
      }
      next
   }
   {
      for (i=1; i<=NF; i++) {
         if ((i in p) && $i != "NA") {
            print $d["FINNGENID"], c[i], $i,
                  $d[c[i]"_FU_AGE"], $d[c[i]"_APPROX_EVENT_DAY"], $d[c[i]"_NEVT"]
         }
      }
   }
' | gzip --fast > "${tmp_endpoint}"

run_duckdb "
DBI::dbExecute(conn, \"
   COPY (
      SELECT * FROM read_csv('${tmp_endpoint}', delim='\t', nullstr='NA', header=TRUE)
   )
   TO '${out_endpoint}.parquet'
   (${PARQUET_OPTS})
\")
"

## ============================================================
## 6. VNR mappings (no update from R13 - copy as-is)
## ============================================================
echo -e "\n[6/8] VNR mappings (copy)"
cp -v "${in_vnr}" "${out_vnr}.tsv"

## ============================================================
## 7. Hilmo-Avohilmo anthropometric - preprocess then convert
## ============================================================
echo -e "\n[7/8] Hilmo-Avohilmo anthropometric"
Rscript process_hilmo_avohilmo.R \
   "${in_anthrop}" \
   "${out_anthrop}.txt.gz" \
   hilmo_avohilmo_anthrop_dists.pdf

run_duckdb "
DBI::dbExecute(conn, \"
   COPY (
      SELECT * FROM read_csv('${out_anthrop}.txt.gz', delim='\t', nullstr='NA' )
   )
   TO '${out_anthrop} . parquet'
   (${PARQUET_OPTS})
\")
"

## ============================================================
## 8. Drug events - preprocess then convert
## ============================================================
echo -e "\n[8/8] Drug events"
python process_drugs.py \
   --input "${in_drug_events}" \
   --output "${out_drug_events}.tsv.gz"

run_duckdb "
DBI::dbExecute(conn, \"
   COPY (
      SELECT * FROM read_csv(${out_drug_events}.tsv.gz', delim='\t', nullstr=['NA', ''], all_varchar=TRUE)
      ORDER BY ATC
   )
   TO '${out_drug_events}.parquet'
   (${PARQUET_OPTS})
\")
"

echo -e "\nAll done."
