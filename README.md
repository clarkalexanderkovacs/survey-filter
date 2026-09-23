<details>
  <summary><b>What's New (9.21.26) (Click to expand)</b></summary>

  ### No Personally-Identifying Information version
  - To access this version, click on the drop-down menu on the top left of the screen that says "main" and select "No Personally-Identifiable Information"
  - I created a version of the survey that collects no personally-identifiable information. The following information is no longer collected: Prolific ID, study_ID, session_ID, IP address, all device fingerprinting metadata (e.g., browser metadata, operating system, etc)

</details>

<details>
  <summary><b>What's New (9.14.26) (Click to expand)</b></summary>

  ### Color attention check
  - The color attention check was reverted to a multiple choice tick-box format. clean_tracker.R, main.R, and data_quality_report.R were updated to reflect this change.
  - In these files, a switch was created to enable later reversion to a text-entry based attention check. 

  ### Fixed
  - Decreased the icon size for the video attention check.

  ### Example output from main.R: 
  - Below is an example of tab switch analytics that will now be included in every run of main.R
  ```
-----------------------------------------------------------------
5.  TAB SWITCHES  (N = 2)
-----------------------------------------------------------------

  Question             N   Switched >= 1  Switches  Median s
  ----------------------------------------------------------
  consent              2      2 (100.0%)         2       2.7
  prolific_id          2      0 (  0.0%)         0         -
  captcha              2      0 (  0.0%)         0         -
  colors               2      2 (100.0%)         2      30.5
  video                2      1 ( 50.0%)         1       3.6
  Q23                  1      0 (  0.0%)         0         -
  Q24                  1      0 (  0.0%)         0         -
  ----------------------------------------------------------

  N = respondents who reached the page. Switched >= 1 = left the survey tab
  at least once on that page. Median s = median length of all switches there.

  ```

### More specific data collected:

| prolific_id | exclusion | question | n_tab_switches | tab_switch_lengths_s | total_tab_time_s |
|---:|---:|---|---:|---|---:|
| 1 | 0 | consent | 1 | 3.83 | 3.83 |
| 1 | 0 | prolific_id | 0 | | 0 |
| 1 | 0 | captcha | 0 | | 0 |
| 1 | 0 | colors | 1 | 7.91 | 7.91 |
| 1 | 0 | video | 1 | 3.6 | 3.6 |
| 1 | 0 | Q23 | 0 | | 0 |
| 2 | 0 | consent | 1 | 1.52 | 1.52 |
| 2 | 0 | prolific_id | 0 | | 0 |
| 2 | 0 | captcha | 0 | | 0 |
| 2 | 0 | colors | 1 | 53 | 53 |
| 2 | 0 | video | 0 | | 0 |
| 2 | 0 | Q24 | 0 | | 0 |

  
</details>

## Survey Filter

This repository is adapted from a repository created for the paper **“Mission Possible: The Collection of High-Quality Online Data”**

To begin: 
1. [Read documentation on setting up the Qualtrics survey filter](/qualtrics%20survey%20file/README.md)
2. [Read documentation on using adapted code to extract and clean respondent data from Qualtrics export data](/code/README.md)

The following text includes helpful links and a map of the repository provided by Celebi et al.


## Related links

To run your own screening survey with minimal effort, we now provide new cleaning code (R and STATA) and a new Qualtrics survey file:

- **Cleaning Code (01/04/2026)** 
See the [mission-possible-code](https://github.com/survey-data-quality-lab/mission-possible-code/) Github respository.

- **Qualtrics Survey File (01/04/2026)** 
See [Mission_Possible_Survey_V1.qsf](qualtrics%20survey%20file/)

## What’s Inside?

- **Paper**  
  The working paper (PDF). See [`paper/`](paper/).  
  > If GitHub can’t preview the PDF, click **Download** to view it locally.

- **Tracking scripts for Qualtrics**  
  JavaScript code used in the survey to track behavior, keystrokes, and digital fingerprint. See [`trackers/`](trackers/) .

- **Qualtrics Survey Files**  
  Qualtrics survey with the tracking scripts. See [`qualtrics survey file/`](qualtrics%20survey%20file/).

- **Video attention check**  
  Code to generate your own version of the video-based attention check, plus example outputs. See [`attention-video/`](attention-video/).
  
- **Prompts**  
  The **simple** and **complex** agent prompts used in the paper. See [`prompts/`](prompts/).

## What's Coming? 

To track and compare data quality across online survey platforms over time, we are currently working on a 

- **Data Quality Hub for Online Surveys** - Researchers can submit their study results — the dashboard updates as new studies are added.

## Using this repository

1. Browse to the folder you need (e.g. `attention-video/`).
2. Open that folder’s own `README.md` for installation and usage.
3. Adapt the parameters to your own survey platform (Qualtrics, oTree, nodeGame).

