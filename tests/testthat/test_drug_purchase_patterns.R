# Test cases for parallel_compute_purchase_frequencies_for_VNRs and compute_purchase_frequency
library(testthat)
library(dplyr)

# Dummy data for testing with Date columns
set.seed(123)
base_date <- as.Date("2020-01-01")
test_data <- data.frame(
  VNR = rep(c("A", "B"), each = 5),
  FINNGENID = rep(c("ID1", "ID2"), times = 5),
  APPROX_EVENT_DAY = c(
    base_date,
    base_date + 5,
    base_date + 10,
    base_date + 25,   # within gap
    base_date + 40,   # outside gap
    base_date + 1,
    base_date + 6,
    base_date + 11,
    base_date + 26,   # within gap
    base_date + 41    # outside gap
  ),
  PackageSize = rep(10, 10),
  DDDPerPack = rep(10, 10),
  Substance = rep("TestDrug", 10),
  ATC = rep("C10AA01", 10)
)

# Test compute_purchase_frequency

test_that("compute_purchase_frequency returns correct intervals with Date column", {
  res <- compute_purchase_frequency(test_data %>% filter(VNR == "A"), gap = 15)
  expect_true(is.data.frame(res))
  expect_true(all(res$VNR == "A"))
  expect_true(all(res$cadence >= 0))
  # Only adjacent purchases within PackageSize + gap (10 + 15 = 25 days) are returned
  res_id2 <- compute_purchase_frequency(test_data %>% filter(VNR == "A", FINNGENID == "ID2"), gap = 15)
  expect_equal(res_id2$cadence, c(20))
  # Purchases at day 0, 5, 10, 25, 40 (for ID1) should yield intervals of 5, 5
  res_id1 <- compute_purchase_frequency(test_data %>% filter(VNR == "A", FINNGENID == "ID1"), gap = 15)
  expect_equal(res_id1$cadence, c(10))
})

# Test parallel_compute_purchase_frequencies_for_VNRs

test_that("parallel_compute_purchase_frequencies_for_VNRs returns intervals for all VNRs with Date column", {
  res <- parallel_compute_purchase_frequencies_for_VNRs(test_data, gap = 15, n_workers = 1)
  expect_true(is.data.frame(res))
  expect_true(all(res$VNR %in% c("A", "B")))
  expect_true(all(res$cadence >= 0))
  # Only adjacent purchases within PackageSize + gap (10 + 15 = 25 days) are returned for both VNRs
  res_a <- res %>% filter(VNR == "A", FINNGENID == "ID2")
  expect_equal(res_a$cadence, c(20))
  res_b <- res %>% filter(VNR == "B", FINNGENID == "ID2")
  expect_equal(res_b$cadence, c(10))
})

test_that("parallel_compute_purchase_frequencies_for_VNRs works with multiple workers and Date column", {
  res <- parallel_compute_purchase_frequencies_for_VNRs(test_data, gap = 15, n_workers = 2)
  expect_true(is.data.frame(res))
  expect_true(all(res$VNR %in% c("A", "B")))
  res_a <- res %>% filter(VNR == "A", FINNGENID == "ID2")
  expect_equal(res_a$cadence, c(20))
})

# Test N_PACKS handling

test_that("N_PACKS should be accounted for in total pill calculations", {
  test_data_with_npacks <- data.frame(
    VNR = c("C", "C", "C"),
    FINNGENID = c("ID3", "ID3", "ID3"),
    APPROX_EVENT_DAY = c(
      as.Date("2020-01-01"),
      as.Date("2020-01-15"),
      as.Date("2020-01-30")
    ),
    PackageSize = c(30, 30, 30),
    N_PACKS = c(2, 1, 3),  # Multiple packs purchased
    DDDPerPack = c(30, 30, 30),
    Substance = c("TestDrug", "TestDrug", "TestDrug"),
    ATC = c("C10AA01", "C10AA01", "C10AA01")
  )
  
  # With gap=0, only purchases within PackageSize * N_PACKS days are included
  res <- compute_purchase_frequency(test_data_with_npacks, gap = 0, use_pills_per_pack_only = TRUE)
  
  expect_true(is.data.frame(res))
  expect_equal(nrow(res), 2)  # Two intervals expected
  
  # First interval: Day 15 purchase is within 60 days (30 pills * 2 packs) of Day 1
  expect_equal(res$cadence[1], 14)  # 15 - 1 = 14 days
  expect_equal(res$total_pills[1], 60)  # 30 pills * 2 packs
  
  # Second interval: Day 30 purchase is within 30 days (30 pills * 1 pack) of Day 15
  expect_equal(res$cadence[2], 15)  # 30 - 15 = 15 days
  expect_equal(res$total_pills[2], 30)  # 30 pills * 1 pack
})

test_that("compute_purchase_frequency handles missing N_PACKS column", {
  # Test data without N_PACKS column
  test_data_no_npacks <- data.frame(
    VNR = c("D", "D"),
    FINNGENID = c("ID4", "ID4"),
    APPROX_EVENT_DAY = c(
      as.Date("2020-01-01"),
      as.Date("2020-01-20")
    ),
    PackageSize = c(30, 30),
    DDDPerPack = c(30, 30),
    Substance = c("TestDrug", "TestDrug"),
    ATC = c("C10AA01", "C10AA01")
  )
  
  # Should default to N_PACKS = 1
  res <- compute_purchase_frequency(test_data_no_npacks, gap = 0)
  
  expect_true(is.data.frame(res))
  expect_equal(nrow(res), 1)
  expect_equal(res$total_pills[1], 30)  # 30 pills * 1 (default)
})

test_that("compute_purchase_frequency handles NA values in N_PACKS", {
  test_data_na_npacks <- data.frame(
    VNR = c("E", "E", "E"),
    FINNGENID = c("ID5", "ID5", "ID5"),
    APPROX_EVENT_DAY = c(
      as.Date("2020-01-01"),
      as.Date("2020-01-15"),
      as.Date("2020-01-30")
    ),
    PackageSize = c(30, 30, 30),
    N_PACKS = c(2, NA, 1),  # NA should be treated as 1
    DDDPerPack = c(30, 30, 30),
    Substance = c("TestDrug", "TestDrug", "TestDrug"),
    ATC = c("C10AA01", "C10AA01", "C10AA01")
  )
  
  res <- compute_purchase_frequency(test_data_na_npacks, gap = 0)
  
  expect_true(is.data.frame(res))
  # First interval uses 2 packs (60 pills), second uses NA->1 pack (30 pills)
  expect_equal(res$total_pills[1], 60)  # 30 pills * 2 packs
  expect_equal(res$total_pills[2], 30)  # 30 pills * 1 (NA converted to 1)
})

test_that("N_PACKS affects treatment interval calculation correctly", {
  # Test that larger N_PACKS allows longer gaps to be considered same interval
  test_data_intervals <- data.frame(
    VNR = c("F", "F", "F"),
    FINNGENID = c("ID6", "ID6", "ID6"),
    APPROX_EVENT_DAY = c(
      as.Date("2020-01-01"),
      as.Date("2020-02-20"),  # 50 days later
      as.Date("2020-03-10")   # 18 days after second
    ),
    PackageSize = c(30, 30, 30),
    N_PACKS = c(2, 1, 1),
    DDDPerPack = c(30, 30, 30),
    Substance = c("TestDrug", "TestDrug", "TestDrug"),
    ATC = c("C10AA01", "C10AA01", "C10AA01")
  )
  
  # With gap=0 and N_PACKS=2 on first purchase (60 pills total)
  # Second purchase at day 50 should be included (within 60 days)
  # Third purchase at day 68 should NOT be included (beyond 30 pills from second purchase)
  res <- compute_purchase_frequency(test_data_intervals, gap = 0)
  
  expect_equal(nrow(res), 2)  # Two intervals
  expect_equal(res$cadence[1], 50)  # First interval: 50 days
  expect_equal(res$total_pills[1], 60)  # From 2 packs
  expect_equal(res$cadence[2], 18)  # Second interval: 18 days
  expect_equal(res$total_pills[2], 30)  # From 1 pack
})
