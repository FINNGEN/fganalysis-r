#!/bin/bash
set -euo pipefail

## ============================================================
## FinnGen RX - Convert source files to Parquet
## ============================================================

## input file paths
# source these from a local file
source file_locations_r14.txt


## python check and set binary
# 1. check for 'python3' binary first
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
# 2. fallback to 'python' and check if it's version 3.x
elif command -v python >/dev/null 2>&1 && [[ "$(python -V 2>&1)" == "Python 3"* ]]; then
    PYTHON_CMD="python"
else
    echo "Error :: Python 3 is not installed." >&2
    exit 1
fi

# "stem" function: given a full path, strip extension to get base name
stem() {
   local base
   base=$(basename "$1")
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

# Common COPY options - ZSTD level 3 gives ~20-30% better compression
# than Snappy with negligible read-speed cost for FinnGen-style data.
PARQUET_OPTS="FORMAT PARQUET, CODEC 'ZSTD', COMPRESSION_LEVEL 3, ROW_GROUP_SIZE 500000"

# copy files to local folder
gsutil -m cp $in_pheno $in_labs $in_minimum $in_cov_pheno $in_endpoint $in_vnr $in_anthrop $in_drug_events ./

# 1. phenotypes
echo -e "\n[1/8] Phenotypes - service sector detailed longitudinal"
in_pheno_local=$(basename "$in_pheno")
duckdb -c "COPY (select * from read_csv('${in_pheno_local}', delim='\t', nullstr='NA')) TO '${out_pheno}.parquet' (${PARQUET_OPTS}, PARTITION_BY (SOURCE))"

# 2. labs (already converted)
# skip

# 3. minimum
echo -e "\n[3/8] Minimum extended"
in_minimum_local=$(basename "$in_minimum")
duckdb -c "COPY (select * from read_csv('$in_minimum_local', delim='\t', nullstr='NA')) to '${out_minimum}.parquet' (${PARQUET_OPTS})"

# 4. cov_pheno
echo -e "\n[4/8] Covariates + phenotypes"
in_cov_pheno_local=$(basename "$in_cov_pheno")
duckdb -c "COPY (select * from read_csv('$in_cov_pheno_local', delim='\t', nullstr='NA')) to '${out_cov_pheno}.parquet' (${PARQUET_OPTS})"

# 5. endpoint - first convert from wide to long
echo -e "\n[5/8] Wide endpoints to long format"
in_endpoint_local=$(basename "$in_endpoint")
tmp_endpoint=$(mktemp --suffix =.txt.gz)
trap 'rm -f "${tmp_endpoint}"' EXIT

zcat "${in_endpoint_local}" | awk '
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

duckdb -c "COPY (select * from read_csv('${tmp_endpoint}', delim='\t', nullstr='NA')) to '${out_endpoint}.parquet' (${PARQUET_OPTS})"

# 6. VNR mappings (no update from R13 - copy as-is)
# skip

# 7. Hilmo-Avohilmo anthropometric - preprocess then convert
echo -e "\n[7/8] Hilmo-Avohilmo anthropometric"
in_anthrop_local=$(basename $in_anthrop)
Rscript process_hilmo_avohilmo.R \
   "${in_anthrop_local}" \
   "${out_anthrop}.txt.gz" \
   hilmo_avohilmo_anthrop_dists.pdf 

duckdb -c "COPY (select * from read_csv('${out_anthrop}.txt.gz', delim='\t', nullstr='NA')) to '${out_anthrop}.parquet' (${PARQUET_OPTS})"

# 8. Drug events - preprocess then convert
echo -e "\n[8/8] Drug events"
in_drug_events_local=$(basename $in_drug_events)
$PYTHON_CMD process_drugs.py\
   --input "${in_drug_events_local}" \
   --output "${out_drug_events}.tsv.gz"

duckdb -c "COPY (select * from read_csv('${out_drug_events}.tsv.gz', delim='\t', nullstr=['NA', ''])) to '${out_drug_events}.parquet' (${PARQUET_OPTS})"

# clean-up
rm -rvf $in_pheno_local $in_minimum_local $in_cov_pheno_local $in_endpoint_local $tmp_endpoint $in_anthrop_local ${out_anthrop}.txt.gz ${in_drug_events_local} ${out_drug_events}.tsv.gz

echo -e "\nAll done."
