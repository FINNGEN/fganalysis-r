


get_bigquery_dbplyr <- function(projectid,dataset, table) {
   con <- dbConnect(
    bigrquery::bigquery(),
    project = projectid,
    dataset=dataset
  )
  return(plyr::tbl(con, table))
}

get_parquet_dbplyr <- function(parquet_file) {
  conn = dbConnect(duckdb::duckdb())
  return(duckdb::tbl_file(conn, parquet_file))
}

get_duckdb_dbplyr <- function(duckdb_file, table) {
  conn = dbConnect(duckdb::duckdb(duckdb_file), read_only=TRUE)
  return(dplyr::tbl(conn, table))
}

fg.data.connection <- function(connections) {
    if (!is.list(connections)) {
        stop("Connections must be a list")
    }
    if (!all(c("pheno", "labs") %in% names(connections))) {
        stop("Connections list must contain 'pheno' and 'labs'")
    }
    ## do further checks on the connections as needed. 
    class(connections) <- "fg.data.connection"
    return(connections) 
}

print.fg.data.connection <- function(x, ...) {
    cat("FinnGen data connection object\n")
    cat("Phenotype data:\n")
    print(str(x$pheno))
    cat("\nLab data:\n")
    print(str(x$labs))
}

call_connect <- function(conf) {
    req_tags <- c("path", "type")
    if (!all(req_tags %in% names(conf))) {
        stop(paste("Configuration must contain these tag [", paste(req_tags,collapse=","),"]"))
    }    

    path <- conf$path
    typestring <- conf$type

    if (typestring == "parquet") {
        return(duckdbfs::open_dataset(path, format="parquet"))
    } else if (typestring == "parquet-hive") {
        return(duckdbfs::open_dataset(path, format="parquet", hive_style=TRUE))
    } else {
        stop("Unsupported connection type")
    }
}


#' Connect to FinnGen data
#' @param path_to_conf Path to the configuration file (JSON format)
#' @return A fg.data.connection object containing the connections to data
#' @export
connect_fgdata <-  function(path_to_conf) { 
    json_data <- rjson::fromJSON(file = path_to_conf)
    req_confs <- c("pheno", "labs")
    connections <- list()
    # Extract the values from the JSON object
    if (! all(req_confs %in% names(json_data))) {
        stop(paste("Elements not found in configuration data. Configuration file must contain the following keys:", paste(req_confs, collapse = ", ")))
    }
    print("loading connections")
    for (conf in names(json_data)) {
        connections[[conf]] <- call_connect(json_data[[conf]])
    }

    return(fg.data.connection( connections))
}


