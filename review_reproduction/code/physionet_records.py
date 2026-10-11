"""
PhysioNet repository screen, executed 31 August 2026.
Six topic filters were screened in full, every page.

Each record: (title, topics it appeared under, decision, reason-code)

Decision codes
  INCLUDE   included in the review
  FLAG      eligible in concept but not obtainable/verifiable -> Table 4
  EXCLUDE   excluded, with reason code

Reason codes for exclusion
  DERIV   derivative, extension, annotation layer or re-format of an already
          identified resource
  DEMO    demonstration subset or superseded version of an identified resource
  SIGNAL  physiological-signal or imaging repository without linked
          patient-level clinical context
  TASK    task-, benchmark- or annotation-specific dataset rather than a
          database of care episodes
  SETTING not an anaesthesia or critical-care episode
  ACCESS  restricted access, not obtainable through open credentialing
  STUDY   curated analytic dataset assembled for a single study rather than a
          general-purpose database of routine care episodes
  TOOL    software rather than a dataset
"""

R = [
 # ---------------------------------------------------------------- included --
 ("MIMIC-IV",                                          ["icu","cc","ehr"], "INCLUDE", None),
 ("eICU Collaborative Research Database",              ["cc"],             "INCLUDE", None),
 ("INSPIRE, a publicly available research dataset for perioperative medicine", ["icu","anes","surg"], "INCLUDE", None),
 ("HiRID, a high time-resolution ICU dataset",         ["icu","cc"],       "INCLUDE", None),
 ("Northwestern ICU (NWICU) database",                 ["cc"],             "INCLUDE", None),
 ("Salzburg Intensive Care database (SICdb)",          ["icu","cc","surg"],"INCLUDE", None),
 ("Paediatric Intensive Care database",                ["icu","cc"],       "INCLUDE", None),
 ("VitalDB, a high-fidelity multi-parameter vital signs database", ["anes"],"INCLUDE", None),
 ("Critical care database comprising patients with infection at Zigong Fourth People's Hospital", ["icu","cc"], "INCLUDE", None),

 # ------------------------------------------------------------ flagged (T4) --
 ("Medical Information Mart for Intensive Care Brazil (MIMIC-BR)", ["icu","cc"], "FLAG", None),
 ("Establishment of a Chinese critical care database (Zhejiang PPH)", ["cc"],    "FLAG", None),

 # ------------------------- surfaced by this screen, adjudicated on full text --
 ("SCRIPT CarpeDiem Dataset",                          ["cc"],             "EXCLUDE","STUDY"),
 ("I-CARE: International Cardiac Arrest REsearch consortium Database", ["icu"], "EXCLUDE","SIGNAL"),
 ("Multimodal Clinical Monitoring in the Emergency Department (MC-MED)", ["ehr"], "EXCLUDE","SETTING"),
 ("Kingston ICU AF Dataset",                           ["icu"],            "EXCLUDE","ACCESS"),

 # ------------------------------------------- excluded: derivative of a core --
 ("EchoNotes Structured Database derived from MIMIC-III", ["icu"],           "EXCLUDE","DERIV"),
 ("Phenotype Annotations for Patient Notes in MIMIC-III", ["icu","cc","ehr"],"EXCLUDE","DERIV"),
 ("MIMIC-IV-Ext-CLIF",                                  ["icu","cc","ehr"], "EXCLUDE","DERIV"),
 ("A Temporal Dataset for Respiratory Support in Critically Ill Patients", ["icu","cc"], "EXCLUDE","DERIV"),
 ("BOLD, a blood-gas and oximetry linked dataset",      ["icu","ehr"],      "EXCLUDE","DERIV"),
 ("MIT Critical Datathon 2023 pulse oximetry correction", ["icu","cc"],     "EXCLUDE","DERIV"),
 ("Synthetic Acute Hypotension and Sepsis Datasets (Health Gym)", ["icu"],  "EXCLUDE","DERIV"),
 ("Immunosuppressive Condition and Medication Annotations, MIMIC-III", ["icu","cc","ehr"], "EXCLUDE","DERIV"),
 ("TherLid: A Thermometry Linked Dataset",              ["icu","ehr"],      "EXCLUDE","DERIV"),
 ("Annotation dataset of problematic opioid use, MIMIC-III", ["cc","ehr"],  "EXCLUDE","DERIV"),
 ("GOSSIS-1-eICU",                                      ["cc"],             "EXCLUDE","DERIV"),
 ("Clinical Time Series Datasets for Trajectory Flow Matching Evaluation", ["cc"], "EXCLUDE","DERIV"),
 ("Nosocomial Risk Datasets from MIMIC-III",            ["cc"],             "EXCLUDE","DERIV"),
 ("MIMIC-III and eICU-CRD: FIDDLE Preprocessing",       ["cc","ehr"],       "EXCLUDE","DERIV"),
 ("MIMIC-III - SequenceExamples for TensorFlow modeling", ["cc","ehr"],     "EXCLUDE","DERIV"),
 ("Clinical data from MIMIC-II, indwelling arterial catheters", ["cc","ehr"],"EXCLUDE","DERIV"),
 ("MIMIC-IV-Ext-MDS-ED",                                ["cc"],             "EXCLUDE","DERIV"),
 ("MIMIC-III-Ext-PPG",                                  ["cc"],             "EXCLUDE","DERIV"),
 ("MIMIC-IV demo data in the Medical Event Data Standard (MEDS)", ["cc","ehr"], "EXCLUDE","DERIV"),
 ("MIMIC-IV-Note: deidentified free-text clinical notes", ["cc","ehr"],     "EXCLUDE","DERIV"),
 ("MIMIC-IV Waveform Database",                         ["icu","cc"],       "EXCLUDE","DERIV"),
 ("AIPatient KG (MIMIC-III and CORAL knowledge graph)", ["ehr"],            "EXCLUDE","DERIV"),
 ("MIMIC-III-Ext-VeriFact-BHC",                         ["ehr"],            "EXCLUDE","DERIV"),
 ("Annotation dataset of social determinants of health, MIMIC-III", ["ehr"],"EXCLUDE","DERIV"),
 ("NIHSS Annotations for the MIMIC-III Database",       ["ehr"],            "EXCLUDE","DERIV"),
 ("MIMIC-IV-Ext-MedicalBench",                          ["ehr"],            "EXCLUDE","DERIV"),
 ("MIMIC-Ext-DrugDetection",                            ["ehr"],            "EXCLUDE","DERIV"),
 ("MIMIC-IV-Ext-Instr",                                 ["ehr"],            "EXCLUDE","DERIV"),
 ("SCRIPT X2B8 Dataset (next-day extubation features)", ["ehr"],            "EXCLUDE","DERIV"),
 ("Clinical BERT Models Trained on Pseudo Re-identified MIMIC-III Notes", ["ehr"], "EXCLUDE","DERIV"),
 ("What's in a Note? Predictive Value in Clinical Note Representations", ["ehr"], "EXCLUDE","DERIV"),
 ("MIMIC-IV on FHIR",                                   ["ehr"],            "EXCLUDE","DERIV"),
 ("MIMIC-Ext-MIMIC-CXR-VQA",                            ["ehr"],            "EXCLUDE","DERIV"),

 # ------------------------------------- excluded: demo or superseded version --
 ("MIMIC Database (2000)",                              ["cc"],             "EXCLUDE","DEMO"),
 ("MIMIC-II Clinical Database",                         ["icu","cc"],       "EXCLUDE","DEMO"),
 ("MIMIC-III Clinical Database",                        ["icu","cc"],       "EXCLUDE","DEMO"),
 ("MIMIC-III Clinical Database CareVue subset",         ["icu","cc"],       "EXCLUDE","DEMO"),
 ("MIMIC-III Clinical Database Demo",                   ["cc","ehr"],       "EXCLUDE","DEMO"),
 ("MIMIC-IV Clinical Database Demo",                    ["cc","ehr"],       "EXCLUDE","DEMO"),
 ("MIMIC-IV Clinical Database Demo on FHIR",            ["ehr"],            "EXCLUDE","DEMO"),
 ("eICU Collaborative Research Database Demo",          ["cc"],             "EXCLUDE","DEMO"),

 # ------------------------------- excluded: signal/imaging without context ----
 ("VTaC: Ventricular Tachycardia Alarms from ICU Monitors", ["icu"],        "EXCLUDE","SIGNAL"),
 ("Preterm Infant Cardio-Respiratory Signals Database", ["icu"],            "EXCLUDE","SIGNAL"),
 ("Reducing False Arrhythmia Alarms in the ICU (CinC Challenge 2015)", ["icu","cc"], "EXCLUDE","SIGNAL"),
 ("MGH/MF Waveform Database",                           ["cc"],             "EXCLUDE","SIGNAL"),
 ("Leipzig Heart Center ECG-Database",                  ["cc"],             "EXCLUDE","SIGNAL"),
 ("Dataset for Segmentation and Classification of Cardiac Implantable Electronic Devices in Chest X-Rays", ["cc"], "EXCLUDE","SIGNAL"),
 ("Multitaper spectra during GABAergic anesthetic unconsciousness", ["anes"],"EXCLUDE","SIGNAL"),
 ("Electroencephalogram dynamics during GABAergic anaesthetic unconsciousness", ["anes"], "EXCLUDE","SIGNAL"),
 ("Behavioral and autonomic dynamics during propofol-induced unconsciousness", ["anes"], "EXCLUDE","SIGNAL"),
 ("Electrodermal Activity of Healthy Volunteers",       ["anes"],           "EXCLUDE","SIGNAL"),
 ("Pulse Amplitudes from electrodermal activity under controlled sedation", ["anes"], "EXCLUDE","SIGNAL"),
 ("EEG and Eye-Gaze Datasets for Fundamentals of Laparoscopic Surgery Tasks", ["surg"], "EXCLUDE","SIGNAL"),
 ("EEG and eye-gaze datasets for robot-assisted surgery performance", ["surg"], "EXCLUDE","SIGNAL"),
 ("Endoscapes2023 surgical scene segmentation",         ["surg"],           "EXCLUDE","SIGNAL"),
 ("Paroxysmal Atrial Fibrillation Events Detection (CPSC 2021)", ["surg"],  "EXCLUDE","SIGNAL"),
 ("Shiraz University Fetal Heart Sounds Database",      ["surg"],           "EXCLUDE","SIGNAL"),
 ("Surface electromyographic signals during ground walking", ["surg"],      "EXCLUDE","SIGNAL"),
 ("Continuous Cuffless Monitoring of Arterial Blood Pressure via Graphene Bioimpedance Tattoos", ["ehr"], "EXCLUDE","SIGNAL"),

 # ------------------------------------- excluded: task/annotation benchmark ---
 ("ArchEHR-QA",                                         ["icu","cc","ehr"], "EXCLUDE","TASK"),
 ("Progress Note Understanding Suite of Tasks 1 and 3", ["icu","cc","ehr"], "EXCLUDE","TASK"),
 ("C-REACT: Contextualized Race and Ethnicity Annotations", ["cc"],         "EXCLUDE","TASK"),
 ("EHRCon",                                             ["ehr"],            "EXCLUDE","TASK"),
 ("DrugEHRQA",                                          ["ehr"],            "EXCLUDE","TASK"),
 ("EHRXQA",                                             ["ehr"],            "EXCLUDE","TASK"),
 ("EHRNoteQA",                                          ["ehr"],            "EXCLUDE","TASK"),
 ("ODD: Opioid Related Aberrant Behavior Detection",    ["ehr"],            "EXCLUDE","TASK"),
 ("BioNLP Workshop 2023 Shared Task 1A",                ["ehr"],            "EXCLUDE","TASK"),
 ("Learning to Ask Like a Physician (DiSCQ)",           ["ehr"],            "EXCLUDE","TASK"),
 ("RadQA",                                              ["ehr"],            "EXCLUDE","TASK"),
 ("PatientSim",                                         ["ehr"],            "EXCLUDE","TASK"),
 ("CORAL: expert-Curated medical Oncology Reports",     ["ehr"],            "EXCLUDE","TASK"),
 ("Shareable Artificial Intelligence to Extract Cancer Outcomes", ["ehr"],  "EXCLUDE","TASK"),
 ("CARMEN-I (Spanish and Catalan clinical records)",    ["ehr"],            "EXCLUDE","TASK"),
 ("Fine-tuning foundational models to code veterinary records", ["ehr"],    "EXCLUDE","TASK"),

 # ----------------------------------- excluded: not a critical-care episode ---
 ("Curated Data for Describing Blood Glucose Management in the ICU", ["icu","cc","ehr"], "EXCLUDE","DERIV"),
 ("NCH Sleep DataBank",                                 ["ehr"],            "EXCLUDE","SETTING"),
 ("ARMD-MGB: Antibiotic Resistance Microbiology Dataset", ["ehr"],          "EXCLUDE","SETTING"),
 ("AMR-UTI: Antimicrobial Resistance in Urinary Tract Infections", ["ehr"], "EXCLUDE","SETTING"),
 ("ENCoDE (skin tone and pulse oximetry, acute care)",  ["ehr"],            "EXCLUDE","SETTING"),
 ("Predictors of Hospital Onset Infection",             ["ehr"],            "EXCLUDE","SETTING"),
 ("MIMIC-IV-ED",                                        ["ehr"],            "EXCLUDE","SETTING"),
 ("Wearable-based signals after open-heart surgery",    ["surg"],           "EXCLUDE","SETTING"),
 ("Response to Valsalva Maneuver in Humans",            ["surg"],           "EXCLUDE","SETTING"),
 ("A Wearable Exam Stress Dataset",                     ["surg"],           "EXCLUDE","SETTING"),
 ("Regulation of Brain Cognitive States",               ["surg"],           "EXCLUDE","SETTING"),
 ("Cerebral Vasoregulation in Diabetes",                ["surg"],           "EXCLUDE","SETTING"),
 ("Cerebromicrovascular Disease in Elderly with Diabetes", ["surg","periop"],"EXCLUDE","SETTING"),
 ("Neurophysiological Dataset of Stress Resilience",    ["surg"],           "EXCLUDE","SETTING"),

 # -------------------------------------------------- excluded: access/tool ----
 ("Multimodal Physiological Indices During Surgery Under Anesthesia", ["anes","cc","surg"], "EXCLUDE","ACCESS"),
 ("Hospitalized patients with heart failure (restricted)", ["ehr"],         "EXCLUDE","ACCESS"),
 ("Vital File Web Viewer",                              ["surg"],           "EXCLUDE","TOOL"),
]

# Resources identified outside the repository screen, from the four prior
# comparative reviews and by citation chasing of their reference lists and of
# each resource's own project page.
NON_PHYSIONET = [
 ("MOVER (University of California, Irvine)", "INCLUDE", None),
 ("AmsterdamUMCdb (Amsterdam UMC portal)",    "INCLUDE", None),
 ("K-MIMIC (IMPACT consortium, Republic of Korea)", "FLAG", None),
]

TOPIC_PAGE_COUNTS = {   # records retrieved per topic filter, before deduplication
    "intensive care unit": 28,
    "critical care": 42,
    "anesthesia": 8,
    "surgery": 18,
    "electronic health records": 51,
    "perioperative": 1,
}

REASON_LABEL = {
    "DERIV":   "Derivative, extension, annotation layer or re-format of an already identified resource",
    "DEMO":    "Demonstration subset or superseded version of an identified resource",
    "SIGNAL":  "Physiological-signal or imaging repository without linked patient-level clinical context",
    "TASK":    "Task-, benchmark- or annotation-specific dataset rather than a database of care episodes",
    "SETTING": "Not an anaesthesia or critical-care episode",
    "ACCESS":  "Restricted access, not obtainable through open credentialing",
    "TOOL":    "Software tool rather than a dataset",
    "STUDY":   "Curated analytic dataset assembled for a specific study rather than a general-purpose database of routine care episodes",
}

if __name__ == "__main__":
    from collections import Counter
    raw = sum(TOPIC_PAGE_COUNTS.values())
    uniq = len(R)
    print(f"records retrieved across topic filters : {raw}")
    print(f"unique projects after deduplication    : {uniq}")
    print(f"duplicate records removed              : {raw - uniq}")
    print()
    print(f"additional resources identified outside the repository: {len(NON_PHYSIONET)}")
    print(f"total unique resources assessed for eligibility        : {uniq + len(NON_PHYSIONET)}")
    print()
    d = Counter([x[2] for x in R] + [x[1] for x in NON_PHYSIONET])
    for k in ("INCLUDE", "FLAG", "CANDIDATE", "EXCLUDE"):
        print(f"  {k:<10} {d[k]}")
    print()
    print("exclusion reasons")
    rc = Counter(x[3] for x in R if x[2] == "EXCLUDE")
    for k, v in rc.most_common():
        print(f"  {k:<8} {v:>3}  {REASON_LABEL[k]}")
    print(f"  {'TOTAL':<8} {sum(rc.values()):>3}")
