# INSPIRE v1.3 - VERSION CHECK ONLY (not an additional database).
# The review's Table 1 names v1.3 but Supplement S3 names v1.4.2. The review's INSPIRE statistics (ICU LOS 1.04 d, 923 deaths)
# reproduce on v1.3 and NOT on v1.4.2 (ICU LOS 1.00); this wrapper re-runs the identical adapter on the v1.3 copy so the two
# versions can be compared side by side. See docs/discrepancy_report.md.
source(ccdb_path("databases", "inspire", "adapter.R"), local = TRUE)
adapter_meta$db_id <- "inspire_v1_3"
