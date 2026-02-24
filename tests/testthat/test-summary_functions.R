library(testthat)

# Test summary functions with create_drug_response
test_that("create_drug_response works with summary_median", {
    # Create mock data with multiple measurements per individual
    kanta <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG1", "FG1", "FG1", "FG2", "FG2", "FG2", "FG2", "FG2", "FG2"),
        OMOP_CONCEPT_ID = c("lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1"),
        EVENT_AGE = c(20.5, 20.7, 20.9, 21.3, 21.5, 21.7, 19.3, 19.6, 19.8, 20.3, 20.5, 20.8),
        MEASUREMENT_VALUE_HARMONIZED = c(10, 20, 30, 35, 40, 50, 5, 15, 25, 30, 35, 45),
        MEASUREMENT_VALUE_MERGED = c(10, 20, 30, 35, 40, 50, 5, 15, 25, 30, 35, 45)
    )

    drug_events <- data.frame(
        FINNGENID = c("FG1", "FG2"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-18")),
        ATC = c("A01", "A01"),
        EVENT_AGE = c(21.0, 20.0),
        VNR = c("123", "123"),
        MERGED_SOURCE = c("PURCH", "PURCH"),
        MEDICATION_QUANTITY = c(1, 1)
    )

    phenos <- data.frame(
        FINNGENID = c("FG1", "FG2"),
        SOURCE = c("PURCH", "PURCH"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-18")),
        CODE1 = c("A01", "A01"),
        CODE2 = c("", ""),
        CODE3 = c("", ""),
        CODE4 = c("1", "1"),
        EVENT_AGE = c(21.0, 20.0)
    )

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta, drug_events = drug_events))

    # Test with summary_median for both baseline and followup
    result <- create_drug_response(
        conn, 
        lablist = c("lab1"), 
        druglist = c("A01"),
        before_period = c(-1, 0),
        after_period = c(0.1, 1),
        summary_functions = list(summary_median, summary_median)
    )

    expect_s3_class(result, "drug.response")
    filtres <- result$responses %>% filter(!is.na(response))
    expect_equal(nrow(filtres), 2)
    
    # FG1: baseline measurements at 20.5, 20.7, 20.9 (values 10, 20, 30) -> median = 20
    #      followup measurements at 21.3, 21.5, 21.7 (values 35, 40, 50) -> median = 40
    # FG2: baseline measurements at 19.3, 19.6, 19.8 (values 5, 15, 25) -> median = 15
    #      followup measurements at 20.3, 20.5, 20.8 (values 30, 35, 45) -> median = 35
    expect_equal(filtres$baseline, c(20, 15))
    expect_equal(filtres$followup, c(40, 35))
    expect_equal(filtres$response, c(20, 20))
})

test_that("create_drug_response works with summary_min", {
    # Create mock data with multiple measurements per individual
    kanta <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG1", "FG1", "FG1", "FG2", "FG2", "FG2", "FG2", "FG2", "FG2"),
        OMOP_CONCEPT_ID = c("lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1"),
        EVENT_AGE = c(20.5, 20.7, 20.9, 21.3, 21.5, 21.7, 19.3, 19.6, 19.8, 20.3, 20.5, 20.8),
        MEASUREMENT_VALUE_HARMONIZED = c(10, 20, 30, 38, 40, 50, 5, 15, 25, 28, 35, 45),
        MEASUREMENT_VALUE_MERGED = c(10, 20, 30, 38, 40, 50, 5, 15, 25, 28, 35, 45)
    )

    drug_events <- data.frame(
        FINNGENID = c("FG1", "FG2"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-18")),
        ATC = c("A01", "A01"),
        EVENT_AGE = c(21.0, 20.0),
        VNR = c("123", "123"),
        MERGED_SOURCE = c("PURCH", "PURCH"),
        MEDICATION_QUANTITY = c(1, 1)
    )

    phenos <- data.frame(
        FINNGENID = c("FG1", "FG2"),
        SOURCE = c("PURCH", "PURCH"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-18")),
        CODE1 = c("A01", "A01"),
        CODE2 = c("", ""),
        CODE3 = c("", ""),
        CODE4 = c("1", "1"),
        EVENT_AGE = c(21.0, 20.0)
    )

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta, drug_events = drug_events))

    # Test with summary_min for both baseline and followup
    result <- create_drug_response(
        conn, 
        lablist = c("lab1"), 
        druglist = c("A01"),
        before_period = c(-1, 0),
        after_period = c(0.1, 1),
        summary_functions = list(summary_min, summary_min)
    )

    expect_s3_class(result, "drug.response")
    filtres <- result$responses %>% filter(!is.na(response))
    expect_equal(nrow(filtres), 2)
    
    # FG1: baseline measurements at 20.5, 20.7, 20.9 (values 10, 20, 30) -> min = 10
    #      followup measurements at 21.3, 21.5, 21.7 (values 38, 40, 50) -> min = 38
    # FG2: baseline measurements at 19.3, 19.6, 19.8 (values 5, 15, 25) -> min = 5
    #      followup measurements at 20.3, 20.5, 20.8 (values 28, 35, 45) -> min = 28
    expect_equal(filtres$baseline, c(10, 5))
    expect_equal(filtres$followup, c(38, 28))
    expect_equal(filtres$response, c(28, 23))
})

test_that("create_drug_response works with summary_closest_to_drug", {
    # Create mock data where measurements are at different distances from drug initiation
    kanta <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG1", "FG1", "FG1", "FG2", "FG2", "FG2", "FG2", "FG2", "FG2"),
        OMOP_CONCEPT_ID = c("lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1", "lab1"),
        # FG1: drug at 21.0, baseline at 20.5 (0.5y before), 20.7 (0.3y before), 20.9 (0.1y before)
        #      followup at 21.2 (0.2y after), 21.5 (0.5y after), 21.8 (0.8y after)
        # FG2: drug at 20.0, baseline at 19.0 (1.0y before), 19.5 (0.5y before), 19.8 (0.2y before)
        #      followup at 20.15 (0.15y after), 20.3 (0.3y after), 20.7 (0.7y after)
        EVENT_AGE = c(20.5, 20.7, 20.9, 21.2, 21.5, 21.8, 19.0, 19.5, 19.8, 20.15, 20.3, 20.7),
        MEASUREMENT_VALUE_HARMONIZED = c(10, 20, 30, 38, 40, 48, 5, 15, 25, 28, 35, 42),
        MEASUREMENT_VALUE_MERGED = c(10, 20, 30, 38, 40, 48, 5, 15, 25, 28, 35, 42)
    )

    drug_events <- data.frame(
        FINNGENID = c("FG1", "FG2"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-18")),
        ATC = c("A01", "A01"),
        EVENT_AGE = c(21.0, 20.0),
        VNR = c("123", "123"),
        MERGED_SOURCE = c("PURCH", "PURCH"),
        MEDICATION_QUANTITY = c(1, 1)
    )

    phenos <- data.frame(
        FINNGENID = c("FG1", "FG2"),
        SOURCE = c("PURCH", "PURCH"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-18")),
        CODE1 = c("A01", "A01"),
        CODE2 = c("", ""),
        CODE3 = c("", ""),
        CODE4 = c("1", "1"),
        EVENT_AGE = c(21.0, 20.0)
    )

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta, drug_events = drug_events))

    # Test with summary_closest_to_drug for both baseline and followup
    result <- create_drug_response(
        conn, 
        lablist = c("lab1"), 
        druglist = c("A01"),
        before_period = c(-1, 0),
        after_period = c(0.1, 1),
        summary_functions = list(summary_closest_to_drug, summary_closest_to_drug)
    )

    expect_s3_class(result, "drug.response")
    filtres <- result$responses %>% filter(!is.na(response))
    expect_equal(nrow(filtres), 2)
    
    # FG1: baseline closest to drug (21.0) is 20.9 (0.1y before) -> value = 30
    #      followup closest to drug is 21.2 (0.2y after) -> value = 38
    # FG2: baseline closest to drug (20.0) is 19.8 (0.2y before) -> value = 25
    #      followup closest to drug is 20.15 (0.15y after) -> value = 28
    expect_equal(filtres$baseline, c(30, 25))
    expect_equal(filtres$followup, c(38, 28))
    expect_equal(filtres$response, c(8, 3))
})

test_that("create_drug_response works with different summary functions for baseline and followup", {
    # Create mock data
    kanta <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG1", "FG1"),
        OMOP_CONCEPT_ID = c("lab1", "lab1", "lab1", "lab1", "lab1"),
        # Drug at 21.0
        # Baseline: 20.4 (0.6y), 20.6 (0.4y), 20.8 (0.2y) -> values 10, 20, 30
        # Followup: 21.3 (0.3y), 21.7 (0.7y) -> values 40, 50
        EVENT_AGE = c(20.4, 20.6, 20.8, 21.3, 21.7),
        MEASUREMENT_VALUE_HARMONIZED = c(10, 20, 30, 40, 50),
        MEASUREMENT_VALUE_MERGED = c(10, 20, 30, 40, 50)
    )

    drug_events <- data.frame(
        FINNGENID = c("FG1"),
        APPROX_EVENT_DAY = as.Date("2015-07-17"),
        ATC = c("A01"),
        EVENT_AGE = c(21.0),
        VNR = c("123"),
        MERGED_SOURCE = c("PURCH"),
        MEDICATION_QUANTITY = c(1)
    )

    phenos <- data.frame(
        FINNGENID = c("FG1"),
        SOURCE = c("PURCH"),
        APPROX_EVENT_DAY = as.Date("2015-07-17"),
        CODE1 = c("A01"),
        CODE2 = c(""),
        CODE3 = c(""),
        CODE4 = c("1"),
        EVENT_AGE = c(21.0)
    )

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta, drug_events = drug_events))

    # Test with summary_min for baseline and summary_median for followup
    result <- create_drug_response(
        conn, 
        lablist = c("lab1"), 
        druglist = c("A01"),
        before_period = c(-1, 0),
        after_period = c(0.1, 1),
        summary_functions = list(summary_min, summary_median)
    )

    expect_s3_class(result, "drug.response")
    filtres <- result$responses %>% filter(!is.na(response))
    expect_equal(nrow(filtres), 1)
    
    # Baseline: min of (10, 20, 30) = 10
    # Followup: median of (40, 50) = 45
    expect_equal(filtres$baseline, 10)
    expect_equal(filtres$followup, 45)
    expect_equal(filtres$response, 35)

    # Test with summary_closest_to_drug for baseline and summary_min for followup
    result2 <- create_drug_response(
        conn, 
        lablist = c("lab1"), 
        druglist = c("A01"),
        before_period = c(-1, 0),
        after_period = c(0.1, 1),
        summary_functions = list(summary_closest_to_drug, summary_min)
    )

    expect_s3_class(result2, "drug.response")
    filtres2 <- result2$responses %>% filter(!is.na(response))
    expect_equal(nrow(filtres2), 1)
    
    # Baseline: closest to drug (21.0) is 20.8 (0.2y before) -> value = 30
    # Followup: min of (40, 50) = 40
    expect_equal(filtres2$baseline, 30)
    expect_equal(filtres2$followup, 40)
    expect_equal(filtres2$response, 10)

    # Test with summary_median for baseline and summary_closest_to_drug for followup
    result3 <- create_drug_response(
        conn, 
        lablist = c("lab1"), 
        druglist = c("A01"),
        before_period = c(-1, 0),
        after_period = c(0.1, 1),
        summary_functions = list(summary_median, summary_closest_to_drug)
    )

    expect_s3_class(result3, "drug.response")
    filtres3 <- result3$responses %>% filter(!is.na(response))
    expect_equal(nrow(filtres3), 1)
    
    # Baseline: median of (10, 20, 30) = 20
    # Followup: closest to drug (21.0) is 21.3 (0.3y after) -> value = 40
    expect_equal(filtres3$baseline, 20)
    expect_equal(filtres3$followup, 40)
    expect_equal(filtres3$response, 20)
})

test_that("summary_closest_to_drug returns correct value with ties", {
    # Test the summary_closest_to_drug function directly with tied distances
    lab_values <- data.frame(
        VALUE = c(10, 20, 30),
        time_to_first_drug = c(0.5, -0.5, 0.2),  # 0.2 is closest (absolute distance)
        FINNGENID = c("FG1", "FG1", "FG1")
    )
    
    result <- summary_closest_to_drug(lab_values)
    expect_equal(result, 30)  # Value with smallest absolute time_to_first_drug
    
    # Test with exact tie
    lab_values_tie <- data.frame(
        VALUE = c(10, 20, 30),
        time_to_first_drug = c(0.3, -0.3, 0.5),  # 0.3 and -0.3 are tied
        FINNGENID = c("FG1", "FG1", "FG1")
    )
    
    result_tie <- summary_closest_to_drug(lab_values_tie)
    # With ties, slice_head returns first occurrence after sorting
    expect_true(result_tie %in% c(10, 20))
})

test_that("summary functions handle single measurement correctly", {
    lab_values <- data.frame(
        VALUE = c(42),
        time_to_first_drug = c(0.5),
        FINNGENID = c("FG1")
    )
    
    expect_equal(summary_median(lab_values), 42)
    expect_equal(summary_min(lab_values), 42)
    expect_equal(summary_closest_to_drug(lab_values), 42)
})

test_that("create_drug_response fails with invalid summary_functions parameter", {
    kanta <- data.frame(
        FINNGENID = c("FG1"),
        OMOP_CONCEPT_ID = c("lab1"),
        EVENT_AGE = c(20.5),
        MEASUREMENT_VALUE_HARMONIZED = c(10),
        MEASUREMENT_VALUE_MERGED = c(10)
    )

    drug_events <- data.frame(
        FINNGENID = c("FG1"),
        APPROX_EVENT_DAY = as.Date("2015-07-17"),
        ATC = c("A01"),
        EVENT_AGE = c(21.0),
        VNR = c("123"),
        MERGED_SOURCE = c("PURCH"),
        MEDICATION_QUANTITY = c(1)
    )

    phenos <- data.frame(
        FINNGENID = c("FG1"),
        SOURCE = c("PURCH"),
        APPROX_EVENT_DAY = as.Date("2015-07-17"),
        CODE1 = c("A01"),
        CODE2 = c(""),
        CODE3 = c(""),
        CODE4 = c("1"),
        EVENT_AGE = c(21.0)
    )

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta, drug_events = drug_events))

    # Test with only one function (should fail - needs 2)
    expect_error(
        create_drug_response(
            conn, 
            lablist = c("lab1"), 
            druglist = c("A01"),
            before_period = c(-1, 0),
            after_period = c(0.1, 1),
            summary_functions = list(summary_median)
        )
    )

    # Test with three functions (should fail - needs exactly 2)
    expect_error(
        create_drug_response(
            conn, 
            lablist = c("lab1"), 
            druglist = c("A01"),
            before_period = c(-1, 0),
            after_period = c(0.1, 1),
            summary_functions = list(summary_median, summary_median, summary_min)
        )
    )

    # Test with non-function object
    expect_error(
        create_drug_response(
            conn, 
            lablist = c("lab1"), 
            druglist = c("A01"),
            before_period = c(-1, 0),
            after_period = c(0.1, 1),
            summary_functions = list(summary_median, "not_a_function")
        )
    )
})
