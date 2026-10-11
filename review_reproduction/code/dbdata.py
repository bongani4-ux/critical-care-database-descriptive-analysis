"""
Master data module for:
"Navigating the Data Landscape: A Scoping Review of Publicly Available
 Perioperative and Critical Care Databases"

Eleven distinct database resources. MOVER is treated as ONE resource
(EPIC + SIS sub-cohorts pooled), per the descriptor paper
(Samad et al., JAMIA Open 2023;6(4):ooad084): 58,799 unique patients,
83,468 surgeries.

All figures and tables are generated from this single source of truth.
"""

# ---------------------------------------------------------------- cohort ----
# name, region, country, care setting, N, basis of N
DATABASES = [
    ("MIMIC-IV",       "USA",    "United States", "Mixed (hospital + ICU)", 364627, "patients"),
    ("eICU-CRD",       "USA",    "United States", "Adult ICU (multicentre)", 139367, "patients"),
    ("INSPIRE",        "Asia",   "South Korea",   "Perioperative",           99886, "patients"),
    ("MOVER",          "USA",    "United States", "Perioperative",           58799, "patients"),
    ("HiRID",          "Europe", "Switzerland",   "Adult ICU",               33905, "patients"),
    ("NWICU",          "USA",    "United States", "Adult ICU (COVID-rich)",  25923, "patients"),
    ("SICdb",          "Europe", "Austria",       "Adult ICU",               21583, "patients"),
    ("AmsterdamUMCdb", "Europe", "Netherlands",   "Adult ICU",               20109, "patients"),
    ("PIC",            "Asia",   "China",         "Pediatric ICU",          12881, "patients"),
    ("VitalDB",        "Asia",   "South Korea",   "Perioperative",            6388, "cases"),
    ("Zigong (ZFPH)",  "Asia",   "China",         "Adult ICU (infection)",    2790, "patients"),
]

TOTAL_N = sum(d[4] for d in DATABASES)              # 786,258

# --------------------------------------------------------- demographics -----
# name: (median age, IQR low, IQR high, % male)
DEMOGRAPHICS = {
    "SICdb":          (70.0, 55, 75, 62.4),
    "Zigong (ZFPH)":  (69.0, 56, 78, 60.0),
    "AmsterdamUMCdb": (65.0, 50, 75, 65.2),
    "HiRID":          (65.0, 55, 75, 64.2),
    "NWICU":          (65.0, 52, 75, 56.0),
    "eICU-CRD":       (65.0, 53, 76, 54.0),
    "VitalDB":        (59.0, 48, 68, 51.0),
    "MOVER":          (56.0, 37, 68, 52.0),   # pooled: weighted median, IQR spans both sub-cohorts
    "INSPIRE":        (55.0, 45, 65, 43.3),
    "MIMIC-IV":       (48.0, 29, 65, 47.0),
    "PIC":            (0.7,  0.1, 3.4, 58.0),
}

# MOVER sub-cohort detail retained for the table footnote
MOVER_SUBCOHORTS = {
    "EPIC": dict(patients=39685, surgeries=64354, age=(57, 42, 68), male=53.2),
    "SIS":  dict(patients=19114, surgeries=19114, age=(53, 37, 65), male=49.0),
}

# ------------------------------------------------------------- mortality ----
# name: dict(icu, in_hospital, last_followup, d30, d90, y1)
MORTALITY = {
    "MIMIC-IV":       dict(icu=None, hosp=3.2,  last=None, d30=2.1,  d90=3.4,  y1=5.8),
    "INSPIRE":        dict(icu=None, hosp=0.9,  last=None, d30=0.3,  d90=0.9,  y1=13.3),
    "MOVER":          dict(icu=None, hosp=1.5,  last=None, d30=None, d90=None, y1=None),
    "HiRID":          dict(icu=6.1,  hosp=None, last=None, d30=None, d90=None, y1=None),
    "eICU-CRD":       dict(icu=2.3,  hosp=3.9,  last=None, d30=None, d90=None, y1=None),
    "SICdb":          dict(icu=3.8,  hosp=None, last=7.8,  d30=None, d90=None, y1=None),
    "NWICU":          dict(icu=11.9, hosp=13.7, last=None, d30=None, d90=None, y1=None),
    "AmsterdamUMCdb": dict(icu=None, hosp=None, last=31.0, d30=None, d90=None, y1=None),
    "PIC":            dict(icu=None, hosp=7.2,  last=None, d30=None, d90=None, y1=None),
    "VitalDB":        dict(icu=None, hosp=None, last=None, d30=None, d90=None, y1=None),
    "Zigong (ZFPH)":  dict(icu=None, hosp=5.8,  last=None, d30=35.6, d90=39.5, y1=48.3),
}

# ---------------------------------------------------------- organ support ---
# name: (mechanical ventilation %, vasopressors %, renal replacement %)
ORGAN_SUPPORT = {
    "MIMIC-IV":       (54.0, 29.0, 2.6),
    "eICU-CRD":       (30.0, 15.0, None),
    "NWICU":          (35.0, 25.0, 3.0),
    "HiRID":          (60.8, 39.3, 5.2),
    "SICdb":          (38.0, 51.0, 3.8),
    "AmsterdamUMCdb": (71.8, 58.8, 4.9),
    "Zigong (ZFPH)":  (56.0, 57.2, None),
}

# ------------------------------------------------------------ granularity ---
VITAL_DBS = ["HiRID", "AmsterdamUMCdb", "SICdb", "NWICU", "eICU-CRD", "MIMIC-IV", "Zigong (ZFPH)"]
VITAL_ROWS = ["SpO₂", "FiO₂", "PEEP", "Heart rate", "Systolic BP",
              "Cardiac output", "Medications", "Fluids out"]
VITALS = {  # records per hour
    "SpO₂":        [28.2, 15.5, 1.0, 1.1, 1.1, 1.0, 1.4],
    "FiO₂":        [14.9, 0.4,  0.2, None, 0.3, 2.9, 1.0],
    "PEEP":             [16.8, 5.6,  0.3, None, 0.2, 0.1, None],
    "Heart rate":       [30.5, 16.2, 56.9, 1.2, 11.4, 1.0, 1.4],
    "Systolic BP":      [28.5, 13.7, 1.0, 1.2, 4.2, 1.7, 1.4],
    "Cardiac output":   [14.2, 0.2,  None, None, 3.8, 0.02, None],
    "Medications":      [6.4,  1.7,  2.5, 1.5, 0.8, 2.5, 1.4],
    "Fluids out":       [0.9,  1.0,  0.8, None, 0.7, 0.5, 1.0],
}

LAB_DBS = ["SICdb", "HiRID", "AmsterdamUMCdb", "MIMIC-IV", "NWICU", "Zigong (ZFPH)", "eICU-CRD"]
LAB_ROWS = ["Lactate", "PaO₂", "Sodium", "Hemoglobin", "CRP", "Creatinine", "ALT"]
LABS = {  # records per day
    "Lactate":     [6.8, 2.8, 1.7, 1.4, 1.3, 0.8, 0.6],
    "PaO₂":        [6.8, 2.7, 4.0, 2.4, 1.4, 1.2, 0.9],
    "Sodium":      [8.0, 2.8, 1.7, 4.5, 1.2, 0.6, 1.0],
    "Hemoglobin": [6.9, 3.9, 4.1, 4.2, 1.0, 0.8, 0.9],
    "CRP":         [2.2, 1.5, 0.6, 0.6, 0.5, 0.2, 0.3],
    "Creatinine":  [2.2, 1.6, 1.1, 4.0, 1.1, 0.7, 0.9],
    "ALT":         [1.1, 1.5, 0.7, 1.2, 0.6, 0.5, 0.5],
}

# -------------------------------------------------- variable-domain cover ---
DOMAIN_ROWS = [
    "Identifiers / administrative", "Demographics", "Diagnoses & coding",
    "Surgery / anesthesia", "Vital signs — intraoperative",
    "Waveforms (≥125 Hz)", "Ward / ICU vital signs",
    "Ventilator / respiratory", "Laboratory", "Microbiology", "Medications",
    "Fluids / transfusion", "Intake / output", "Lines / devices / procedures",
    "Severity scores", "Outcomes", "Imaging / free-text notes",
]
PERIOP_COLS = ["MOVER", "INSPIRE", "VitalDB"]
ICU_COLS = ["MIMIC-IV", "SICdb", "eICU-CRD", "AmsterdamUMCdb", "PIC",
            "NWICU", "Zigong (ZFPH)", "HiRID"]
DOMAIN = {  # order: MOVER, INSPIRE, VitalDB | MIMIC-IV, SICdb, eICU, Amsterdam, PIC, NWICU, Zigong, HiRID
    "Identifiers / administrative":     [83, 67, 33,  67, 83, 67, 50, 83, 50, 50, 33],
    "Demographics":                     [80, 60, 60, 100, 60, 80, 60, 60, 100, 60, 60],
    "Diagnoses & coding":               [75, 25, 50,  75, 50, 75, 50, 75, 50, 50, 25],
    "Surgery / anesthesia":            [80, 100, 80, 40, 60, 40, None, 60, None, None, None],
    "Vital signs — intraoperative":[91, 73, 100, 73, 73, 64, 73, 64, 64, 36, 73],
    "Waveforms (≥125 Hz)":         [60, None, 100, None, None, None, None, None, None, None, None],
    "Ward / ICU vital signs":           [None, 50, 25, 75, 75, 75, 75, 50, 50, 75, 50],
    "Ventilator / respiratory":         [100, 100, 80, 60, 60, 60, 60, 60, 60, 60, 60],
    "Laboratory":                       [100, 89, 56, 100, 100, 100, 100, 89, 100, 89, 89],
    "Microbiology":                     [None, None, None, 100, 100, 100, None, 100, None, 100, None],
    "Medications":                      [83, 100, 67, 67, 67, 67, 67, 50, 67, 50, 33],
    "Fluids / transfusion":             [67, 100, 100, 67, 67, 67, 67, 67, 67, 67, 67],
    "Intake / output":                  [100, 67, 33, 100, 100, 100, 100, 100, 100, 100, 100],
    "Lines / devices / procedures":     [60, 100, 60, 100, 100, 80, 100, 60, 100, 80, 100],
    "Severity scores":                  [None, None, None, 67, 100, 100, 100, None, 67, 33, 100],
    "Outcomes":                         [83, 67, 50, 67, 67, 50, 50, 50, 50, 67, 50],
    "Imaging / free-text notes":        [33, None, None, 33, None, 33, 33, 33, None, 33, None],
}

# Number of charted subdomains in each domain group (85 in total). Overall
# coverage per database = documented subdomains / 85.
DOMAIN_SIZES = {
    "Identifiers / administrative": 6, "Demographics": 5, "Diagnoses & coding": 4,
    "Surgery / anesthesia": 5, "Vital signs — intraoperative": 11,
    "Waveforms (≥125 Hz)": 5, "Ward / ICU vital signs": 4,
    "Ventilator / respiratory": 5, "Laboratory": 9, "Microbiology": 2,
    "Medications": 6, "Fluids / transfusion": 3, "Intake / output": 3,
    "Lines / devices / procedures": 5, "Severity scores": 3, "Outcomes": 6,
    "Imaging / free-text notes": 3,
}
N_SUBDOMAINS = sum(DOMAIN_SIZES.values())


def overall_coverage():
    """Documented subdomains / 85, per database, in PERIOP_COLS + ICU_COLS order."""
    cols = PERIOP_COLS + ICU_COLS
    out = []
    for j in range(len(cols)):
        k = 0
        for row in DOMAIN_ROWS:
            v = DOMAIN[row][j]
            if v:
                k += round(v / 100 * DOMAIN_SIZES[row])
        out.append(100 * k / N_SUBDOMAINS)
    return out


# ------------------------------------------------------------------ style ---
SERIF = "Liberation Serif"          # metric-compatible with Times New Roman

PALETTE = {
    "navy":    "#1F3B63",
    "teal":    "#2E7D8F",
    "amber":   "#C8802A",
    "rust":    "#A8442A",
    "slate":   "#6B7B8C",
    "plum":    "#6B4A7A",
    "olive":   "#5E7A3E",
    "grey":    "#8C8C8C",
    "ink":     "#1A1A1A",
    "rule":    "#4D4D4D",
}

REGION_COLOUR = {"USA": PALETTE["navy"], "Europe": PALETTE["teal"], "Asia": PALETTE["amber"]}
SETTING_COLOUR = {
    "Perioperative":  PALETTE["teal"],
    "Adult ICU":      PALETTE["navy"],
    "Pediatric ICU": PALETTE["amber"],
    "Mixed":          PALETTE["plum"],
    "ICU (infection)": PALETTE["rust"],
}

SETTING_OF = {
    "MIMIC-IV": "Mixed", "eICU-CRD": "Adult ICU", "INSPIRE": "Perioperative",
    "MOVER": "Perioperative", "HiRID": "Adult ICU", "NWICU": "Adult ICU",
    "SICdb": "Adult ICU", "AmsterdamUMCdb": "Adult ICU", "PIC": "Pediatric ICU",
    "VitalDB": "Perioperative", "Zigong (ZFPH)": "ICU (infection)",
}


def apply_style():
    """Journal-style matplotlib defaults: serif type, thin rules, no chartjunk."""
    import matplotlib as mpl
    mpl.rcParams.update({
        "font.family": "serif",
        "font.serif": [SERIF, "DejaVu Serif"],
        "mathtext.fontset": "dejavuserif",
        "font.size": 9,
        "axes.titlesize": 10,
        "axes.labelsize": 9.5,
        "xtick.labelsize": 8.5,
        "ytick.labelsize": 8.5,
        "legend.fontsize": 8.5,
        "axes.edgecolor": PALETTE["rule"],
        "axes.linewidth": 0.7,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "xtick.major.width": 0.7,
        "ytick.major.width": 0.7,
        "xtick.color": PALETTE["rule"],
        "ytick.color": PALETTE["rule"],
        "text.color": PALETTE["ink"],
        "axes.labelcolor": PALETTE["ink"],
        "figure.dpi": 120,
        "savefig.dpi": 600,
        "savefig.bbox": "tight",
        "savefig.pad_inches": 0.05,
        "legend.frameon": False,
    })


if __name__ == "__main__":
    print(f"Databases: {len(DATABASES)}")
    print(f"Total N:   {TOTAL_N:,}")
    from collections import defaultdict
    agg = defaultdict(lambda: [0, 0])
    for name, region, *_rest, n, basis in DATABASES:
        agg[region][0] += n
        agg[region][1] += 1
    for r, (n, k) in sorted(agg.items(), key=lambda x: -x[1][0]):
        print(f"  {r:<8} {n:>9,}  ({k} databases)")
    print("Countries:", len({d[2] for d in DATABASES}))
