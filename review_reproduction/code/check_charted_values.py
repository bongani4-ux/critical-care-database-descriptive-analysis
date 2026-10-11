"""Check that the charted-value CSVs (../charted_values) and the importable module dbdata.py agree, and that the
overall-coverage table (08) is exactly what the domain table (07) implies. Exit code 1 on any inconsistency.

    python check_charted_values.py        (run from this folder; no third-party packages needed)
"""
import csv
import os
import sys

import dbdata as D

HERE = os.path.dirname(os.path.abspath(__file__))
CSV = os.path.join(HERE, "..", "charted_values")
bad = []


def rows(name):
    with open(os.path.join(CSV, name), encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def num(x):
    return None if x in ("", None) else float(x)


def same(a, b, tag):
    if (a is None) != (b is None) or (a is not None and abs(a - b) > 1e-9):
        bad.append(f"{tag}: module={a} csv={b}")


for r in rows("01_cohort.csv"):
    d = next(x for x in D.DATABASES if x[0] == r["database"])
    same(d[4], int(r["cohort_size"]), f"cohort {r['database']}")
same(D.TOTAL_N, sum(int(r["cohort_size"]) for r in rows("01_cohort.csv")), "total N")

for r in rows("02_demographics.csv"):
    csvv = (num(r["median_age_years"]), num(r["iqr_low"]), num(r["iqr_high"]), num(r["percent_male"]))
    for a, b, k in zip(D.DEMOGRAPHICS[r["database"]], csvv, ("median", "q1", "q3", "male")):
        same(a, b, f"demographics {r['database']} {k}")

mort = {"icu_mortality_pct": "icu", "in_hospital_mortality_pct": "hosp", "last_followup_mortality_pct": "last",
        "day30_pct": "d30", "day90_pct": "d90", "year1_or_allcause_pct": "y1"}
for r in rows("03_mortality.csv"):
    for col, key in mort.items():
        same(D.MORTALITY[r["database"]][key], num(r[col]), f"mortality {r['database']} {key}")

for r in rows("04_organ_support.csv"):
    vals = (num(r["mechanical_ventilation_pct"]), num(r["vasopressors_pct"]), num(r["renal_replacement_pct"]))
    for a, b, k in zip(D.ORGAN_SUPPORT[r["database"]], vals, ("mech_vent", "vasopressor", "rrt")):
        same(a, b, f"organ support {r['database']} {k}")

for name, table, dbs in (("05_granularity_vitals.csv", D.VITALS, D.VITAL_DBS), ("06_granularity_labs.csv", D.LABS, D.LAB_DBS)):
    for r in rows(name):
        for j, db in enumerate(dbs):
            same(table[r["parameter"]][j], num(r[db]), f"{name} {r['parameter']} {db}")

cols = D.PERIOP_COLS + D.ICU_COLS
for r in rows("07_domain_coverage.csv"):
    if int(r["n_subdomains"]) != D.DOMAIN_SIZES[r["domain_group"]]:
        bad.append(f"domain size {r['domain_group']}")
    for j, db in enumerate(cols):
        same(D.DOMAIN[r["domain_group"]][j], num(r[db]), f"domain {r['domain_group']} {db}")

for r in rows("08_overall_coverage.csv"):
    implied = D.overall_coverage()[cols.index(r["database"])]
    k = round(implied * D.N_SUBDOMAINS / 100)
    if k != int(r["subdomains_documented"]) or abs(round(100 * k / D.N_SUBDOMAINS, 1) - float(r["percent_of_85"])) > 1e-9:
        bad.append(f"overall coverage {r['database']}: implied {k}, csv {r['subdomains_documented']}")

if bad:
    print("INCONSISTENT:\n  " + "\n  ".join(bad))
    sys.exit(1)
print("OK: charted CSVs, dbdata.py and the coverage arithmetic agree.")
