#' @importFrom stats qnorm quantile cor lm predict sd
#' @importFrom dplyr %>% group_by summarise mutate select n filter pull arrange
#' @importFrom graphics hist par text plot.new
#' @importFrom grDevices dev.new
#' @importFrom rlang .data
#' @importFrom utils read.table write.table
NULL

# Declare global variables to avoid R CMD check notes
utils::globalVariables(c("FINNGENID", "fixed_slope", "VALUE", "time_diff", "cluster_id"))

#' @title Inverse Rank Normalize Values
#' @description Performs inverse rank normalization on a numeric vector
#' @param x Numeric vector to normalize
#' @return Inverse rank normalized vector with same length as input
#' @export
inverse_rank_normalize <- function(x) {
  # Remove NAs for ranking but keep track of their positions
  na_pos <- is.na(x)
  x_no_na <- x[!na_pos]

  # If all values are NA or vector is empty, return the original vector
  if (length(x_no_na) == 0) {
    return(x)
  }

  # Rank the values, handling ties by taking their mean
  r <- rank(x_no_na, ties.method = "average")

  # Calculate normalized values using normal distribution
  norm_vals <- qnorm(r / (length(r) + 1))

  # Put the normalized values back in the original vector
  x_norm <- x
  x_norm[!na_pos] <- norm_vals

  return(x_norm)
}

#' @title Calculate Fixed-Effect Slopes
#' @description Calculates individual-specific slopes using simple linear regression
#' @param data Data frame with columns: FINNGENID, EVENT_AGE, VALUE
#' @param min_measurements Minimum number of measurements per individual (default: 2)
#' @return Data frame with FINNGENID and fixed_slope columns
#' @export
calculate_fixed_slopes <- function(data, min_measurements = 2) {
  # Calculate slopes for each individual
  fixed_slopes <- data %>%
    group_by(.data$FINNGENID) %>%
    summarise(
      n_measurements = n(),
      fixed_slope = if(n() >= min_measurements) {
        tryCatch({
          lm(.data$VALUE ~ .data$EVENT_AGE)$coefficients[2]
        }, error = function(e) NA_real_)
      } else {
        NA_real_
      }
    ) %>%
    filter(!is.na(.data$fixed_slope)) %>%
    select(FINNGENID, fixed_slope)

  return(as.data.frame(fixed_slopes))
}

#' @title Process Variance Files with Inverse Rank Normalization
#' @description Reads variance files, adds inverse rank normalized column, and generates summary
#' @param output_dir Directory containing variance files (default: current directory)
#' @param pattern Regular expression pattern to match variance files (default: "_variance\\.tsv$")
#' @param generate_plots Logical, whether to generate comparison plots (default: FALSE)
#' @param save_normalized Logical, whether to save files with normalized column (default: TRUE)
#' @return Summary data frame with statistics for original and normalized values
#' @export
process_variance_files <- function(output_dir = ".", pattern = "_variance\\.tsv$",
                                   generate_plots = FALSE,
                                   save_normalized = TRUE) {

  # List all *_variance.tsv files
  variance_files <- list.files(path = output_dir, pattern = pattern,
                               full.names = TRUE)

  if (length(variance_files) == 0) {
    warning("No variance files found in the specified directory.")
    return(NULL)
  }

  # Initialize summary list
  summary_list <- list()

  for (file_path in variance_files) {
    file_name <- basename(file_path)
    cat(paste0("Processing: ", file_name, "\n"))

    # Read the file
    df <- read.table(file_path, header = TRUE, sep = "\t", stringsAsFactors = FALSE)

    # Infer the variance column name
    base_name <- sub("\\.tsv$", "", file_name)

    # Look for the column - it might have an X prefix if it starts with a number
    variance_col <- NULL
    if (base_name %in% colnames(df)) {
      variance_col <- base_name
    } else if (paste0("X", base_name) %in% colnames(df)) {
      variance_col <- paste0("X", base_name)
    } else {
      # Try to find any column ending with _variance
      variance_cols <- grep("_variance$", colnames(df), value = TRUE)
      if (length(variance_cols) > 0) {
        variance_col <- variance_cols[1]
        if (length(variance_cols) > 1) {
          warning(sprintf("Multiple variance columns found in %s, using %s", file_name, variance_col))
        }
      }
    }

    # Check if the column exists
    if (is.null(variance_col) || !variance_col %in% colnames(df)) {
      warning(sprintf("No variance column found in %s", file_name))
      next
    }

    # Apply inverse rank normalization
    norm_col_name <- paste0(variance_col, "_qnorm")
    df[[norm_col_name]] <- inverse_rank_normalize(df[[variance_col]])

    # Save normalized file if requested
    if (save_normalized) {
      output_path <- sub("\\.tsv$", "_qnorm.tsv", file_path)
      write.table(df, file = output_path, sep = "\t", row.names = FALSE, quote = FALSE)
      cat(paste0("  Saved normalized file: ", basename(output_path), "\n"))
    }

    # Calculate statistics
    total_records <- nrow(df)
    non_missing <- sum(!is.na(df[[variance_col]]))

    # Summary statistics for original values
    orig_summary <- summary(df[[variance_col]])
    orig_sd <- sd(df[[variance_col]], na.rm = TRUE)

    # Summary statistics for normalized values
    norm_summary <- summary(df[[norm_col_name]])
    norm_sd <- sd(df[[norm_col_name]], na.rm = TRUE)

    # Store results
    summary_list[[file_name]] <- list(
      file = file_name,
      total_records = total_records,
      non_missing = non_missing,
      orig_summary = orig_summary,
      orig_sd = orig_sd,
      norm_summary = norm_summary,
      norm_sd = norm_sd,
      orig_data = df[[variance_col]],
      norm_data = df[[norm_col_name]]
    )
  }

  # Create summary table
  summary_table <- create_variance_summary_table(summary_list)

  # Generate plots if requested
  if (generate_plots && length(summary_list) > 0) {
    generate_variance_plots(summary_list)
  }

  return(summary_table)
}

#' @title Create Variance Summary Table
#' @description Creates a summary table from processed variance data
#' @param summary_list List of summary statistics from process_variance_files
#' @return Data frame with summary statistics
create_variance_summary_table <- function(summary_list) {

  if (length(summary_list) == 0) {
    return(NULL)
  }

  # Helper function to safely extract values
  safe_extract <- function(summary_obj, name) {
    if (name %in% names(summary_obj)) {
      return(as.numeric(summary_obj[name]))
    } else {
      return(NA_real_)
    }
  }

  # Build summary table
  summary_rows <- lapply(names(summary_list), function(file_name) {
    res <- summary_list[[file_name]]
    orig_stats <- res$orig_summary
    norm_stats <- res$norm_summary

    data.frame(
      File = res$file,
      Total_records = res$total_records,
      Non_missing = res$non_missing,
      Orig_SD = res$orig_sd,
      Orig_Min = safe_extract(orig_stats, "Min."),
      Orig_Q1 = safe_extract(orig_stats, "1st Qu."),
      Orig_Median = safe_extract(orig_stats, "Median"),
      Orig_Mean = safe_extract(orig_stats, "Mean"),
      Orig_Q3 = safe_extract(orig_stats, "3rd Qu."),
      Orig_Max = safe_extract(orig_stats, "Max."),
      Norm_SD = res$norm_sd,
      Norm_Min = safe_extract(norm_stats, "Min."),
      Norm_Q1 = safe_extract(norm_stats, "1st Qu."),
      Norm_Median = safe_extract(norm_stats, "Median"),
      Norm_Mean = safe_extract(norm_stats, "Mean"),
      Norm_Q3 = safe_extract(norm_stats, "3rd Qu."),
      Norm_Max = safe_extract(norm_stats, "Max."),
      stringsAsFactors = FALSE
    )
  })

  summary_table <- do.call(rbind, summary_rows)

  return(summary_table)
}

#' @title Generate Variance Comparison Plots
#' @description Generates plots comparing original and normalized variance distributions
#' @param summary_list List of summary statistics from process_variance_files
#' @importFrom grDevices dev.new
#' @importFrom graphics hist par text
generate_variance_plots <- function(summary_list) {

  # Save original par settings
  old_par <- par(no.readonly = TRUE)
  on.exit(par(old_par))

  for (i in seq_along(summary_list)) {
    res <- summary_list[[names(summary_list)[i]]]

    # Set up 2x1 plotting layout
    par(mfrow = c(2, 1))

    # Original distribution
    orig_data <- res$orig_data[!is.na(res$orig_data)]
    if (length(orig_data) > 0) {
      hist(orig_data,
           main = paste("Original Distribution:", sub("_variance\\.tsv$", "", res$file)),
           xlab = "Variance",
           ylab = "Frequency",
           col = "lightblue",
           border = "black")
    } else {
      plot.new()
      text(0.5, 0.5, "No data available", cex = 1.5)
    }

    # Normalized distribution
    norm_data <- res$norm_data[!is.na(res$norm_data)]
    if (length(norm_data) > 0) {
      hist(norm_data,
           main = paste("Normalized Distribution:", sub("_variance\\.tsv$", "", res$file)),
           xlab = "Normalized Variance",
           ylab = "Frequency",
           col = "lightgreen",
           border = "black")
    } else {
      plot.new()
      text(0.5, 0.5, "No normalized data available", cex = 1.5)
    }

    # Pause between plots if there are more files
    if (i < length(summary_list)) {
      cat("Press [Enter] to see next plot...")
      readline()
    }
  }
}

#' @title Winsorize a Numeric Vector
#' @description Caps extreme values in a numeric vector at specified percentiles.
#' This is used to mitigate the influence of outliers without removing them.
#' @param x A numeric vector.
#' @param winsorize_pct A numeric value between 0 and 0.5 representing the
#' percentage to winsorize on each tail. For example, 0.05 (5%) will cap values
#' below the 5th percentile and above the 95th percentile.
#' @return A numeric vector with extreme values capped.
#' @export
winsorize_vector <- function(x, winsorize_pct = 0.01) {
  if (!is.numeric(x) || !is.numeric(winsorize_pct) || winsorize_pct < 0 || winsorize_pct > 0.5) {
    stop("Invalid input for winsorize_vector. winsorize_pct must be between 0 and 0.5")
  }

  lower_bound <- quantile(x, winsorize_pct, na.rm = TRUE)
  upper_bound <- quantile(x, 1 - winsorize_pct, na.rm = TRUE)

  x[x < lower_bound] <- lower_bound
  x[x > upper_bound] <- upper_bound

  return(x)
}

#' @title Smooth Measurement Intervals
#' @description For a given individual's data, this function identifies clusters of measurements
#' that are less than a specified number of months apart and replaces each cluster with a single
#' representative measurement (mean age, median value). All other columns are carried over by
#' taking the first value in each cluster.
#' @param df A data frame for a single individual, containing EVENT_AGE and VALUE.
#' Any additional columns will be preserved by taking the first value in each cluster.
#' @param min_interval_months The minimum interval in months. Measurements closer than this will be clustered. Defaults to 6.
#' @return A data frame with smoothed measurement intervals, preserving all original columns.
#' @export
smooth_measurement_intervals <- function(df, min_interval_months = 6) {
  if (nrow(df) < 2) {
    return(df)
  }

  df <- df %>% arrange(EVENT_AGE)

  # Calculate time difference to the previous measurement in months
  df <- df %>%
    mutate(time_diff = c(NA, diff(.data$EVENT_AGE) * 12))

  # Identify cluster boundaries (where time_diff is >= min_interval_months)
  df <- df %>%
    mutate(cluster_id = cumsum(is.na(.data$time_diff) | .data$time_diff >= min_interval_months))

  # Summarize each cluster
  smoothed_df <- df %>%
    group_by(.data$cluster_id) %>%
    summarise(
      EVENT_AGE = mean(.data$EVENT_AGE, na.rm = TRUE),
      VALUE = median(.data$VALUE, na.rm = TRUE),
      # Carry over all other columns, taking the first value in the cluster
      across(-c(EVENT_AGE, VALUE, time_diff), first),
      .groups = "drop"
    ) %>%
    select(-cluster_id)

  return(smoothed_df)
}

#' @title Filter Outliers using Median Absolute Deviation (MAD)
#' @description Removes outliers from a numeric vector based on the Median Absolute Deviation (MAD).
#' This method is generally more robust than standard deviation-based outlier removal.
#' @param x A numeric vector.
#' @param th The threshold for MAD. A higher value is more conservative. Defaults to 5.
#' @return A numeric vector with outliers removed.
#' @importFrom stats mad
#' @export
filter_outliers_mad <- function(x, th = 3) {
  median_x <- median(x, na.rm = TRUE)
  mad_x <- stats::mad(x, na.rm = TRUE)

  lower_bound <- median_x - th * mad_x
  upper_bound <- median_x + th * mad_x

  return(x[x >= lower_bound & x <= upper_bound])
}