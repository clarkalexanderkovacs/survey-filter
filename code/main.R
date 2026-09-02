# =============================================================================
# Script:  main.R
# Author:  Sören Harrs
# Date:    2026-04-01
#
# Purpose: Imports the raw Qualtrics Excel export,
#          merges tracker output from clean_tracker.R, applies exclusion
#          criteria and data quality flags, and writes all outputs used in
#          the analysis. An equivalent Stata implementation is in main.do.
#
# Run AFTER clean_tracker.R — tracker.xlsx must exist before running this.
#
# Sections:
#   0. Settings [VERIFY]
#   1. Import data and define exclusion criteria
#   2. Merge tracker data
#   3. Define data quality flags
#   4. Save datasets
#   5. Exports
#
#
# Outputs (written to data/):
#   main.RData              — analysis dataset; excluded observations removed
#   all.RData               — full dataset with exclusion flags retained
#
# Outputs (written to output/):
#   keep_ids.xlsx           — participant IDs passing all checks (two-stage procedure)
#   bonus_ids.xlsx          — participant IDs and bonus amounts from dictator game
#   data_quality_report.txt — plain-text data quality report
#   codebook.xlsx          — variable-level codebook for df_main
# =============================================================================



# =============================================================================
# 0.  SETTINGS
# =============================================================================

packages <- c("readxl", "dplyr", "openxlsx", "stringr", "lubridate")
installed <- packages %in% rownames(installed.packages())
if (any(!installed)) install.packages(packages[!installed])

library(readxl)
library(dplyr)
library(openxlsx)
library(stringr)
library(lubridate)


# =============================================================================
# VERIFY — check that these are correct for your dataset. Adjust if needed.
#
# Defaults match standard Prolific setup using Mission_Possible_Baseline_Survey.qsf
# =============================================================================

# [1] Working directory 
#     Inherited from clean_tracker.R if run in the same session. 
#     Only set this if running main.R standalone.

# setwd(".../mission_possible_code") 

# [2] Raw Qualtrics Excel export 
#     Inherited from clean_tracker.R if run in the same session. 
#     Only set this if running main.R standalone.

# input_raw <- "data raw/<filename>.xlsx"
# input_raw       # Verify raw data path

# [3] Define platform identifier
platform <- "prolific"

# [4] Identify name of the participant ID in the raw export
participant_id <- "prolific_id"

# [5] Identify column names for key survey variables
#     CHECK "output/qualtrics_variable_list.txt" or your raw data export.
#     Defaults match v3.qsf.

text       <- "colors"        # open text question for typing checks
ip_address <- "ip_address" # IP address variable (e.g. "IPAddress")

# Attention check (section 3.1): the color free-text answer must contain both
# "red" and "brown". Adjust the logic in section 3.1 if your check differs.

# Ranking check (section 3.2): the "video" rank-order question. Qualtrics names
# rank-order columns by CHOICE ID, not by position, so the columns are
# video_5 / video_7 / video_8 / video_9 / video_10. Set the expected ranks in
# q20_correct in section 3.2. The same ranks are kept in VIDEO_CORRECT in
# code/make_testdata.py -- update both together.

# =============================================================================
# OPTIONAL — leave as-is unless you have a reason to change
# =============================================================================

# Tracker data (output of clean_tracker.R)
tracker_path  <- "data/tracker.xlsx"

# Output datasets
output_main     <- "data/main.RData"
output_all      <- "data/all.RData"

# Export: IDs of those who passed all main checks (for two-stage procedure)
keep_ids_out  <- "output/keep_ids.xlsx"

# Export: Data quality report output path (set to NULL to skip)
dq_report_out <- "output/data_quality_report.txt"

# Export: Per-respondent pass/fail table for the five main checks (NULL to skip)
checks_out    <- "output/checks.xlsx"

# Export: Codebook (set codebook_out to NULL to skip)
codebook_out    <- "output/codebook.xlsx"
codebook_labels <- NULL



# =============================================================================
# =============================================================================
# 1.  IMPORT DATA AND DEFINE EXCLUSION CRITERIA
# =============================================================================
# =============================================================================

# Read the raw export. A Qualtrics CSV export carries THREE header rows
# (variable names / question text / ImportId); an XLSX export carries two.
# read.csv and read_excel both consume row 1 as the names, so the number of
# leftover header rows to drop differs by format.
if (grepl("\\.csv$", input_raw, ignore.case = TRUE)) {
  df     <- read.csv(input_raw, colClasses = "character",
                     check.names = FALSE, fileEncoding = "UTF-8")
  n_drop <- 2L   # question text + ImportId
} else {
  df     <- read_excel(input_raw, sheet = "Sheet0")
  n_drop <- 1L   # question text
}

# Drop the remaining Qualtrics header row(s)
df <- df[-seq_len(n_drop), ]


# Parse date variables. Try text formats first; fall back to Excel serial number.
date_cols <- c("StartDate", "EndDate", "RecordedDate")
df <- df %>% mutate(across(all_of(date_cols), ~ {
  parsed <- suppressWarnings(
    parse_date_time(.x, orders = c("mdy HM", "mdy HMS", "Ymd HMS", "Ymd HM"))
  )
  if (all(is.na(parsed))) {
    as.POSIXct((as.numeric(.x) - 25569) * 86400, origin = "1970-01-01", tz = "UTC")
  } else {
    parsed
  }
}))
df$t <- df$RecordedDate

# Destring numeric variables (equivalent to Stata's destring _all, replace)
# read_excel types all columns as character when the Qualtrics description row
# is present. Convert any column that is entirely numeric-looking to numeric.
df <- df %>% mutate(across(where(is.character), ~ {
  num <- suppressWarnings(as.numeric(.x))
  if (all(is.na(num) == is.na(.x))) num else .x
}))

# Sanitise variable names: remove characters invalid in Stata variable names
# (spaces, parentheses, #, etc.) — matches Stata's import behaviour.
# E.g. "Duration (in seconds)" -> "Durationinseconds",
#      "metadata_Operating System" -> "metadata_OperatingSystem",
#      "Last Seen Flow Element ID" -> "LastSeenFlowElementID"
names(df) <- gsub("[^a-zA-Z0-9_]", "", names(df))

# Verify that columns configured in settings [4] and [5] exist in the imported data
required_cols <- c(participant_id, text)
missing_cols  <- setdiff(required_cols, names(df))
if (length(missing_cols) > 0) {
  stop(sprintf(
    "Column(s) not found in the imported data:\n  %s\nCheck settings [4]/[5] and verify against data/qualtrics_variable_list.txt",
    paste(missing_cols, collapse = ", ")
  ))
}

# Add study identifier
df$study <- platform
df$day_of_month <- as.integer(day(df$t))
df$month        <- as.integer(month(df$t))

# --------------------------------------------------------------------------- #
# Define exclusion flag. Observations are only dropped before saving the final
# dataset so that all raw data is preserved in intermediate files.
# --------------------------------------------------------------------------- #

df$exclusion <- 0L

# Incomplete surveys
df$exclusion[df$Finished != "True"] <- 1L

# Survey previews
df$exclusion[df$Status != "IP Address"] <- 1L

# Pilot data identified by dates (uncomment and adjust as needed)
# df$exclusion[df$month == 8] <- 1L

# --------------------------------------------------------------------------- #
# Flag repeated platform IDs among completed responses
# --------------------------------------------------------------------------- #

df$participant_id <- df[[participant_id]]

# Within each study-exclusion-participant_id group, sort by recorded time and
# flag every observation after the first (i.e. the later duplicate entries).
df <- df %>%
  arrange(study, exclusion, participant_id, t) %>%
  group_by(study, exclusion, participant_id) %>%
  mutate(flag_id = as.integer(row_number() > 1)) %>%
  ungroup()

df$exclusion[df$flag_id == 1L & df$Finished == "True"] <- 1L

# Check number of completed and excluded observations
table(df$exclusion)



# =============================================================================
# =============================================================================
# 2.  MERGE TRACKER DATA
# =============================================================================
# =============================================================================

# Standardise ResponseId to lowercase (matches tracker.xlsx key)
df <- df %>% rename(responseid = ResponseId)

tracker <- read_excel(tracker_path, sheet = "Sheet1")

# Only join tracker columns not already present in df 
tracker_cols <- c("responseid", setdiff(names(tracker), names(df)))
df <- left_join(df, tracker[, tracker_cols], by = "responseid")

# Drop unmatched observations from tracker file (should not occur)
# Note: left_join keeps only rows from df, so unmatched tracker rows are
# automatically excluded (equivalent to Stata's drop if _merge == 2).


# =============================================================================
# =============================================================================
# 3.  DEFINE DATA QUALITY FLAGS
# =============================================================================
# =============================================================================

# ============================================================================ #
# 3.0  STANDARDISE KEY VARIABLE NAMES
# ============================================================================ #

#if (video %in% names(df)) names(df)[names(df) == video] <- "video"
#if (text  %in% names(df)) names(df)[names(df) == text]  <- "text"
if (!"text" %in% names(df) && text %in% names(df)) df$text <- df[[text]]


# ============================================================================ #
# 3.1  INATTENTION FLAG
# ============================================================================ #

# Classic attention check (Qualtrics survey questions)
q22 <- tolower(as.character(df$text))
df$ok_attention <- as.integer(
  !is.na(q22) & grepl("red", q22, fixed = TRUE) & grepl("brown", q22, fixed = TRUE)
)
df$flag_attention <- 1L - df$ok_attention
# df$ok_attention  <- as.integer(
#   !is.na(df[["attention1_3"]]) & df[["attention1_3"]] == "Strongly Disagree" &
#   !is.na(df[["attention1_4"]]) & df[["attention1_4"]] == "Strongly Agree"
# )
# df$flag_attention <- 1L - df$ok_attention


# ============================================================================ #
# 3.2  VIDEO CHECK FLAG
# ============================================================================ #

q20_correct <- c(video_5 = 5, video_7 = 2, video_8 = 3, video_9 = 1, video_10 = 4)

if (anyNA(q20_correct)) {
  warning("q20_correct not set — ok_video defaults to 1 (check disabled)")
  df$ok_video <- 1L
} else {
  # Unanswered rank cells arrive as "" from a CSV export, which as.numeric()
  # turns into NA. Coerce first, then test, so a blank counts as a FAILED check
  # rather than propagating NA into ok_video and all_passed.
  ok <- Reduce(`&`, lapply(names(q20_correct), function(v) {
    x <- suppressWarnings(as.numeric(df[[v]]))
    !is.na(x) & x == q20_correct[[v]]
  }))
  df$ok_video <- as.integer(ok)
}
df$flag_video <- 1L - df$ok_video

# if (!"video" %in% names(df)) df$video <- NA_character_
# df$video <- as.character(df$video)

# # Strip spaces and punctuation before comparing against expected answer
# df$video_clean <- gsub("[[:punct:][:space:]]", "", df$video)
# df$ok_video    <- as.integer(!is.na(df$video_clean) & df$video_clean == "3169")
# df$flag_video  <- 1L - df$ok_video


# ============================================================================ #
# 3.3  OPEN TEXT RESPONSE FLAGS
# ============================================================================ #

# --- No keystrokes recorded --------------------------------------------- #

# key_log_num: recode missing values to 0 (no keys pressed)
df$key_log_num[is.na(df$key_log_num)] <- 0

df$flag_nokeys <- as.integer(df$key_log_num == 0)
df$ok_nokeys   <- 1L - df$flag_nokeys

# --- Paste event -------------------------------------------------------- #

# Column name is constructed from text to match the tracker naming convention.
paste_col <- paste0(text, "_paste")
if (paste_col %in% names(df)) {
  df$flag_paste <- as.integer(!is.na(df[[paste_col]]) & df[[paste_col]] == 1)
} else {
  warning(paste0(paste_col, " not found in tracker — flag_paste set to 0"))
  df$flag_paste <- 0L
}
df$ok_paste <- 1L - df$flag_paste

# --- Large input jump event --------------------------------------------- #
# A jump >= 50 characters suggests text was inserted without typing.

df$flag_inputjump <- as.integer(
  !is.na(df$key_log_inputjump)     & df$key_log_inputjump == 1 &
  !is.na(df$key_log_inputjump_max) & df$key_log_inputjump_max >= 50
)
df$ok_inputjump <- 1L - df$flag_inputjump

# --- Unusually fast typing speed ---------------------------------------- #
# Threshold: median inter-keystroke interval <= 75 ms.
# Observations with only one or zero keys have missing median and are flagged as well.

df$flag_speed <- as.integer(is.na(df$key_log_median) | df$key_log_median <= 75)
df$ok_speed   <- 1L - df$flag_speed

# --- Typed-text flag ---------------------------------------------------- #
# This composite flag combines paste, input jump, and no-keystroke
# indicators to improve detection coverage.

df$flag_typed <- as.integer(df$flag_paste == 1 | df$flag_inputjump == 1 | df$flag_nokeys == 1)
df$ok_typed   <- 1L - df$flag_typed

# --- Typed with typical speed ------------------------------------------- #
# Requires both the composite typed flag and the speed flag to pass.

df$ok_typedspeed <- df$ok_typed * df$ok_speed


# ============================================================================ #
# 3.4  DUPLICATE IP ADDRESS FLAG
# ============================================================================ #

df <- df %>%
  group_by(study, exclusion, ip_address) %>%
  mutate(flag_ip = as.integer(n() > 1)) %>%
  ungroup()
df$ok_ip <- 1L - df$flag_ip


# ============================================================================ #
# 3.5  SUMMARY FLAG: ALL MAIN CHECKS PASSED
# ============================================================================ #

df$all_passed <- as.integer(
  df$ok_attention  == 1 &
  df$ok_video      == 1 &
  df$ok_typed      == 1 &
  df$ok_typedspeed == 1 &
  df$ok_ip         == 1
)



# =============================================================================
# =============================================================================
# 4.  SAVE DATASETS
# =============================================================================
# =============================================================================

# Sort by recorded time (matches Stata sort order for 1:1 comparison)
df <- df %>% arrange(t)

# Save full dataset (including excluded observations)
save(df, file = output_all)

# Drop excluded observations
df_main <- df %>% filter(exclusion == 0)

# Drop useless Qualtrics variables
df_main <- df_main %>%
  select(-any_of(c("RecipientLastName", "RecipientFirstName", "RecipientEmail",
                   "ExternalReference", "UserLanguage"))) %>%
  select(-matches("_FirstClick|_LastClick|_PageSubmit|_ClickCount"))

# Save cleaned main dataset
save(df_main, file = output_main)

cat(sprintf("all.RData:  %d rows\n", nrow(df)))
cat(sprintf("main.RData: %d rows (exclusion == 0)\n", nrow(df_main)))



# =============================================================================
# =============================================================================
# 5.  EXPORTS
# =============================================================================
# =============================================================================

# ============================================================================ #
# 5.1  TWO-STAGE PROCEDURE: PARTICIPANT IDs PASSING ALL CHECKS
# ============================================================================ #

# Export participant IDs of those who passed all main checks
# (used to invite participants to stage 2)

keep_ids_df <- df_main %>%
  filter(all_passed == 1) %>%
  select(participant_id)

cat(sprintf("keep_ids: %d participants passed all checks\n", nrow(keep_ids_df)))
write.xlsx(keep_ids_df, keep_ids_out, rowNames = FALSE)

# ============================================================================ #
# 5.3  CODEBOOK
# ============================================================================ #

if (!is.null(codebook_out)) {
  n_main <- nrow(df_main)

  cb_rows <- lapply(names(df_main), function(v) {
    col       <- df_main[[v]]
    type      <- class(col)[1]
    n_valid   <- sum(!is.na(col))
    n_missing <- sum(is.na(col))
    pct_miss  <- if (n_main > 0) round(100 * n_missing / n_main, 1) else NA_real_

    values <- if (is.numeric(col) || inherits(col, "POSIXct")) {
      if (n_valid == 0) {
        "all missing"
      } else {
        rng <- range(col, na.rm = TRUE)
        sprintf("[%.6g, %.6g]", rng[1], rng[2])
      }
    } else {
      u <- sort(unique(as.character(col[!is.na(col)])))
      if (length(u) == 0) {
        "all missing"
      } else if (length(u) <= 12) {
        paste(u, collapse = " | ")
      } else {
        sprintf("%d unique values", length(u))
      }
    }

    label <- if (!is.null(codebook_labels) && v %in% names(codebook_labels)) {
      codebook_labels[[v]]
    } else {
      ""
    }

    data.frame(variable = v, type = type, n_valid = n_valid,
               n_missing = n_missing, pct_missing = pct_miss,
               values = values, label = label, stringsAsFactors = FALSE)
  })

  cb_df <- do.call(rbind, cb_rows)
  write.xlsx(cb_df, codebook_out, rowNames = FALSE)
  cat(sprintf("Codebook written to: %s  (%d variables)\n", codebook_out, nrow(cb_df)))
}


# ============================================================================ #
# 5.4  DATA QUALITY REPORT
# ============================================================================ #

if (!is.null(dq_report_out)) {
  report_out <- dq_report_out
  source("code/data_quality_report.R")

  if (file.exists(report_out)) {
    cat("\n")
    cat(strrep("=", 80), "\n", sep = "")
    cat(strrep("=", 80), "\n", sep = "")
    cat(paste(readLines(report_out, warn = FALSE), collapse = "\n"), "\n", sep = "")
    cat(strrep("=", 80), "\n", sep = "")
  } else {
    warning(sprintf("Report file not found after generation: %s", report_out))
  }
}


# =============================================================================
# =============================================================================
# 6.  PER-RESPONDENT CHECK TABLE
# =============================================================================
# =============================================================================

# One row per respondent (all respondents, including exclusion == 1), with the
# five main data checks coded 1 = passed, 0 = failed.
#
#   pass_video      Ranking question answered in the correct order.
#   pass_attention  Open-text colour answer contains both "red" and "brown".
#   pass_typing     Typing pattern is consistent with manual typing: no paste
#                   event, no input jump >= 50 characters, and at least one
#                   keystroke recorded. Catches copy-paste, drag-and-drop and
#                   fully automated insertion.
#   pass_speed      Median inter-keystroke interval is ABOVE 75 ms, i.e. typing
#                   is not implausibly fast. Respondents with fewer than two
#                   keystrokes have no median and fail this check.
#   pass_ip         IP address is not shared with another respondent.
#
# participant_id is carried through so rows can be matched back to the data;
# the five check columns follow it.

if (!is.null(checks_out)) {
  df_checks <- df %>%
    transmute(
      !!participant_id := .data[[participant_id]],
      pass_video     = ok_video,
      pass_attention = ok_attention,
      pass_typing    = ok_typed,
      pass_speed     = ok_speed,
      pass_ip        = ok_ip
    )

  write.xlsx(df_checks, checks_out, rowNames = FALSE)

  check_cols <- c("pass_video", "pass_attention", "pass_typing",
                  "pass_speed", "pass_ip")
  cat(sprintf("\nchecks.xlsx: %d respondents\n", nrow(df_checks)))
  for (v in check_cols) {
    cat(sprintf("  %-15s passed %d / %d\n",
                v, sum(df_checks[[v]] == 1), nrow(df_checks)))
  }
  cat(sprintf("  %-15s %d / %d\n", "all five",
              sum(rowSums(df_checks[check_cols]) == length(check_cols)),
              nrow(df_checks)))
}
