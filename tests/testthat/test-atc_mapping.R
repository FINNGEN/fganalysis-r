# Test file for ATC code mapping functionality
library(testthat)
library(fganalysis)

# Get path to test fixtures
test_fixtures_dir <- file.path(testthat::test_path(), "fixtures")
test_mapping_file <- file.path(test_fixtures_dir, "atc_mappings.json")

test_that("ATC mapping expansion works for dulaglutide", {

  # Clear cache to ensure fresh load
  clear_atc_cache()

  # Test expansion of dulaglutide current code
  expanded <- expand_atc_codes(
    atc_codes = c("A10BJ05"),  # Current dulaglutide code
    include_hierarchical = FALSE,
    verbose = FALSE,
    custom_mapping_file = test_mapping_file
  )

  # Should include both current and historical codes
  expect_true("A10BJ05" %in% expanded)  # Current code
  expect_true("A10BX07" %in% expanded)  # Historical code

  # Test expansion of historical code
  expanded_historical <- expand_atc_codes(
    atc_codes = c("A10BX07"),  # Historical dulaglutide code
    include_hierarchical = FALSE,
    verbose = FALSE,
    custom_mapping_file = test_mapping_file
  )

  # Should include both codes when starting from historical
  expect_true("A10BJ05" %in% expanded_historical)  # Current code
  expect_true("A10BX07" %in% expanded_historical)  # Original input
})

test_that("ATC mapping with hierarchical expansion works", {

  # Clear cache to ensure fresh load
  clear_atc_cache()

  # Test with hierarchical expansion
  expanded <- expand_atc_codes(
    atc_codes = c("A10BJ05"),
    include_hierarchical = TRUE,
    verbose = FALSE,
    custom_mapping_file = test_mapping_file
  )

  # Should include hierarchical codes
  expect_true("A10BJ05" %in% expanded)  # Full code
  expect_true("A10BJ" %in% expanded)     # 5-character hierarchy
  expect_true("A10B" %in% expanded)      # 4-character hierarchy
  expect_true("A10" %in% expanded)       # 3-character hierarchy
})

test_that("get_atc_relationships returns correct information", {

  # Clear cache to ensure fresh load
  clear_atc_cache()

  # Load mappings first
  mappings_data <- load_atc_mappings(custom_file = test_mapping_file)

  # Get relationships for current code
  relationships <- get_atc_relationships("A10BJ05", mappings = mappings_data$mappings)

  expect_equal(relationships$original, "A10BJ05")
  expect_equal(relationships$current, "A10BJ05")
  # Handle both list and vector formats
  historical <- if (is.list(relationships$historical)) unlist(relationships$historical) else relationships$historical
  expect_true("A10BX07" %in% historical)
  expect_equal(relationships$description, "dulaglutide")

  # Get relationships for historical code
  relationships_old <- get_atc_relationships("A10BX07", mappings = mappings_data$mappings)

  expect_equal(relationships_old$original, "A10BX07")
  expect_equal(relationships_old$current, "A10BJ05")
  # Handle both list and vector formats
  related <- if (is.list(relationships_old$related)) unlist(relationships_old$related) else relationships_old$related
  expect_true("A10BJ05" %in% related)
})

test_that("Integration with get_drug_purchases works with mock data", {

  # Skip if we're not in a test environment with mock data
  skip_if_not(exists("create_mock_connection"))

  # Clear cache to ensure fresh load
  clear_atc_cache()

  # Create mock data with both old and new dulaglutide codes
  # Note: FINNGENIDs are anonymized test IDs
  pheno_data <- data.frame(
    FINNGENID = c("TEST001", "TEST002", "TEST003", "TEST004"),
    EVENT_AGE = c(50, 55, 60, 65),
    APPROX_EVENT_DAY = c(18250, 20075, 21900, 23725),
    CODE1 = c("A10BJ05", "A10BX07", "A10BJ05", "C10AA01"),  # Mix of new, old dulaglutide and a statin
    CODE2 = c("205", "205", "205", "315"),  # Reimbursement codes
    CODE3 = c("VNR123", "VNR124", "VNR125", "VNR126"),  # VNR codes
    CODE4 = c("1", "1", "1", "1"),  # Number of packs
    SOURCE = rep("PURCH", 4),
    stringsAsFactors = FALSE
  )

  labs_data <- data.frame(
    FINNGENID = c("TEST001", "TEST002", "TEST003"),
    OMOP_CONCEPT_ID = c("3004410", "3004410", "3004410"),  # HbA1c
    EVENT_AGE = c(49, 54, 59),
    VALUE = c(8.5, 9.0, 7.5),
    stringsAsFactors = FALSE
  )

  # Create mock connection
  mock_conn <- create_mock_connection(
    pheno_data = pheno_data,
    labs_data = labs_data
  )

  # Load mappings for the test (this populates the cache)
  # This ensures the cache is populated before get_drug_purchases is called
  clear_atc_cache()
  mappings_loaded <- load_atc_mappings(custom_file = test_mapping_file)
  # Verify mappings were loaded
  expect_true(mappings_loaded$total_mappings > 0)

  # Manually expand codes to populate cache with the test fixture
  # This ensures expand_atc_codes will use cached mappings
  expanded_test <- expand_atc_codes(
    atc_codes = c("A10BJ05"),
    include_hierarchical = FALSE,
    verbose = FALSE,
    custom_mapping_file = test_mapping_file
  )
  expect_true("A10BX07" %in% expanded_test)

  # Test with ATC mapping enabled (default)
  # expand_atc_codes will use the cached mappings
  drug_purchases_mapped <- get_drug_purchases(
    conn = mock_conn,
    druglist = c("A10BJ05"),  # Search for current dulaglutide code
    use_atc_mapping = TRUE,
    use_only_reimbursement = TRUE
  )

  # Should find TEST001 (A10BJ05), TEST002 (A10BX07), and TEST003 (A10BJ05)
  expect_equal(nrow(drug_purchases_mapped), 3)  # TEST001, TEST002, and TEST003
  expect_true("TEST001" %in% drug_purchases_mapped$FINNGENID)
  expect_true("TEST002" %in% drug_purchases_mapped$FINNGENID)
  expect_true("TEST003" %in% drug_purchases_mapped$FINNGENID)
  expect_false("TEST004" %in% drug_purchases_mapped$FINNGENID)  # Different drug

  # Test with ATC mapping disabled
  drug_purchases_no_map <- get_drug_purchases(
    conn = mock_conn,
    druglist = c("A10BJ05"),
    use_atc_mapping = FALSE,
    use_only_reimbursement = TRUE
  )

  # Should only find TEST001 and TEST003 (exact match A10BJ05)
  expect_equal(nrow(drug_purchases_no_map), 2)
  expect_true("TEST001" %in% drug_purchases_no_map$FINNGENID)
  expect_false("TEST002" %in% drug_purchases_no_map$FINNGENID)  # Old code not found
  expect_true("TEST003" %in% drug_purchases_no_map$FINNGENID)
})

test_that("create_drug_response works with ATC mapping", {

  skip_if_not(exists("create_mock_connection"))

  # Clear cache to ensure fresh load
  clear_atc_cache()

  # Create comprehensive mock data
  pheno_data <- data.frame(
    FINNGENID = c(rep("TEST001", 2), rep("TEST002", 2), rep("TEST003", 1)),
    EVENT_AGE = c(50, 52, 55, 57, 60),
    APPROX_EVENT_DAY = c(18250, 18980, 20075, 20805, 21900),
    CODE1 = c("A10BJ05", "A10BJ05", "A10BX07", "A10BX07", "A10BJ05"),
    CODE2 = c("205", "205", "205", "205", "205"),
    CODE3 = paste0("VNR", 1:5),
    CODE4 = rep("1", 5),
    SOURCE = rep("PURCH", 5),
    stringsAsFactors = FALSE
  )

  labs_data <- data.frame(
    FINNGENID = c(rep("TEST001", 4), rep("TEST002", 4), rep("TEST003", 3)),
    OMOP_CONCEPT_ID = rep("3004410", 11),  # HbA1c
    EVENT_AGE = c(
      49, 49.5, 51, 53,       # TEST001: before and after
      54, 54.5, 56, 58,       # TEST002: before and after
      59, 61, 62              # TEST003: before and after
    ),
    VALUE = c(
      8.5, 8.3, 7.8, 7.5,     # TEST001: improvement
      9.0, 8.8, 8.2, 8.0,     # TEST002: improvement
      7.5, 7.0, 6.8           # TEST003: improvement
    ),
    MEASUREMENT_VALUE_MERGED = c(
      8.5, 8.3, 7.8, 7.5,     # TEST001: improvement
      9.0, 8.8, 8.2, 8.0,     # TEST002: improvement
      7.5, 7.0, 6.8           # TEST003: improvement
    ),
    stringsAsFactors = FALSE
  )

  mock_conn <- create_mock_connection(
    pheno_data = pheno_data,
    labs_data = labs_data
  )

  # Load mappings for the test (populate cache)
  clear_atc_cache()
  mappings_loaded <- load_atc_mappings(custom_file = test_mapping_file)
  expect_true(mappings_loaded$total_mappings > 0)

  # Create drug response with ATC mapping
  response <- create_drug_response(
    conn = mock_conn,
    lablist = c("3004410"),
    druglist = c("A10BJ05"),  # Current code only
    before_period = c(-1, 0),
    after_period = c(0.1, 2),
    use_atc_mapping = TRUE  # Will find both old and new codes
  )

  # All three patients should be included
  expect_equal(nrow(response$responses), 3)

  # Check that responses are calculated correctly
  expect_true(all(response$responses$response < 0))  # All show improvement (lower HbA1c)
})

test_that("Verbose output provides clear information", {

  # Clear cache to ensure fresh load
  clear_atc_cache()

  # Verify test fixture exists
  skip_if_not(file.exists(test_mapping_file), "Test mapping file not found")

  # Capture messages - need to ensure mappings are loaded first
  messages <- capture_messages({
    # Load mappings first to populate cache and generate load message
    load_atc_mappings(custom_file = test_mapping_file)
    # Now expand codes with verbose output
    expanded <- expand_atc_codes(
      atc_codes = c("A10BJ05", "A10BX07"),
      include_hierarchical = FALSE,
      verbose = TRUE,
      custom_mapping_file = test_mapping_file
    )
  })

  # Debug: print captured messages if test fails
  if (length(messages) == 0) {
    cat("No messages captured. Messages:", paste(messages, collapse = "\n"), "\n")
  }

  # Check that messages contain expected information
  # Note: messages may include loading messages as well
  all_messages <- paste(messages, collapse = " ")
  expect_true(any(grepl("ATC Code Expansion", messages)) || grepl("ATC Code Expansion", all_messages))
  expect_true(any(grepl("Expanding.*input ATC code", messages)) || grepl("Expanding.*input ATC code", all_messages))
  expect_true(any(grepl("expanded to", messages)) || grepl("expanded to", all_messages))
  expect_true(any(grepl("Expansion Complete", messages)) || grepl("Expansion Complete", all_messages))
})

test_that("Error when mapping file not found and use_atc_mapping = TRUE", {

  # Clear cache to ensure fresh state
  clear_atc_cache()

  # Test that expand_atc_codes errors when require_mapping = TRUE and no file found
  # Use a non-existent file to simulate missing mappings
  clear_atc_cache()

  # This should error because require_mapping = TRUE and no valid mapping file
  expect_error(
    expand_atc_codes(
      atc_codes = c("A10BJ05"),
      include_hierarchical = FALSE,
      verbose = FALSE,
      custom_mapping_file = "/nonexistent/path/atc_mappings.json",
      require_mapping = TRUE
    ),
    "ATC mapping file not found"
  )

  # Test that expand_atc_codes works when require_mapping = FALSE (default)
  # Even without mappings, it should return original codes
  clear_atc_cache()
  result_no_require <- expand_atc_codes(
    atc_codes = c("A10BJ05"),
    include_hierarchical = FALSE,
    verbose = FALSE,
    custom_mapping_file = "/nonexistent/path/atc_mappings.json",
    require_mapping = FALSE
  )
  expect_true("A10BJ05" %in% result_no_require)  # Should return original code

  # Test that get_drug_purchases works when use_atc_mapping = FALSE
  # Create minimal mock connection
  pheno_data <- data.frame(
    FINNGENID = c("TEST001"),
    EVENT_AGE = c(50),
    APPROX_EVENT_DAY = c(18250),
    CODE1 = c("A10BJ05"),
    CODE2 = c("205"),
    CODE3 = c("VNR123"),
    CODE4 = c("1"),
    SOURCE = "PURCH",
    stringsAsFactors = FALSE
  )

  labs_data <- data.frame(
    FINNGENID = c("TEST001"),
    OMOP_CONCEPT_ID = c("3004410"),
    EVENT_AGE = c(49),
    VALUE = c(8.5),
    stringsAsFactors = FALSE
  )

  mock_conn <- create_mock_connection(
    pheno_data = pheno_data,
    labs_data = labs_data
  )

  # This should work because mapping is disabled
  result_no_mapping <- get_drug_purchases(
    conn = mock_conn,
    druglist = c("A10BJ05"),
    use_atc_mapping = FALSE,
    use_only_reimbursement = TRUE
  )
  expect_true(nrow(result_no_mapping) >= 0)  # Should succeed without error
})
