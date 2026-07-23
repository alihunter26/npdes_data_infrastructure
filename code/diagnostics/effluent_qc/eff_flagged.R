# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# eff_flagged.R
# --------------------------------------------------------------------------
# Reads a state's effluent-violation CSV and writes out only the SUSPICIOUS
# rows, so they are easy to review by hand.
#
# A row is flagged if ANY of these are true:
#   1. DMR_VALUE_NMBR            is negative
#   2. DMR_VALUE_STANDARD_UNITS  is negative
#   3. the monitoring year is before 1984
#   4. any number above 1,000,000 appears in a value column
#
# Each flagged row gets a FLAG_REASON column saying which check(s) it tripped.
# --------------------------------------------------------------------------

library(data.table)

# ---- Option: pick the state -------------------------------------------------
# Change STATE here, OR pass it on the command line:
#     Rscript eff_flagged.R va
STATE <- "va"
args  <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 1) STATE <- args[1]
STATE <- tolower(STATE)

out_dir <- file.path(CWA_ROOT, "output")

# ---- Find the newest effluent-violation file for that state -----------------
pattern <- sprintf("^eff_violations_%s_.*\\.csv$", STATE)
files   <- list.files(out_dir, pattern = pattern, full.names = TRUE)
if (length(files) == 0)
  stop("No effluent-violation CSV found for state '", STATE, "' in ", out_dir)
in_file <- files[which.max(file.mtime(files))]   # most recent one
cat("Reading:", basename(in_file), "\n")

dat <- fread(in_file, colClasses = "character")   # read everything as text first

# ---- Small helper: turn a text column into numbers (blanks/letters -> NA) ---
to_number <- function(x) suppressWarnings(as.numeric(x))

# ---- Check 1 & 2: negative DMR values ---------------------------------------
is_neg_dmr <- to_number(dat$DMR_VALUE_NMBR) < 0
is_neg_std <- to_number(dat$DMR_VALUE_STANDARD_UNITS) < 0

# ---- Check 3: any of these dates has a year before 1984 ---------------------
date_cols <- c("MONITORING_PERIOD_END_DATE", "VALUE_RECEIVED_DATE",
               "RNC_DETECTION_DATE", "RNC_RESOLUTION_DATE")
is_old    <- rep(FALSE, nrow(dat))
old_where <- rep("", nrow(dat))                  # remember which date column was too old
for (col in date_cols) {
  year <- as.integer(format(as.Date(dat[[col]], "%m/%d/%Y"), "%Y"))
  hit  <- !is.na(year) & year < 1984
  is_old <- is_old | hit
  old_where[hit] <- paste0(old_where[hit], col, " ")
}

# ---- Check 4: any value over 1,000,000 in a value column --------------------
# Skip ID columns: they are huge ID numbers, not measurements, so they would
# flag every single row. (Edit this list if you want to include/exclude more.)
id_cols <- c("ACTIVITY_ID", "NPDES_VIOLATION_ID", "PERMIT_ACTIVITY_ID",
             "DMR_FORM_VALUE_ID", "DMR_VALUE_ID", "DMR_PARAMETER_ID", "LIMIT_ID")

is_too_big <- rep(FALSE, nrow(dat))
big_where  <- rep("", nrow(dat))                 # remember which column was too big
for (col in setdiff(names(dat), id_cols)) {
  vals <- to_number(dat[[col]])
  hit  <- !is.na(vals) & vals > 1000000
  is_too_big <- is_too_big | hit
  big_where[hit] <- paste0(big_where[hit], col, " ")
}

# ---- Treat NA flags as FALSE (a blank value is not a violation) --------------
is_neg_dmr[is.na(is_neg_dmr)] <- FALSE
is_neg_std[is.na(is_neg_std)] <- FALSE

# ---- Build a plain-English reason for each row ------------------------------
reason <- rep("", nrow(dat))
reason[is_neg_dmr] <- paste0(reason[is_neg_dmr], "negative DMR_VALUE_NMBR; ")
reason[is_neg_std] <- paste0(reason[is_neg_std], "negative DMR_VALUE_STANDARD_UNITS; ")
reason[is_old]     <- paste0(reason[is_old],     "year before 1984 (", trimws(old_where[is_old]), "); ")
reason[is_too_big] <- paste0(reason[is_too_big], "value over 1,000,000 (", trimws(big_where[is_too_big]), "); ")

# ---- Keep only flagged rows, add the reason, and save -----------------------
keep    <- is_neg_dmr | is_neg_std | is_old | is_too_big
flagged <- dat[keep, ]
flagged$FLAG_REASON <- trimws(reason[keep])

stamp    <- format(Sys.time(), "%Y-%m-%d_%H%M")
out_file <- file.path(out_dir, sprintf("eff_flagged_%s_%s.csv", STATE, stamp))
fwrite(flagged, out_file)

# ---- Print a short summary ---------------------------------------------------
cat("\nState:                 ", toupper(STATE), "\n")
cat("Total rows checked:    ", nrow(dat), "\n")
cat("Flagged rows:          ", nrow(flagged), "\n")
cat("  negative DMR value:        ", sum(is_neg_dmr), "\n")
cat("  negative DMR std value:    ", sum(is_neg_std), "\n")
cat("  year before 1984:          ", sum(is_old), "\n")
cat("  value over 1,000,000:      ", sum(is_too_big), "\n")
cat("Written to:", out_file, "\n")
