Supplemental file 6 — Charted data and figure-generating source code
==================================================================

Publicly Available Perioperative and Critical Care Databases: A Scoping
Review of Scope, Access, and Applications

This archive contains every value charted in the review, together with the
code that generates Figures 1-5 and Figures S1-S2 from those values. No patient-level data
are included or redistributed here; all values are database-level summary
statistics as charted from the versions named in Supplemental file 4.

CONTENTS
--------
  01_cohort.csv               Cohort size, region, country, care setting and the
                              basis of each denominator, for the 11 resources.
  02_demographics.csv         Median age with interquartile range, and the
                              percentage of male patients.
  03_mortality.csv            ICU, in-hospital, last-follow-up, 30-day, 90-day
                              and one-year or all-cause mortality.
  04_organ_support.csv        Mechanical ventilation, vasopressor and renal
                              replacement therapy utilization.
  05_granularity_vitals.csv   Vital-sign recording frequency (records per hour).
  06_granularity_labs.csv     Laboratory recording frequency (records per day).
  07_domain_coverage.csv      Percentage of subdomains documented per domain
                              group, with the number of subdomains in each.
  08_overall_coverage.csv     Subdomains documented per resource, out of 85.
  dbdata.py                   The same values as an importable Python module,
                              plus the figure styling parameters.
  make_figures.py             Generates Figures 1-5 and Figure S2 at 600 dpi
                              in PNG, TIFF and PDF.
  figure_flow.py              Generates Figure S1, the PRISMA-ScR flow diagram,
                              from flow_data.py. Every count in the diagram
                              is computed, not typed.
  flow_data.py                The study-identification flow: per-source yields,
                              duplicate and screening counts, and the exclusion
                              reason tally. Run it directly to print the flow.
  physionet_records.py        The full PhysioNet repository screen of 31 August
                              2026: every record retrieved, the topic filters it
                              appeared under, the decision and the exclusion
                              reason. Run it directly to print the flow counts.
  pubmed_records.py           The PubMed arm: the six title-phrase lines with
                              their yields, and the 19 resources the search
                              surfaced that the repository screen had not, with
                              a decision and reason for each.
  screen_records.json         The same screening record as JSON, one row per
                              resource assessed, as used in Supplemental file 2.

REPRODUCING THE FIGURES
-----------------------
  python3 -m pip install "matplotlib>=3.8" numpy
  python3 make_figures.py     # Figures 1-5 and Figure S2
  python3 figure_flow.py      # Figure S1

Output is written to ./figures/. figure_flow.py imports flow_data.py, which in
turn imports the screening records, so editing a screening decision there
regenerates Figure S1 with the corrected counts automatically. The figures use a serif typeface metrically
compatible with Times New Roman; if it is unavailable the code falls back to
DejaVu Serif without altering layout.

MISSING VALUES
--------------
Empty cells and the Python value None denote a measurement or endpoint that the
resource does not capture. Where a resource captures an endpoint but does not
publish a summary statistic for it, this is recorded as "not reported" in
Table 3 of the main article rather than as a missing value here.

NOTES ON PARTICULAR VALUES
--------------------------
- MOVER is reported as a single resource (58,799 unique patients; 83,468
  surgical cases). Sub-cohort figures are retained in dbdata.MOVER_SUBCOHORTS.
- VitalDB's denominator is surgical cases, not deduplicated patients.
- MOVER's median age is the patient-weighted mean of the EPIC and SIS
  sub-cohort medians; its interquartile range spans the union of the two.
- NWICU's in-hospital mortality is given at the patient level; the admission-
  level and ICU-stay denominators are reported in Table 3.
- AmsterdamUMCdb records only vital status at last follow-up, which mixes
  in-hospital with post-discharge death.

SEARCH AND SCREENING
--------------------
Six sources were searched between 31 August and 2 September 2026.

  Repository      PhysioNet screened in full across six topic filters, 148
                  records, 41 duplicates removed, 107 unique projects.
  PubMed          Six title-phrase lines, 95 records, of which 76 described or
                  analyzed an already identified resource; 19 resources
                  remained.
  Web of Science  Core Collection, setting by resource by availability,
                  1,231 records.
  Europe PMC      Preprint index, three title-field queries, 185 records,
                  177 unique.
  arXiv           Two queries, 16 records.
  Other sources   3 resources from the four prior comparative reviews and
                  citation chasing.

1,678 records were identified and 1,629 screened after duplicates. 190 candidate
resources were assessed at full-record level: 11 charted, 5 reported in
Table S1, 174 excluded with a reason recorded for each. PhysioNet was the
only repository screened systematically. Every query, yield and decision is
given in Supplemental file 2.

Charted values are current as of 30 June 2026; the repository screen and all
access pathways are current as of 2 September 2026.
