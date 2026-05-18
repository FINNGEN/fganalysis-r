library(testthat)
library(fganalysis)


### Integration tests
## Starting from get_lab_measurements and get_drug_events, create response, plot and check that everything runs.
## This test does not validate the outputs of the different functions, only that the functions run.
test_that("integration test: drug response and plotting for mock data", {
    # create dummy data
    lab_meas_data <- data.frame(
        OMOP_CONCEPT_ID=c("1","1","1","1","1","1","1","1"),
        FINNGENID=c("FG1","FG1","FG1","FG2","FG2","FG2","FG3","FG3"),
        EVENT_AGE=c(1.0,1.2,1.8,1.1,1.3,1.9,1.25,2.0),
        MEASUREMENT_VALUE_MERGED=c(1.0,1.2,1.9,0.9,1.2,2.0,1.1,2.1),
        APPROX_EVENT_DATETIME=c(as.Date("2000-01-01"),as.Date("2000-01-01"),as.Date("2000-01-01"),as.Date("2000-01-01"),as.Date("2000-01-01"),as.Date("2000-01-01"),as.Date("2000-01-01"),as.Date("2000-01-01"))
    )
    drug_data <- data.frame(
        FINNGENID=c("FG1","FG2","FG3","FG3"),
        EVENT_AGE=c(1.5,1.45,1.3,1.4),
        APPROX_EVENT_DAY=c(as.Date("2000-01-01"),as.Date("2000-01-01"),as.Date("2000-01-01"),as.Date("2000-01-01")),
        SOURCE=c("PURCH","PURCH","PURCH","PURCH"),
        CODE1=c("ATC1","ATC1","ATC1","ATC2"),
        CODE2=c("1","1","1","1"),
        CODE3=c("1","1","1","1"),
        CODE4=c(1,1,1,1)
    )

    #create mock connection object
    mock_conn <- create_mock_connection(
        drug_data,lab_meas_data
    )
    #calculate response
    drug_response <- create_drug_response(mock_conn,
        c("1"),
        c("ATC1","ATC2"),
        c(-1.0,0),
        c(0.01,1))
    #plot
    summary <- summarize_drug_response(drug_response,"/tmp/test_integration")
    plot_lab_value_distribution(drug_response)
    summarize_drug_purchases_upset(drug_response,"/tmp/test_integration2")
    expect_true(T)
})

test_that("get_drug_events function works correctly", {
    # create dummy drug data
    drug_data <- data.frame(
        FINNGENID=c("FG1","FG2","FG3"),
        EVENT_AGE=c(1.5,1.45,1.3),
        APPROX_EVENT_DAY=c(as.Date("2000-01-01"),as.Date("2000-01-01"),as.Date("2000-01-01")),
        SOURCE=c("PURCH","PURCH","PURCH"),
        CODE1=c("ATC1","ATC1","ATC2"),
        CODE2=c("1","1","1"),
        CODE3=c("1","1","1"),
        CODE4=c(1,1,1)
    )

    lab_meas_data <- data.frame(
        OMOP_CONCEPT_ID=c("1","1","1"),
        FINNGENID=c("FG1","FG2","FG3"),
        EVENT_AGE=c(1.0,1.2,1.8),
        MEASUREMENT_VALUE_MERGED=c(1.0,1.2,1.9),
        APPROX_EVENT_DATETIME=c(as.Date("2000-01-01"),as.Date("2000-01-01"),as.Date("2000-01-01"))
    )

    #create mock connection object
    mock_conn <- create_mock_connection(
        drug_data, lab_meas_data
    )

    # Test get_drug_events
    events <- get_drug_events(mock_conn, c("ATC1"))
    expect_equal(nrow(events), 2)
    expect_true(all(c("FINNGENID", "EVENT_AGE", "ATC") %in% colnames(events)))
})

test_that("get_drug_purchases (deprecated) still works with warning", {
    # create dummy drug data
    drug_data <- data.frame(
        FINNGENID=c("FG1","FG2","FG3"),
        EVENT_AGE=c(1.5,1.45,1.3),
        APPROX_EVENT_DAY=c(as.Date("2000-01-01"),as.Date("2000-01-01"),as.Date("2000-01-01")),
        SOURCE=c("PURCH","PURCH","PURCH"),
        CODE1=c("ATC1","ATC1","ATC2"),
        CODE2=c("1","1","1"),
        CODE3=c("1","1","1"),
        CODE4=c(1,1,1)
    )

    lab_meas_data <- data.frame(
        OMOP_CONCEPT_ID=c("1","1","1"),
        FINNGENID=c("FG1","FG2","FG3"),
        EVENT_AGE=c(1.0,1.2,1.8),
        MEASUREMENT_VALUE_MERGED=c(1.0,1.2,1.9),
        APPROX_EVENT_DATETIME=c(as.Date("2000-01-01"),as.Date("2000-01-01"),as.Date("2000-01-01"))
    )

    #create mock connection object
    mock_conn <- create_mock_connection(
        drug_data, lab_meas_data
    )

    # Test that get_drug_purchases still works but issues a warning
    expect_warning(
        purchases <- get_drug_purchases(mock_conn, c("ATC1")),
        "get_drug_purchases\\(\\) is deprecated"
    )
    expect_equal(nrow(purchases), 2)
})