# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

zip_path <- file.path(DMR_DIR, "npdes_dmrs_fy2025.zip")

preview <- data.table::fread(cmd = paste("unzip -p", shQuote(zip_path)), nrows = 50)
View(preview)


head_panel <- read.csv(file.path(PROC_DIR, "06_facility_month_panel_major_individual_effluent_2005_2025.csv"), nrows = 100)


shortened_dmr <-read.csv(file.path(PROC_DIR, "dmr_fy2025_exo_00530_effgross_monthlyavg.csv"), nrows = 100)