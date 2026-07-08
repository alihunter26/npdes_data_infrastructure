# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# Why are RNC fields ~61% blank in NPDES_CS_VIOLATIONS?
# Test whether RNC population tracks permit-level RNC tracking / major-minor.
# Read-only.
d <- file.path(CWA_ROOT, "data/raw/npdes_downloads")
v <- read.csv(file.path(d, "NPDES_CS_VIOLATIONS.csv"), colClasses = "character")
p <- read.csv(file.path(d, "ICIS_PERMITS.csv"), colClasses = "character")
bl <- function(x) is.na(x) | trimws(x) == ""
v$rnc_present <- !bl(v$RNC_DETECTION_CODE)

mm  <- p$MAJOR_MINOR_STATUS_FLAG[match(v$NPDES_ID, p$EXTERNAL_PERMIT_NMBR)]
rnc <- p$RNC_TRACKING_FLAG[match(v$NPDES_ID, p$EXTERNAL_PERMIT_NMBR)]
lab <- function(s) if (is.na(s)) "(no match)" else if (s == "") "(blank)" else s

report <- function(g, title) {
  cat("\n===", title, "===\n")
  g[is.na(g)] <- "__NA__"
  for (s in names(sort(table(g), decreasing = TRUE))) {
    idx <- g == s
    cat(sprintf("  %-10s n=%6d  RNC-present %5.1f%%\n",
                lab(if (s == "__NA__") NA else s), sum(idx),
                100 * mean(v$rnc_present[idx])))
  }
}
report(mm,  "RNC-present rate by permit MAJOR/MINOR status")
report(rnc, "RNC-present rate by permit RNC_TRACKING_FLAG")
