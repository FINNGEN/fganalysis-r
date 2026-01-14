#' @title Get lab measurements from FinnGen data
#' @param all_labs data frame with lab measurements
#' @param lablist vector of lab measurement concept IDs
#' @param require_values logical, if TRUE, only return rows with non-missing VALUE
#' @param use_freetext_values logical, if TRUE, use lab measurement also from result free text column
#' @param finngen_ids vector of FINNGENIDs to filter the data
#' @param lazy logical, if TRUE, return a lazy tbl object
#' @return data frame with lab measurements
#' @export
#' @importFrom dplyr %>% filter select collect all_of mutate
#' @import stringr
get_lab_measurements <- function(all_labs, lablist, require_values=TRUE,
                                  use_freetext_values = TRUE,
                                 finngen_ids=NULL, lazy=FALSE) {

    if(! use_freetext_values){
        print("Using only MEASUREMENT_VALUE_HARMONIZED column for lab values and not combining from reported values and extracted from free text")
        lab_value_column <- "MEASUREMENT_VALUE_HARMONIZED"
    }
    else {
        print("Using MEASUREMENT_VALUE_MERGED column for lab values, which combines reported values and those extracted from free text")
        lab_value_column <- "MEASUREMENT_VALUE_MERGED"
    }

    return_cols <- c("OMOP_CONCEPT_ID","FINNGENID", "OMOP_CONCEPT_ID", "EVENT_AGE", "VALUE"=lab_value_column)


  # Ensure robust matching regardless of column/vector types (character vs numeric)
  # The OMOP_CONCEPT_ID column may be stored as DECIMAL in the parquet file
  # We need to cast it to character BEFORE filtering to avoid type conversion errors
  # Convert lablist to character for consistent comparison
  lablist_chr <- as.character(lablist)

  # Cast OMOP_CONCEPT_ID to character in the database query before filtering
  # This ensures the comparison works regardless of the storage type
  labs <- all_labs %>%
    mutate(OMOP_CONCEPT_ID = as.character(.data$OMOP_CONCEPT_ID)) %>%
    select(all_of(return_cols)) %>%
    dplyr::filter(.data$OMOP_CONCEPT_ID %in% lablist_chr)

  if (!is.null(finngen_ids)) {
    labs <- labs %>% dplyr::filter(.data$FINNGENID %in% finngen_ids)
  }
  if (require_values) {
    labs <- labs %>% dplyr::filter(!is.na(.data$VALUE))
  }

  if (lazy) {
    labs
  } else {
    dplyr::collect(labs)
  }
}


#' @title Get drug purchases from FinnGen data
#' @param conn finngen data connection object
#' @param druglist vector of drug ATC codes. The ATC codes are matched with the first part of the code (e.g. A01*)
#' @param finngen_ids vector of FINNGENIDs to filter the data. leave empty to get all
#' @param use_only_reimbursement logical, if TRUE, use only reimbursement data (default FALSE) and combine reimbursement and delivery data if available in conn
#' @param use_atc_mapping logical, if TRUE, expand ATC codes to include historical alterations (default TRUE)
#' @param lazy logical, if TRUE, return a lazy tbl object
#' @return data frame with drug purchases
#' @export
#' @importFrom dplyr %>% filter select collect rename
#' @importFrom rlang sym :=
#' @import stringr
get_drug_purchases <- function(conn, druglist, finngen_ids=NULL, use_only_reimbursement = FALSE,
                               use_atc_mapping = TRUE, lazy=FALSE) {

    ## check that conn is a fg_data_connection object and has pheno data name
    if (!inherits(conn, "fg_data_connection")) {
        stop("conn must be a fg_data_connection object")
    }

    if (!"pheno" %in% names(conn)) {
        stop("conn must contain 'pheno' data")
    }

    # Expand ATC codes if mapping is enabled
    if (use_atc_mapping) {
        # Require mapping file when use_atc_mapping is explicitly TRUE
        expanded_druglist <- expand_atc_codes(druglist, include_hierarchical = FALSE, verbose = TRUE, require_mapping = TRUE)
    } else {
        expanded_druglist <- druglist
        message("ATC mapping disabled - using original ATC codes only")
    }

    drugs_regex <- paste0("^(",
                        paste0(expanded_druglist, collapse = '|'),
                        ")")


    all_phenos <- conn$pheno

    if ("drug_events" %in% names(conn) & !use_only_reimbursement) {
        print("Using drug data combining reimbursement and delivery data.")
        drugs <- conn$drug_events %>%
                dplyr::filter( str_detect( .data$ATC, drugs_regex ) )
    } else {
        print("Using drug data from reimbursement data only! i.e. longitudinal data from purchase registry.")
        return_cols <- c("FINNGENID", "EVENT_AGE", "APPROX_EVENT_DAY", ATC = "CODE1", REIMB_CODE = "CODE2", VNR = "CODE3", N_PACKS = "CODE4")
        drugs <- all_phenos %>%
            dplyr::filter(.data$SOURCE == "PURCH" & str_detect( .data$CODE1, drugs_regex )) %>%
            select(all_of(return_cols))
    }


    if (!is.null(finngen_ids)) {
        drugs <- drugs %>% dplyr::filter(.data$FINNGENID %in% finngen_ids)
    }

    if ("vnr" %in% names(conn)) {
        columns <- c("VNR", "Substance", "MedicineName", "PackageSize", "DDDPerPack", "Dosage", "DosageUnit")
        vnr <- conn$vnr %>% select(all_of(columns))
        drugs <- left_join(drugs, vnr, by = "VNR", copy = TRUE)
    }

    if (lazy) {
        drugs
    } else {
        dplyr::collect(drugs)
    }
}


#' @title Get first drug purchase from FinnGen data
#' @param conn finngen data connection object
#' @param druglist vector of drug ATC codes. The ATC codes are matched with the first part of the code (e.g. A01*)
#' @param finngen_ids vector of FINNGENIDs to filter the data. leave empty to get all
#' @param use_only_reimbursement logical, if TRUE, use only reimbursement data (default FALSE) and combine reimbursement and delivery data if available in conn
#' @param use_atc_mapping logical, if TRUE, expand ATC codes to include historical alterations (default TRUE)
#' @param lazy logical, if TRUE, return a lazy tbl object
#' @return data frame with first drug purchases for each FINNGENID
#' @export
#' @importFrom dplyr %>% group_by filter distinct ungroup select collect
get_first_purchase <- function(conn, druglist, finngen_ids=NULL,
                                use_only_reimbursement = FALSE,
                                use_atc_mapping = TRUE,
                               lazy=FALSE) {

  first_purch <- get_drug_purchases(conn, druglist, finngen_ids, lazy=TRUE,
                                   use_only_reimbursement = use_only_reimbursement,
                                   use_atc_mapping = use_atc_mapping) %>%
    group_by(.data$FINNGENID) %>%
    filter(.data$EVENT_AGE == min(.data$EVENT_AGE)) %>% distinct(.data$EVENT_AGE, .keep_all = TRUE) %>%
    ungroup()
  if (lazy) {
    first_purch
  } else {
    dplyr::collect(first_purch)
  }
}

#' @title Join Covariates to Lab Measurements
#' @description Helper function to join covariate data to lab measurements data frame.
#' This function handles the common pattern of adding covariates like sex, age, etc. to lab data.
#' @param lab_data Data frame with lab measurements (must contain FINNGENID column)
#' @param covariates Data frame or lazy table containing covariate data
#' @param covariate_cols Character vector of column names to join from the covariates table
#' @return Data frame with lab measurements and joined covariates
#' @export
#' @examples
#' # Create sample data
#' lab_measurements <- data.frame(
#'   FINNGENID = c("FG1", "FG2", "FG3"),
#'   OMOP_CONCEPT_ID = "3001308",
#'   EVENT_AGE = c(50, 60, 70),
#'   VALUE = c(100, 110, 120)
#' )
#' cov_pheno <- data.frame(
#'   FINNGENID = c("FG1", "FG2", "FG3"),
#'   SEX = c(1, 2, 1),
#'   AGE_AT_DEATH_OR_END_OF_FOLLOWUP = c(80, 85, 90)
#' )
#'
#' # Join sex covariate to lab measurements
#' lab_with_sex <- join_covariates_to_labs(
#'   lab_data = lab_measurements,
#'   covariates = cov_pheno,
#'   covariate_cols = c("SEX")
#' )
#'
#' # Join multiple covariates
#' lab_with_covariates <- join_covariates_to_labs(
#'   lab_data = lab_measurements,
#'   covariates = cov_pheno,
#'   covariate_cols = c("SEX", "AGE_AT_DEATH_OR_END_OF_FOLLOWUP")
#' )
join_covariates_to_labs <- function(lab_data, covariates, covariate_cols) {
  if (is.null(covariates) || is.null(covariate_cols)) {
    return(lab_data)
  }

  # Ensure FINNGENID is in the columns for the join
  cols_to_select <- unique(c("FINNGENID", covariate_cols))

  # Check that all requested columns exist in the covariates dataframe
  missing_cols <- setdiff(cols_to_select, colnames(covariates))
  if (length(missing_cols) > 0) {
    stop(paste("The following `covariate_cols` are not in the `covariates` dataframe:",
               paste(missing_cols, collapse = ", ")))
  }

  # Select the requested columns and ensure one row per FINNGENID
  cov_data_to_join <- covariates %>%
    select(all_of(cols_to_select)) %>%
    distinct(.data$FINNGENID, .keep_all = TRUE)

  # If covariates is a lazy table (database connection), collect it
  if (inherits(covariates, "tbl_lazy") || inherits(covariates, "tbl_sql")) {
    cov_data_to_join <- dplyr::collect(cov_data_to_join)
  }

  # Join covariates with lab measurements
  # If lab_data is a lazy table (e.g., DuckDB), allow copying the RHS to the same src
  copy_needed <- inherits(lab_data, "tbl_lazy") || inherits(lab_data, "tbl_sql")
  result <- lab_data %>%
    left_join(cov_data_to_join, by = "FINNGENID", copy = copy_needed)

  return(result)
}

#' @title Join Covariates to Any Data Frame
#' @description Generic helper function to join covariate data to any data frame with FINNGENID.
#' @param data Data frame with FINNGENID column
#' @param covariates Data frame or lazy table containing covariate data
#' @param covariate_cols Character vector of column names to join from the covariates table
#' @return Data frame with joined covariates
#' @export
#' @examples
#' # Create sample data
#' drug_response_data <- data.frame(
#'   FINNGENID = c("FG1", "FG2", "FG3"),
#'   before = c(100, 110, 120),
#'   after = c(95, 105, 115),
#'   response = c(-5, -5, -5)
#' )
#' cov_pheno <- data.frame(
#'   FINNGENID = c("FG1", "FG2", "FG3"),
#'   SEX = c(1, 2, 1),
#'   AGE_AT_DEATH_OR_END_OF_FOLLOWUP = c(80, 85, 90)
#' )
#'
#' # Join covariates to drug response data
#' response_with_covariates <- join_covariates(
#'   data = drug_response_data,
#'   covariates = cov_pheno,
#'   covariate_cols = c("SEX", "AGE_AT_DEATH_OR_END_OF_FOLLOWUP")
#' )
join_covariates <- function(data, covariates, covariate_cols) {
  if (is.null(covariates) || is.null(covariate_cols)) {
    return(data)
  }

  # Ensure FINNGENID is in the columns for the join
  cols_to_select <- unique(c("FINNGENID", covariate_cols))

  # Check that all requested columns exist in the covariates dataframe
  missing_cols <- setdiff(cols_to_select, colnames(covariates))
  if (length(missing_cols) > 0) {
    stop(paste("The following `covariate_cols` are not in the `covariates` dataframe:",
               paste(missing_cols, collapse = ", ")))
  }

  # Select the requested columns and ensure one row per FINNGENID
  cov_data_to_join <- covariates %>%
    select(all_of(cols_to_select)) %>%
    distinct(.data$FINNGENID, .keep_all = TRUE)

  # If covariates is a lazy table (database connection), collect it
  if (inherits(covariates, "tbl_lazy") || inherits(covariates, "tbl_sql")) {
    cov_data_to_join <- dplyr::collect(cov_data_to_join)
  }

  # Join covariates with data
  # If data is a lazy table (e.g., DuckDB), allow copying the RHS to the same src
  copy_needed <- inherits(data, "tbl_lazy") || inherits(data, "tbl_sql")
  result <- data %>%
    left_join(cov_data_to_join, by = "FINNGENID", copy = copy_needed)

  return(result)
}