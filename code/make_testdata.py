"""
Script:  make_testdata.py

Purpose: Generate synthetic Qualtrics responses that match the REAL v3 export
         schema exactly, and merge them with the real responses in
         V3_TESTDATA.csv. The synthetic rows are engineered to trip each
         exclusion criterion and data quality flag exactly once, which the
         real responses do not cover.

Usage:   python code/make_testdata.py          (run from the repo root)
         requires: pip install openpyxl        (only for the optional .xlsx)

Input:   data raw/V3_TESTDATA.csv              (real responses; not modified)
Output:  data raw/V3_MERGED_TESTDATA.csv       (real + synthetic)

Schema is taken verbatim from V3_TESTDATA.csv: 47 columns, three header rows
(names / question text / ImportId), dates as 'YYYY-MM-DD HH:MM:SS', and the
rank-order columns named by CHOICE ID (video_5, video_7, video_8, video_9, video_10)
rather than by position.

Synthetic rows are identifiable by their ResponseId prefix (R_ok, R_att,
R_vid, R_pst, R_key, R_spd, R_jmp, R_ip, R_inc, R_prv, R_dup, R_trn, R_bad,
R_klt). Real responses all begin with a random Qualtrics suffix.

See the expected-results notes at the bottom of this file.
"""
import csv, json, datetime as dt, os

REAL_CSV = os.path.join("data raw", "V3_TESTDATA.csv")
OUT_CSV = os.path.join("data raw", "V3_MERGED_TESTDATA.csv")

# Correct video ranking, read off the real passing responses and matching the
# survey's own branch logic: choice 9 -> rank 1, 7 -> 2, 8 -> 3, 10 -> 4, 5 -> 5
VIDEO_CORRECT = {"video_5": 5, "video_7": 2, "video_8": 3, "video_9": 1, "video_10": 4}
VIDEO_WRONG = {"video_5": 1, "video_7": 2, "video_8": 3, "video_9": 4, "video_10": 5}

PASS_TEXT = "red and brown"

# Page sequence of the v3 flow, as it appears in real tracking_json payloads
PAGES = [
    (1, ["QID45", "QID43"]),   # Consent        -> tracker prefix 'consent'
    (2, ["QID47"]),            # Prolific ID    -> 'prolific_id'
    (3, ["QID21"]),            # Study Overview -> 'captcha'
    (4, ["QID50"]),            # Block 5        -> 'colors'
    (5, ["QID48"]),            # Block 4        -> 'video'
    (6, ["QID52"]),            # Block 7 (Q24)  -> 'Q24'
]

BASE_MS = 1788400000000


def tracking(paste_page=None, seed=0, n_pages=6):
    out, t = [], BASE_MS + seed * 900_000
    for page, qids in PAGES[:n_pages]:
        dur = 3 + (seed + page * 5) % 30
        out.append({
            "page": page,
            "question_ids": qids,
            "start_time": t,
            "time_on_page": dur,
            "mouse_moved": True,
            "mouse_move_count": 40 + (seed * 7 + page * 13) % 300,
            "click_count": (seed + page) % 3,
            "total_keys": 0,
            "paste_detected": (page == paste_page),
            "copy_detected": False,
            "tab_hidden": False,
            "window_blurred": False,
            "scroll_event_count": (seed + page) % 9,
            "event_log": ([{"event": "PASTE", "time": t + dur * 1000}]
                          if page == paste_page else []),
            "ts": t + dur * 1000,
        })
        t += dur * 1000 + 1200
    return json.dumps(out, separators=(",", ":"))


def keylog(text, gap=180, jump=None, seed=0):
    """Keystrokes for `text`. jump=(after_n_keys, size) inserts an INPUT_JUMP."""
    out, t = [], BASE_MS + seed * 900_000
    for i, ch in enumerate(text):
        wobble = ((seed * 31 + i * 17) % 60) - 30 if gap > 60 else ((seed + i) % 7) - 3
        t += gap + wobble
        out.append({"key": ch, "time": t})
        if jump and i + 1 == jump[0]:
            t += gap
            out.append({"key": "INPUT_JUMP", "time": t,
                        "jump": jump[1], "total": jump[1] + i + 1})
    return json.dumps(out, separators=(",", ":"))


def truncate(s, frac=0.62):
    return s[:int(len(s) * frac)]


# ---------------------------------------------------------------------------
# Read the real export -- header rows and data rows are preserved verbatim
# ---------------------------------------------------------------------------
with open(REAL_CSV, newline="", encoding="utf-8-sig") as f:
    real_rows = list(csv.reader(f))

COLS = real_rows[0]
HEADER = real_rows[:3]          # names / question text / ImportId
REAL_DATA = real_rows[3:]


def row(rid, pid, ip, *, colors=PASS_TEXT, video=None, klog=None, trk=None,
        finished="True", status="IP Address", progress=100, seed=0,
        visitor="synth_device_0001", day=3, hour=9, dur=430):
    video = VIDEO_CORRECT if video is None else video
    preview = status != "IP Address"
    start = dt.datetime(2026, 9, day, hour, 12, 0)
    end = start + dt.timedelta(seconds=dur)
    r = {c: "" for c in COLS}
    r.update({
        "StartDate": start.strftime("%Y-%m-%d %H:%M:%S"),
        "EndDate": end.strftime("%Y-%m-%d %H:%M:%S"),
        "RecordedDate": (end + dt.timedelta(seconds=1)).strftime("%Y-%m-%d %H:%M:%S"),
        "Status": status,
        "IPAddress": "" if preview else ip,
        "Progress": progress,
        "Duration (in seconds)": dur,
        "Finished": finished,
        "ResponseId": rid,
        "LocationLatitude": "41.3874",
        "LocationLongitude": "2.1686",
        "DistributionChannel": "preview" if preview else "anonymous",
        "UserLanguage": "EN",
        "Q_RecaptchaScore": "" if preview else "1",
        "Last Seen Flow Element ID": "FL_15",
        "metadata_Browser": "Chrome",
        "metadata_Version": "141.0.0.0",
        "metadata_Operating System": "Windows NT 10.0",
        "metadata_Resolution": "1920x1080",
        "prolific_id": pid,
        "colors": colors,
        "time": "5", "showup": "1", "npage": "3",
        "tracking_json": tracking(seed=seed) if trk is None else trk,
        "visitorId": visitor,
        "requestId": f"{BASE_MS + seed * 900_000}.synth{seed:02d}",
        "fp_error": "",
        "ip_address": ip,
        "page": 6,
        "key_log": keylog(PASS_TEXT, seed=seed) if klog is None else klog,
        "key_log2": "",
    })
    r.update({k: v for k, v in video.items()})
    # Any key that is not a real export column would be dropped silently by the
    # comprehension below, producing plausible-looking rows with blank answers.
    # Fail loudly instead if this script and the export headers drift apart.
    unknown = [k for k in r if k not in COLS]
    if unknown:
        raise KeyError(
            f"{unknown} not found in {REAL_CSV} headers. "
            "Re-export from Qualtrics or update the column names in this script."
        )
    return [r[c] for c in COLS]


SYNTH = [
    # 1-2  clean passes
    row("R_SYNok000000001", "5f8a1c2d3e4b5a6c7d01", "88.10.0.1", seed=1, day=3),
    row("R_SYNok000000002", "5f8a1c2d3e4b5a6c7d02", "88.10.0.2", seed=2, day=3, hour=11),
    # 3    fails attention (colors text wrong)
    row("R_SYNatt00000003", "5f8a1c2d3e4b5a6c7d03", "88.10.0.3", seed=3, day=3, hour=13,
        colors="blue and green", klog=keylog("blue and green", seed=3)),
    # 4    fails the video ranking
    row("R_SYNvid00000004", "5f8a1c2d3e4b5a6c7d04", "88.10.0.4", seed=4, day=3, hour=15,
        video=VIDEO_WRONG),
    # 5    paste event on the colors page
    row("R_SYNpst00000005", "5f8a1c2d3e4b5a6c7d05", "88.10.0.5", seed=5, day=4,
        trk=tracking(paste_page=4, seed=5)),
    # 6    no keystrokes at all
    row("R_SYNkey00000006", "5f8a1c2d3e4b5a6c7d06", "88.10.0.6", seed=6, day=4, hour=11,
        klog="[]"),
    # 7    unusually fast typing (~20 ms gaps)
    row("R_SYNspd00000007", "5f8a1c2d3e4b5a6c7d07", "88.10.0.7", seed=7, day=4, hour=13,
        klog=keylog(PASS_TEXT, gap=20, seed=7)),
    # 8    large input jump (>= 50) at otherwise normal speed
    row("R_SYNjmp00000008", "5f8a1c2d3e4b5a6c7d08", "88.10.0.8", seed=8, day=4, hour=15,
        klog=keylog(PASS_TEXT, gap=180, jump=(6, 80), seed=8)),
    # 9-10 duplicate IP + shared device fingerprint
    row("R_SYNip000000009", "5f8a1c2d3e4b5a6c7d09", "88.10.9.9", seed=9, day=5,
        visitor="synth_shared_device"),
    row("R_SYNip000000010", "5f8a1c2d3e4b5a6c7d10", "88.10.9.9", seed=10, day=5, hour=11,
        visitor="synth_shared_device"),
    # 11   incomplete survey
    row("R_SYNinc00000011", "5f8a1c2d3e4b5a6c7d11", "88.10.0.11", seed=11, day=5, hour=13,
        finished="False", progress=45, dur=95,
        trk=tracking(seed=11, n_pages=3), klog="[]"),
    # 12   survey preview
    row("R_SYNprv00000012", "5f8a1c2d3e4b5a6c7d12", "", seed=12, day=5, hour=15,
        status="Survey Preview"),
    # 13-14 duplicate prolific_id; 14 is the later entry -> flag_id
    row("R_SYNdup00000013", "5f8a1c2d3e4b5a6c7d13", "88.10.0.13", seed=13, day=6),
    row("R_SYNdup00000014", "5f8a1c2d3e4b5a6c7d13", "88.10.0.14", seed=14, day=6, hour=16),
    # 15   truncated tracking_json -> salvage()
    row("R_SYNtrn00000015", "5f8a1c2d3e4b5a6c7d15", "88.10.0.15", seed=15, day=7,
        trk=truncate(tracking(seed=15))),
    # 16   unparseable tracking_json
    row("R_SYNbad00000016", "5f8a1c2d3e4b5a6c7d16", "88.10.0.16", seed=16, day=7, hour=11,
        trk="{not valid json at all"),
    # 17   truncated key_log -> salvage()
    row("R_SYNklt00000017", "5f8a1c2d3e4b5a6c7d17", "88.10.0.17", seed=17, day=7, hour=13,
        klog=truncate(keylog(PASS_TEXT, seed=17), 0.55)),
]

with open(OUT_CSV, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f, quoting=csv.QUOTE_ALL)
    for r in HEADER:
        w.writerow(r)
    for r in REAL_DATA:
        w.writerow(r)
    for r in SYNTH:
        w.writerow(r)

print(f"wrote {OUT_CSV}")
print(f"  {len(COLS)} columns | 3 header rows")
print(f"  {len(REAL_DATA)} real rows + {len(SYNTH)} synthetic rows "
      f"= {len(REAL_DATA) + len(SYNTH)} data rows")

# =============================================================================
# NOTES
# =============================================================================
#
# THREE HEADER ROWS. A Qualtrics CSV export carries names / question text /
# ImportId. clean_tracker.R and main.R both do `[-1, ]`, which drops only one.
# Both need `[-c(1, 2), ]` (and read.csv rather than read_excel) for this file.
#
# main.do parses dates with clock(RecordedDate, "MDY hm"). The real export uses
# 'YYYY-MM-DD HH:MM:SS', so that mask yields missing. Use clock(., "YMDhms").
#
# video COLUMN NAMES are video_5 / video_7 / video_8 / video_9 / video_10 -- Qualtrics names
# rank-order columns by choice ID, not by position. video_correct in main.R must
# use these names and the values in video_CORRECT above.
#
# EVERY REAL ROW SHARES ip_address 130.132.173.28 and visitorId
# msvaHSJoPXanfafy0raq, so flag_ip fires for all of them. That is correct
# behaviour on data collected from one machine, not a bug -- but it means
# keep_ids will be driven almost entirely by the synthetic rows.
#
# Synthetic row design (all 17 verified against a simulation of the pipeline):
#   1,2   clean pass
#   3     colors = "blue and green"       -> flag_attention
#   4     video ranked wrongly              -> flag_video
#   5     paste_detected on colors page   -> flag_paste, flag_typed
#   6     key_log = "[]"                  -> flag_nokeys, flag_speed, flag_typed
#   7     ~20 ms keystroke gaps           -> flag_speed
#   8     INPUT_JUMP of 80 chars          -> flag_inputjump, flag_typed
#   9,10  share ip 88.10.9.9              -> flag_ip (both)
#   11    Finished = False, Progress 45   -> exclusion
#   12    Status  = Survey Preview        -> exclusion
#   13,14 share a prolific_id; 14 later   -> flag_id + exclusion on 14
#   15    truncated tracking_json         -> salvaged, then passes
#   16    unparseable tracking_json       -> tracker vars NA, silently passes
#   17    truncated key_log               -> salvaged, then passes
#
# Real row 13 (R_52Y6CZhyBHT2ALa) submitted "red and brown\n" with a trailing
# newline. main.R's grepl() accepts it; the survey's EqualTo branch does not.
# It is a useful regression case for that mismatch.
