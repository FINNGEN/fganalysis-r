library(testthat)


# Load the functions from the package
#source("R/drug_response_functions.R")

# Test the drug.response function
test_that("drug.response creates the correct object", {
  response <- data.frame(FINNGENID = c(1, 2), response = c(1, 2))
  lab_measurements <- data.frame(FINNGENID = c(1, 2), MEASUREMENT_VALUE_HARMONIZED = c(10, 20))
  drug_purchases <- data.frame(FINNGENID = c(1, 2), ATC = c("A01", "A02"))
  
  result <- drug.response(response, lab_measurements, drug_purchases, c(-1, -0.5), c(0.5, 1))
  
  expect_s3_class(result, "drug.reponse")
  expect_equal(result$response, response)
  expect_equal(result$all_measurements, lab_measurements)
  expect_equal(result$all_drug_purchases, drug_purchases)
})

# Test the generate_response_summary function
test_that("generate_response_summary calculates correct summaries", {
lab_measurements <- data.frame(FINNGENID = c("FG1", "FG1", "FG1", "FG1", "FG1", "FG2", "FG2", "FG2", "FG2", "FG3", "FG3"),
                                  EVENT_AGE = c(21.1, 20, 20.5, 21.5, 22.0, 34, 34.4, 33.5, 35.0, 40, 40.5),
                                  MEASUREMENT_VALUE_HARMONIZED = c(10, 20, 42, 15, 12, 30, 44, 25, 50, 120, 38),
                                  first_drug = c("A01", "A01", "A01", "A01", "A01", "A02", "A02", "A02", "A02", "A03", "A03"),
                                  first_drug_age = c(21.05, 21.05, 21.05, 21.05, 21.05, 34.2, 34.2, 34.2, 34.2, 35, 35))
  lab_measurements <-  lab_measurements %>% mutate(time_to_drug = first_drug_age - EVENT_AGE)

  before_period <- c(-1.5, 0)
  after_period <- c(0.00001, 1.5)
  
  result <- generate_response_summary(lab_measurements, before_period, after_period)
  
  expect_equal(nrow(result), 2)
  expect_equal(result$before, c(31, 27.5))
  expect_equal(result$after, c(12, 47)) 
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
    FINNGENID = c("FG1", "FG1", "FG1", "FG1", "FG2", "FG2", "FG2", "FG2","FG3", "FG3"),
    OMOP_CONCEPT_ID = c("lab1", "lab1", "lab1", "lab1", "lab2", "lab2", "lab2", "lab2", "lab2", "lab2"),
    EVENT_AGE = c(20.6, 20.7, 20.8, 21.5, 19.5, 19.6, 19.7, 20.5,25, 25.5),
    MEASUREMENT_VALUE_HARMONIZED = c(15, 16, 17, 25, 8, 9, 10, 40, 50, 38))
  
  phenos <- data.frame(
    FINNGENID = c("FG1", "FG2","FG3"),
    SOURCE = c("PURCH", "PURCH","PURCH"),
    CODE1 = c("A01", "A02", "A02"),
    CODE2 = c("", "", ""),
    CODE3 = c("", "", ""),
    CODE4 = c("1", "1", "1"),
    EVENT_AGE = c(21.0, 20.0, 35)
  )
                        
  lablist <- c("lab1", "lab2")
  druglist <- c("A01", "A02")
  
  result <- create_drug_response(kanta, phenos, lablist, druglist, c(-1, 0), c(0.1, 1))
  
  expect_s3_class(result, "drug.reponse")
  expect_equal(nrow(result$response), 2)
  expect_equal(result$response$FINNGENID, c("FG1", "FG2"))
  expect_equal(result$response$before, c(16, 9))
  expect_equal(result$response$after, c(25, 40))
  expect_equal(result$response$response, c(9, 31))
})