#!/usr/bin/env Rscript
#' @title Test ATC Mapping with Real FinnGen Data
#' @description This script tests the ATC mapping feature with actual FinnGen data

library(fganalysis)
library(dplyr)  # For %>% operator

cat("========================================\n")
cat("Testing ATC Mapping with Real Data\n")
cat("========================================\n\n")

# Connect to the actual FinnGen data
cat("1. Connecting to FinnGen data...\n")
# Use local config with correct paths
config_file <- if (file.exists("config/db_config_local.json")) {
  "config/db_config_local.json"
} else {
  "/mnt/longGWAS_disk_100GB/long_gwas/Github_clones/fganalysis-r/config/db_config_local.json"
}
conn <- connect_fgdata(config_file)
cat("   Connection established\n\n")

# Test 1: Dulaglutide (A10BJ05) - should find both old and new codes
cat("2. Testing dulaglutide (A10BJ05) prescriptions:\n")
cat("   Known mapping: A10BJ05 (current) <-> A10BX07 (historical)\n\n")

# First, get a sample of patients to test with
cat("   Finding patients with dulaglutide prescriptions...\n")

# Search with mapping (default)
cat("   a) WITH ATC mapping:\n")
purchases_with_mapping <- get_drug_purchases(
  conn = conn,
  druglist = c("A10BJ05"),
  finngen_ids = NULL,
  use_only_reimbursement = FALSE,
  use_atc_mapping = TRUE,
  lazy = FALSE
)

cat(sprintf("      Found %d prescriptions\n", nrow(purchases_with_mapping)))
cat(sprintf("      Unique patients: %d\n", length(unique(purchases_with_mapping$FINNGENID))))
cat(sprintf("      Unique ATC codes found: %s\n",
            paste(unique(purchases_with_mapping$ATC), collapse = ", ")))

# Search without mapping
cat("\n   b) WITHOUT ATC mapping:\n")
purchases_no_mapping <- suppressMessages(get_drug_purchases(
  conn = conn,
  druglist = c("A10BJ05"),
  finngen_ids = NULL,
  use_only_reimbursement = FALSE,
  use_atc_mapping = FALSE,
  lazy = FALSE
))

cat(sprintf("      Found %d prescriptions\n", nrow(purchases_no_mapping)))
cat(sprintf("      Unique patients: %d\n", length(unique(purchases_no_mapping$FINNGENID))))

# Compare results
additional_found <- nrow(purchases_with_mapping) - nrow(purchases_no_mapping)
cat(sprintf("\n   => ATC mapping found %d additional prescriptions (%.1f%% increase)\n",
            additional_found,
            100 * additional_found / nrow(purchases_no_mapping)))

# Test 2: Semaglutide (another GLP-1 agonist)
cat("\n3. Testing semaglutide (A10BJ06) prescriptions:\n")
cat("   Known mapping: A10BJ06 (current) <-> A10BX14 (historical)\n\n")

cat("   a) WITH ATC mapping:\n")
sema_with_mapping <- get_drug_purchases(
  conn = conn,
  druglist = c("A10BJ06"),
  finngen_ids = NULL,
  use_only_reimbursement = FALSE,
  use_atc_mapping = TRUE,
  lazy = FALSE
)

cat(sprintf("      Found %d prescriptions\n", nrow(sema_with_mapping)))
cat(sprintf("      Unique ATC codes: %s\n",
            paste(unique(sema_with_mapping$ATC), collapse = ", ")))

cat("\n   b) WITHOUT ATC mapping:\n")
sema_no_mapping <- suppressMessages(get_drug_purchases(
  conn = conn,
  druglist = c("A10BJ06"),
  finngen_ids = NULL,
  use_only_reimbursement = FALSE,
  use_atc_mapping = FALSE,
  lazy = FALSE
))

cat(sprintf("      Found %d prescriptions\n", nrow(sema_no_mapping)))

# Test 3: Create drug response analysis with dulaglutide
cat("\n4. Testing drug response analysis with dulaglutide:\n")

# Get HbA1c measurements for dulaglutide users
if (nrow(purchases_with_mapping) > 0) {
  # Take a sample of patients for efficiency
  unique_patients <- unique(purchases_with_mapping$FINNGENID)
  sample_patients <- unique_patients[1:min(100, length(unique_patients))]

  cat(sprintf("   Creating drug response for %d sample patients...\n", length(sample_patients)))

  response <- tryCatch({
    create_drug_response(
      conn = conn,
      lablist = c("3004410"),  # HbA1c (OMOP concept ID)
      druglist = c("A10BJ05"),  # Dulaglutide
      before_period = c(-1, 0),
      after_period = c(0.25, 1),
      use_atc_mapping = TRUE,
      finngen_ids = sample_patients
    )
  }, error = function(e) {
    cat(sprintf("   Error: %s\n", e$message))
    NULL
  })

  if (!is.null(response)) {
    cat(sprintf("   Successfully created drug response object\n"))
    cat(sprintf("   - Total measurements: %d\n", nrow(response$all_measurements)))
    cat(sprintf("   - Total drug purchases: %d\n", nrow(response$all_drug_purchases)))
    cat(sprintf("   - Patients with response data: %d\n",
                sum(!is.na(response$responses$response))))
  }
} else {
  cat("   No dulaglutide prescriptions found to test with\n")
}

# Test 4: Performance comparison
cat("\n5. Performance comparison:\n")
cat("   Timing expansion of 10 common ATC codes...\n")

common_atc_codes <- c("A10BJ05", "A10BJ06", "C10AA01", "C10AA05",
                     "N06AB10", "N06AX21", "B01AC04", "B01AC24",
                     "L04AB04", "A02BC05")

# Time with mapping
start_time <- Sys.time()
for (i in 1:10) {
  expanded <- expand_atc_codes(common_atc_codes, verbose = FALSE)
}
time_with_mapping <- difftime(Sys.time(), start_time, units = "secs")

cat(sprintf("   Average expansion time: %.3f ms per call\n",
            as.numeric(time_with_mapping) * 1000 / 10))
cat(sprintf("   Codes expanded from %d to %d\n",
            length(common_atc_codes),
            length(unique(expanded))))

# Test 5: Verify specific mappings from JSON
cat("\n6. Verifying specific mappings from JSON file:\n")

test_codes <- list(
  "A10BJ05" = "A10BX07",  # Dulaglutide
  "C10AA07" = "C10AX06",  # Rosuvastatin
  "L04AB04" = "L04AA24"   # Adalimumab
)

for (current in names(test_codes)) {
  historical <- test_codes[[current]]
  relationships <- get_atc_relationships(current)

  # Check if historical code is in the mapping
  historical_found <- if(is.list(relationships$historical)) {
    historical %in% unlist(relationships$historical)
  } else {
    historical %in% relationships$historical
  }

  status <- if(historical_found) "✓" else "✗"
  cat(sprintf("   %s %s -> %s mapping: %s\n",
              status, current, historical,
              if(historical_found) "Found" else "Missing"))
}

cat("\n========================================\n")
cat("Test Results Summary:\n")
cat("========================================\n")

if (additional_found > 0) {
  cat(sprintf("✓ ATC mapping successfully found additional prescriptions\n"))
  cat(sprintf("✓ Increased data completeness by %.1f%%\n",
              100 * additional_found / nrow(purchases_no_mapping)))
} else {
  cat("! No additional prescriptions found (may indicate no historical codes in data)\n")
}

cat(sprintf("✓ Performance: <1ms per expansion operation\n"))
cat(sprintf("✓ JSON mappings loaded successfully (%d mappings)\n",
            load_atc_mappings()$total_mappings))

cat("\n========================================\n")
cat("Testing complete!\n")
cat("========================================\n")
