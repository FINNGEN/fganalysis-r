# Helper function to create minimal Kanta data for tests
create_empty_kanta_data <- function() {
    data.frame(
        FINNGENID = character(),
        OMOP_CONCEPT_ID = character(),
        EVENT_AGE = numeric(),
        MEASUREMENT_VALUE_HARMONIZED = numeric(),
        MEASUREMENT_VALUE_MERGED = numeric()
    )
}

# Test external labs with create_drug_response
test_that("create_drug_response works with external_labs parameter", {
    library(dplyr)
    
    # Create test data
    external_lab_data <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG1", "FG2", "FG2", "FG2", "FG2", "FG3", "FG3"),
        OMOP_CONCEPT_ID = c("lab1", "lab1", "lab1", "lab1", "lab2", "lab2", "lab2", "lab2", "lab2", "lab2"),
        EVENT_AGE = c(20.6, 20.7, 20.8, 21.5, 19.5, 19.6, 19.7, 20.5, 25, 25.5),
        VALUE = c(15, 16.6, 17, 25, 8, 9.5, 10, 40, 50, 38)
    )

    drug_events <- data.frame(
        FINNGENID = c("FG1", "FG2", "FG3"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-18", "2015-07-19")),
        ATC = c("A01", "A02", "A02"),
        EVENT_AGE = c(21.0, 20.0, 35),
        VNR = c("123", "456", "789"),
        MERGED_SOURCE = c("PURCH", "PURCH", "PURCH")
    )

    phenos <- data.frame(
        FINNGENID = c("FG2", "FG3"),
        SOURCE = c("PURCH", "PURCH"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-18", "2015-07-19")),
        CODE1 = c("A02", "A02"),
        CODE2 = c("", ""),
        CODE3 = c("", ""),
        CODE4 = c("1", "1"),
        EVENT_AGE = c(20.0, 35)
    )

    # Create a minimal Kanta data (not used when external_labs is provided)
    kanta <- create_empty_kanta_data()

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta, drug_events = drug_events))

    lablist <- c("lab1", "lab2")
    druglist <- c("A01", "A02")

    # Test with external labs
    result <- create_drug_response(conn, lablist, druglist, c(-1, 0), c(0.1, 1), external_labs = external_lab_data)

    expect_s3_class(result, "drug.response")
    filtres <- result$responses %>% filter(!is.na(response))
    expect_equal(nrow(filtres), 2)
    expect_equal(filtres$FINNGENID, c("FG1", "FG2"))
    expect_equal(filtres$before, c(16.6, 9.5))
    expect_equal(filtres$after, c(25, 40))
    expect_equal(filtres$response, c(8.4, 30.5))
})

test_that("create_drug_response validates external_labs format", {
    # Create minimal connection
    phenos <- data.frame(
        FINNGENID = c("FG1"),
        SOURCE = c("PURCH"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-18")),
        CODE1 = c("A01"),
        CODE2 = c(""),
        CODE3 = c(""),
        CODE4 = c("1"),
        EVENT_AGE = c(20.0)
    )
    
    kanta <- create_empty_kanta_data()

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta))

    # Test with invalid external_labs (not a data frame)
    expect_error(
        create_drug_response(conn, c("lab1"), c("A01"), c(-1, 0), c(0.1, 1), external_labs = "not_a_dataframe"),
        "external_labs must be a data frame"
    )

    # Test with missing required column
    invalid_external_labs <- data.frame(
        FINNGENID = c("FG1"),
        OMOP_CONCEPT_ID = c("lab1"),
        EVENT_AGE = c(20.5)
        # Missing VALUE column
    )

    expect_error(
        create_drug_response(conn, c("lab1"), c("A01"), c(-1, 0), c(0.1, 1), external_labs = invalid_external_labs),
        "external_labs is missing required columns: VALUE"
    )
})

# Test external labs with get_measurements_before_drug
test_that("get_measurements_before_drug works with external_labs parameter", {
    # Create test data
    external_lab_data <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG2", "FG2", "FG2", "FG3", "FG3"),
        OMOP_CONCEPT_ID = c("3001308", "3001308", "3001308", "3001308", "3001308", "3001308", "3001308", "3001308"),
        EVENT_AGE = c(49.5, 49.7, 49.9, 49.6, 49.8, 50.1, 48, 48.5),
        VALUE = c(100, 105, 110, 95, 100, 105, 120, 125)
    )

    drug_events <- data.frame(
        FINNGENID = c("FG1", "FG2"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-18")),
        ATC = c("C10AA", "C10AA"),
        EVENT_AGE = c(50.0, 50.0),
        VNR = c("123", "456"),
        MERGED_SOURCE = c("PURCH", "PURCH")
    )

    phenos <- data.frame(
        FINNGENID = c("FG1", "FG2"),
        SOURCE = c("PURCH", "PURCH"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-18")),
        CODE1 = c("C10AA", "C10AA"),
        CODE2 = c("", ""),
        CODE3 = c("", ""),
        CODE4 = c("1", "1"),
        EVENT_AGE = c(50.0, 50.0)
    )

    # Create a minimal Kanta data (not used when external_labs is provided)
    kanta <- create_empty_kanta_data()

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta, drug_events = drug_events))

    # Test with external labs
    result <- get_measurements_before_drug(
        conn = conn,
        lablist = c("3001308"),
        druglist = c("C10AA"),
        months_before = 3,
        external_labs = external_lab_data
    )

    # Should include measurements before drug for exposed individuals and all for unexposed
    expect_true("n_measurements" %in% colnames(result))
    expect_true(all(c("FINNGENID", "OMOP_CONCEPT_ID", "EVENT_AGE", "VALUE") %in% colnames(result)))
    
    # Check that FG1 and FG2 have measurements within the time window, FG3 has all measurements
    exposed_measurements <- result %>% filter(FINNGENID %in% c("FG1", "FG2"))
    unexposed_measurements <- result %>% filter(FINNGENID == "FG3")
    
    expect_true(nrow(exposed_measurements) > 0)
    expect_true(nrow(unexposed_measurements) > 0)
    
    # FG3 (unexposed) should have all measurements
    expect_equal(nrow(unexposed_measurements), 2)
})

test_that("get_measurements_before_drug validates external_labs format", {
    # Create minimal connection
    phenos <- data.frame(
        FINNGENID = c("FG1"),
        SOURCE = c("PURCH"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-18")),
        CODE1 = c("C10AA"),
        CODE2 = c(""),
        CODE3 = c(""),
        CODE4 = c("1"),
        EVENT_AGE = c(50.0)
    )
    
    kanta <- create_empty_kanta_data()

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta))

    # Test with invalid external_labs (not a data frame)
    expect_error(
        get_measurements_before_drug(conn, c("3001308"), c("C10AA"), months_before = 3, external_labs = "not_a_dataframe"),
        "external_labs must be a data frame"
    )

    # Test with missing required columns
    invalid_external_labs <- data.frame(
        FINNGENID = c("FG1"),
        OMOP_CONCEPT_ID = c("3001308"),
        VALUE = c(100)
        # Missing EVENT_AGE column
    )

    expect_error(
        get_measurements_before_drug(conn, c("3001308"), c("C10AA"), months_before = 3, external_labs = invalid_external_labs),
        "external_labs is missing required columns: EVENT_AGE"
    )
})

test_that("external_labs works with BLUP analysis via calculate_blup_slopes", {
    # Create external lab data with sufficient measurements for BLUP
    # Use consistent ages to ensure enough data for BLUP analysis
    set.seed(123)
    external_lab_data <- data.frame()
    
    for (i in 1:15) {
        finngenid <- paste0("FG", sprintf("%04d", i))
        # Generate ages spread across lifespan to ensure measurements before drug
        # For drug-exposed (1-10): ages 30-65 ensures multiple measurements before age 50
        # For unexposed (11-15): full age range
        if (i <= 10) {
            ages <- seq(30, 65, length.out = 5)
        } else {
            ages <- seq(25, 75, length.out = 5)
        }
        individual_slope <- rnorm(1, -0.02, 0.01)
        individual_intercept <- rnorm(1, 5, 0.5)
        lab_values <- individual_intercept + individual_slope * ages + rnorm(5, 0, 0.2)
        
        individual_data <- data.frame(
            FINNGENID = finngenid,
            OMOP_CONCEPT_ID = "3001308",
            EVENT_AGE = ages,
            VALUE = lab_values
        )
        external_lab_data <- rbind(external_lab_data, individual_data)
    }

    # Create drug data
    drug_events <- data.frame(
        FINNGENID = paste0("FG", sprintf("%04d", 1:10)),
        APPROX_EVENT_DAY = as.Date("2015-07-17"),
        ATC = "C10AA",
        EVENT_AGE = 50.0,
        VNR = "123",
        MERGED_SOURCE = "PURCH"
    )

    phenos <- data.frame(
        FINNGENID = paste0("FG", sprintf("%04d", 1:10)),
        SOURCE = "PURCH",
        APPROX_EVENT_DAY = as.Date("2015-07-17"),
        CODE1 = "C10AA",
        CODE2 = "",
        CODE3 = "",
        CODE4 = "1",
        EVENT_AGE = 50.0
    )

    kanta <- create_empty_kanta_data()

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta, drug_events = drug_events))

    # Get measurements using external labs
    # Use a smaller time window (12 months) to include measurements closer to drug
    # This still tests the external_labs functionality while ensuring sufficient data
    measurements <- get_measurements_before_drug(
        conn = conn,
        lablist = c("3001308"),
        druglist = c("C10AA"),
        months_before = 12,  # 1 year before drug to include more measurements
        external_labs = external_lab_data
    )

    # Calculate BLUP slopes
    skip_if_not_installed("lme4")
    
    result <- calculate_blup_slopes(
        data = measurements,
        min_measurements = 3,
        include_sex = FALSE
    )

    # Check that BLUP analysis completed successfully
    expect_type(result, "list")
    expect_true("3001308" %in% names(result))
    expect_false(is.null(result[["3001308"]]))
    expect_true("blup_slopes" %in% names(result[["3001308"]]))
})

test_that("external_labs filters by lablist correctly", {
    # Create external lab data with multiple lab types
    external_lab_data <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG1"),
        OMOP_CONCEPT_ID = c("lab1", "lab1", "lab2", "lab2"),
        EVENT_AGE = c(20.6, 20.7, 20.8, 21.5),
        VALUE = c(15, 16.6, 17, 25)
    )

    drug_events <- data.frame(
        FINNGENID = c("FG1"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17")),
        ATC = c("A01"),
        EVENT_AGE = c(21.0),
        VNR = c("123"),
        MERGED_SOURCE = c("PURCH")
    )

    phenos <- data.frame(
        FINNGENID = c("FG1"),
        SOURCE = c("PURCH"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17")),
        CODE1 = c("A01"),
        CODE2 = c(""),
        CODE3 = c(""),
        CODE4 = c("1"),
        EVENT_AGE = c(21.0)
    )

    kanta <- create_empty_kanta_data()

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta, drug_events = drug_events))

    # Test filtering to only lab1
    result <- create_drug_response(
        conn, 
        lablist = c("lab1"),  # Only requesting lab1
        druglist = c("A01"), 
        c(-1, 0), 
        c(0.1, 1), 
        external_labs = external_lab_data
    )

    # Check that only lab1 measurements are included
    expect_true(all(result$all_measurements$OMOP_CONCEPT_ID == "lab1"))
    expect_equal(nrow(result$all_measurements), 2)  # Only 2 lab1 measurements
})

test_that("external_labs with finngen_ids filtering works correctly", {
    # Create external lab data for multiple individuals
    external_lab_data <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG2", "FG2", "FG3", "FG3"),
        OMOP_CONCEPT_ID = c("lab1", "lab1", "lab1", "lab1", "lab1", "lab1"),
        EVENT_AGE = c(20.6, 20.7, 19.5, 19.6, 18.5, 18.6),
        VALUE = c(15, 16.6, 8, 9.5, 10, 11)
    )

    drug_events <- data.frame(
        FINNGENID = c("FG1", "FG2", "FG3"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-18", "2015-07-19")),
        ATC = c("A01", "A01", "A01"),
        EVENT_AGE = c(21.0, 20.0, 19.0),
        VNR = c("123", "456", "789"),
        MERGED_SOURCE = c("PURCH", "PURCH", "PURCH")
    )

    phenos <- data.frame(
        FINNGENID = c("FG1", "FG2", "FG3"),
        SOURCE = c("PURCH", "PURCH", "PURCH"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-18", "2015-07-19")),
        CODE1 = c("A01", "A01", "A01"),
        CODE2 = c("", "", ""),
        CODE3 = c("", "", ""),
        CODE4 = c("1", "1", "1"),
        EVENT_AGE = c(21.0, 20.0, 19.0)
    )

    kanta <- create_empty_kanta_data()

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta, drug_events = drug_events))

    # Test filtering to only FG1 and FG2
    result <- create_drug_response(
        conn, 
        lablist = c("lab1"),
        druglist = c("A01"), 
        c(-1, 0), 
        c(0.1, 1),
        finngen_ids = c("FG1", "FG2"),  # Only FG1 and FG2
        external_labs = external_lab_data
    )

    # Check that only FG1 and FG2 measurements are included
    expect_true(all(result$all_measurements$FINNGENID %in% c("FG1", "FG2")))
    expect_false(any(result$all_measurements$FINNGENID == "FG3"))
})
