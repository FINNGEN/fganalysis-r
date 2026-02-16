library(testthat)

# Load the functions from the package
# source("R/drug_response_functions.R")

# Test the drug.response function
test_that("drug.response creates the correct object", {
    response <- data.frame(FINNGENID = c(1, 2), response = c(1, 2))
    lab_measurements <- data.frame(FINNGENID = c(1, 2), VALUE = c(10, 20))
    drug_purchases <- data.frame(FINNGENID = c(1, 2), ATC = c("A01", "A02"))

    result <- drug.response(response, lab_measurements, drug_purchases, c(-1, -0.5), c(0.5, 1))

    expect_s3_class(result, "drug.response")
    expect_equal(result$response, response)
    expect_equal(result$all_measurements, lab_measurements)
    expect_equal(result$all_drug_purchases, drug_purchases)
})

# Test the generate_response_summary function
test_that("generate_response_summary calculates correct summaries", {
    lab_measurements <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG1", "FG1", "FG2", "FG2", "FG2", "FG2", "FG3", "FG3"),
        EVENT_AGE = c(21.1, 20, 20.5, 21.5, 22.0, 34, 34.4, 33.5, 35.0, 40, 40.5),
        VALUE = c(10, 20, 42, 15, 12, 30, 44, 25, 50, 120, 38),
        first_drug = c("A01", "A01", "A01", "A01", "A01", "A02", "A02", "A02", "A02", "A03", "A03"),
        first_drug_age = c(21.05, 21.05, 21.05, 21.05, 21.05, 34.2, 34.2, 34.2, 34.2, 35, 35),
        first_drug_date = as.Date(c("2015-07-17" , "2015-07-17", "2015-07-17", "2015-07-17", "2015-07-17",
                                         "2015-07-18", "2015-07-18", "2015-07-18", "2015-07-18",
                                         "2015-07-19", "2015-07-19"))
        
    )

    drug_purchases <- data.frame(
        FINNGENID = c("FG1", "FG2", "FG3"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17" , "2015-07-18", "2015-07-19")),
        ATC = c("A01","A02", "A03"),
        EVENT_AGE = c(21.05, 34.2, 35),
        VNR = c("123","456", "789"),
        MERGED_SOURCE = c("PURCH","PURCH", "PURCH"),
        time_to_first_drug = c(0,0,0),
        purchase_period = c("Baseline", "Baseline", "Baseline")
    )

    lab_measurements <- lab_measurements %>% mutate(time_to_first_drug = first_drug_age - EVENT_AGE)

    before_period <- c(-1.5, 0)
    after_period <- c(0.00001, 1.5)

    # Add lab_period column as expected by generate_response_summary
    lab_measurements <- lab_measurements %>% mutate(lab_period = case_when(
        dplyr::between(time_to_first_drug, -before_period[2], -before_period[1]) ~ "Baseline",
        dplyr::between(time_to_first_drug, -after_period[2], -after_period[1]) ~ "Followup",
        TRUE ~ NA_character_
    ))

    result <- generate_response_summary(lab_measurements, drug_purchases = drug_purchases, before_period, after_period)

    expect_equal(nrow(result), 2)
    expect_equal(result$baseline, c(31, 27.5))
    expect_equal(result$followup, c(12, 47))
    expect_equal(result$response, c(-19, 19.5))
})

# Test the quant_text function
test_that("quant_text formats quantiles correctly", {
    vector <- c(1, 2, 3, 4, 5)
    result <- quant_text(vector)

    expect_true(grepl("0%:", result))
    expect_true(grepl("100%:", result))
})

# Test the create_drug_response function
test_that("create_drug_response returns the correct structure", {
    kanta <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG1", "FG2", "FG2", "FG2", "FG2", "FG3", "FG3"),
        OMOP_CONCEPT_ID = c("lab1", "lab1", "lab1", "lab1", "lab2", "lab2", "lab2", "lab2", "lab2", "lab2"),
        EVENT_AGE = c(20.6, 20.7, 20.8, 21.5, 19.5, 19.6, 19.7, 20.5, 25, 25.5),
        MEASUREMENT_VALUE_HARMONIZED = c(15, 16.6, 17, 25, 8, 9.5, 10, 40, 50, 38),
        MEASUREMENT_VALUE_MERGED = c(15, 16.6, 17, 25, 8, 9.5, 10, 40, 50, 38)
    )

    drug_events <- data.frame(
        FINNGENID = c("FG1", "FG2", "FG3"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17" , "2015-07-18", "2015-07-19")),
        ATC = c("A01","A02", "A02"),
        EVENT_AGE = c(21.0, 20.0, 35),
        VNR = c("123","456", "789"),
        MERGED_SOURCE = c("PURCH","PURCH", "PURCH"),
        time_to_first_drug = c(0.4, 0.5, 0),
        MEDICATION_QUANTITY = c(1, 1, 1)
    )

    phenos <- data.frame(
        FINNGENID = c("FG2", "FG3"),
        SOURCE = c("PURCH", "PURCH"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-18", "2015-07-19")),
        CODE1 = c("A02", "A02"),
        CODE2 = c("", ""),
        CODE3 = c("", ""),
        CODE4 = c("1", "1"),
        EVENT_AGE = c( 20.0, 35)
    )

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta, drug_events = drug_events))

    lablist <- c("lab1", "lab2")
    druglist <- c("A01", "A02")

    result <- create_drug_response(conn, lablist, druglist, c(-1, 0), c(0.1, 1))
    print(result$responses)
    expect_s3_class(result, "drug.response")
    filtres <- result$responses %>% filter(!is.na(response))
    expect_equal(nrow(result$responses %>% filter(!is.na(response))), 2)
    expect_equal(filtres$FINNGENID, c("FG1", "FG2"))
    expect_equal(filtres$baseline, c(16.6, 9.5))
    expect_equal(filtres$followup, c(25, 40))
    expect_equal(filtres$response, c(8.4, 30.5))


    result <- create_drug_response(conn, lablist, druglist, c(-1, 0), c(0.1, 1), use_only_reimbursement_drugs = TRUE)
    expect_s3_class(result, "drug.response")
    filtres <- result$responses %>% filter(!is.na(response))
    expect_equal(nrow(result$responses %>% filter(!is.na(response))), 1)
    expect_equal(filtres$FINNGENID, c("FG2"))
    expect_equal(filtres$baseline, c(9.5))
    expect_equal(filtres$followup, c(40))
    expect_equal(filtres$response, c(30.5))


    result <- create_drug_response(conn, lablist, druglist, c(-1, 0), c(0.1, 1), use_lab_free_text_values = FALSE)
    filtres <- result$responses %>% filter(!is.na(response))
    expect_s3_class(result, "drug.response")
    expect_equal(nrow(filtres), 2)
    expect_equal(filtres$FINNGENID, c("FG1", "FG2"))
    expect_equal(filtres$baseline, c(16.6, 9.5))
    expect_equal(filtres$followup, c(25, 40))
    expect_equal(filtres$response, c(8.4, 30.5))

})