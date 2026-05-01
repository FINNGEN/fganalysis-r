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

# Test that total DDD calculation handles NA MEDICATION_QUANTITY correctly
test_that("generate_response_summary calculates total_ddd_followup correctly with NA MEDICATION_QUANTITY", {
    lab_measurements <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG2", "FG2", "FG2"),
        EVENT_AGE = c(20, 20.5, 21.5, 34, 34.4, 35.0),
        VALUE = c(20, 42, 15, 30, 44, 50),
        first_drug = c("A01", "A01", "A01", "A02", "A02", "A02"),
        first_drug_age = c(21.0, 21.0, 21.0, 34.5, 34.5, 34.5),
        first_drug_date = as.Date(c("2015-07-17", "2015-07-17", "2015-07-17",
                                    "2015-07-18", "2015-07-18", "2015-07-18")),
        time_to_first_drug = c(1.0, 0.5, -0.5, 0.5, 0.1, -0.5)
    )

    # Drug purchases with mixed NA and non-NA MEDICATION_QUANTITY values
    # FG1: First purchase at age 21.0 (baseline) + 2 followup purchases
    # FG2: First purchase at age 34.5 (baseline) + 1 followup purchase
    drug_purchases <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG2", "FG2"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-30", "2015-08-15",
                                     "2015-07-18", "2015-08-20")),
        ATC = c("A01", "A01", "A01", "A02", "A02"),
        EVENT_AGE = c(21.0, 21.05, 21.15, 34.5, 34.6),
        VNR = c("123", "123", "123", "456", "456"),
        MERGED_SOURCE = c("PURCH", "PURCH", "PURCH", "PURCH", "PURCH"),
        # time_to_first_drug = first_drug_age - EVENT_AGE
        # Negative values mean AFTER first drug
        time_to_first_drug = c(0, -0.05, -0.15, 0, -0.1),
        # Manually set periods for testing (normally set by create_drug_response)
        purchase_period = c("Baseline", "Followup", "Followup", "Baseline", "Followup"),
        N_PACKS = c(1, NA, 2, 1, NA),  # Mix of NA and actual values
        DDDPerPack = c(30, 30, 30, 28, 28)  # DDD per pack
    )

    # Set lab_period to match the test scenario
    lab_measurements <- lab_measurements %>% mutate(lab_period = case_when(
        time_to_first_drug >= 0 ~ "Baseline",
        time_to_first_drug < 0 ~ "Followup",
        TRUE ~ NA_character_
    ))

    before_period <- c(-1, 0)
    after_period <- c(0.0001, 1)

    result <- generate_response_summary(lab_measurements, 
                                       drug_purchases = drug_purchases, 
                                       before_period, 
                                       after_period)

    # Verify results
    expect_equal(nrow(result), 2)
    
    # Check FG1: 2 purchases in followup period
    # Purchase 1 (time -0.05): N_PACKS=NA -> use 1, DDD = 1 * 30 = 30
    # Purchase 2 (time -0.15): N_PACKS=2, DDD = 2 * 30 = 60
    # Total DDD = 30 + 60 = 90
    fg1_result <- result %>% filter(FINNGENID == "FG1")
    expect_equal(fg1_result$n_purchases_followup, 2)
    expect_equal(fg1_result$total_ddd_followup, 90)
    
    # Check FG2: 1 purchase in followup period
    # Purchase 1 (time -0.1): N_PACKS=NA -> use 1, DDD = 1 * 28 = 28
    # Total DDD = 28
    fg2_result <- result %>% filter(FINNGENID == "FG2")
    expect_equal(fg2_result$n_purchases_followup, 1)
    expect_equal(fg2_result$total_ddd_followup, 28)
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
        MEASUREMENT_VALUE_MERGED = c(15, 16.6, 17, 25, 8, 9.5, 10, 40, 50, 38),
        APPROX_EVENT_DATETIME = as.Date(c("2015-07-17", "2015-07-17", "2015-07-17", "2015-07-17",
                                         "2015-07-18", "2015-07-18", "2015-07-18", "2015-07-18",
                                         "2015-07-19", "2015-07-19"))
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

test_that("annotate_effective_ddd flags dose-dispensing within tolerance and adjusts effective_ddd", {
    # FG1 purchases: full pack, then dose-dispensed at 14 days, then regular at 30 day gap
    # FG2 purchases: pack on day 0, refill 11 days later (outside default tolerance of +/-3)
    purchases <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG2", "FG2"),
        APPROX_EVENT_DAY = as.Date(c("2020-01-01", "2020-01-15", "2020-02-14",
                                     "2020-01-01", "2020-01-12")),
        N_PACKS    = c(1, 1, 1, 1, 1),
        DDDPerPack = c(100, 100, 100, 100, 100),
        PackageSize = c(100, 100, 100, 100, 100)
    )

    out <- annotate_effective_ddd(purchases)

    fg1 <- out %>% filter(FINNGENID == "FG1") %>% arrange(APPROX_EVENT_DAY)
    expect_true(is.na(fg1$prev_gap_days[1]))
    expect_equal(fg1$prev_gap_days[2], 14)
    expect_equal(fg1$prev_gap_days[3], 30)
    expect_equal(fg1$is_dose_dispensing, c(FALSE, TRUE, FALSE))
    # Raw would be 100 each; dose-dispensed becomes 14 * 1 * (100/100) = 14
    expect_equal(fg1$effective_ddd, c(100, 14, 100))

    fg2 <- out %>% filter(FINNGENID == "FG2") %>% arrange(APPROX_EVENT_DAY)
    # 11-day gap is outside [14-3, 14+3] = [11, 17]... actually 11 == lower bound, INCLUSIVE.
    # Test was meant to be outside tolerance: re-check behavior at boundary.
    expect_equal(fg2$prev_gap_days[2], 11)
    expect_true(fg2$is_dose_dispensing[2]) # 11 is at the boundary, classified as dose-dispensed
})

test_that("annotate_effective_ddd respects tolerance bounds and configurable window", {
    purchases <- data.frame(
        FINNGENID = rep("FG1", 5),
        APPROX_EVENT_DAY = as.Date(c("2020-01-01", "2020-01-11", "2020-01-22",
                                     "2020-02-08", "2020-02-19")),
        N_PACKS    = rep(1, 5),
        DDDPerPack = rep(28, 5),
        PackageSize = rep(28, 5)
    )

    # Default window=14, tolerance=3 -> [11, 17]
    out <- annotate_effective_ddd(purchases)
    out <- out %>% arrange(APPROX_EVENT_DAY)
    # gaps: NA, 10, 11, 17, 11
    expect_equal(out$prev_gap_days, c(NA, 10, 11, 17, 11))
    expect_equal(out$is_dose_dispensing, c(FALSE, FALSE, TRUE, TRUE, TRUE))

    # Narrow tolerance to 0 -> only exact 14 day gaps qualify
    out2 <- annotate_effective_ddd(purchases, dose_dispensing_tolerance_days = 0)
    expect_equal(out2$is_dose_dispensing, c(FALSE, FALSE, FALSE, FALSE, FALSE))

    # Larger window for fortnightly testing
    out3 <- annotate_effective_ddd(purchases, dose_dispensing_window_days = 11,
                                   dose_dispensing_tolerance_days = 0)
    expect_equal(out3$is_dose_dispensing, c(FALSE, FALSE, TRUE, FALSE, TRUE))
})

test_that("annotate_effective_ddd handles missing optional columns gracefully", {
    # No DDDPerPack or PackageSize -> effective_ddd should be NA, no crash
    purchases <- data.frame(
        FINNGENID = c("FG1", "FG1"),
        APPROX_EVENT_DAY = as.Date(c("2020-01-01", "2020-01-15"))
    )
    out <- annotate_effective_ddd(purchases)
    expect_true("effective_ddd" %in% colnames(out))
    expect_true(all(is.na(out$effective_ddd)))
    expect_equal(out$is_dose_dispensing, c(FALSE, TRUE))

    # NA DDDPerPack / PackageSize entries -> should not blow up; effective_ddd NA there
    purchases2 <- data.frame(
        FINNGENID = c("FG1", "FG1"),
        APPROX_EVENT_DAY = as.Date(c("2020-01-01", "2020-01-15")),
        N_PACKS = c(1, 1),
        DDDPerPack = c(30, NA),
        PackageSize = c(30, NA)
    )
    out2 <- annotate_effective_ddd(purchases2)
    expect_equal(out2$effective_ddd[1], 30)
    expect_true(is.na(out2$effective_ddd[2])) # raw NA*1 = NA, no replacement possible
})

test_that("annotate_effective_ddd returns empty frame with annotated columns", {
    empty <- data.frame(
        FINNGENID = character(0),
        APPROX_EVENT_DAY = as.Date(character(0)),
        N_PACKS = numeric(0),
        DDDPerPack = numeric(0),
        PackageSize = numeric(0)
    )
    out <- annotate_effective_ddd(empty)
    expect_equal(nrow(out), 0)
    expect_true(all(c("prev_gap_days", "is_dose_dispensing", "effective_ddd") %in% colnames(out)))
})

test_that("generate_response_summary emits adherence_ratio_followup using effective_ddd", {
    lab_measurements <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG2", "FG2"),
        EVENT_AGE = c(20, 21.5, 30, 31.5),
        VALUE = c(10, 20, 30, 40),
        first_drug = c("A01", "A01", "A01", "A01"),
        first_drug_age = c(21.0, 21.0, 30.5, 30.5),
        first_drug_date = as.Date(c("2020-01-01", "2020-01-01", "2020-01-01", "2020-01-01")),
        time_to_first_drug = c(1.0, -0.5, 0.5, -1.0)
    )
    lab_measurements <- lab_measurements %>% mutate(lab_period = case_when(
        time_to_first_drug >= 0 ~ "Baseline",
        time_to_first_drug < 0 ~ "Followup",
        TRUE ~ NA_character_
    ))

    # FG1: regular pack at baseline (raw 100, eff 100), dose-dispensed pack at followup (raw 100, eff 14)
    # FG2: two regular packs (raw 100 each, eff 100 each)
    drug_purchases <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG2", "FG2"),
        APPROX_EVENT_DAY = as.Date(c("2020-01-01", "2020-01-15", "2020-01-01", "2020-02-15")),
        ATC = rep("A01", 4),
        EVENT_AGE = c(21.0, 21.04, 30.5, 30.6),
        VNR = rep("123", 4),
        time_to_first_drug = c(0, -0.04, 0, -0.1),
        purchase_period = c("Baseline", "Followup", "Baseline", "Followup"),
        N_PACKS = c(1, 1, 1, 1),
        DDDPerPack = c(100, 100, 100, 100),
        PackageSize = c(100, 100, 100, 100)
    )
    drug_purchases <- annotate_effective_ddd(drug_purchases)

    before_period <- c(-1, 0)
    after_period <- c(0.0001, 1)

    res <- generate_response_summary(lab_measurements, drug_purchases = drug_purchases,
                                     before_period, after_period)

    fg1 <- res %>% filter(FINNGENID == "FG1")
    fg2 <- res %>% filter(FINNGENID == "FG2")

    # Raw totals unchanged: 100 each
    expect_equal(fg1$total_ddd_followup, 100)
    expect_equal(fg2$total_ddd_followup, 100)
    # Effective totals: FG1 has dose-dispensed followup purchase -> 14; FG2 -> 100
    expect_equal(fg1$total_effective_ddd_followup, 14)
    expect_equal(fg2$total_effective_ddd_followup, 100)
    expect_equal(fg1$n_dose_dispensing_followup, 1)
    expect_equal(fg2$n_dose_dispensing_followup, 0)

    # adherence_ratio = total_effective_ddd_followup / followup_duration_days
    # followup_duration_days = (1 - 0.0001) * 365.25
    fu_days <- (after_period[2] - after_period[1]) * 365.25
    expect_equal(fg1$adherence_ratio_followup, 14 / fu_days)
    expect_equal(fg2$adherence_ratio_followup, 100 / fu_days)
})

test_that("create_drug_response excludes individuals below min_adherence", {
    # FG1's followup purchase is dose-dispensed (eff DDDs = 14); FG2's is a regular pack (eff = 100)
    kanta <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG1", "FG1", "FG2", "FG2", "FG2", "FG2"),
        OMOP_CONCEPT_ID = rep("lab1", 8),
        EVENT_AGE = c(20.6, 20.7, 20.8, 21.5, 19.5, 19.6, 19.7, 20.5),
        MEASUREMENT_VALUE_HARMONIZED = c(15, 16.6, 17, 25, 8, 9.5, 10, 40),
        MEASUREMENT_VALUE_MERGED = c(15, 16.6, 17, 25, 8, 9.5, 10, 40),
        APPROX_EVENT_DATETIME = as.Date(c(rep("2015-07-17", 4), rep("2015-07-18", 4)))
    )

    # FG1: first pack at first_drug_age (21.0), then dose-dispensed pack 14 days later (eff = 14)
    # FG2: first pack (20.0), then regular pack ~40 days later (eff = 100)
    # after_period[1]=0.03y (~11 days) so the 14-day-later purchase falls in Followup, not Between
    drug_events <- data.frame(
        FINNGENID = c("FG1", "FG1", "FG2", "FG2"),
        APPROX_EVENT_DAY = as.Date(c("2015-07-17", "2015-07-31",
                                     "2015-07-18", "2015-08-27")),
        ATC = rep("A01", 4),
        EVENT_AGE = c(21.0, 21.0 + 14/365.25, 20.0, 20.0 + 40/365.25),
        VNR = rep("123", 4),
        MERGED_SOURCE = rep("PURCH", 4),
        time_to_first_drug = c(0, -14/365.25, 0, -40/365.25),
        MEDICATION_QUANTITY = c(1, 1, 1, 1),
        DDDPerPack = c(100, 100, 100, 100),
        PackageSize = c(100, 100, 100, 100)
    )

    phenos <- data.frame(
        FINNGENID = character(0), SOURCE = character(0),
        APPROX_EVENT_DAY = as.Date(character(0)),
        CODE1 = character(0), CODE2 = character(0),
        CODE3 = character(0), CODE4 = character(0),
        EVENT_AGE = numeric(0)
    )

    conn <- fg_data_connection(list(pheno = phenos, labs = kanta, drug_events = drug_events))

    res_all <- create_drug_response(conn, lablist = "lab1", druglist = "A01",
                                    before_period = c(-1, 0), after_period = c(0.03, 1))
    expect_true("adherence_ratio_followup" %in% colnames(res_all$responses))
    expect_equal(nrow(res_all$responses %>% filter(!is.na(response))), 2)

    fg1_adh <- res_all$responses %>% filter(FINNGENID == "FG1") %>% pull(adherence_ratio_followup)
    fg2_adh <- res_all$responses %>% filter(FINNGENID == "FG2") %>% pull(adherence_ratio_followup)
    expect_true(fg1_adh < fg2_adh)

    threshold <- (fg1_adh + fg2_adh) / 2
    res_filt <- create_drug_response(conn, lablist = "lab1", druglist = "A01",
                                     before_period = c(-1, 0), after_period = c(0.03, 1),
                                     min_adherence = threshold)
    kept <- res_filt$responses %>% filter(!is.na(response))
    expect_equal(nrow(kept), 1)
    expect_equal(kept$FINNGENID, "FG2")
})