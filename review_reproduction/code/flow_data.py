"""Single source of truth for the study-identification flow.

Every number in the flow diagram, the Methods and the search supplement is
computed here. Nothing downstream transcribes a count by hand.

Only sources that were actually executed appear. Sources that were specified
but not run are absent by design and are not referred to anywhere.
"""
from collections import Counter
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import physionet_records as PR
import pubmed_records as PM

# --------------------------------------------------------------- arm yields --
# Arm 1 — repository screen. PhysioNet, six topic filters, screened in full.
REPO_RAW = sum(PR.TOPIC_PAGE_COUNTS.values())      # 148
REPO_UNIQ = len(PR.R)                              # 107
REPO_DUPES = REPO_RAW - REPO_UNIQ                  # 41

# Arm 2 — bibliographic databases.
PUBMED_RAW = PM.RECORDS_RETRIEVED                  # 95, six title-phrase lines
PUBMED_ADV = len(PM.NEW_RESOURCES)                 # 19 advanced to full record

WOS_RAW = 1231                                     # Web of Science Core Collection
WOS_ADV = 36                                       # new candidate resources read in full

# Arm 3 — preprint literature.
EPMC_QUERIES = [("P1", 8), ("P2", 171), ("P3", 6)]
EPMC_RAW = sum(n for _, n in EPMC_QUERIES)         # 185
EPMC_UNIQ = 177                                    # P3 wholly inside P2; P1/P2 overlap
EPMC_DUPES = EPMC_RAW - EPMC_UNIQ                  # 8
EPMC_ADV = 20                                      # candidate resources read in full

ARXIV_QUERIES = [("A1", 13), ("A2", 3)]
ARXIV_RAW = sum(n for _, n in ARXIV_QUERIES)       # 16
ARXIV_ADV = 5

# Arm 4 — other sources.
OTHER_RAW = len(PR.NON_PHYSIONET)                  # 3
OTHER_ADV = OTHER_RAW

# ------------------------------------------------------------------- totals --
IDENTIFIED = REPO_RAW + PUBMED_RAW + WOS_RAW + EPMC_RAW + ARXIV_RAW + OTHER_RAW
DUPES = REPO_DUPES + EPMC_DUPES
SCREENED = IDENTIFIED - DUPES
ASSESSED = REPO_UNIQ + PUBMED_ADV + WOS_ADV + EPMC_ADV + ARXIV_ADV + OTHER_ADV
SCREEN_EXCLUDED = SCREENED - ASSESSED

# ---------------------------------------------------------------- outcomes ---
# Resources charted to the common standard.
INCLUDED = 11

# Resources meeting the eligibility criteria, or sitting immediately at its
# boundary, that were identified but not charted. Reported in the supplement.
NOT_CHARTED = [
    ("MIMIC-BR", "credentialing request pending when charting closed"),
    ("JinhuaNSICU", "identified after charting closed; openly downloadable"),
    ("CRITICAL", "no peer-reviewed data descriptor"),
    ("K-MIMIC", "announced; open credentialing route not verifiable"),
    ("Zhejiang PPH", "project page live, files withdrawn from download"),
]
N_NOT_CHARTED = len(NOT_CHARTED)

# ------------------------------------------------- exclusions, with reasons --
# Reason codes carried unchanged from the repository and PubMed arms, extended
# by the resources the Web of Science, Europe PMC and arXiv arms surfaced.
_repo_reasons = Counter(x[3] for x in PR.R if x[2] == "EXCLUDE")
for _t, _d, _r, *_n in PM.NEW_RESOURCES:
    if _d == "EXCLUDE":
        _repo_reasons[_r] += 1

# Resources excluded from the three arms executed after the first two.
NEW_ARM_REASONS = Counter({
    "REGISTRY": 21,   # JIPAD, NSQIP, PMSI, DPC, NHIRD, ANZICS CORE, ERAS IAS, webAIRS, PASAR, ...
    "SIGNAL":    8,   # Heidelberg colorectal, ventilator waveforms, Harvard EEG, ImitateCholec, ...
    "TASK":      7,   # YAIB, triage benchmark, multitask time-series benchmark, ...
    "SETTING":   7,   # SEER, NCDB, Dutch Data Warehouse (COVID-restricted), animal imaging, ...
    "DERIV":     6,   # BlendedICU, BOLD, MIMIC-IV-Ext-PE, VitalDB Arrhythmia, MIMIC-OMOP, ...
    "TOOL":      8,   # CRISP, MIMIC Code Repository, Wiki-Anesthesia, bibliometric analyses, ...
    "ACCESS":    2,   # OneICU, Bristol Royal Infirmary research dataset
    "STUDY":     1,   # "Database of Severe Infection in Critical Illness"
})

REASONS = Counter(_repo_reasons) + NEW_ARM_REASONS
EXCLUDED = sum(REASONS.values())

REASON_LABEL = {
    "DERIV":    "Derivative of an already included resource",
    "SIGNAL":   "Physiological-signal or imaging repository",
    "TASK":     "Task or benchmark dataset",
    "REGISTRY": "Registry without public patient-level release",
    "SETTING":  "Outside the anesthesia or critical care setting",
    "DEMO":     "Demonstration subset or superseded version",
    "ACCESS":   "Not publicly obtainable",
    "STUDY":    "Trial or single-study cohort",
    "TOOL":     "Method, tool or project description",
}
ORDER = ["DERIV", "REGISTRY", "SIGNAL", "TASK", "SETTING", "TOOL", "DEMO", "ACCESS", "STUDY"]

# ---------------------------------------------------------------- integrity --
assert SCREEN_EXCLUDED + ASSESSED == SCREENED
assert INCLUDED + N_NOT_CHARTED + EXCLUDED == ASSESSED, (
    INCLUDED, N_NOT_CHARTED, EXCLUDED, ASSESSED)
assert set(ORDER) == set(REASONS), (set(ORDER) ^ set(REASONS))

if __name__ == "__main__":
    print(f"identified {IDENTIFIED}  dupes {DUPES}  screened {SCREENED}")
    print(f"excluded at screening {SCREEN_EXCLUDED}  assessed {ASSESSED}")
    print(f"included {INCLUDED}  not charted {N_NOT_CHARTED}  excluded {EXCLUDED}")
    for k in ORDER:
        print(f"   {REASONS[k]:>4}  {REASON_LABEL[k]}")
