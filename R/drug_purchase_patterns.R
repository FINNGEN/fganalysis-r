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
#' @description For a given set of purchases for a single VNR, compute the intervals between purchases for each individual. Purchases are considered part of the same treatment interval if they are within max(PackageSize, DDDPerPack) + gap days of each other.
#' @param purchases data.frame of purchases for a single VNR as returned by get_drug_purchases.
#' if use_pills_per_pack_only Uses max(PackageSize, DDDPerPack) + gap else use packageSize + gap to determine which adjacent purchases are considered part of the same treatment interval
#' @param gap maximum permissible gap between purchases
#' @param use_pills_per_pack_only logical, whether to use only PackageSize + gap to determine treatment intervals default TRUE
#' @return data.frame of purchase intervals
#' @export
compute_purchase_frequency <- function(purchases, gap=30, use_pills_per_pack_only=TRUE){
    purchases <- purchases %>% arrange(.data$FINNGENID, .data$APPROX_EVENT_DAY)
    intervals <- list()
    for(i in 2:nrow(purchases) ){
        row <- purchases[i,]
        allowed_gap <- if(!use_pills_per_pack_only) max(row$PackageSize, row$DDDPerPack,na.rm=TRUE) + gap else row$PackageSize + gap
        if(row$FINNGENID == purchases[i-1,]$FINNGENID & row$APPROX_EVENT_DAY - purchases[i-1,]$APPROX_EVENT_DAY <= allowed_gap){
            intervals[[length(intervals)+1]] <- data.frame(VNR=row$VNR, ATC=row$ATC, medicine=row$Substance, FINNGENID=row$FINNGENID,
            cadence= as.numeric(row$APPROX_EVENT_DAY - purchases[i-1,]$APPROX_EVENT_DAY))
        }
    }
    return(do.call(rbind, intervals))
}