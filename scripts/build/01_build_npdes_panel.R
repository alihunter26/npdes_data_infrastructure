# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# build_npdes_panel.R
# ------------------------------------------------------------------------------
# Build a FACILITY-by-YEAR panel of all NPDES facilities that had at least one
# enforcement action (formal or informal) between 2005 and 2025.
#
# Source: EPA ECHO bulk "ICIS-NPDES" download
#   https://echo.epa.gov/files/echodownloads/npdes_downloads.zip
#
# Output: data/processed/npdes_enforcement_panel_2005_2025.csv
#
# NOTE ON COLUMN NAMES: ECHO occasionally renames columns. This script reads the
# documented names defensively (via any_of / candidate-name matching) and prints
# the actual column names of each file so you can verify against the current
# ECHO NPDES data dictionary:
#   https://echo.epa.gov/tools/data-downloads
# ==============================================================================

# ---- 0. Setup ----------------------------------------------------------------
suppressPackageStartupMessages({
  library(data.table)   # fast reads of the large ICIS_PERMITS file
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(lubridate)
  library(readr)
})

## ---- Config (edit here) ----
YEAR_MIN     <- 2005
YEAR_MAX     <- 2025
DATA_DIR     <- file.path(CWA_ROOT, "data")
RAW_DIR      <- file.path(DATA_DIR, "raw", "npdes_downloads")   # already-unzipped ECHO files
PROC_DIR     <- file.path(DATA_DIR, "processed")
ZIP_URL      <- "https://echo.epa.gov/files/echodownloads/npdes_downloads.zip"
ZIP_PATH     <- file.path(RAW_DIR, "npdes_downloads.zip")
DOWNLOAD     <- FALSE         # data already present locally; set TRUE to (re)download
BALANCED     <- TRUE          # TRUE = full facility x year grid w/ zeros; FALSE = action-years only
INCLUDE_INFORMAL <- TRUE      # include informal actions in panel inclusion + counts

dir.create(RAW_DIR,  showWarnings = FALSE, recursive = TRUE)
dir.create(PROC_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- 1. Download + unzip -----------------------------------------------------
if (DOWNLOAD && !file.exists(ZIP_PATH)) {
  message("Downloading NPDES bulk data (~hundreds of MB) ...")
  options(timeout = 3600)
  download.file(ZIP_URL, ZIP_PATH, mode = "wb")
}
if (DOWNLOAD) {
  message("Unzipping ...")
  unzip(ZIP_PATH, exdir = RAW_DIR)
}

# Helper: locate a file inside RAW_DIR by (case-insensitive) name fragment
find_file <- function(fragment) {
  hits <- list.files(RAW_DIR, pattern = fragment, recursive = TRUE,
                     ignore.case = TRUE, full.names = TRUE)
  if (length(hits) == 0) stop("Could not find a file matching: ", fragment)
  hits[1]
}

# Helper: pick the first column name that exists from a set of candidates
pick_col <- function(df, candidates) {
  hit <- intersect(candidates, names(df))
  if (length(hit) == 0) NA_character_ else hit[1]
}

# Helper: coalesce several date columns, parse, return year
year_from <- function(df, candidates) {
  cols <- intersect(candidates, names(df))
  if (length(cols) == 0) return(rep(NA_integer_, nrow(df)))
  parsed <- lapply(cols, function(cc) {
    x <- df[[cc]]
    suppressWarnings(
      coalesce(mdy(x, quiet = TRUE), ymd(x, quiet = TRUE), dmy(x, quiet = TRUE))
    )
  })
  d <- Reduce(function(a, b) coalesce(a, b), parsed)
  year(d)
}

# ---- 2. Read the source files ------------------------------------------------
# Location lives in ICIS_FACILITIES (keyed by NPDES_ID); ICIS_PERMITS adds the
# major/minor discharger flag (keyed by EXTERNAL_PERMIT_NMBR == NPDES_ID).
f_formal      <- find_file("NPDES_FORMAL_ENFORCEMENT_ACTIONS")
f_informal    <- find_file("NPDES_INFORMAL_ENFORCEMENT_ACTIONS")
f_facils      <- find_file("ICIS_FACILITIES")
f_permits     <- find_file("ICIS_PERMITS")
f_inspections <- find_file("NPDES_INSPECTIONS")

formal      <- as_tibble(fread(f_formal,      colClasses = "character", showProgress = FALSE))
informal    <- as_tibble(fread(f_informal,    colClasses = "character", showProgress = FALSE))
facils      <- as_tibble(fread(f_facils,      colClasses = "character", showProgress = FALSE))
permits     <- as_tibble(fread(f_permits,     colClasses = "character", showProgress = FALSE))
inspections <- as_tibble(fread(f_inspections, colClasses = "character", showProgress = FALSE))

message("\n--- Column names found (verify against ECHO data dictionary) ---")
message("FORMAL:      ", paste(names(formal),      collapse = ", "))
message("INFORMAL:    ", paste(names(informal),    collapse = ", "))
message("FACILITIES:  ", paste(names(facils),      collapse = ", "))
message("PERMITS:     ", paste(names(permits),     collapse = ", "))
message("INSPECTIONS: ", paste(names(inspections), collapse = ", "))

# ---- 3. Standardize enforcement actions --------------------------------------
# Candidate columns (ECHO has shifted these over time; we match flexibly).
ID_CANDS        <- c("NPDES_ID", "EXTERNAL_PERMIT_NMBR", "SOURCE_ID")
FORMAL_DATE     <- c("SETTLEMENT_ENTERED_DATE", "ENF_ACTION_DATE", "ACHIEVED_DATE", "ENF_DATE")
INFORMAL_DATE   <- c("ACHIEVED_DATE", "ENF_ACTION_DATE", "ENF_DATE")
ENFTYPE_CANDS   <- c("ENF_TYPE_DESC", "ENF_TYPE_CODE")
FED_PEN_CANDS   <- c("FED_PENALTY_ASSESSED_AMT", "FED_PENALTY")
SL_PEN_CANDS    <- c("STATE_LOCAL_PENALTY_AMT", "STATE_LOCAL_PENALTY_ASSESSED_AMT")

prep_actions <- function(df, date_cands, kind) {
  id_col   <- pick_col(df, ID_CANDS)
  type_col <- pick_col(df, ENFTYPE_CANDS)
  fed_col  <- pick_col(df, FED_PEN_CANDS)
  sl_col   <- pick_col(df, SL_PEN_CANDS)
  if (is.na(id_col)) stop("No NPDES_ID-like column in the ", kind, " file.")

  out <- tibble(
    NPDES_ID  = str_trim(df[[id_col]]),
    year      = year_from(df, date_cands),
    enf_type  = if (!is.na(type_col)) df[[type_col]] else NA_character_,
    fed_pen   = if (!is.na(fed_col)) parse_number(df[[fed_col]]) else NA_real_,
    sl_pen    = if (!is.na(sl_col))  parse_number(df[[sl_col]])  else NA_real_,
    kind      = kind
  )
  out %>% filter(!is.na(NPDES_ID), NPDES_ID != "",
                 !is.na(year), year >= YEAR_MIN, year <= YEAR_MAX)
}

formal_a   <- prep_actions(formal,   FORMAL_DATE,   "formal")
informal_a <- if (INCLUDE_INFORMAL) prep_actions(informal, INFORMAL_DATE, "informal") else formal_a[0, ]

actions <- bind_rows(formal_a, informal_a)
message("\nEnforcement-action rows in window (", YEAR_MIN, "-", YEAR_MAX, "): ",
        nrow(actions))

has_penalties <- any(!is.na(actions$fed_pen)) || any(!is.na(actions$sl_pen))
if (!has_penalties)
  message("NOTE: no penalty $ columns present in the bulk files; penalty vars omitted.")

# ---- 4. Facilities in the panel (>=1 action in window) -----------------------
panel_facilities <- actions %>% distinct(NPDES_ID)
message("Facilities with >=1 enforcement action: ", nrow(panel_facilities))

# ---- 5. Aggregate enforcement to facility-year -------------------------------
enf_year <- actions %>%
  group_by(NPDES_ID, year) %>%
  summarise(
    n_formal_actions   = sum(kind == "formal"),
    n_informal_actions = sum(kind == "informal"),
    n_enf_actions_total= n(),
    fed_penalty        = if (has_penalties) sum(fed_pen, na.rm = TRUE) else NA_real_,
    state_local_penalty= if (has_penalties) sum(sl_pen,  na.rm = TRUE) else NA_real_,
    enf_type_list      = paste(sort(unique(na.omit(enf_type))), collapse = "; "),
    .groups = "drop"
  ) %>%
  mutate(total_penalty = if (has_penalties)
           coalesce(fed_penalty, 0) + coalesce(state_local_penalty, 0) else NA_real_)

# ---- 5b. Aggregate inspections to facility-year ------------------------------
insp_id_col <- pick_col(inspections, ID_CANDS)
if (is.na(insp_id_col)) stop("No NPDES_ID-like column in NPDES_INSPECTIONS.")

insp_fac_year <- tibble(
  NPDES_ID = str_trim(inspections[[insp_id_col]]),
  year     = year_from(inspections, c("ACTUAL_BEGIN_DATE", "ACTUAL_END_DATE"))
) %>%
  filter(!is.na(NPDES_ID), NPDES_ID != "",
         !is.na(year), year >= YEAR_MIN, year <= YEAR_MAX) %>%
  distinct(NPDES_ID, year) %>%
  mutate(inspected = 1L)

message("Facility-years with >=1 inspection (", YEAR_MIN, "-", YEAR_MAX, "): ",
        nrow(insp_fac_year))

# ---- 6. Facility location lookup (one row per NPDES_ID) -----------------------
# Location comes from ICIS_FACILITIES (already keyed by NPDES_ID).
fac_id <- pick_col(facils, ID_CANDS)
loc_map <- list(
  REGISTRY_ID = c("FACILITY_UIN", "REGISTRY_ID"),
  FAC_NAME    = c("FACILITY_NAME", "FAC_NAME"),
  FAC_STREET  = c("LOCATION_ADDRESS", "FAC_STREET", "STREET_ADDRESS"),
  FAC_CITY    = c("CITY", "FAC_CITY"),
  COUNTY_CODE = c("COUNTY_CODE", "FAC_COUNTY"),
  FAC_STATE   = c("STATE_CODE", "FAC_STATE", "STATE"),
  FAC_ZIP     = c("ZIP", "FAC_ZIP", "ZIP_CODE"),
  FAC_LAT     = c("GEOCODE_LATITUDE", "FAC_LAT", "LATITUDE_MEASURE"),
  FAC_LONG    = c("GEOCODE_LONGITUDE", "FAC_LONG", "LONGITUDE_MEASURE")
)

locations <- tibble(NPDES_ID = str_trim(facils[[fac_id]]))
for (nm in names(loc_map)) {
  src <- pick_col(facils, loc_map[[nm]])
  locations[[nm]] <- if (!is.na(src)) facils[[src]] else NA_character_
}

# One row per facility; keep the first non-missing-named record per NPDES_ID.
locations <- locations %>%
  mutate(.has_name = as.integer(!is.na(FAC_NAME) & FAC_NAME != "")) %>%
  arrange(NPDES_ID, desc(.has_name)) %>%
  group_by(NPDES_ID) %>% slice(1) %>% ungroup() %>%
  select(-.has_name) %>%
  semi_join(panel_facilities, by = "NPDES_ID")

# Major/minor discharger flag from ICIS_PERMITS (latest permit version).
p_id    <- pick_col(permits, ID_CANDS)
mm_col  <- pick_col(permits, c("MAJOR_MINOR_STATUS_FLAG", "MAJOR_MINOR_STATUS"))
iss_col <- pick_col(permits, c("ISSUE_DATE", "EFFECTIVE_DATE", "ORIGINAL_ISSUE_DATE"))
if (!is.na(mm_col)) {
  mm <- tibble(
    NPDES_ID = str_trim(permits[[p_id]]),
    MAJOR_MINOR_STATUS = permits[[mm_col]],
    .issue = if (!is.na(iss_col))
      suppressWarnings(coalesce(mdy(permits[[iss_col]], quiet = TRUE),
                                ymd(permits[[iss_col]], quiet = TRUE)))
      else as.Date(NA)
  ) %>%
    arrange(NPDES_ID, desc(.issue)) %>%
    group_by(NPDES_ID) %>% slice(1) %>% ungroup() %>%
    select(-.issue)
  locations <- left_join(locations, mm, by = "NPDES_ID")
}

# ---- 7. Build the panel ------------------------------------------------------
if (BALANCED) {
  grid <- tidyr::crossing(NPDES_ID = panel_facilities$NPDES_ID,
                          year     = YEAR_MIN:YEAR_MAX)
} else {
  grid <- enf_year %>% distinct(NPDES_ID, year)
}

panel <- grid %>%
  left_join(enf_year,      by = c("NPDES_ID", "year")) %>%
  left_join(locations,     by = "NPDES_ID") %>%
  left_join(insp_fac_year, by = c("NPDES_ID", "year")) %>%
  mutate(
    across(c(n_formal_actions, n_informal_actions, n_enf_actions_total),
           ~ replace_na(., 0L)),
    enf_type_list   = replace_na(enf_type_list, ""),
    any_enforcement = as.integer(n_enf_actions_total > 0),
    inspected       = replace_na(inspected, 0L)
  )

if (has_penalties) {
  panel <- panel %>%
    mutate(across(c(fed_penalty, state_local_penalty, total_penalty),
                  ~ replace_na(., 0)))
}

# Order columns: keys -> location -> outcomes
panel <- panel %>%
  relocate(NPDES_ID, year,
           any_of(names(loc_map)), any_of("MAJOR_MINOR_STATUS"),
           any_enforcement, inspected, n_formal_actions, n_informal_actions,
           n_enf_actions_total, enf_type_list) %>%
  arrange(NPDES_ID, year)

# ---- 8. Write + report -------------------------------------------------------
out_path <- file.path(PROC_DIR, "npdes_enforcement_panel_2005_2025.csv")
write_csv(panel, out_path)

message("\n=== DONE ===")
message("Facilities: ", dplyr::n_distinct(panel$NPDES_ID))
message("Rows:       ", nrow(panel))
message("Years:      ", YEAR_MIN, "-", YEAR_MAX, if (BALANCED) " (balanced)" else " (unbalanced)")
message("Written to: ", out_path)
