"""
Script:  make_nopii_qsf.py

Purpose: Build the non-identifiable version of the survey. Reads the original
         Qualtrics survey file and removes everything that collects personally
         identifiable information, leaving the attention check, video check,
         branch logic and page tracker untouched.

Usage:   python code/make_nopii_qsf.py     (run from the repo root; stdlib only)

Input:   qualtrics survey file/v5.qsf        (not modified)
Output:  qualtrics survey file/v5_noPII.qsf  (import this into Qualtrics)

Removed:
  - FingerprintJS header script           -> visitorId, requestId, fp_error
  - QID43 browser meta question            -> metadata_Browser / _Version / ...
  - QID47 Prolific ID question + block     -> prolific_id
  - QID50 keystroke logger JavaScript      -> key_log
  - Embedded data fields                   -> ip_address (${loc://IPAddress}),
                                              PROLIFIC_PID, STUDY_ID, SESSION_ID,
                                              visitorId, requestId, fp_error,
                                              key_log, key_log2
  - Anonymize responses switched ON        -> IPAddress, LocationLatitude,
                                              LocationLongitude, Recipient* blank

After importing, follow TODO_noPII.md to verify the settings in Qualtrics.
"""
import json, os, re

IN_QSF = os.path.join("qualtrics survey file", "v5.qsf")
OUT_QSF = os.path.join("qualtrics survey file", "v5_noPII.qsf")

DROP_QIDS = {"QID43", "QID47"}                  # meta question, Prolific ID
DROP_BLOCKS = {"BL_8c5nAV1lPyhWPD8"}            # "Prolific ID" block
DROP_FIELDS = {"ip_address", "PROLIFIC_PID", "STUDY_ID", "SESSION_ID",
               "visitorId", "requestId", "fp_error", "key_log", "key_log2"}
KEYLOG_QID = "QID50"                            # colors question

# Substrings that must not survive anywhere in the output file
FORBIDDEN = ["fpjscdn", "loc://IPAddress", "PROLIFIC_PID", "STUDY_ID",
             "SESSION_ID", "visitorId", "requestId", "fp_error", "key_log",
             "ip_address", '"QID43"', '"QID47"']


def element(qsf, kind):
    return [e for e in qsf["SurveyElements"] if e["Element"] == kind]


def prune_flow(node):
    """Drop flow items for removed blocks and strip removed embedded fields."""
    if node.get("Type") == "EmbeddedData":
        node["EmbeddedData"] = [f for f in node["EmbeddedData"]
                                if f["Field"] not in DROP_FIELDS]
    if "Flow" in node:
        node["Flow"] = [prune_flow(c) for c in node["Flow"]
                        if c.get("ID") not in DROP_BLOCKS]
    return node


with open(IN_QSF, encoding="utf-8") as f:
    qsf = json.load(f)

qsf["SurveyEntry"]["SurveyName"] += " (no PII)"

# --- 1. Survey options: drop the FingerprintJS header script, anonymize ------
so = element(qsf, "SO")[0]["Payload"]
scripts = re.findall(r"<script\b.*?</script>", so["Header"], flags=re.S)
fp = [s for s in scripts if "fpjscdn" in s]
if len(fp) != 1:
    raise ValueError(f"Expected 1 FingerprintJS script in the header, found {len(fp)}")
so["Header"] = so["Header"].replace(fp[0], "", 1).lstrip()
so["AnonymizeResponse"] = "Yes"

# --- 2. Questions: drop QID43 / QID47, remove the keylogger ------------------
qsf["SurveyElements"] = [e for e in qsf["SurveyElements"]
                         if not (e["Element"] == "SQ" and e["PrimaryAttribute"] in DROP_QIDS)]
colors = [e for e in element(qsf, "SQ") if e["PrimaryAttribute"] == KEYLOG_QID][0]["Payload"]
colors["QuestionJS"] = False

# --- 3. Blocks: drop the Prolific ID block, take QID43 out of Consent --------
blocks = element(qsf, "BL")[0]["Payload"]
for key in [k for k, b in blocks.items() if b["ID"] in DROP_BLOCKS]:
    del blocks[key]
for b in blocks.values():
    b["BlockElements"] = [be for be in b["BlockElements"]
                          if be.get("QuestionID") not in DROP_QIDS]

# --- 4. Survey flow: drop the Prolific ID block and PII embedded fields ------
prune_flow(element(qsf, "FL")[0]["Payload"])

# --- 5. Write -----------------------------------------------------------------
out = json.dumps(qsf, ensure_ascii=False, separators=(",", ":"))
with open(OUT_QSF, "w", encoding="utf-8") as f:
    f.write(out)

# --- 6. Checks: fail loudly rather than write a half-cleaned survey ----------
problems = [s for s in FORBIDDEN if s in out]

header = element(qsf, "SO")[0]["Payload"]["Header"]
if header.count("<script") != 1 or "tracking_json" not in header:
    problems.append("header should hold exactly one <script> (the page tracker)")

sq_ids = {e["PrimaryAttribute"] for e in element(qsf, "SQ")}
bl_ids = {b["ID"] for b in blocks.values()}
for b in blocks.values():
    for be in b["BlockElements"]:
        if be.get("QuestionID") and be["QuestionID"] not in sq_ids:
            problems.append(f"block {b['ID']} references missing {be['QuestionID']}")


def flow_block_ids(node):
    ids = [node["ID"]] if node.get("ID", "").startswith("BL_") else []
    for c in node.get("Flow", []):
        ids += flow_block_ids(c)
    return ids


for bid in flow_block_ids(element(qsf, "FL")[0]["Payload"]):
    if bid not in bl_ids:
        problems.append(f"flow references missing block {bid}")

if problems:
    os.remove(OUT_QSF)
    raise SystemExit("v5_noPII.qsf NOT written:\n  " + "\n  ".join(problems))

print(f"wrote {OUT_QSF}")
print(f"  questions: {', '.join(sorted(sq_ids, key=lambda q: int(q[3:])))}")
print(f"  AnonymizeResponse = {so['AnonymizeResponse']}")
