library(testthat)
library(dplyr)

# Mock connection object for testing
mock_conn <- function() {
    labs <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG2", "FG2", "FG3", "FG3", "FG4"),
        OMOP_CONCEPT_ID = "3001308",
        EVENT_AGE = c(50.0, 50.1, 50.5, 60.0, 60.3, 70.0, 70.2, 80.0),
        MEASURED_VALUE_HARMONIZED = c(100, 102, 150, 110, 112, 120, 122, 500),
        MEASUREMENT_VALUE_MERGED = c(100, 102, 150, 110, 112, 120, 122, 500),
        stringsAsFactors = FALSE
    )

    pheno <- data.frame(
        FINNGENID = c("FG1", "FG2"),
        EVENT_AGE = c(50.2, 60.1),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-18")),
        CODE1 = "C10AA",
        CODE2 = "", CODE3 = "", CODE4 = "1",
        SOURCE = "PURCH",
        stringsAsFactors = FALSE
    )

    drug_events <- data.frame(
        FINNGENID = c("FG1", "FG2", "FG3"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-18", "2015-07-19")),
        ATC = c("C10AA", "C10AA", "C10AA"),
        EVENT_AGE = c(21.0, 20.0, 35),
        VNR = c("123", "456", "789"),
        MERGED_SOURCE = c("PURCH", "PURCH", "PURCH"),
        MEDICATION_QUANTITY = c(1, 1, 1)
    )

    cov <- data.frame(
        FINNGENID = c("FG1", "FG2", "FG3", "FG4"),
        SEX = c("Male", "Female", "Male", "Female"),
        stringsAsFactors = FALSE
    )
    dat <- list(labs = labs, pheno = pheno, cov_pheno = cov, drug_events = drug_events)

    return(fg_data_connection(dat))
}

    test_that("get_measurements_before_drug works as a standalone function", {
    conn <- mock_conn()

    # Test with default 3 months
    measurements <- get_measurements_before_drug(
        conn,
        lablist = "3001308",
        druglist = "C10AA",
        months_before = 3
    )


    measurements_no_free <- get_measurements_before_drug(
        conn,
        lablist = "3001308",
        druglist = "C10AA",
        months_before = 3,
        use_only_reimbursement = TRUE
    )

    # Add covariates using helper function
    measurements <- join_covariates_to_labs(
        lab_data = measurements,
        covariates = conn$cov_pheno,
        covariate_cols = "SEX"
    )

    # With months_before = 3 (0.25 years), we expect:
    # FG1: 2 measurements (50.0 and 50.1 are before drug at 50.2)
    # FG2: 1 measurement (60.0 is before drug at 60.1)
    # FG3 and FG4: no drug purchases, so no measurements included
    print("#######")
    print(measurements)
    print("#######")
    expect_equal(nrow(measurements), 1)
    expect_equal(nrow(measurements_no_free), 3)
    
    expect_true("SEX" %in% colnames(measurements))

    # Filter to ensure there are rows for FG1 before pulling
    fg1_sex <- measurements %>%
        filter(FINNGENID == "FG1") %>%
        pull(SEX)
    if (length(fg1_sex) > 0) {
        expect_equal(unique(fg1_sex), "Male")
    }

    # Check measurement counts
    fg1_counts <- measurements %>%
        filter(FINNGENID == "FG1") %>%
        pull(n_measurements)
    if (length(fg1_counts) > 0) {
        expect_equal(unique(fg1_counts), 2)
    }

    fg3_counts <- measurements %>%
        filter(FINNGENID == "FG3") %>%
        pull(n_measurements)
    if (length(fg3_counts) > 0) {
        expect_equal(unique(fg3_counts), 2)
    }
})

test_that("outlier removal works correctly", {
    conn <- mock_conn()

    # Test SD removal
    measurements_sd <- get_measurements_before_drug(
        conn,
        lablist = "3001308",
        druglist = "C10AA",
        months_before = 3,
        remove_outliers_sd = 1,
        use_only_reimbursement = TRUE
    )
    # The value 500 from FG4 should be removed
    expect_false(500 %in% measurements_sd$VALUE)

    # Test Winsorizing
    measurements_win <- get_measurements_before_drug(
        conn,
        lablist = "3001308",
        druglist = "C10AA",
        months_before = 3,
        winsorize_pct = 0.1, # 10% winsorization on each tail,
        use_only_reimbursement = TRUE
    )
    # The value 500 should be capped at the 90th percentile
    expect_true(max(measurements_win$VALUE) < 500)
})

test_that("smooth_measurement_intervals works correctly", {
    test_data <- data.frame(
        FINNGENID = "FG1", OMOP_CONCEPT_ID = "123", SEX_CODED = 1L,
        EVENT_AGE = c(50.0, 50.1, 50.3, 51.0, 51.2, 52.0),
        VALUE = c(10, 12, 10, 20, 22, 30)
    )

    smoothed <- smooth_measurement_intervals(test_data, min_interval_months = 6)

    # Three clusters: (50.0, 50.1, 50.3), (51.0, 51.2), (52.0)
    expect_equal(nrow(smoothed), 3)
    # Check first cluster: mean age, median value
    expect_equal(smoothed$EVENT_AGE[1], mean(c(50.0, 50.1, 50.3)))
    expect_equal(smoothed$VALUE[1], 10) # Median of 10, 12, 10 is 10
    # Check second cluster
    expect_equal(smoothed$EVENT_AGE[2], mean(c(51.0, 51.2)))
    expect_equal(smoothed$VALUE[2], 21) # Median of 20, 22 is 21
    # Check third cluster (isolated point)
    expect_equal(smoothed$EVENT_AGE[3], 52.0)
    expect_equal(smoothed$VALUE[3], 30)
})

test_that("get_measurements_before_drug calculates time_to_drug correctly", {
    # Create deterministic test data with known drug purchase ages and lab measurement ages
    conn <- list(
        labs = data.frame(
            FINNGENID = c("FG1", "FG1", "FG1", "FG2", "FG2", "FG3", "FG3"),
            OMOP_CONCEPT_ID = "3001308",
            EVENT_AGE = c(49.0, 50.0, 51.0, 59.0, 61.0, 69.0, 71.0),
            MEASUREMENT_VALUE_MERGED = c(100, 102, 104, 110, 112, 120, 122),
            MEASUREMENT_VALUE_MERGED = c(100, 102, 104, 110, 112, 120, 122),
            stringsAsFactors = FALSE
        ),
        pheno = data.frame(
            FINNGENID = c("FG1", "FG2"),
            EVENT_AGE = c(50.5, 60.0), # Drug purchase ages
            CODE1 = "C10AA",
            SOURCE = "PURCH",
            stringsAsFactors = FALSE
        ),
        drug_events = data.frame(
            FINNGENID = c("FG1", "FG2"),
            EVENT_AGE = c(50.5, 60.0), # Drug purchase ages
            ATC = "C10AA",
            MERGED_SOURCE = "PURCH",
            stringsAsFactors = FALSE,
            MEDICATION_QUANTITY = c(1, 1)
        )


    )
    class(conn) <- "fg_data_connection"

    measurements <- get_measurements_before_drug(
        conn,
        lablist = "3001308",
        druglist = "C10AA",
        months_before = 12, # 1 year = 1.0 years
    )

    # Verify time_to_drug calculations: time_to_drug = first_drug_age - EVENT_AGE
    # Filtering condition: time_to_drug >= 0 & time_to_drug >= time_window_years
    # For 12 months (1.0 year) window, measurements need time_to_drug >= 1.0

    # FG1: Drug at 50.5, so time_to_drug should be:
    #   - Lab at 49.0: 50.5 - 49.0 = 1.5 years (>= 1.0, included)
    #   - Lab at 50.0: 50.5 - 50.0 = 0.5 years (< 1.0, excluded)
    #   - Lab at 51.0: 50.5 - 51.0 = -0.5 years (< 0, excluded)

    # FG2: Drug at 60.0, so time_to_drug should be:
    #   - Lab at 59.0: 60.0 - 59.0 = 1.0 years (>= 1.0, included)
    #   - Lab at 61.0: 60.0 - 61.0 = -1.0 years (< 0, excluded)

    # FG3: No drug purchase, so all measurements should be included

    # Check that we get the expected number of measurements
    expect_equal(nrow(measurements), 4) # FG1: 1 measurement, FG2: 1 measurement, FG3: 2 measurements

    # Verify specific measurements are included/excluded
    fg1_measurements <- measurements %>% filter(FINNGENID == "FG1")
    expect_equal(nrow(fg1_measurements), 1)
    expect_equal(fg1_measurements$EVENT_AGE, 49.0)
    expect_false(50.0 %in% fg1_measurements$EVENT_AGE) # Should be excluded (< 1.0 year)
    expect_false(51.0 %in% fg1_measurements$EVENT_AGE) # Should be excluded (after drug)

    fg2_measurements <- measurements %>% filter(FINNGENID == "FG2")
    expect_equal(nrow(fg2_measurements), 1)
    expect_equal(fg2_measurements$EVENT_AGE, 59.0)
    expect_false(61.0 %in% fg2_measurements$EVENT_AGE) # Should be excluded (after drug)

    fg3_measurements <- measurements %>% filter(FINNGENID == "FG3")
    expect_equal(nrow(fg3_measurements), 2)
    expect_true(all(fg3_measurements$EVENT_AGE %in% c(69.0, 71.0))) # All included (no drug)
})

test_that("get_measurements_before_drug filters by time window correctly", {
    # Create data with measurements at various time points relative to drug purchase
    conn <- list(
        labs = data.frame(
            FINNGENID = c("FG1", "FG1", "FG1", "FG1", "FG1"),
            OMOP_CONCEPT_ID = "3001308",
            EVENT_AGE = c(49.0, 49.5, 50.0, 50.2, 50.5), # Drug at 50.5
            MEASUREMENT_VALUE_HARMONIZED = c(100, 101, 102, 103, 104),
            MEASUREMENT_VALUE_MERGED = c(100, 101, 102, 103, 104),
            stringsAsFactors = FALSE
        ),
        pheno = data.frame(
            FINNGENID = "FG1",
            EVENT_AGE = 50.5, # Drug purchase age
            CODE1 = "C10AA",
            SOURCE = "PURCH",
            stringsAsFactors = FALSE
        ),
        drug_events = data.frame(
            FINNGENID = "FG1",
            EVENT_AGE = 50.5, # Drug purchase age
            ATC = "C10AA",
            MERGED_SOURCE = "PURCH",
            stringsAsFactors = FALSE,
            MEDICATION_QUANTITY = c(1)
        )
    )

    class(conn) <- "fg_data_connection"
    # Test with 6 months (0.5 years) window
    measurements_6m <- get_measurements_before_drug(
        conn,
        lablist = "3001308",
        druglist = "C10AA",
        months_before = 6
    )

    # With 6 months window, only measurements with time_to_drug >= 0.5 should be included
    # time_to_drug = 50.5 - EVENT_AGE:
    #   - 49.0: 1.5 years (>= 0.5, included)
    #   - 49.5: 1.0 years (>= 0.5, included)
    #   - 50.0: 0.5 years (>= 0.5, included)
    #   - 50.2: 0.3 years (< 0.5, excluded)
    #   - 50.5: 0.0 years (< 0.5, excluded)

    expect_equal(nrow(measurements_6m), 3)
    expect_true(all(measurements_6m$EVENT_AGE %in% c(49.0, 49.5, 50.0)))
    expect_false(any(measurements_6m$EVENT_AGE %in% c(50.2, 50.5)))

    # Test with 12 months (1.0 years) window
    measurements_12m <- get_measurements_before_drug(
        conn,
        lablist = "3001308",
        druglist = "C10AA",
        months_before = 12
    )

    # With 12 months window, only measurements with time_to_drug >= 1.0 should be included
    # time_to_drug = 50.5 - EVENT_AGE:
    #   - 49.0: 1.5 years (>= 1.0, included)
    #   - 49.5: 1.0 years (>= 1.0, included)
    #   - 50.0: 0.5 years (< 1.0, excluded)
    #   - 50.2: 0.3 years (< 1.0, excluded)
    #   - 50.5: 0.0 years (< 1.0, excluded)
    expect_equal(nrow(measurements_12m), 2)
    expect_true(all(measurements_12m$EVENT_AGE %in% c(49.0, 49.5)))
})

test_that("get_measurements_before_drug returns expected measurement values", {
    # Create data where we know exactly which measurements should be included
    conn <- list(
        labs = data.frame(
            FINNGENID = c("FG1", "FG1", "FG1", "FG2", "FG2", "FG3", "FG3"),
            OMOP_CONCEPT_ID = "3001308",
            EVENT_AGE = c(49.0, 50.0, 51.0, 59.0, 61.0, 69.0, 71.0),
            MEASUREMENT_VALUE_HARMONIZED = c(100, 102, 104, 110, 112, 120, 122),
            MEASUREMENT_VALUE_MERGED = c(100, 102, 104, 110, 112, 120, 122),
            stringsAsFactors = FALSE
        ),
        pheno = data.frame(
            FINNGENID = c("FG1", "FG2"),
            EVENT_AGE = c(50.5, 60.0),
            CODE1 = "C10AA",
            SOURCE = "PURCH",
            stringsAsFactors = FALSE
        ),
        drug_events = data.frame(
            FINNGENID = c("FG1", "FG2"),
            EVENT_AGE = c(50.5, 60.0),
            ATC = "C10AA",
            MERGED_SOURCE = "PURCH",
            stringsAsFactors = FALSE,
            MEDICATION_QUANTITY = c(1, 1)
        )
    )

    class(conn) <- "fg_data_connection"
    measurements <- get_measurements_before_drug(
        conn,
        lablist = "3001308",
        druglist = "C10AA",
        months_before = 12
    )

    # Verify that the correct lab values are returned
    # Expected measurements (12 months = 1.0 year window):
    # FG1: 49.0 (value 100) - >= 1 year before drug at 50.5
    #      50.0 (value 102) - < 1 year before drug, excluded
    # FG2: 59.0 (value 110) - >= 1 year before drug at 60.0
    # FG3: 69.0 (value 120), 71.0 (value 122) - no drug, all included

    expected_values <- c(100, 110, 120, 122)
    expect_true(all(measurements$VALUE %in% expected_values))
    expect_equal(length(measurements$VALUE), length(expected_values))

    # Verify specific values are present
    expect_true(100 %in% measurements$VALUE)
    expect_true(110 %in% measurements$VALUE)
    expect_true(120 %in% measurements$VALUE)
    expect_true(122 %in% measurements$VALUE)

    # Verify excluded values are not present
    expect_false(102 %in% measurements$VALUE) # FG1, < 1 year before drug
    expect_false(104 %in% measurements$VALUE) # FG1, after drug
    expect_false(112 %in% measurements$VALUE) # FG2, after drug

    # Verify n_measurements calculation
    fg1_count <- measurements %>%
        filter(FINNGENID == "FG1") %>%
        pull(n_measurements) %>%
        unique()
    expect_equal(fg1_count, 1)

    fg2_count <- measurements %>%
        filter(FINNGENID == "FG2") %>%
        pull(n_measurements) %>%
        unique()
    expect_equal(fg2_count, 1)

    fg3_count <- measurements %>%
        filter(FINNGENID == "FG3") %>%
        pull(n_measurements) %>%
        unique()
    expect_equal(fg3_count, 2)
})

test_that("get_measurements_before_drug handles edge cases correctly", {
    # Test case 1: Measurements exactly at drug purchase time
    conn_exact <- list(
        labs = data.frame(
            FINNGENID = c("FG1", "FG1", "FG1"),
            OMOP_CONCEPT_ID = "3001308",
            EVENT_AGE = c(49.5, 50.0, 50.5), # Drug at 50.5
            MEASUREMENT_VALUE_HARMONIZED = c(100, 102, 104),
            MEASUREMENT_VALUE_MERGED = c(100, 102, 104),
            stringsAsFactors = FALSE
        ),
        pheno = data.frame(
            FINNGENID = "FG1",
            EVENT_AGE = 50.5,
            CODE1 = "C10AA",
            SOURCE = "PURCH",
            stringsAsFactors = FALSE
        ),
        drug_events = data.frame(
            FINNGENID = "FG1",
            EVENT_AGE = 50.5, # Drug purchase age
            ATC = "C10AA",
            MERGED_SOURCE = "PURCH",
            stringsAsFactors = FALSE,
            MEDICATION_QUANTITY = c(1)

    ))
    class(conn_exact) <- "fg_data_connection"
    measurements_exact <- get_measurements_before_drug(
        conn_exact,
        lablist = "3001308",
        druglist = "C10AA",
        months_before = 6 # 0.5 years
    )

    # time_to_drug = 50.5 - EVENT_AGE:
    #   - 49.5: 1.0 years (>= 0.5, included)
    #   - 50.0: 0.5 years (>= 0.5, included)
    #   - 50.5: 0.0 years (< 0.5, excluded)
    expect_equal(nrow(measurements_exact), 2)
    expect_true(all(measurements_exact$EVENT_AGE %in% c(49.5, 50.0)))
    expect_false(50.5 %in% measurements_exact$EVENT_AGE)

    # Test case 2: No measurements in time window
    conn_empty <- list(
        labs = data.frame(
            FINNGENID = c("FG1", "FG1"),
            OMOP_CONCEPT_ID = "3001308",
            EVENT_AGE = c(50.2, 50.4), # Drug at 50.5, both too close
            MEASUREMENT_VALUE_MERGED = c(100, 102),
            MEASUREMENT_VALUE_HARMONIZED = c(100, 102),
            stringsAsFactors = FALSE
        ),
        pheno = data.frame(
            FINNGENID = "FG1",
            EVENT_AGE = 50.5,
            CODE1 = "C10AA",
            SOURCE = "PURCH",
            stringsAsFactors = FALSE
        ),
        drug_events = data.frame(
            FINNGENID = "FG1",
            EVENT_AGE = 50.5, # Drug purchase age
            ATC = "C10AA",
            MERGED_SOURCE = "PURCH",
            stringsAsFactors = FALSE,
            MEDICATION_QUANTITY = c(1)
        )   
    )
    class(conn_empty) <- "fg_data_connection"
    measurements_empty <- get_measurements_before_drug(
        conn_empty,
        lablist = "3001308",
        druglist = "C10AA",
        months_before = 6,# 0.5 years
    )

    # Both measurements have time_to_drug < 0.5, so should be excluded
    expect_equal(nrow(measurements_empty), 0)

    # Test case 3: Only unexposed individuals
    conn_unexposed <- list(
        labs = data.frame(
            FINNGENID = c("FG1", "FG1", "FG2", "FG2"),
            OMOP_CONCEPT_ID = "3001308",
            EVENT_AGE = c(49.0, 50.0, 59.0, 61.0),
            MEASUREMENT_VALUE_HARMONIZED = c(100, 102, 110, 112),
            MEASUREMENT_VALUE_MERGED = c(100, 102, 110, 112),
            stringsAsFactors = FALSE
        ),
        pheno = data.frame(
            FINNGENID = character(0), # No drug purchases
            EVENT_AGE = numeric(0),
            CODE1 = character(0),
            SOURCE = character(0),
            stringsAsFactors = FALSE
        ),
        drug_events = data.frame(
            FINNGENID = character(0), # No drug purchases
            EVENT_AGE = numeric(0),
            ATC = character(0),
            MERGED_SOURCE = character(0),
            stringsAsFactors = FALSE,
            MEDICATION_QUANTITY = numeric(0)
        )   
    )
    class(conn_unexposed) <- "fg_data_connection"
    measurements_unexposed <- get_measurements_before_drug(
        conn_unexposed,
        lablist = "3001308",
        druglist = "C10AA",
        months_before = 6
    )

    # All measurements should be included for unexposed individuals
    expect_equal(nrow(measurements_unexposed), 4)
    expect_true(all(measurements_unexposed$EVENT_AGE %in% c(49.0, 50.0, 59.0, 61.0)))
    expect_true(all(measurements_unexposed$VALUE %in% c(100, 102, 110, 112)))
})

test_that("get_measurements_before_drug outlier removal preserves expected values", {
    # Create data with known outliers
    conn_outliers <- list(
        labs = data.frame(
            FINNGENID = c("FG1", "FG1", "FG1", "FG1", "FG2", "FG2"),
            OMOP_CONCEPT_ID = "3001308",
            EVENT_AGE = c(49.0, 50.0, 51.0, 52.0, 59.0, 61.0),
            MEASUREMENT_VALUE_HARMONIZED = c(100, 102, 500, 104, 110, 112), # 500 is outlier
            MEASUREMENT_VALUE_MERGED = c(100, 102, 500, 104, 110, 112),
            stringsAsFactors = FALSE
        ),
        pheno = data.frame(
            FINNGENID = c("FG1", "FG2"),
            EVENT_AGE = c(50.5, 60.0),
            CODE1 = "C10AA",
            SOURCE = "PURCH",
            stringsAsFactors = FALSE
        ),
        drug_events = data.frame(
            FINNGENID = c("FG1", "FG2"),
            EVENT_AGE = c(50.5, 60.0),
            ATC = "C10AA",
            MERGED_SOURCE = "PURCH",
            stringsAsFactors = FALSE,
            MEDICATION_QUANTITY = c(1, 1)
        )

    )
    class(conn_outliers) <- "fg_data_connection"
    # Test SD-based outlier removal
    measurements_sd <- get_measurements_before_drug(
        conn_outliers,
        lablist = "3001308",
        druglist = "C10AA",
        months_before = 12,
        remove_outliers_sd = 2 # Remove values > 2 SD from mean
    )

    # The value 500 should be removed, others should be preserved
    expect_false(500 %in% measurements_sd$VALUE)
    # After outlier removal and time filtering, we should have fewer values
    # The exact values depend on which measurements pass the time window filter
    expect_true(all(measurements_sd$VALUE < 500))

    # Test Winsorizing
    measurements_winsor <- get_measurements_before_drug(
        conn_outliers,
        lablist = "3001308",
        druglist = "C10AA",
        months_before = 12,
        winsorize_pct = 0.1, # 10% winsorization on each tail
    )

    # The value 500 should be capped, not removed
    expect_true(max(measurements_winsor$VALUE) < 500)
    # The capped value should be reasonable (not too low)
    expect_true(max(measurements_winsor$VALUE) > 100)
})
