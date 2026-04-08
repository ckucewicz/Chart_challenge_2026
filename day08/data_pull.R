# EPA AQS API — Hourly PM2.5 for Philadelphia, PA
# =================================================
# State:  Pennsylvania → FIPS 42
# County: Philadelphia → FIPS 101
#
# Setup:
#   1. Register for a free API key at:
#      https://aqs.epa.gov/data/api/signup?email=YOUR_EMAIL
#   2. Fill in your email and key below
#   3. Run Step 1 first to list monitors, then Step 2 to pull data
#
# Required packages:
#   install.packages(c("httr", "jsonlite", "dplyr", "readr", "lubridate"))

library(httr)
library(jsonlite)
library(dplyr)
library(readr)
library(lubridate)

# ── Config ────────────────────────────────────────────────────
EMAIL   <- "cfkucewicz@gmail.com"      # your EPA AQS registered email
API_KEY <- "copperfox31"   # from EPA signup email

STATE   <- "42"                  # Pennsylvania
COUNTY  <- "101"                 # Philadelphia County
YEAR    <- 2024                  # change to desired year

PM25    <- "88101"               # PM2.5 FRM/FEM parameter code
BASE    <- "https://aqs.epa.gov/data/api"


# ── Step 1: List monitors ─────────────────────────────────────
list_monitors <- function() {
  cat("\nFetching Philadelphia PM2.5 monitors...\n")
  
  res <- GET(
    url   = paste0(BASE, "/monitors/byCounty"),
    query = list(
      email  = EMAIL,
      key    = API_KEY,
      param  = PM25,
      bdate  = "20200101",
      edate  = "20241231",
      state  = STATE,
      county = COUNTY
    )
  )
  
  stop_for_status(res)
  data <- fromJSON(content(res, "text", encoding = "UTF-8"))$Data
  
  if (is.null(data) || nrow(data) == 0) {
    cat("No monitors found.\n")
    return(invisible(NULL))
  }
  
  cat(sprintf("\n── Philadelphia PM2.5 monitors (%d found) ────────\n", nrow(data)))
  data %>%
    select(any_of(c("site_number", "local_site_name", "city_name",
                    "open_date", "close_date", "latitude", "longitude"))) %>%
    mutate(close_date = ifelse(is.na(close_date) | close_date == "", "present", close_date)) %>%
    print(n = Inf)
  
  invisible(data)
}


# ── Step 2a: Pull all monitors in county ─────────────────────
fetch_by_county <- function(year = YEAR) {
  cat(sprintf("\nFetching hourly PM2.5 — Philadelphia County — %d...\n", year))
  
  res <- GET(
    url   = paste0(BASE, "/sampleData/byCounty"),
    query = list(
      email  = EMAIL,
      key    = API_KEY,
      param  = PM25,
      bdate  = sprintf("%d0101", year),
      edate  = sprintf("%d1231", year),
      state  = STATE,
      county = COUNTY
    ),
    timeout(180)
  )
  
  stop_for_status(res)
  parsed <- fromJSON(content(res, "text", encoding = "UTF-8"))
  
  # Check for API-level errors
  header <- parsed$Header
  if (!is.null(header) && isTRUE(header$status[1] == "Failed")) {
    stop(paste("API error:", header$error[1]))
  }
  
  rows <- parsed$Data
  cat(sprintf("  → %s records returned\n", format(nrow(rows), big.mark = ",")))
  rows
}


# ── Step 2b: Pull a specific monitor site ────────────────────
fetch_by_site <- function(site, year = YEAR) {
  cat(sprintf("\nFetching hourly PM2.5 — site %s-%s-%s — %d...\n",
              STATE, COUNTY, site, year))
  
  res <- GET(
    url   = paste0(BASE, "/sampleData/bySite"),
    query = list(
      email  = EMAIL,
      key    = API_KEY,
      param  = PM25,
      bdate  = sprintf("%d0101", year),
      edate  = sprintf("%d1231", year),
      state  = STATE,
      county = COUNTY,
      site   = site
    ),
    timeout(120)
  )
  
  stop_for_status(res)
  rows <- fromJSON(content(res, "text", encoding = "UTF-8"))$Data
  cat(sprintf("  → %s records returned\n", format(nrow(rows), big.mark = ",")))
  rows
}


# ── Parse to clean data frame ─────────────────────────────────
to_dataframe <- function(rows) {
  if (is.null(rows) || nrow(rows) == 0) {
    warning("No data returned.")
    return(tibble())
  }
  
  df <- as_tibble(rows) %>%
    rename(pm25_ugm3 = sample_measurement) %>%
    mutate(
      pm25_ugm3 = as.numeric(pm25_ugm3),
      datetime  = ymd_hm(paste(date_local, time_local))
    ) %>%
    select(any_of(c(
      "datetime", "date_local", "time_local", "pm25_ugm3",
      "units_of_measure", "qualifier", "local_site_name",
      "site_number", "latitude", "longitude",
      "state_name", "county_name", "city_name", "method", "poc"
    ))) %>%
    arrange(datetime)
  
  df
}


# ── Summary ───────────────────────────────────────────────────
summarize_data <- function(df) {
  if (nrow(df) == 0) return(invisible(NULL))
  
  cat("\n── Data summary ──────────────────────────────────\n")
  cat(sprintf("  Records:       %s\n",   format(nrow(df), big.mark = ",")))
  cat(sprintf("  Date range:    %s → %s\n",
              as.Date(min(df$datetime, na.rm = TRUE)),
              as.Date(max(df$datetime, na.rm = TRUE))))
  
  if ("site_number" %in% names(df))
    cat(sprintf("  Monitor sites: %d\n", n_distinct(df$site_number)))
  
  cat(sprintf("  PM2.5 mean:    %.2f µg/m³\n", mean(df$pm25_ugm3, na.rm = TRUE)))
  cat(sprintf("  PM2.5 median:  %.2f µg/m³\n", median(df$pm25_ugm3, na.rm = TRUE)))
  cat(sprintf("  PM2.5 max:     %.2f µg/m³\n", max(df$pm25_ugm3, na.rm = TRUE)))
  cat(sprintf("  Missing:       %s hours\n",   format(sum(is.na(df$pm25_ugm3)), big.mark = ",")))
  
  # Days over EPA standards
  daily <- df %>%
    group_by(date_local) %>%
    summarise(daily_mean = mean(pm25_ugm3, na.rm = TRUE), .groups = "drop")
  
  cat(sprintf("  Days avg >35 µg/m³ (EPA 24h standard): %d\n", sum(daily$daily_mean > 35, na.rm = TRUE)))
  cat(sprintf("  Days avg >12 µg/m³ (EPA annual std):   %d\n", sum(daily$daily_mean > 12, na.rm = TRUE)))
  
  invisible(df)
}


# ── Main ──────────────────────────────────────────────────────

# STEP 1: See what monitors exist — uncomment to run first
# list_monitors()

# STEP 2: Pull full year for all Philadelphia monitors
rows <- fetch_by_county(year = YEAR)
df   <- to_dataframe(rows)
summarize_data(df)

# Save hourly CSV
out_hourly <- sprintf("pm25_philadelphia_hourly_%d.csv", YEAR)
write_csv(df, out_hourly)
cat(sprintf("\n  Saved → %s\n", out_hourly))

# Save daily averages
if (nrow(df) > 0) {
  daily <- df %>%
    group_by(date_local, site_number) %>%
    summarise(
      pm25_mean = mean(pm25_ugm3, na.rm = TRUE),
      pm25_max  = max(pm25_ugm3,  na.rm = TRUE),
      hours     = sum(!is.na(pm25_ugm3)),
      .groups   = "drop"
    )
  
  out_daily <- sprintf("pm25_philadelphia_daily_%d.csv", YEAR)
  write_csv(daily, out_daily)
  cat(sprintf("  Saved → %s\n", out_daily))
  
}