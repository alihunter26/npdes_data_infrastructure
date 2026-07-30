# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

# ==============================================================================
# make_dmr_funnel_fig.R
# ------------------------------------------------------------------------------
# Plots the DMR row/permit "filter funnel" (major-individual -> +TSS(00530) ->
# +effluent gross -> +C1/Q1) for FY2009 vs FY2025, side by side (rows on a log
# scale, distinct permits on a linear scale).
#
# Writes: docs/institutional_briefs/fig/dmr_filter_funnel.pdf
#
# Row/permit counts for `d` below are computed directly from the 8 DMR
# row-filter pipeline output files in code/dmr/ (01-04, FY2009 and FY2025) on
# every run -- not hardcoded -- so the figure always reflects whatever those
# files currently contain. Requires all 8 files to already exist (run
# filter_dmr_major_individual.R / filter_dmr_00530.R / filter_dmr_monloc1.R /
# filter_dmr_c1q1.R for both FY2009 and FY2025 first).
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
  library(cowplot)
  library(data.table)
})

# ---- Compute rows + distinct permits from the actual pipeline output files ---
stage_suffix <- c("01_dmr_fy%s.csv", "02_dmr_fy%s_00530.csv",
                  "03_dmr_fy%s_00530_monloc1.csv", "04_dmr_fy%s_00530_monloc1_c1q1.csv")

stage_counts <- function(path) {
  permit_col <- fread(path, select = "EXTERNAL_PERMIT_NMBR", colClasses = "character",
                       showProgress = FALSE)
  list(rows = nrow(permit_col), permits = uniqueN(permit_col$EXTERNAL_PERMIT_NMBR))
}

d <- rbindlist(lapply(c("2009", "2025"), function(fy) {
  paths <- file.path(CWA_ROOT, "code", "dmr", sprintf(stage_suffix, fy))
  missing <- paths[!file.exists(paths)]
  if (length(missing) > 0)
    stop("Missing DMR row-filter pipeline output(s) for FY", fy, ": ",
         paste(missing, collapse = ", "),
         " -- run filter_dmr_major_individual.R/filter_dmr_00530.R/",
         "filter_dmr_monloc1.R/filter_dmr_c1q1.R ", fy, " first.")
  message("Reading FY", fy, " pipeline stages (01-04) ...")
  counts <- lapply(paths, stage_counts)
  data.table(fy = fy, stage = 1:4,
             rows    = vapply(counts, `[[`, integer(1), "rows"),
             permits = vapply(counts, `[[`, integer(1), "permits"))
}))

message("\nComputed funnel counts:")
print(d)

# x-axis tick labels: one per filter stage, matching `stage` 1-4 in `d` above.
stage_labels <- c(
  "1\nMajor-\nIndividual",
  "2\n+TSS\n(00530)",
  "3\n+Effluent\nGross",
  "4\n+C1/Q1"
)

theme_set(theme_minimal(base_size = 11))

# One fixed color per fiscal year, shared by both panels below so the two
# plots read as one comparison rather than two unrelated charts.
pal <- c("2009" = "#4C72B0", "2025" = "#DD8452")

# ---- Panel 1: row counts, log scale ------------------------------------------
# Rows shrink by orders of magnitude across the funnel stages (millions ->
# tens of thousands), so a log y-axis is needed to see stage-to-stage
# movement at every step, not just the first one.
p_rows <- ggplot(d, aes(x = stage, y = rows, color = fy, group = fy)) +
  geom_line(linewidth = 1) +                                  # connects the 4 stages per FY
  geom_point(size = 2.4) +                                    # marks each stage explicitly
  scale_x_continuous(breaks = 1:4, labels = stage_labels) +   # numeric stage -> readable label
  scale_y_log10(labels = label_comma()) +                     # log scale + comma-formatted numbers
  scale_color_manual(values = pal, name = "Fiscal Year") +
  labs(title = "Observations (rows)", x = NULL, y = "Rows (log scale)") +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold", size = 11),
        panel.grid.minor = element_blank())

# ---- Panel 2: distinct permits, linear scale ---------------------------------
# Permit counts only shrink by ~30% end to end (not orders of magnitude), so a
# linear y-axis (anchored at 0 via `limits`) is more honest here than log,
# which would visually exaggerate a small relative change.
p_permits <- ggplot(d, aes(x = stage, y = permits, color = fy, group = fy)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2.4) +
  scale_x_continuous(breaks = 1:4, labels = stage_labels) +
  scale_y_continuous(labels = label_comma(), limits = c(0, NA)) +
  scale_color_manual(values = pal, name = "Fiscal Year") +
  labs(title = "Distinct Permits", x = NULL, y = "Permits") +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold", size = 11),
        panel.grid.minor = element_blank())

# ---- Combine: one shared legend underneath both panels -----------------------
# Pull the legend off of p_rows (both panels use the same color mapping, so
# either would do), then lay the two panels side by side with that one legend
# shared beneath them, instead of a redundant legend under each panel.
legend <- get_legend(p_rows + theme(legend.box.margin = margin(0, 0, 0, 0)))

combined <- plot_grid(
  plot_grid(p_rows + theme(legend.position = "none"),
            p_permits + theme(legend.position = "none"),
            ncol = 2, align = "hv"),
  legend,
  ncol = 1, rel_heights = c(1, 0.1)   # legend strip much shorter than the plots
)

out_path <- file.path(CWA_ROOT, "docs", "institutional_briefs", "fig", "dmr_filter_funnel.pdf")
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
ggsave(out_path, combined, width = 9, height = 4.3, device = "pdf")
cat("Saved:", out_path, "\n")
