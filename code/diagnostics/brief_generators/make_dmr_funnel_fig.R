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
# LABELED ASSUMPTION: the `d` table below is entered as literal numbers, not
# recomputed here. Per the comment at its definition, they were checked
# directly against the 8 pipeline output files via DuckDB -- but that check
# was not run inside this script, so it is not independently traceable to a
# logged run. TODO: replace with a query against the actual pipeline output
# files (or a saved summary CSV) so these numbers are reproducible from code,
# not just asserted correct in a comment.
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
  library(cowplot)
  library(data.table)
})

# Verified directly from the 8 pipeline output files via DuckDB (not from memory)
d <- data.table(
  fy    = rep(c("2009", "2025"), each = 4),
  stage = rep(1:4, 2),
  rows    = c(4015793, 440369, 328296,  80196,
              4703897, 489033, 336437,  75818),
  permits = c(   6555,   6426,   6091,   4974,
                 6701,   6572,   6117,   4880)
)

stage_labels <- c(
  "1\nMajor-\nIndividual",
  "2\n+TSS\n(00530)",
  "3\n+Effluent\nGross",
  "4\n+C1/Q1"
)

theme_set(theme_minimal(base_size = 11))

pal <- c("2009" = "#4C72B0", "2025" = "#DD8452")

p_rows <- ggplot(d, aes(x = stage, y = rows, color = fy, group = fy)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2.4) +
  scale_x_continuous(breaks = 1:4, labels = stage_labels) +
  scale_y_log10(labels = label_comma()) +
  scale_color_manual(values = pal, name = "Fiscal Year") +
  labs(title = "Observations (rows)", x = NULL, y = "Rows (log scale)") +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold", size = 11),
        panel.grid.minor = element_blank())

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

legend <- get_legend(p_rows + theme(legend.box.margin = margin(0, 0, 0, 0)))

combined <- plot_grid(
  plot_grid(p_rows + theme(legend.position = "none"),
            p_permits + theme(legend.position = "none"),
            ncol = 2, align = "hv"),
  legend,
  ncol = 1, rel_heights = c(1, 0.1)
)

out_path <- file.path(CWA_ROOT, "docs", "institutional_briefs", "fig", "dmr_filter_funnel.pdf")
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
ggsave(out_path, combined, width = 9, height = 4.3, device = "pdf")
cat("Saved:", out_path, "\n")
