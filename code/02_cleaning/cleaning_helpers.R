# ==============================================================================
# cleaning_helpers.R
# ------------------------------------------------------------------------------
# Shared "cleaning" building blocks used by every step of the facility-by-month
# panel pipeline (code/03_panel_building/01 through 06).
#
# WHY THIS FILE EXISTS: before this file was written, each of the six numbered
# scripts in code/03_panel_building/ had its OWN copy-pasted version of these
# same few pieces of logic (reading a raw file safely, matching a permit to its
# physical facility, and parsing dates). That's a maintenance risk: if someone
# fixes a bug in one copy but forgets the other five, the six panel-building
# steps quietly start disagreeing with each other. This file collects that
# duplicated logic in ONE place, so there is exactly one version of each rule
# to read, test, and fix.
#
# WHAT DID *NOT* MOVE HERE: the actual research decisions -- for example,
# "which date column counts as a permit's opening date" or "what does it mean
# if a permit has no closing date at all" -- stay inline in the script that
# makes that decision (mainly 01_build_facility_month_panel_major_individual.R),
# right next to the code comment that explains and justifies it. This file only
# holds the generic MECHANICS ("combine these date columns into one date, using
# this combination rule"), not the domain-specific CHOICES ("use these three
# particular columns, with this fallback"). Keeping the choices next to their
# justification matters more than eliminating a few lines of duplication.
#
# HOW TO USE THIS FILE: every script in code/03_panel_building/ sources this
# file (via CWA_ROOT, right after it sources _paths.R) and then calls the
# functions below instead of re-defining them locally. This file assumes the
# calling script has already loaded the `data.table` package (for `fread`,
# `fifelse`, `fcoalesce`) and, if it uses the date functions, the `lubridate`
# package (for `mdy`). We don't call `library()` ourselves here, because this
# file only *defines* functions -- R doesn't actually need those packages
# loaded until the functions are *called*, which always happens later, after
# the calling script has already loaded them.
# ==============================================================================


# ------------------------------------------------------------------------------
# rd(): read one column-selected slice of a raw ICIS-NPDES CSV, safely.
# ------------------------------------------------------------------------------
# WHAT IT DOES: reads only the columns you ask for (`cols`) from a CSV file in
# data/raw/npdes_downloads/, and forces every one of those columns to be read
# as plain text (character), never as a number or date.
#
# WHY "read as character" MATTERS: a lot of the ID codes in this data --
# NPDES_ID, FACILITY_UIN, ZIP code, county code, and so on -- are made of
# digits but are not actually numbers; they're labels that happen to look
# numeric. Some of them have meaningful LEADING ZEROS (e.g. a ZIP code of
# "00501"). If you let R guess the column type, it will often "helpfully"
# read a leading-zero ID as the number 501, silently throwing away the zero
# and corrupting the ID. Reading everything as character up front avoids that
# entire class of bug; codes get converted to numbers deliberately, later,
# only for the specific columns where a real numeric value is wanted.
#
# ARGUMENTS:
#   file     -- the raw CSV's filename, e.g. "ICIS_FACILITIES.csv"
#   cols     -- a character vector of which columns to keep, e.g.
#               c("NPDES_ID", "FACILITY_UIN")
#   raw_dir  -- which folder to look for `file` in. Defaults to RAW_DIR, a
#               variable each panel-building script already defines (pointing
#               at data/raw/npdes_downloads/), so most callers can omit this.
#
# RETURNS: a data.table with just the requested columns, all as character.
rd <- function(file, cols, raw_dir = RAW_DIR) {
  # `class_map` tells fread(): "no matter what this column looks like, treat
  # it as character." setNames() just builds a named list like
  # list(NPDES_ID = "character", FACILITY_UIN = "character") from `cols`.
  class_map <- setNames(rep("character", length(cols)), cols)
  fread(file.path(raw_dir, file), select = cols,
        colClasses = class_map, showProgress = FALSE)
}


# ------------------------------------------------------------------------------
# build_facility_crosswalk(): map every permit (NPDES_ID) to its physical
# facility (facility_id).
# ------------------------------------------------------------------------------
# BACKGROUND: this project's panel is built one row per PHYSICAL FACILITY per
# month, not one row per permit. But most of the raw EPA data (inspections,
# violations, enforcement actions, ...) is recorded against a PERMIT
# (identified by NPDES_ID), not directly against a facility. So every one of
# those raw files needs to be translated from "this happened to permit X" to
# "this happened at facility Y" before it can be added to the panel. This
# function builds that permit -> facility translation table once, so every
# script can use the exact same translation.
#
# THE RULE: EPA's own facility registry (ICIS_FACILITIES.csv) links each
# NPDES_ID to a `FACILITY_UIN` -- a more stable ID for the physical SITE,
# assigned by EPA's cross-program Facility Registry Service (FRS), which is
# shared across environmental programs (not just NPDES). Most permits have a
# FACILITY_UIN on file, and we use it as the facility's identity, because it's
# the more stable, cross-program ID. But a real minority of permits have a
# BLANK FACILITY_UIN (no FRS match). Rather than lose those permits entirely,
# we fall back to using the permit's own NPDES_ID as a stand-in facility
# identifier in that case. So: "use FACILITY_UIN if we have one, otherwise
# fall back to NPDES_ID" -- exactly what the one line of logic below does.
#
# A NOTE ON WHICH FACILITIES FILE TO READ: this function always reads a fresh,
# UNRESTRICTED copy of ICIS_FACILITIES.csv (every NPDES_ID in the country),
# not a copy that's already been filtered down to some smaller population
# (like "only major individual permits"). This matters: if a script filtered
# the facilities file first and built the crosswalk from that filtered copy,
# any raw-data row belonging to a facility's OTHER permits (say, a general
# stormwater permit at a site whose main permit is the one in our population)
# would have nowhere to route to, and would be silently dropped. Building the
# crosswalk from the full, unrestricted file avoids that.
#
# ARGUMENTS:
#   raw_dir -- passed straight through to rd(); defaults to RAW_DIR.
#
# RETURNS: a data.table with one row per NPDES_ID, columns (NPDES_ID,
# facility_id), ready to join other tables against via `on = "NPDES_ID"`.
build_facility_crosswalk <- function(raw_dir = RAW_DIR) {
  fac <- rd("ICIS_FACILITIES.csv", c("NPDES_ID", "FACILITY_UIN"), raw_dir = raw_dir)
  fac[, NPDES_ID     := trimws(NPDES_ID)]
  fac[, FACILITY_UIN := trimws(FACILITY_UIN)]
  # The actual "FACILITY_UIN if present, else NPDES_ID" rule described above:
  fac[, facility_id  := fifelse(FACILITY_UIN != "", FACILITY_UIN, NPDES_ID)]
  # A permit needs a non-blank NPDES_ID to be usable as a join key at all;
  # unique() collapses any accidental repeat rows for the same NPDES_ID.
  unique(fac[NPDES_ID != "", .(NPDES_ID, facility_id)])
}


# ------------------------------------------------------------------------------
# coalesce_date_priority(): parse "the" date for an event from several
# candidate date columns, using the FIRST one that's actually filled in.
# ------------------------------------------------------------------------------
# BACKGROUND: EPA's raw date columns are stored as text (e.g. "03/14/2019")
# and are frequently blank. Several of the raw files record more than one
# candidate date column for what is conceptually a single event (for example,
# an inspection has both an ACTUAL_BEGIN_DATE and an ACTUAL_END_DATE). This
# function picks ONE date to represent the event, by trying each candidate
# column IN THE ORDER YOU LIST THEM, and using the first one that has an
# actual value. This is the "priority" version: order matters, and it's the
# caller's job to list the candidate columns in the order they want them
# preferred, most-preferred first.
#
# (There's a second, DIFFERENT way this project combines several date
# candidates into one -- see coalesce_date_extreme() below -- used only for
# figuring out when a whole PERMIT opens or closes, where the rule is
# "earliest/latest across whichever dates are present," not "first in a
# preferred order." Don't mix the two up; they answer different questions.)
#
# ARGUMENTS:
#   dt        -- a data.table containing the raw date columns as text.
#   date_cols -- a character vector of column names to try, most-preferred
#                column first, e.g. c("ACTUAL_BEGIN_DATE", "ACTUAL_END_DATE").
#
# RETURNS: a vector of parsed Dates (one per row of `dt`), with NA for any row
# where every one of `date_cols` was blank or unparseable.
coalesce_date_priority <- function(dt, date_cols) {
  # For each candidate column, mdy(..., quiet = TRUE) parses text like
  # "03/14/2019" into a real R Date, and quietly returns NA for anything it
  # can't parse (blank, malformed, etc.) instead of erroring out. fcoalesce()
  # then walks across the parsed columns row by row and keeps the first
  # non-NA value it finds, in the order the columns were given.
  parsed_cols <- lapply(date_cols, function(col) mdy(dt[[col]], quiet = TRUE))
  do.call(fcoalesce, parsed_cols)
}


# ------------------------------------------------------------------------------
# coalesce_date_extreme(): combine several candidate date columns into one
# date, by taking the EARLIEST or LATEST value across whichever candidates are
# actually present.
# ------------------------------------------------------------------------------
# BACKGROUND: a permit's ICIS_PERMITS record carries several candidate columns
# for when it started (EFFECTIVE_DATE, ISSUE_DATE, ORIGINAL_ISSUE_DATE) and
# several candidate columns for when it ended (EXPIRATION_DATE,
# TERMINATION_DATE, RETIREMENT_DATE). Unlike coalesce_date_priority() above,
# here we're not looking for "the one true date" among interchangeable
# options -- we want the WIDEST possible window, so we take whichever
# candidate is earliest (for an opening date) or latest (for a closing date),
# out of whatever's actually filled in. A blank candidate is simply ignored,
# not treated as "earlier/later than everything else."
#
# WHICH COLUMNS TO USE, AND WHAT COUNTS AS "NO DATE AT ALL," ARE RESEARCH
# DECISIONS THAT LIVE ELSEWHERE: this function just does the min/max
# arithmetic. The actual choice of which three columns to pass in for opening
# vs. closing, and what to do when a permit has NO usable date in any of
# them, are labeled, PI-guided assumptions documented in
# 01_build_facility_month_panel_major_individual.R, right next to where this
# function gets called -- see that script's "LABELED ASSUMPTIONS" section.
#
# ARGUMENTS:
#   dt        -- a data.table containing the raw date columns as text.
#   date_cols -- a character vector of candidate column names (order doesn't
#                matter here, unlike coalesce_date_priority()).
#   which     -- either "min" (earliest present date -- for an opening date)
#                or "max" (latest present date -- for a closing date).
#
# RETURNS: a vector of Dates (one per row of `dt`). A row is NA only if EVERY
# one of `date_cols` was blank/unparseable for that row.
coalesce_date_extreme <- function(dt, date_cols, which = c("min", "max")) {
  which <- match.arg(which)
  parsed_cols <- lapply(date_cols, function(col) mdy(dt[[col]], quiet = TRUE))
  # pmin()/pmax() compare the candidate columns position-by-position (row by
  # row) rather than collapsing the whole vector to one number, which is what
  # we want here: one earliest/latest date PER ROW. na.rm = TRUE means a
  # blank candidate is skipped rather than making the whole row NA.
  extreme_fn <- if (which == "min") pmin else pmax
  do.call(extreme_fn, c(parsed_cols, list(na.rm = TRUE)))
}
