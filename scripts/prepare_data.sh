

duckdb -c "COPY (select * from read_csv('finngen_R13_service_sector_detailed_longitudinal_1.0.txt.gz',delim='\t') ) to 'finngen_R13_service_sector_detailed_longitudinal_1.0.parquet' (FORMAT parquet,  PARTITION_BY (SOURCE))"

duckdb -c 'COPY (select * from read_parquet("finngen_R13_kanta_lab_1.0.parquet")) to "finngen_R13_kanta_lab_1.0.parquet" (format PARQUET)'


### this crazy wide table runs out of memory.  could try setting datatypes to tinynt etc. or then transform to long format.
duckdb -c "SET preserve_insertion_order = false;SET threads TO 3; COPY (select * from read_csv('finngen_R13_endpoint_1.0.txt.gz',delim='\t', nullstr="NA", auto_type_candidates=['int','varchar']) ) to 'finngen_R13_endpoint_1.0.txt.gz.parquet' (FORMAT parquet)"

## 
duckdb -c "COPY (select * from read_csv('finngen_R13_minimum_extended_1.0.txt.gz',delim='\t') ) to 'finngen_R13_minimum_extended_1.0.parquet' (FORMAT parquet)"


duckdb -c "COPY (select * from read_csv('R13_COV_PHENO_V0.txt.gz',delim='\t', nullstr="NA") ) to 'R13_COV_PHENO_V0.parquet' (FORMAT parquet)"









