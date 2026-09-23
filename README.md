## Mission Possible: Clean Data Quality Trackers

This repository constructs data quality metrics from raw Qualtrics survey exports. 

The tracking data is cleaned, merged with the survey responses, and used to define five main data quality flags. The scripts export analysis-ready datasets, participant ID lists for the two-stage procedure, and a plain-text data quality report.

The default values are set to work with our [Mission_Possible_Survey_V1.qsf](https://github.com/survey-data-quality-lab/mission-possible/tree/03819bb4e7fdb9259a7d82d04e53e38ecc55b209/qualtrics%20survey%20file) survey. For testing, an example .xlsx file and .qsf file are provided.

You can adapt it to your own Qualtrics survey by following the instructions below. 

See https://github.com/survey-data-quality-lab/mission-possible for more information. 

**Requirements:** R ≥ 4.0 · Python 3 (only to regenerate the survey file)

---

## Non-identifiable branch <!-- [NO-PII] -->

This branch of `mission-possible-code-main` collects **no personally identifiable information**. The survey to deploy is `qualtrics survey file/v5_noPII.qsf`, generated from `v5.qsf` by `code/make_nopii_qsf.py`. Follow `TODO_noPII.md` to import it and verify the settings.

**Not collected:** IP address, location (latitude/longitude), Prolific ID (`prolific_id`, `PROLIFIC_PID`, `STUDY_ID`, `SESSION_ID`), device fingerprint (FingerprintJS `visitorId`/`requestId`, browser/OS/resolution metadata), keystroke log. *Anonymize responses* is switched on in Qualtrics.

**Consequences:**

- Rows are keyed by the Qualtrics `ResponseId`. `keep_ids.xlsx`, `checks.xlsx` and `tab_switches.xlsx` list ResponseIds, not Prolific IDs, so passing respondents cannot be re-invited for a stage 2.
- The **duplicate Prolific ID** exclusion and the **unique IP address** check are removed. Prolific itself stops a participant from taking a study twice.
- The remaining checks are the attention check and the video check. The typing checks remain switched off, and re-enabling them would need a keystroke logger in the survey.
- `main.R` drops any identifying column it still finds in a raw export (setting [5]) and warns if any of them held data.
- Only the R pipeline is maintained. `main.do` and `data_quality_report.do` are out of date and still expect the IP address and Prolific ID.

---

## Folder structure

```
data raw/                          ← Qualtrics Excel export (.xlsx)
qualtrics survey file/             ← Qualtrics survey file (.qsf)
code/                              ← scripts listed below
data/                              ← cleaned datasets (written by scripts)
output/                            ← reports, codebook, ID lists (written by scripts)
```

---

## Scripts

| File | Role |
|---|---|
| `clean_tracker.R` | Parses tracker JSON and key log JSON; writes `tracker.xlsx` |
| `qsf_extract.R` | Extracts survey questions (QID) and export labels from the `.qsf` file; runs as part of `clean_tracker.R` |
| `main.R` | Main cleaning script; merges tracker output, defines data quality checks, and writes all outputs including the data quality report |
| `data_quality_report.R` | Standalone script to regenerate the data quality report from `all.RData` |
| `make_nopii_qsf.py` | Builds `v5_noPII.qsf` from `v5.qsf` by removing everything that collects identifying data |
| `main.do` / `data_quality_report.do` | Stata versions. **Not maintained in this fork.** |

---

## Workflow

### Step 0 — Download or clone the repository

Download or clone this repository to your computer, then open the project folder locally.

### Step 1 — Download files from Qualtrics

1. Export survey responses as an **Excel (.xlsx)** file (use **Export Labels**), and place it in `data raw/`.
2. Export the **Qualtrics survey (.qsf)** file (Survey → Tools → Import / Export → Export survey) and place it in `qualtrics survey file/`.

Note: make sure to export these two files at about the same time so there are no inconsistencies. 

### Step 2 — Run the R clean tracker script

Open `clean_tracker.R` and update the required settings at the top (section 0):

- `setwd(...)` — path to the project root         **[UPDATE]**
- `input_raw` — path to the raw Excel export      **[UPDATE]**
- `qsf_path` — path to the `.qsf` file            **[UPDATE]**

Then run the script. It calls `qsf_extract.R` automatically and writes the following outputs:

| File | Folder | Contents |
|---|---|---|
| `tracker.xlsx` | `data/` | Cleaned tracker and keystroke data, including per-page tab-switch counts and lengths (`<page>_tabCount`, `<page>_tabTime`, `<page>_tabDurations`); merged into main dataset in Step 3 |
| `tracker_cleaning_report.txt` | `output/` | How many tracker and key log rows were parsed, salvaged, or flagged |
| `qualtrics_variable_list.txt` | `output/` | Human-readable table of all survey questions and their Qualtrics export column names; constructed by `qsf_extract.R`  |
| `qid_map.R` | `code/` | Machine-readable table of all survey questions and their Qualtrics export column names; constructed by `qsf_extract.R` |

### Step 3 — Run the main cleaning script

Open `main.R` and verify the settings at the top (section 0):

- If run in the same session as `clean_tracker.R`, the working directory and `input_raw` path are inherited automatically.
- Settings [3] to [5]                                 **[VERIFY]**

(The Stata script `main.do` is not maintained in this fork.)

The script imports the raw survey data, drops any identifying columns, merges `tracker.xlsx`, applies exclusion criteria and data quality flags, and writes the following outputs:

**Written to `data/`:**

| File | Contents |
|---|---|
| `main.RData` | Cleaned dataset restricted to participants who pass all exclusion criteria |
| `all.RData` | Full dataset including excluded participants, with exclusion and quality flags retained |

**Written to `output/`:**

| File | Contents |
|---|---|
| `keep_ids.xlsx` | ResponseIds of those who pass all main checks |
| `checks.xlsx` | One row per respondent: ResponseId and pass/fail for each main check |
| `data_quality_report.txt` | Plain-text data quality report covering exclusion and data quality metrics |
| `codebook.xlsx` | Variable-level codebook for the main dataset |
| `tab_switches.xlsx` | One row per respondent × question: number of tab switches and the length of each in seconds |


---

## Notes

- `tracker.xlsx` must exist before running `main.R`. Always run `clean_tracker.R` first.
- Typing-based checks (speed, paste, input jump) operate on the `key_log` column, which corresponds to the main open-text response. Multiple key log trackers can be processed simultaneously by adding entries to the `keylogs` list in `clean_tracker.R` section 0. But only `key_log` is used for constructing our main data quality checks in `main.do` and `main.R`.
- Tab switches are recorded per survey page by the tracker script in the survey header, so put each question you want to measure on its own page. A switch is counted whenever the survey page becomes hidden: the respondent switches to another browser tab, minimises the browser, locks the screen, or switches to another app on a phone. In Chrome, another window fully covering the browser may also count. Switching to another application while the survey stays visible on screen is not recorded. Responses collected with the older tracker script have no tab data, so their tab columns are NA. <!-- [TAB-SWITCHES] -->
