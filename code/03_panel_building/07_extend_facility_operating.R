# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# 07_extend_facility_operating.R
# ------------------------------------------------------------------------------
# SEVENTH STEP in the facility-by-month pipeline (post-processing correction).
# Reads the final panel produced by 06_add_effluent_violations.R and corrects
# FACILITY_OPERATING, which undercounts a facility's true active window.
#
#   Input  : data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv
#            (one row per FACILITY_UIN x YEAR x MONTH; built by scripts 01-06)
#   Output : data/processed/07_facility_month_panel_major_individual_operating_corrected_2005_2025.csv
#            (the same panel, with FACILITY_OPERATING corrected + 1 new column)
#
# COLUMNS CHANGED / ADDED:
#   FACILITY_OPERATING               - CORRECTED: 1 iff the month falls within the
#                                       facility's window after extending it to also
#                                       cover any month with a real recorded event
#                                       (see LABELED ASSUMPTIONS below)
#   FACILITY_OPERATING_PERMIT_WINDOW - the ORIGINAL script-01 definition (permit
#                                       open/close dates only), preserved unchanged,
#                                       placed immediately after FACILITY_OPERATING
#   every N_*/n_* count column       - NA -> 0 filled in any row that is newly
#                                       operating under the corrected flag (was NA
#                                       because FACILITY_OPERATING_PERMIT_WINDOW==0;
#                                       now 0 because a covered month with no
#                                       matched event is a true zero -- ASSUMPTION 4)
#   FED_PENALTY / STATE_PENALTY      - UNCHANGED. Their NA already means "no amount
#                                       assessed", independent of operating status
#                                       (script 05's ASSUMPTION 5); nothing changes.
#
# ------------------------------------------------------------------------------
# LABELED ASSUMPTIONS (read before using results):
#
#   1. WHY THIS STEP EXISTS. FACILITY_OPERATING (script 01) is computed purely
#      from ICIS_PERMITS date fields (EFFECTIVE/ISSUE/ORIGINAL_ISSUE_DATE for
#      opening; EXPIRATION/TERMINATION/RETIREMENT_DATE for closing). Measured on
#      the 06 panel: 12.66% of FACILITY_OPERATING==0 rows (32,033 of 253,028)
#      still carry a real recorded event -- proof the facility was genuinely
#      active. 75.9% of those are >12 months outside the computed window (median
#      31, max 250 months); 2,381 of 7,511 facilities (32%) are affected -- 2,132
#      on the close side, 413 on the open side. ROOT CAUSE (confirmed): permits
#      with PERMIT_STATUS_CODE == "ADC" (Administrative Continuance -- legally
#      still active past their nominal EXPIRATION_DATE while a renewal is
#      pending) have that EXPIRATION_DATE read as a real closing date anyway.
#      Example: facility 110006619212 / permit NH0100455, EXPIRATION_DATE =
#      01/29/2005, PERMIT_STATUS_CODE = "ADC", no TERMINATION_DATE/
#      RETIREMENT_DATE -- its computed window closes at the start of the panel
#      even though it has real recorded events up to 250 months later. 86.7% of
#      the 8,007 permits linked to this panel's facilities carry ADC status at
#      some point. (Per PI decision: fix both directions.)
#
#   2. "REAL EVENT" = any of 10 top-level total/count columns is non-NA and >0:
#      N_INSPECTIONS_TOTAL, N_PS_VIOLATIONS, N_CS_VIOLATIONS, N_SE_VIOLATIONS,
#      N_TSS_EFF_VIOLATIONS, N_FORMAL_ACTIONS, N_INFORMAL_ACTIONS, n_D80, n_D90,
#      n_E90. Every other N_*/n_* column is a breakout of one of these ten and
#      shares its NA/0 status (each build step in 02/04/05/06 fills its whole
#      block of count columns from one joined source row per facility-month --
#      see those scripts' READMEs), so checking these ten catches every event.
#
#   3. EXTENDED WINDOW = min/max of (computed window, first/last real-event
#      month), PER FACILITY. Per PI decision, both directions are extended:
#        new_start = min(orig_spine_start, first month with a real event)
#        new_end   = max(orig_spine_end,   last month with a real event)
#      A facility with no recorded events anywhere is unaffected (its window is
#      unchanged). This never shrinks a facility's window, only grows it.
#
#   4. A NEWLY-OPERATING MONTH WITH NO EVENT IS A TRUE ZERO. Any N_*/n_* column
#      that is NA in a row now covered by the extended window becomes 0 --
#      exactly the same "operating, no event = 0" rule script 01 established,
#      just applied to the newly-covered months. Cells that were already real
#      (non-NA) are never touched.
#
#   5. PENALTY COLUMNS ARE UNAFFECTED. FED_PENALTY/STATE_PENALTY are NA
#      whenever no formal action carried a dollar amount, regardless of
#      operating status (script 05's ASSUMPTION 5) -- extending the operating
#      window changes nothing about their meaning or values.
#
#   6. NON-DESTRUCTIVE. Writes a NEW file; the 06 panel is untouched. The
#      original permit-window-only flag is preserved as
#      FACILITY_OPERATING_PERMIT_WINDOW for full traceability -- nothing here
#      is silently overwritten or lost.
#
# Deterministic (no stochastic steps); rebuilt entirely from the 06 panel + this
# script -- no raw ICIS files are re-read, so this step is fast (one ~430 MB
# CSV in, no crosswalk rebuild needed).
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)   # fast CSV read + per-facility grouped min/max over ~1.9M rows
})

## ---- Config ----
IN_PATH  <- file.path(CWA_ROOT, "data/processed/06_facility_month_panel_major_individual_effluent_2005_2025.csv")
OUT_PATH <- file.path(CWA_ROOT, "data/processed/07_facility_month_panel_major_individual_operating_corrected_2005_2025.csv")

# The ten top-level event-total columns (LABELED ASSUMPTION 2). Every other
# N_*/n_* column is a breakout that shares one of these ten's NA/0 status.
EVENT_COLS <- c("N_INSPECTIONS_TOTAL", "N_PS_VIOLATIONS", "N_CS_VIOLATIONS", "N_SE_VIOLATIONS",
                "N_TSS_EFF_VIOLATIONS", "N_FORMAL_ACTIONS", "N_INFORMAL_ACTIONS",
                "n_D80", "n_D90", "n_E90")

# ------------------------------------------------------------------------------
# STEP 1: Read the final panel (output of script 06), as character like every
# other step, then convert only the columns this script computes on.
# ------------------------------------------------------------------------------
panel <- fread(IN_PATH, colClasses = "character", showProgress = FALSE)
# Read the header fresh from disk for STEP 6's column order, rather than
# `names(panel)`: data.table's `:=`/setnames() grow/rename the columns vector
# by reference (using over-allocated slack), so a plain `orig_col_order <-
# names(panel)` captured here would silently mutate as panel's columns change
# later in this script -- it is not an independent copy.
orig_col_order <- names(fread(IN_PATH, nrows = 0))

count_cols <- grep("^(N_|n_)", orig_col_order, value = TRUE)  # every count column
stopifnot(all(EVENT_COLS %in% count_cols))

panel[, `:=`(YEAR = as.integer(YEAR), MONTH = as.integer(MONTH),
             FACILITY_OPERATING = as.integer(FACILITY_OPERATING))]
for (c in count_cols) set(panel, j = c, value = suppressWarnings(as.integer(panel[[c]])))
panel[, ym := YEAR * 12L + MONTH]

n_rows_in    <- nrow(panel)
n_op0_before <- sum(panel$FACILITY_OPERATING == 0L)

# ------------------------------------------------------------------------------
# STEP 2: Flag rows with a real recorded event (LABELED ASSUMPTION 2).
# ------------------------------------------------------------------------------
panel[, any_event := Reduce(`|`, lapply(EVENT_COLS, function(c) !is.na(panel[[c]]) & panel[[c]] > 0L))]
n_op0_with_event_before <- sum(panel$FACILITY_OPERATING == 0L & panel$any_event)

# ------------------------------------------------------------------------------
# STEP 3: Per facility, compute the extended window (LABELED ASSUMPTION 3).
# ------------------------------------------------------------------------------
bounds <- panel[, .(
    orig_start  = min(ym[FACILITY_OPERATING == 1L]),
    orig_end    = max(ym[FACILITY_OPERATING == 1L]),
    event_start = if (any(any_event)) min(ym[any_event]) else NA_integer_,
    event_end   = if (any(any_event)) max(ym[any_event]) else NA_integer_
  ), by = FACILITY_UIN]
bounds[, `:=`(new_start = pmin(orig_start, event_start, na.rm = TRUE),
              new_end   = pmax(orig_end,   event_end,   na.rm = TRUE))]

# ------------------------------------------------------------------------------
# STEP 4: Preserve the original flag under its new name; compute the corrected one.
# ------------------------------------------------------------------------------
setnames(panel, "FACILITY_OPERATING", "FACILITY_OPERATING_PERMIT_WINDOW")
panel <- bounds[, .(FACILITY_UIN, new_start, new_end)][panel, on = "FACILITY_UIN"]
panel[, FACILITY_OPERATING := as.integer(ym >= new_start & ym <= new_end)]
panel[, c("new_start", "new_end", "ym", "any_event") := NULL]

# ------------------------------------------------------------------------------
# STEP 5: Fill newly-operating rows' NA count columns with 0 (LABELED ASSUMPTION 4).
# ------------------------------------------------------------------------------
newly_operating <- panel$FACILITY_OPERATING == 1L & panel$FACILITY_OPERATING_PERMIT_WINDOW == 0L
n_na_to_zero <- 0L
for (c in count_cols) {
  hit <- newly_operating & is.na(panel[[c]])
  n_na_to_zero <- n_na_to_zero + sum(hit)
  panel[hit, (c) := 0L]
}

# ------------------------------------------------------------------------------
# STEP 6: Restore column order (FACILITY_OPERATING_PERMIT_WINDOW immediately
# after FACILITY_OPERATING) and row order, then write.
# ------------------------------------------------------------------------------
new_col_order <- unlist(lapply(orig_col_order, function(c) {
  if (c == "FACILITY_OPERATING") c("FACILITY_OPERATING", "FACILITY_OPERATING_PERMIT_WINDOW") else c
}))
setcolorder(panel, new_col_order)
setorder(panel, FACILITY_UIN, YEAR, MONTH)

fwrite(panel, OUT_PATH)

# ------------------------------------------------------------------------------
# STEP 7: Run log -- always print what was built, so a bad run is caught early.
# ------------------------------------------------------------------------------
n_extended_close  <- sum(bounds$new_end   > bounds$orig_end,   na.rm = TRUE)
n_extended_open   <- sum(bounds$new_start < bounds$orig_start, na.rm = TRUE)
n_extended_either <- sum(bounds$new_end > bounds$orig_end | bounds$new_start < bounds$orig_start, na.rm = TRUE)
any_event_after <- Reduce(`|`, lapply(EVENT_COLS, function(c) !is.na(panel[[c]]) & panel[[c]] > 0L))
n_op0_with_event_after <- sum(panel$FACILITY_OPERATING == 0L & any_event_after)

message("=== 07_extend_facility_operating: correcting FACILITY_OPERATING ===")
message("Panel rows in / out (unchanged)                  : ", n_rows_in, " / ", nrow(panel))
message("FACILITY_OPERATING==0 rows before correction      : ", n_op0_before)
message("  ...of which had a real event anyway (the bug)   : ", n_op0_with_event_before,
        sprintf(" (%.2f%%)", 100 * n_op0_with_event_before / n_op0_before))
message("Facilities with window extended                   : ", n_extended_either, " of ", nrow(bounds),
        " (close side: ", n_extended_close, " / open side: ", n_extended_open, ")")
message("Rows flipped FACILITY_OPERATING 0 -> 1             : ", sum(newly_operating))
message("NA -> 0 fills across all N_*/n_* count columns     : ", n_na_to_zero)
message("Self-check -- FACILITY_OPERATING==0 rows with a real event AFTER correction (must be 0): ",
        n_op0_with_event_after)
stopifnot(n_op0_with_event_after == 0L)
message("Written to: ", OUT_PATH)
