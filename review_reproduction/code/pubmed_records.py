"""
Bibliographic arm: PubMed search executed 31 August 2026.

Long boolean URLs could not be executed reliably from the working environment,
so the strategy was run as a multi-line search of title-phrase blocks of the kind
systematic reviews report as numbered lines. Each line below is independently
repeatable and PubMed returned the query translation verbatim for every one.

Records were screened by title. Records describing a resource already identified
by the repository screen, and secondary analyses of such resources, were removed.
The resources that remained -- those the repository screen had NOT retrieved --
are listed in NEW_RESOURCES with a decision and a reason for each.
"""

LINES = [
    ("S1", '"intensive care database"[ti]', 29),
    ("S2", '"critical care database"[ti]', 21),
    ("S3", '"ICU database"[ti] OR "intensive care dataset"[ti]', 25),
    ("S4", '"anesthesia database"[ti] OR "anaesthesia database"[ti]', 11),
    ("S5", '"perioperative database"[ti] OR "operating room database"[ti]', 5),
    ("S6", '"vital signs database"[ti] OR "waveform database"[ti]', 4),
]

# Known-item validation searches, run to confirm recall against resources already
# included. Not screening lines, and not counted in the flow.
VALIDATION = [
    ('VitalDB[tiab]', 62, "retrieved the VitalDB descriptor"),
    ('physionet[tiab] AND 2015:2026[dp]', 886, "confirms repository coverage in the literature"),
]

RECORDS_RETRIEVED = sum(n for _, _, n in LINES)   # 95

# Distinct resources surfaced by the bibliographic arm that the repository screen
# did not retrieve. (title, decision, reason-code, note)
NEW_RESOURCES = [
    ("JinhuaNSICU, an open accessible Neurosurgical Intensive Care Database", "FLAG", None,
     "Meets the eligibility criteria: 8,773 patients, 20,530 neurosurgical ICU admissions, "
     "Jinhua Central Hospital, China, 2014-2023, openly released under CC BY-NC-ND 4.0 through "
     "the China National Center for Bioinformation. Identified by this search after charting "
     "closed and not chartable to the common standard from its descriptor alone; reported in Table 4."),

    ("BlendedICU, the first harmonised international intensive care dataset", "EXCLUDE", "DERIV",
     "A harmonised re-formatting of MIMIC-III/IV, eICU-CRD, AmsterdamUMCdb and HiRID; contributes no independent cohort."),
    ("CEDAR, Critical carE Database for Advanced Research", "EXCLUDE", "TOOL",
     "An automated extraction method supporting a single institution, not a released dataset."),
    ("ELISE evolutionary open paediatric intensive care dataset", "EXCLUDE", "TOOL",
     "A project description; no dataset released at the time of screening."),

    ("Danish Intensive Care Database", "EXCLUDE", "REGISTRY", ""),
    ("Danish Anaesthesia Database", "EXCLUDE", "REGISTRY", ""),
    ("Australian and New Zealand binational adult patient ICU database", "EXCLUDE", "REGISTRY", ""),
    ("Critical Care Health Informatics Collaborative (CCHIC), United Kingdom", "EXCLUDE", "REGISTRY", ""),
    ("ICNARC national critical care database, United Kingdom", "EXCLUDE", "REGISTRY", ""),
    ("Epimed Monitor ICU Database, Brazil", "EXCLUDE", "REGISTRY", ""),
    ("Japanese national ICU database (JIPAD)", "EXCLUDE", "REGISTRY", ""),
    ("Spanish multicentre ICU database", "EXCLUDE", "REGISTRY", ""),
    ("Critical care database of a Saudi Arabian tertiary hospital", "EXCLUDE", "REGISTRY", ""),
    ("TRIPLE-A perioperative database, Eastern Denmark", "EXCLUDE", "REGISTRY", ""),
    ("Paediatric cardiac anaesthesia and intensive care database", "EXCLUDE", "REGISTRY", ""),
    ("Critical care database built on specialised hospital information systems, China", "EXCLUDE", "REGISTRY", ""),

    ("CHECKLIST-ICU trial database", "EXCLUDE", "STUDY", ""),
    ("COVID-ICU prospective cohort database", "EXCLUDE", "STUDY", ""),

    ("UnoViS, the MedIT public unobtrusive vital signs database", "EXCLUDE", "SETTING", ""),
]

REASON_LABEL = {
    "REGISTRY": "National, consortium or institutional registry without public patient-level release",
    "DERIV":    "Derivative, extension or re-format of an already identified resource",
    "TOOL":     "Method, tool or project description rather than a released dataset",
    "STUDY":    "Trial or study cohort assembled for a single investigation",
    "SETTING":  "Not an anaesthesia or critical-care episode",
}

if __name__ == "__main__":
    from collections import Counter
    print(f"lines run                     : {len(LINES)}")
    print(f"records retrieved             : {RECORDS_RETRIEVED}")
    print(f"distinct new resources        : {len(NEW_RESOURCES)}")
    d = Counter(x[1] for x in NEW_RESOURCES)
    for k, v in d.items():
        print(f"  {k:<9}{v}")
    print("exclusion reasons")
    for k, v in Counter(x[2] for x in NEW_RESOURCES if x[1] == "EXCLUDE").most_common():
        print(f"  {k:<9}{v:>3}  {REASON_LABEL[k]}")
