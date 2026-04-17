library(data.table)
ext_anthrop <- fread("/mnt/nfs/R13/finngen_R13_hilmo_avohilmo_extended_1.0.txt.gz")

#3,4,5 are always height, weight, bmi.
ext_anthrop <- ext_anthrop %>% rename( WEIGHT=CODE3, HEIGHT=CODE4, BMI=CODE5, SMOKING=CODE6, 
                AUDIT_FULL=CODE7, SYSTOLIC_BP=CODE8, DIASTOLIC_BP=CODE9)


pdf("dists.pdf")
    ggplot(ext_anthrop, aes(x=WEIGHT)) + geom_histogram()
    ggplot(ext_anthrop, aes(x=HEIGHT)) + geom_histogram()
    ggplot(ext_anthrop, aes(x=BMI)) + geom_histogram()
    ggplot(ext_anthrop, aes(x=SMOKING)) + geom_histogram()
    ggplot(ext_anthrop, aes(x=AUDIT_FULL)) + geom_histogram()
    ggplot(ext_anthrop, aes(x=SYSTOLIC_BP,y=DIASTOLIC_BP)) + geom_point()
dev.off()


## prim out has 392 the wrong way around. 
wrong <- filter(ext_anthrop, SYSTOLIC_BP<DIASTOLIC_BP)

ext_anthrop %>% mutate(SYSTOLIC_BP=if_else(SYSTOLIC_BP<DIASTOLIC_BP, DIASTOLIC_BP, SYSTOLIC_BP),
                       DIASTOLIC_BP=if_else(SYSTOLIC_BP<DIASTOLIC_BP, SYSTOLIC_BP, DIASTOLIC_BP)) -> 
                       ext_anthrop

ext_anthrop %>% filter( !(is.na(WEIGHT) & is.na(HEIGHT) & is.na(BMI) & is.na(SMOKING) & is.na(AUDIT_FULL) &
                         is.na(SYSTOLIC_BP) & is.na(DIASTOLIC_BP) )) -> ext_anthrop

# duplicate rows?

#limit to a single measurement for individual per day.
ext_anthrop$fg_date <- paste(ext_anthrop$FINNGENID,ext_anthrop$APPROX_EVENT_DAY)

dup_events <- filter(ext_anthrop, duplicated(fg_date))

ext_anthrop <- distinct(ext_anthrop, WEIGHT, HEIGHT, BMI, SMOKING, AUDIT_FULL, SYSTOLIC_BP, 
    DIASTOLIC_BP,FINNGENID,APPROX_EVENT_DAY, .keep_all = TRUE)
dup_events <- filter(ext_anthrop, duplicated(fg_date))
## no more dup events

fwrite(ext_anthrop %>% select(FINNGENID,SOURCE,EVENT_AGE,APPROX_EVENT_DAY,WEIGHT,HEIGHT,BMI,
         SMOKING,AUDIT_FULL,SYSTOLIC_BP,DIASTOLIC_BP),
        "/mnt/nfs/R13/finngen_R13_hilmo_avohilmo_extended_1.0_dedup_fixbp.txt.gz", sep="\t", na="NA", quote=F)