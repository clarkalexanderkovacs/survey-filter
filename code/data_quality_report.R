# =============================================================================
# Script:  data_quality_report.R
# Author:  Sören Harrs
# Date:    2026-03-20
#
# Purpose: R equivalent of data_quality_report.do. Produces a plain-text
#          data quality report from all.RData (output of main.R).
#
# Run AFTER main.R — data/all.RData must exist before running this.
#
# Input:   data/all.RData
# Output:  output/data_quality_reportR.txt
# =============================================================================

if (!exists("report_out")) {
  report_out <- "output/data_quality_reportR.txt"
}

# [TYPING-CHECKS] inherited from main.R when sourced; default off standalone.
if (!exists("typing_checks")) typing_checks <- FALSE


input_all <- "data/all.RData"
if (!exists("df")) {
  load(input_all)   # loads df
}


# =============================================================================
# Helper functions
# =============================================================================

n_where <- function(cond) sum(cond, na.rm = TRUE)

pct <- function(n, total) n / total * 100

# Format a flag-table row: label (left-aligned), failed count+%, passed count+%
fmt_row <- function(label, n_fail, n_total) {
  n_pass <- n_total - n_fail
  sprintf("  %-28s  %5d  (%4.1f%%)     %5d  (%5.1f%%)",
          label, n_fail, pct(n_fail, n_total), n_pass, pct(n_pass, n_total))
}

# Format an exclusion row: label (left-aligned in 44 chars), count, %
fmt_excl <- function(label, n, total) {
  sprintf("    %-44s %5d  (%4.1f%%)", label, n, pct(n, total))
}


# =============================================================================
# 1. Compute statistics
# =============================================================================

N      <- nrow(df)
n_incl <- n_where(df$exclusion == 0)
n_excl <- n_where(df$exclusion == 1)

n_incomplete <- n_where(df$Finished != "True")
n_preview    <- n_where(df$Status   != "IP Address")
# [NO-PII] No duplicate-platform-ID count: the Prolific ID is not collected.

platform <- df$study[1]
date_min <- format(min(df$t, na.rm = TRUE), "%d %b %Y")
date_max <- format(max(df$t, na.rm = TRUE), "%d %b %Y")

# --- Attrition (real incomplete responses only) ---

df_drop <- df[df$Finished != "True" & df$Status == "IP Address", ]
n_drop  <- nrow(df_drop)

n_d0  <- n_where(df_drop$Progress == 0)
n_d1  <- n_where(df_drop$Progress >= 1  & df_drop$Progress < 25)
n_d25 <- n_where(df_drop$Progress >= 25 & df_drop$Progress < 50)
n_d50 <- n_where(df_drop$Progress >= 50 & df_drop$Progress < 75)
n_d75 <- n_where(df_drop$Progress >= 75)

pct_drop <- function(n) if (n_drop > 0) pct(n, n_drop) else 0

# --- Quality flags (analysis sample only) ---

df_a <- df[df$exclusion == 0, ]
N_a  <- nrow(df_a)

n_att    <- n_where(df_a$flag_attention == 1)
n_vid    <- n_where(df_a$flag_video     == 1)
n_typed  <- n_where(df_a$flag_typed     == 1)
n_ts     <- n_where(df_a$ok_typedspeed  == 0)
# [NO-PII] No duplicate-IP count: the IP address is not collected.
n_nokeys <- n_where(df_a$flag_nokeys    == 1)
n_paste  <- n_where(df_a$flag_paste     == 1)
n_jump   <- n_where(df_a$flag_inputjump == 1)
n_speed  <- n_where(df_a$flag_speed     == 1)

n_pass <- n_where(df_a$all_passed == 1)
n_fail <- N_a - n_pass

# --- Tab switches (analysis sample only) --- [TAB-SWITCHES]

tab_pages <- sub("_tabCount$", "", grep("_tabCount$", names(df_a), value = TRUE))

tab_header <- sprintf("  %-16s %5s  %14s  %8s  %8s",
                      "Question", "N", "Switched >= 1", "Switches", "Median s")

tab_rows <- vapply(tab_pages, function(p) {
  n_sw   <- df_a[[paste0(p, "_tabCount")]]
  durs   <- as.character(df_a[[paste0(p, "_tabDurations")]])
  secs   <- as.numeric(unlist(strsplit(durs[!is.na(durs)], "|", fixed = TRUE)))
  n_seen <- sum(!is.na(n_sw))
  n_any  <- n_where(n_sw > 0)
  sprintf("  %-16s %5d  %5d (%5.1f%%)  %8d  %8s",
          p, n_seen, n_any, if (n_seen > 0) pct(n_any, n_seen) else 0,
          as.integer(sum(n_sw, na.rm = TRUE)),
          if (length(secs) > 0) sprintf("%.1f", median(secs)) else "-")
}, character(1), USE.NAMES = FALSE)

if (length(tab_rows) == 0) {
  tab_rows <- "  No tab-switch columns found (data collected with the old tracker?)."
}

# =============================================================================
# 2. Build report lines
# =============================================================================

S1 <- strrep("=", 65)
S2 <- strrep("-", 65)
S3 <- paste0("  ", strrep("-", 58))

# [TYPING-CHECKS]

if (typing_checks) {
  typing_main  <- c(fmt_row("Typed text",               n_typed, N_a),
                    fmt_row("Typed with typical speed", n_ts,    N_a))
  typing_detail <- c(fmt_row("Keystrokes > 0",            n_nokeys, N_a),
                     fmt_row("No paste event",            n_paste,  N_a),
                     fmt_row("No input jump >= 50 chars", n_jump,   N_a),
                     fmt_row("Typing speed > 75 ms",      n_speed,  N_a),
                     "",
                     "  Note: Typed text = keystrokes > 0 AND no paste AND no input jump.",
                     "        Typed with typical speed additionally requires speed > 75 ms.")
} else {
  typing_main   <- "  Typed text / typing speed        [DISABLED — no open-text question]"
  typing_detail <- c("  Typing sub-checks are disabled because the colours question",
                     "  is a checkbox question with no free-text answer.")
}

lines <- c(

  S1,
  "DATA QUALITY REPORT",
  S1,
  sprintf("Generated : %s", format(Sys.time(), "%d %b %Y  %H:%M:%S")),
  sprintf("Platform  : %s", platform),
  sprintf("Date range: %s \u2013 %s", date_min, date_max),
  sprintf("Input     : %s", input_all),
  "",

  # --- 1. Sample Overview ---
  S2,
  "1.  SAMPLE OVERVIEW",
  S2,
  "",
  sprintf("  %-46s %6d", "Total observations (raw)", N),
  "",
  "  Exclusion criteria (may overlap across rows):",
  fmt_excl("Incomplete survey  (Finished != True)",   n_incomplete, N),
  fmt_excl("Survey preview     (Status  != IP Addr)", n_preview,    N),
  "",
  fmt_excl("Total excluded  (exclusion == 1)",        n_excl, N),
  fmt_excl("Analysis sample (exclusion == 0)",        n_incl, N),
  "",

  # --- 2. Survey Attrition ---
  S2,
  sprintf("2.  SURVEY ATTRITION  (N = %d incomplete real responses)", n_drop),
  S2,
  "",
  "  Progress at drop-off:",
  "",
  "    Range                          N    % of incomplete",
  "    ------------------------------------------------",
  sprintf("    0%%  (never left landing page) %5d  (%4.1f%%)", n_d0,  pct_drop(n_d0)),
  sprintf("    1  \u2013 24%%                      %5d  (%4.1f%%)", n_d1,  pct_drop(n_d1)),
  sprintf("    25 \u2013 49%%                      %5d  (%4.1f%%)", n_d25, pct_drop(n_d25)),
  sprintf("    50 \u2013 74%%                      %5d  (%4.1f%%)", n_d50, pct_drop(n_d50)),
  sprintf("    75 \u2013 99%%                      %5d  (%4.1f%%)", n_d75, pct_drop(n_d75)),
  "    ------------------------------------------------",
  sprintf("    Total                         %5d", n_drop),
  "",

  # --- 3. Main Data Quality Flags ---
  S2,
  sprintf("3.  MAIN DATA QUALITY FLAGS  (N = %d)", N_a),
  S2,
  "",
  "  Check                            Failed              Passed",
  S3,
  fmt_row("Attention check",           n_att,    N_a),
  fmt_row("Video check",               n_vid,    N_a),
  typing_main,
  S3,
  "",
  typing_detail,
  "",

  # --- 4. Summary ---
  S2,
  "4.  SUMMARY",
  S2,
  "",
  sprintf("  %-44s %5d  (%4.1f%%)", "All main checks passed (all_passed == 1)", n_pass, pct(n_pass, N_a)),
  sprintf("  %-44s %5d  (%4.1f%%)", "At least one check failed",                n_fail, pct(n_fail, N_a)),
  "",

  # --- 5. Tab Switches --- [TAB-SWITCHES]
  S2,
  sprintf("5.  TAB SWITCHES  (N = %d)", N_a),
  S2,
  "",
  tab_header,
  S3,
  tab_rows,
  S3,
  "",
  "  N = respondents who reached the page. Switched >= 1 = left the survey tab",
  "  at least once on that page. Median s = median length of all switches there.",
  "",
  S1

)

writeLines(lines, report_out, useBytes = FALSE)
cat(sprintf("Report written to: %s\n", report_out))
