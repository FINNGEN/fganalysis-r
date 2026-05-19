#' @import foreach
#' @import doParallel
#' @importFrom parallel detectCores makeCluster stopCluster
NULL

# Declare global variables to avoid R CMD check notes
utils::globalVariables(c("vnr"))

#' @title Function to compute purchase frequencies for all VNRs in parallel. 
#' @description Calls compute_purchase_frequency for each VNR, check that function for details of computation
#' @param data data.frame of purchases for multiple VNRs as returned by get_drug_purchases
#' @param gap maximum permissible gap between purchases to consider them part of the same treatment interval
#' @param use_pills_per_pack_only logical, whether to use only PackageSize + gap to determine treatment intervals default TRUE
#' @param n_workers number of parallel workers to use, default NULL uses detectCores() - 1
#' @return data.frame of purchase intervals across all VNRs
#' @export
parallel_compute_purchase_frequencies_for_VNRs <- function(data, gap, use_pills_per_pack_only=TRUE, n_workers=NULL){
    num_workers <- if(is.null(n_workers)) detectCores() - 1 else n_workers
    vnrs <- unique(data$VNR)
    cl <- NULL
    intervals <- NULL
    if(num_workers == 1){
        print("Only one worker specified, parallel computation will not be used.")
        `%myinfix%` <- `%do%`
        intervals <- foreach(vnr=vnrs,.combine = rbind, .packages = c("dplyr","foreach"),
            .export=c("compute_purchase_frequency"), .inorder=FALSE) %myinfix% {
            vnr_purch <- data %>% filter(.data$VNR==vnr)
            print(paste("Processing VNR:", vnr, " with ", nrow(vnr_purch), " purchases"))
            freqs <- compute_purchase_frequency(vnr_purch, gap=gap, use_pills_per_pack_only=use_pills_per_pack_only)
            freqs
        }
    } else {
        `%myinfix%` <- `%dopar%`
        print(paste("Starting parallel computation of purchase frequencies... spinning up", num_workers, " workers takes a while..."))
        cl <- makeCluster(num_workers, outfile="")
        registerDoParallel(cl)
        tryCatch({
            intervals <- foreach(vnr=vnrs,.combine = rbind, .packages = c("dplyr","foreach"),
                .export=c("compute_purchase_frequency"), .inorder=FALSE) %myinfix% {
                vnr_purch <- data %>% filter(.data$VNR==vnr)
                print(paste("Processing VNR:", vnr, " with ", nrow(vnr_purch), " purchases"))
                freqs <- compute_purchase_frequency(vnr_purch, gap=gap, use_pills_per_pack_only=use_pills_per_pack_only)
                freqs
            }
        }, finally = {
            if(!is.null(cl)) stopCluster(cl)
        })
    }
    return(intervals)
}


#' @title Function to compute purchase frequency
#' @description For a given set of purchases for a single VNR, compute the intervals between purchases for each individual. Purchases are considered part of the same treatment interval if they are within max(PackageSize, DDDPerPack) * N_PACKS + gap days of each other (or max(PackageSize, DDDPerPack) + gap if use_pills_per_pack_only is FALSE). When N_PACKS column is present, it accounts for multiple packs purchased in a single transaction.
#' @param purchases data.frame of purchases for a single VNR as returned by get_drug_purchases. Should contain N_PACKS column if available (defaults to 1 if missing).
#' if use_pills_per_pack_only Uses PackageSize * N_PACKS + gap, else use max(PackageSize, DDDPerPack) * N_PACKS + gap to determine which adjacent purchases are considered part of the same treatment interval 
#' @param gap maximum permissible gap between purchases
#' @param use_pills_per_pack_only logical, whether to use only PackageSize + gap to determine treatment intervals default TRUE
#' @return data.frame of purchase intervals with total_pills column showing total pills from previous purchase
#' @export
compute_purchase_frequency <- function(purchases, gap=30, use_pills_per_pack_only=TRUE){
    purchases <- purchases %>% arrange(.data$FINNGENID, .data$APPROX_EVENT_DAY)
    
    # Handle N_PACKS column - default to 1 if missing or NA
    if(!"N_PACKS" %in% names(purchases)){
        purchases$N_PACKS <- 1
    } else {
        purchases$N_PACKS[is.na(purchases$N_PACKS)] <- 1
    }
    
    intervals <- list()
    for(i in 2:nrow(purchases) ){ 
        row <- purchases[i,]
        prev_row <- purchases[i-1,]
        
        # Calculate total pills from previous purchase (PackageSize * N_PACKS)
        prev_total_pills <- prev_row$PackageSize * prev_row$N_PACKS
        
        # Calculate allowed gap based on previous purchase's total supply
        if(!use_pills_per_pack_only) {
            allowed_gap <- max(prev_row$PackageSize, prev_row$DDDPerPack, na.rm=TRUE) * prev_row$N_PACKS + gap
        } else {
            allowed_gap <- prev_total_pills + gap
        }
        
        if(row$FINNGENID == prev_row$FINNGENID & row$APPROX_EVENT_DAY - prev_row$APPROX_EVENT_DAY <= allowed_gap){
            intervals[[length(intervals)+1]] <- data.frame(
                VNR=row$VNR, 
                ATC=row$ATC, 
                medicine=row$Substance, 
                FINNGENID=row$FINNGENID, 
                cadence= as.numeric(row$APPROX_EVENT_DAY - prev_row$APPROX_EVENT_DAY),
                total_pills=prev_total_pills
            )
        }
    }
    return(do.call(rbind, intervals))
}