#' @import ggplot2
#' @import ggpubr
#' @import grDevices
#' @import UpSetR
#' @import utils
#' @import tidyr
#' @importFrom stats lm quantile sd
NULL

#' Helper function to create quantile text
#' @param vector numeric vector
#' @return character string with quantile information
#' @noRd
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
    labs <- drug_response$all_measurements %>% filter(!is.na(.data$VALUE))
    responses <- drug_response$responses %>% filter(!is.na(.data$response))
    drugs <- drug_response$all_drug_purchases

    pdf(paste0(out_file_prefix, ".pdf"), width = 10, height = 6)

    inds_with_lab <- length(unique(labs$FINNGENID))
    n_lab_meas <- nrow(labs)

    inds_with_drugs <- length(unique(drugs$FINNGENID))
    n_drugs_meas <- nrow(drugs)

    inds_in_analysis <- nrow(responses )

    n_range_before <- quant_text(responses$n_before)
    n_range_after <- quant_text(responses$n_before)

    range_baseline_age <- quant_text(responses$n_before)

    n_no_pre <- drug_response$responses %>% filter(is.na(.data$response) & .data$n_before == 0)
    n_no_pos <- drug_response$responses %>% filter(is.na(.data$response) & .data$n_after == 0)

    plot(ggtexttable(data.frame(
        "Group" = c("labs", "drugs", "in analysis", "no_pre_value", "no_post_value"),
        "N" = c(inds_with_lab, inds_with_drugs, inds_in_analysis, nrow(n_no_pre), nrow(n_no_pos)),
        "N events" = c(n_lab_meas, n_drugs_meas, inds_in_analysis, sum(n_no_pre$n_after), sum(n_no_pos$n_before))
    ), rows = NULL))


    per_drug <- responses %>%
        group_by(.data$first_drug) %>%
        summarise(
            N = n(), p = summary(lm("response ~ 1", data = pick(.data$FINNGENID, .data$response)))$coefficients[1, 4], sd = sd(.data$response),
            response = mean(.data$response),
            purch_age_dist = quant_text(.data$baseline_age)
        )

    all_resp <- rbind(per_drug, data.frame(
        first_drug = "All drugs", N = inds_in_analysis,
        response = mean(responses$response), p = summary(lm("response ~ 1", data = responses))$coefficients[1, 4],
        purch_age_dist = quant_text(responses$baseline_age), sd = sd(responses$response)
    ))

    write.table(
        all_resp %>% arrange(desc(.data$N)) %>%
            select(.data$first_drug, .data$N, .data$response, .data$p, .data$purch_age_dist),
        paste0(out_file_prefix, "_responses_by_drug.txt"),
        sep = "\t", row.names = FALSE, quote = FALSE
    )


    plot(ggtexttable(responses %>% group_by(.data$first_drug) %>%
        summarise(
            n_purch = n(), n_indiv = length(unique(.data$FINNGENID)),
            p = summary(lm("response ~ 1", data = pick(.data$FINNGENID, .data$response)))$coefficients[1, 4],
            response = mean(.data$response),
            purch_age_dist = quant_text(.data$baseline_age)
        ) %>%
        select(.data$first_drug, .data$n_purch, .data$response, .data$p, .data$purch_age_dist) %>%
        arrange(desc(.data$n_purch))))


    begin <- ceiling(max(min(-labs$time_to_drug, na.rm = TRUE), drug_response$lab_response_period$before_period[1]))
    end <- ceiling(min(max(-labs$time_to_drug, na.rm = TRUE), drug_response$lab_response_period$after_period[2]))
    labs$bin <- cut(-labs$time_to_drug,
        breaks = seq(begin, end, by = .25),
        include.lowest = TRUE
    )

    plot(ggplot(labs %>% filter(!is.na(.data$bin))) +
        geom_boxplot(aes(x = .data$bin, y = .data$VALUE)) +
        labs(x = "Time to drug purchase (years)", y = "Lab measurement") +
        ggtitle("Lab measurements before and after drug purchase")) + theme_bw() +
        theme(axis.text.x = element_text(angle = 45, size = 20)) 


    uniq_drugs <- unique(responses$first_drug)

    for( drug in uniq_drugs){
        labs_sub <- labs %>% filter(!is.na(.data$bin))  
        p <- ggplot(labs_sub)  + geom_boxplot(aes(x = .data$bin, y = .data$VALUE)) +
        labs(x = "Time to drug purchase (years)", y = "Lab measurement") +
        ggtitle(paste("Lab measurements before and after drug purchase for drug ", drug)) + theme_bw() +
        theme(axis.text.x = element_text(size = 10))
        plot(p)
    }

    write.table(
        labs %>% group_by(.data$bin) %>%
            summarise(n = n(), mean = mean(.data$VALUE), sd = sd(.data$VALUE)),
        paste0(out_file_prefix, "_labs_by_time_to_drug.txt"),
        sep = "\t", row.names = FALSE, quote = FALSE
    )


    plot(ggplot(responses) +
        geom_histogram(aes(x = .data$response)) +
        theme_bw() +
        labs(x = "Response (after - before)", y = "Count") +
        ggtitle("Distribution of drug response"))

    
    plot(ggplot(responses) +
        geom_histogram(aes(x = .data$response_percent)) +
        theme_bw() +
        labs(x = "Response%", y = "Count") +
        ggtitle("Distribution of % drug response"))
    
    for( drug in uniq_drugs){
        labs_sub <- responses %>% filter( .data$first_drug == drug)
        p <- ggplot(labs_sub) +
        geom_histogram(aes(x = .data$response)) +
        theme_bw() +
        labs(x = "Response (after - before)", y = "Count") +
        ggtitle( paste0("Distribution of drug response for drug ", drug))   
        plot(p)

        p <- ggplot(labs_sub) +
        geom_histogram(aes(x = .data$response_percent)) +
        theme_bw() +
        labs(x = "Response%", y = "Count") +
        ggtitle(paste0("Distribution of % drug response for drug ", drug))
        plot(p)

    }



    fit <- summary(lm(after ~ before, data = responses))

    slope <- format(fit$coefficients["before", "Estimate"], digits = 2)
    r2 <- format(fit$r.squared, digits = 2)
    p <- format(fit$coefficients["before", "Pr(>|t|)"], digits = 2, scientific = TRUE)

    suppressWarnings(print(ggplot(responses, aes(x = .data$before, y = .data$after)) +
        geom_point() +
        geom_smooth(method = "lm") +
        geom_abline(slope = 1) +
        ggtitle(paste0("Before vs. after values. Slope: ", slope, " R2: ", r2, " p: ", p))))

    dev.off()

    print(paste0("Created summary plots and tables with prefix: ", out_file_prefix))
}


#' @title Plot Distribution of Lab Values Before and After Drug Use
#' @description Creates a violin plot comparing the distribution of lab values
#' before and after the first drug purchase, faceted by drug type.
#' The plot uses consistent ordering with "Before" always on the left (teal)
#' and "After" always on the right (gold).
#' @param drug_response A `drug.response` object.
#' @param remove_outliers A logical indicating whether to remove outliers
#' using the 1.5 * IQR rule. Defaults to `FALSE`.
#' @return A `ggplot` object with consistent ordering and ggpubr color palette.
#' @export
plot_lab_value_distribution <- function(drug_response, remove_outliers = FALSE) {
  if (!inherits(drug_response, "drug.response")) {
    stop("Input must be a drug.response object.")
  }

  # Define periods from the response object for consistency
  before_period_def <- drug_response$lab_response_period$before_period
  after_period_def <- drug_response$lab_response_period$after_period

  # IMPORTANT: time_to_drug = first_drug_age - EVENT_AGE
  # So: positive time_to_drug = BEFORE drug; negative time_to_drug = AFTER drug
  # But the period parameters use the opposite convention:
  # before_period uses negative values (e.g., c(-1, 0))
  # after_period uses positive values (e.g., c(0.1, 1))
  # We need to flip the signs when matching
  lab_data_periods <- drug_response$all_measurements %>%
    filter(!is.na(.data$first_drug_age) & !is.na(.data$VALUE)) %>%
    mutate(period = case_when(
      between(.data$time_to_drug, -before_period_def[2], -before_period_def[1]) ~ "Before",
      between(.data$time_to_drug, -after_period_def[2], -after_period_def[1]) ~ "After",
      TRUE ~ NA_character_
    )) %>%
    filter(!is.na(.data$period))

  plot_data <- lab_data_periods
  if (remove_outliers) {
    plot_data <- plot_data %>%
      group_by(.data$first_drug, .data$period) %>%
      mutate(
        Q1 = quantile(.data$VALUE, 0.25, na.rm = TRUE),
        Q3 = quantile(.data$VALUE, 0.75, na.rm = TRUE),
        IQR = .data$Q3 - .data$Q1
      ) %>%
      filter(
        .data$VALUE >= (.data$Q1 - 1.5 * .data$IQR) &
        .data$VALUE <= (.data$Q3 + 1.5 * .data$IQR)
      ) %>%
      ungroup()
  }

  # Ensure consistent ordering: Before on left, After on right
  plot_data <- plot_data %>%
    mutate(period = factor(.data$period, levels = c("Before", "After")))

  # Generate violin plot with ggpubr
  p <- ggpubr::ggviolin(plot_data,
                        x = "period", y = "VALUE",
                        fill = "period",
                        palette = c("#00AFBB", "#E7B800"),
                        add = "boxplot",
                        add.params = list(fill = "white")) +
    ggpubr::stat_compare_means(method = "t.test",
                               label = "p.signif",
                               label.x = 1.5) +
    ggpubr::stat_compare_means(method = "t.test",
                               label.y.npc = 0.9) +
    labs(
      title = "Distribution of Lab Values Before and After First Drug Purchase",
      x = "Period Relative to Drug Purchase",
      y = "Harmonised Measurement Value"
    ) +
    theme_minimal() +
    facet_wrap(~.data$first_drug, scales = "free_y") +
    theme(legend.position = "bottom")

  return(p)
}


#' @title Generate an UpSet plot of drug purchase combinations
#' @description Creates and saves an UpSet plot to visualize the overlap of purchased drug ATC codes.
#' @param drug_response A `drug.response` object created by `create_drug_response`.
#' @param out_file_prefix A string to use as the prefix for the output PDF file.
#' @return NULL
#' @export
summarize_drug_purchases_upset <- function(drug_response, out_file_prefix) {
  if (!inherits(drug_response, "drug.response")) {
    stop("Input must be a drug.response object.")
  }

  upset_data <- drug_response$all_drug_purchases %>%
    select("FINNGENID", "ATC") %>%
    distinct() %>%
    mutate(value = 1) %>%
    tidyr::pivot_wider(names_from = "ATC", values_from = "value", values_fill = 0) %>%
    select(-"FINNGENID") %>%
    as.data.frame()
  if(ncol(upset_data)<2){
    stop("Drug response must contain at least 2 drugs to create UpSet plots.")
  }
  pdf(paste0(out_file_prefix, "_upset_plot.pdf"), width = 10, height = 7)

  UpSetR::upset(upset_data,
        nsets = ncol(upset_data),
        nintersects = 20,
        mb.ratio = c(0.6, 0.4),
        order.by = "freq",
        decreasing = TRUE,
        text.scale = 1.2,
        mainbar.y.label = "Number of FINNGEN IDs",
        sets.x.label = "Patients per Drug Subtype",
        set_size.show = TRUE)

  dev.off()

  print(paste0("UpSet plot saved to ", out_file_prefix, "_upset_plot.pdf"))
}