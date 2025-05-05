#' @import dplyr
#' @import ggplot2
#' @import ggpubr
#' @import stringr
#NULL

#' @title data object returned from drug response analyse (create_drug_response)
#' @param responses data frame with response data
#' @param lab_measurements data frame with all lab measurements
#' @param drug_purchases data frame with all drug purchases
#' @param before_period vector with two elements, start and end of the before period
#' @param after_period vector with two elements, start and end of the after period
#' @return object of class drug.response
#' @export 
drug.response <- function(responses, lab_measurements, drug_purchases, before_period, after_period) {
  obj <- list(responses=responses, all_measurements=lab_measurements, all_drug_purchases=drug_purchases,
              lab_response_period=list(before_period=before_period, after_period=after_period))
  class(obj) <- "drug.reponse"
  return(obj)
}

#' @title Create drug response object
#' @param kanta data frame with lab measurements
#' @param phenos data frame with drug purchases
#' @param lablist vector of lab measurement concept IDs
#' @param druglist vector of drug ATC codes. The ATC codes are matched with the first part of the code (e.g. A01*). 
#' @param before_period vector with two elements, start and end of the before period
#' @param after_period vector with two elements, start and end of the after period
#' @param finngen_ids vector of FINNGENIDs to filter the data
#' @return drug.response object
#' @export
create_drug_response <- function(kanta, phenos, lablist, druglist, before_period, after_period, finngen_ids=NULL) {
  print("Querying lab measurements...")
  lab_measurements <- get_lab_measurements(all_labs=kanta, lablist=lablist, finngen_ids=finngen_ids, require_values = TRUE)
  
  all_fg_ids <- unique(c(lab_measurements$FINNGENID, finngen_ids))
  print("Querying purchases...")
  drug_purchases <- get_drug_purchases(phenos, druglist, all_fg_ids)
  
  dr_first_purchase <- drug_purchases %>% group_by(FINNGENID) %>% arrange(EVENT_AGE) %>%
    summarize(n = n(), first_drug_age = first(EVENT_AGE), first_drug=first(ATC))
  
  lab_measurements <- left_join(lab_measurements, dr_first_purchase, by = "FINNGENID")
  lab_measurements <- lab_measurements %>% mutate(time_to_drug = first_drug_age - EVENT_AGE)
  
  print("generating response summary...")
  lab_response <- generate_response_summary(lab_measurements, before_period, after_period)
  cat("Number of individuals with response data: ", nrow(lab_response), "\n")
  
  return(drug.response(responses=lab_response, lab_measurements=lab_measurements,
                              drug_purchases=drug_purchases, before_period, after_period))
}

quant_text <- function(vector) {
  paste0( paste(names(quantile(vector)), sep="\t"), ":", paste(quantile(vector),sep="\t"), collapse=" ")
}


#' @title Summarize drug response 
#' @description Summarize drug response data created with create_drug_response. writes plots and tables to disk
#' @param drug_response drug.response object
#' @param out_file_prefix prefix for output files
#' @return NULL
#' @export
summarize_drug_response <- function(drug_response, out_file_prefix) {

  labs <- drug_response$all_measurements %>% filter(!is.na(MEASUREMENT_VALUE_HARMONIZED))
  responses <- drug_response$responses
  drugs <- drug_response$all_drug_purchases
                         
  pdf(paste0(out_file_prefix, ".pdf"), width=10, height=6)
  
  inds_with_lab <- length(unique(labs$FINNGENID))
  n_lab_meas <- nrow(labs)
  
  inds_with_drugs <- length(unique(drugs$FINNGENID))
  n_drugs_meas <- nrow(drugs)
  
  inds_in_analysis <- nrow(responses)  
  n_range_before <- quant_text(responses$n_before)
  n_range_after <- quant_text(responses$n_before)

  range_baseline_age <- quant_text(responses$n_before)

  plot(ggtexttable(data.frame("Group"=c("labs","drugs","in analysis"),
                         "N"= c(inds_with_lab, inds_with_drugs, inds_in_analysis),
                         "N events" = c(n_lab_meas, n_drugs_meas, inds_in_analysis)), rows=NULL))
  

  per_drug <- responses %>% group_by(first_drug) %>% 
    summarise(N=n(),p=summary(lm("response ~ 1", data=pick(FINNGENID,response)))$coefficients[1,4],sd=sd(response),
    response=mean(response),
    purch_age_dist=quant_text(baseline_age)) 

  all_resp <- rbind(per_drug, data.frame(first_drug="All drugs", N=inds_in_analysis, 
            response=mean(responses$response), p=summary(lm("response ~ 1", data=responses))$coefficients[1,4],
            purch_age_dist=quant_text(responses$baseline_age), sd=sd(responses$response)))

  write.table(all_resp %>% arrange(desc(N)) %>% 
    select(first_drug, N, response, p, purch_age_dist),
    paste0(out_file_prefix, "_responses_by_drug.txt"), sep="\t", row.names=FALSE, quote=FALSE)


  plot(ggtexttable(responses %>% group_by(first_drug) %>% 
    summarise(n_purch=n(), n_indiv=length(unique(FINNGENID)), 
     p=summary(lm("response ~ 1", data=pick(FINNGENID,response)))$coefficients[1,4],
     response=mean(response),
     purch_age_dist=quant_text(baseline_age)) %>%
     select(first_drug, n_purch, response, p, purch_age_dist) %>%
    arrange(desc(n_purch))))
  

  begin <- ceiling(max(min(-labs$time_to_drug, na.rm = TRUE), drug_response$lab_response_period$before_period[1]))
  end <- ceiling(min(max(-labs$time_to_drug, na.rm = TRUE), drug_response$lab_response_period$after_period[2]))  
  labs$bin <- cut(-labs$time_to_drug, 
                  breaks=seq(begin, end, by=.25), 
                  include.lowest = TRUE)
  
  plot(ggplot(labs %>% filter(!is.na(bin))) + geom_boxplot(aes(x=bin, y=MEASUREMENT_VALUE_HARMONIZED)) +
      labs(x="Time to drug purchase (years)", y="Lab measurement") + 
      ggtitle("Lab measurements before and after drug purchase")) +  theme_bw() +
      theme(axis.text.x = element_text(angle = 45, size=20)) +
  

  write.table(labs %>% group_by(bin) %>% 
    summarise(n=n(), mean=mean(MEASUREMENT_VALUE_HARMONIZED), sd=sd(MEASUREMENT_VALUE_HARMONIZED)),
    paste0(out_file_prefix, "_labs_by_time_to_drug.txt"), sep="\t", row.names=FALSE, quote=FALSE)
     

  plot(ggplot(responses) + geom_histogram(aes(x=response)) + theme_bw() +
      labs(x="Response (after - before)", y="Count") + 
      ggtitle("Distribution of drug response"))
    
  fit <- summary(lm(after ~ before, data=responses))
  
  slope <- format(fit$coefficients["before","Estimate"], digits=2)
  r2 <- format(fit$r.squared, digits=2)
  p <- format(fit$coefficients["before","Pr(>|t|)"], digits=2, scientific=TRUE)
  
  suppressWarnings(print(ggplot(responses, aes(x=before, y=after)) + geom_point() + geom_smooth(method="lm") +
      geom_abline(slope=1) + 
      ggtitle(paste0("Before vs. after values. Slope: ", slope, " R2: ", r2, " p: ", p))))
  
  dev.off()

  print(paste0("Created summary plots and tables with prefix: ", out_file_prefix))
  
}


#' @title Generate response summary
#' @param lab_measurements data frame with lab measurements
#' @param before_period vector with two elements, start and end of the before period
#' @param after_period vector with two elements, start and end of the after period
#' @param summary_function function to summarize the lab measurements (default is median)
#' @return data frame with response summary
#' @export
generate_response_summary <- function(lab_measurements, before_period, after_period, summary_function=median) {
  lab_measurements <- lab_measurements %>% mutate(lab_period = case_when(
    between(time_to_drug, after_period[1], after_period[2]) ~ 'Before',
    between(time_to_drug, before_period[1], before_period[2]) ~ 'After',
    TRUE ~ NA_character_
  ))
  
  lab_response <- lab_measurements %>% filter(!is.na(lab_period) & !is.na(MEASUREMENT_VALUE_HARMONIZED)) %>%
    group_by(FINNGENID) %>%
    summarize(before = summary_function(MEASUREMENT_VALUE_HARMONIZED[lab_period=='Before'], na.rm=TRUE),
              after = summary_function(MEASUREMENT_VALUE_HARMONIZED[lab_period=='After'], na.rm=TRUE),
              n_before = length(MEASUREMENT_VALUE_HARMONIZED[lab_period=='Before']),
              n_after = length(MEASUREMENT_VALUE_HARMONIZED[lab_period=='After']),
              baseline_age = first(first_drug_age),
              first_drug = first(first_drug),
              response = after - before) %>% filter(!is.na(response))
  
  return(lab_response)
}

#' @title Get lab measurements from FinnGen data
#' @param all_labs data frame with lab measurements
#' @param lablist vector of lab measurement concept IDs
#' @param require_values logical, if TRUE, only return rows with non-missing MEASUREMENT_VALUE_HARMONIZED
#' @param return_cols vector of column names to return
#' @param finngen_ids vector of FINNGENIDs to filter the data
#' @param lazy logical, if TRUE, return a lazy tbl object
#' @return data frame with lab measurements
#' @export
get_lab_measurements <- function(all_labs, lablist, require_values=TRUE, return_cols=c("FINNGENID","OMOP_CONCEPT_ID", "EVENT_AGE", "MEASUREMENT_VALUE_HARMONIZED"),
                                 finngen_ids=NULL, lazy=FALSE) {
  
  return_cols <- unique(c("OMOP_CONCEPT_ID", return_cols))
  
  labs <- all_labs %>% select(all_of(return_cols)) %>% filter(OMOP_CONCEPT_ID %in% lablist)
  
  if (!is.null(finngen_ids)) {
    labs <- labs %>% filter(FINNGENID %in% finngen_ids)
  }
  if (require_values) {
    labs <- labs %>% filter(!is.na(MEASUREMENT_VALUE_HARMONIZED))
  }
  
  ifelse(lazy, return(labs), return(dplyr::collect(labs)))
}


#' @title Get drug purchases from FinnGen data
#' @param all_phenos data frame with drug purchases
#' @param druglist vector of drug ATC codes. The ATC codes are matched with the first part of the code (e.g. A01*)
#' @param finngen_ids vector of FINNGENIDs to filter the data. leave empty to get all
#' @param return_cols vector of column names to return
#' @param lazy logical, if TRUE, return a lazy tbl object
#' @return data frame with drug purchases
#' @export
get_drug_purchases <- function(all_phenos, druglist, finngen_ids=NULL, 
                               return_cols=c("FINNGENID","EVENT_AGE", ATC="CODE1", REIMB_CODE="CODE2", VNR="CODE3", N_PACKS="CODE4"),
                               lazy=FALSE) {
  
  drugs_regex <- druglist %>% 
    stringr::str_c(collapse = '|') %>% 
    stringr::str_c('^(', ., ')')
  
  drugs <- all_phenos %>% filter(SOURCE=="PURCH" & str_detect(CODE1, drugs_regex)) %>% select(all_of(return_cols))
  
  if (!is.null(finngen_ids)) {
    drugs <- drugs %>% filter(FINNGENID %in% finngen_ids)
  }
  
  ifelse(lazy, return(drugs), return(dplyr::collect(drugs)))
}


#' @title Get first drug purchase from FinnGen data
#' @param all_phenos data frame with drug purchases
#' @param druglist vector of drug ATC codes. The ATC codes are matched with the first part of the code (e.g. A01*)
#' @param finngen_ids vector of FINNGENIDs to filter the data. leave empty to get all
#' @param return_cols vector of column names to return
#' @param lazy logical, if TRUE, return a lazy tbl object
#' @return data frame with first drug purchases for each FINNGENID
#' @export
get_first_purchase <- function(all_phenos, druglist, finngen_ids=NULL, return_cols=c("FINNGENID","EVENT_AGE","CODE1"),
                               lazy=FALSE) {
  
  first_purch <- get_drug_purchases(all_phenos, druglist, finngen_ids, return_cols, lazy=TRUE) %>% 
    group_by(FINNGENID) %>%
    filter(EVENT_AGE == min(EVENT_AGE)) %>% distinct(EVENT_AGE, .keep_all = TRUE) %>%
    ungroup() %>% 
    select(all_of(return_cols))
}