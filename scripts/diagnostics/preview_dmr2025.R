# Portable paths: locate & source the repo _paths.R (defines CWA_ROOT, RAW_DIR, OUT_DIR, ...)
source(local({d<-getwd(); while(!file.exists(file.path(d,".git"))&&dirname(d)!=d) d<-dirname(d); file.path(d,"_paths.R")}))

library(data.table)

zip_path <- file.path(CWA_ROOT, "data/raw/npdes_dmrs_fy2025.zip")

df <- fread(cmd = paste("unzip -p", shQuote(zip_path), "NPDES_DMRS_FY2025.csv"), nrows = 50)

View(df)
