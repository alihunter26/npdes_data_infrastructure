# Calculate days between scheduled and actual dates
cs_violations$days_between <- as.numeric(as.Date(cs_violations$ACTUAL_DATE, format = "%m/%d/%Y") -
                              as.Date(cs_violations$SCHEDULE_DATE, format = "%m/%d/%Y"))
summary(cs_violations$days_between)

# Prints min
cs_violations[which.min(cs_violations$days_between), ]

# 5th and 95th percentiles
quantile(cs_violations$days_between, probs = c(0.05, 0.95), na.rm = TRUE)
