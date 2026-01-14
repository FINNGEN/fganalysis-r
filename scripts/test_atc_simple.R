#!/usr/bin/env Rscript
# Simple test of ATC mapping functionality

# Load required libraries
library(dplyr)
library(rjson)
library(stringr)

# Source the package files directly
# Robustly determine the script directory
get_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))
  } else if (!is.null(sys.frame(1)$ofile)) {
    return(dirname(normalizePath(sys.frame(1)$ofile)))
  } else {
    # Fallback: use current working directory
    return(getwd())
  }
}
script_dir <- get_script_dir()
source(file.path(script_dir, "..", "R", "atc_mapping.R"))

cat("========================================\n")
cat("Simple ATC Mapping Test\n")
cat("========================================\n\n")

# Test 1: Load mappings
cat("1. Loading ATC mappings from JSON...\n")
mappings <- load_atc_mappings()
cat(sprintf("   Successfully loaded %d mappings\n\n", mappings$total_mappings))

# Test 2: Expand a single ATC code
cat("2. Testing expansion of dulaglutide (A10BJ05):\n")
expanded <- expand_atc_codes(
  atc_codes = c("A10BJ05"),
  include_hierarchical = FALSE,
  verbose = TRUE
)
cat(sprintf("   Result: %s\n\n", paste(expanded, collapse = ", ")))

# Test 3: Get relationships
cat("3. Testing get_atc_relationships for A10BJ05:\n")
rels <- get_atc_relationships("A10BJ05")
cat(sprintf("   Current: %s\n", rels$current))
cat(sprintf("   Historical: %s\n", paste(unlist(rels$historical), collapse = ", ")))
cat(sprintf("   Description: %s\n\n", rels$description))

# Test 4: Test multiple codes
cat("4. Testing multiple ATC codes:\n")
test_codes <- c("A10BJ05", "A10BJ06", "C10AA07")
expanded_multi <- expand_atc_codes(
  atc_codes = test_codes,
  include_hierarchical = FALSE,
  verbose = FALSE
)
cat(sprintf("   Input: %d codes -> Output: %d codes\n",
            length(test_codes), length(expanded_multi)))
cat(sprintf("   Expanded codes: %s\n\n", paste(expanded_multi, collapse = ", ")))

# Test 5: Hierarchical expansion
cat("5. Testing hierarchical expansion:\n")
expanded_hier <- expand_atc_codes(
  atc_codes = c("A10BJ05"),
  include_hierarchical = TRUE,
  verbose = FALSE
)
cat(sprintf("   With hierarchical: %d codes\n", length(expanded_hier)))
cat(sprintf("   Includes: %s\n", paste(head(expanded_hier, 10), collapse = ", ")))

cat("\n========================================\n")
cat("All basic tests passed successfully!\n")
cat("========================================\n")













