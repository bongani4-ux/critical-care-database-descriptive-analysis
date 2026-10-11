#!/usr/bin/env Rscript
# =============================================================================
# Review figures in R (ggplot2 + patchwork + ragg). Port of the review team's matplotlib code (Supplemental file 6):
# same data, panels, ordering, colours and labels; typography and exact spacing differ slightly.
#
#   Rscript review_reproduction/R/make_figures.R [--values=<dir>] [--out=<dir>] [--granularity=charted|pipeline]
#
#   --values       directory holding 01_cohort.csv ... 08_overall_coverage.csv (default: review_reproduction/charted_values).
#                  Point it at an updated copy of the CSVs and every figure follows - no number is typed in this script.
#   --out          output directory (default: review_reproduction/R/figures, git-ignored)
#   --granularity  charted  = Figure S2 from 05/06 CSVs (default)
#                  pipeline = Figure S2 from this pipeline's own results (outputs/tables/<db>_granularity.csv, median per ICU stay)
# Figure numbering follows the manuscript: Figure_1 cohort, Figure_2 age and sex, Figure_3 domain coverage, Figure_4 mortality,
# Figure_5 organ support, FigureS1_flow (search flow), FigureS2_granularity.
# Differences from the matplotlib originals: hatching (infection-specific / mixed) is shown as a lighter tint; corners of the
# flow-diagram boxes and the exact label offsets are approximate.
# =============================================================================
suppressPackageStartupMessages({ library(ggplot2); library(patchwork); library(grid) })
for (p in c("ragg", "jsonlite")) if (!requireNamespace(p, quietly = TRUE)) stop("package '", p, "' is required")

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default) { a <- grep(paste0("^--", name, "="), args, value = TRUE); if (length(a)) sub(paste0("^--", name, "="), "", a[1]) else default }
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
HERE <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]), winslash = "/")) else normalizePath("review_reproduction/R", winslash = "/")
ROOT <- normalizePath(file.path(HERE, ".."), winslash = "/")
VALUES <- normalizePath(arg("values", file.path(ROOT, "charted_values")), winslash = "/")
OUT <- arg("out", file.path(HERE, "figures")); dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
GRAN <- arg("granularity", "charted")
REPO <- normalizePath(file.path(ROOT, ".."), winslash = "/")

rd <- function(f) as.data.frame(data.table::fread(file.path(VALUES, f), na.strings = c("", "NA"), encoding = "UTF-8", check.names = FALSE, data.table = FALSE))
FONT <- "serif"

# ---- palette (the review team's validated tokens) --------------------------------------------------------------------------------
BLUE <- "#2266CC"; AMBER <- "#E08A00"; GREEN <- "#178A5A"; RED <- "#CC3B2E"
INK <- "#1A1A1A"; MUTED <- "#5A6470"; HAIR <- "#C8CDD4"; RULE <- "#4D4D4D"; NAVY <- "#1F3B63"
SEQ_BLUE <- c("#F2F6FC", "#9EC0E8", "#4E8FD6", "#1B4F91"); SEQ_WARM <- c("#FDF4E8", "#F3CE95", "#DE9A33", "#95590A")
REGION_COL <- c(USA = BLUE, Europe = GREEN, Asia = AMBER)
SETTING_OF <- c("MIMIC-IV" = "Mixed", "eICU-CRD" = "Adult ICU", "INSPIRE" = "Perioperative", "MOVER" = "Perioperative", "HiRID" = "Adult ICU",
                "NWICU" = "Adult ICU", "SICdb" = "Adult ICU", "AmsterdamUMCdb" = "Adult ICU", "PIC" = "Pediatric ICU", "VitalDB" = "Perioperative",
                "Zigong (ZFPH)" = "ICU (infection)")
SETTING_COL <- c("Perioperative" = BLUE, "Adult ICU" = RED, "ICU (infection)" = "#E58A82", "Pediatric ICU" = AMBER, "Mixed" = "#7FA6E0")
SETTING_LAB <- c("Perioperative" = "Perioperative", "Adult ICU" = "Adult ICU", "ICU (infection)" = "Adult ICU (infection-specific)",
                 "Pediatric ICU" = "Pediatric ICU", "Mixed" = "Mixed hospital and ICU")

theme_review <- function(base = 9) {
  theme_minimal(base_size = base, base_family = FONT) %+replace%
    theme(text = element_text(family = FONT, colour = INK), panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line(colour = HAIR, linewidth = 0.25),
          axis.line = element_line(colour = RULE, linewidth = 0.35), axis.ticks = element_line(colour = RULE, linewidth = 0.35),
          axis.text = element_text(colour = RULE, size = base - 0.6), axis.title = element_text(colour = INK, size = base + 0.4),
          plot.title = element_text(face = "bold", size = base + 0.8, hjust = 0, margin = margin(b = 6)), plot.title.position = "plot",
          legend.title = element_text(size = base - 0.8), legend.text = element_text(size = base - 0.6), legend.key.size = unit(3.5, "mm"),
          plot.margin = margin(4, 6, 4, 4))
}

save_fig <- function(p, stem, w, h) {
  ragg::agg_png(file.path(OUT, paste0(stem, ".png")), width = w, height = h, units = "in", res = 600); print(p); invisible(dev.off())
  ragg::agg_tiff(file.path(OUT, paste0(stem, ".tif")), width = w, height = h, units = "in", res = 600, compression = "lzw"); print(p); invisible(dev.off())
  grDevices::cairo_pdf(file.path(OUT, paste0(stem, ".pdf")), width = w, height = h, family = FONT); print(p); invisible(dev.off())
  cat("  wrote", stem, "\n")
}
ptitle <- function(letter, text) paste0("(", letter, ")  ", text)

# ---- data -------------------------------------------------------------------------------------------------------------------------
cohort <- rd("01_cohort.csv"); demo <- rd("02_demographics.csv"); mort <- rd("03_mortality.csv"); org <- rd("04_organ_support.csv")
gv <- rd("05_granularity_vitals.csv"); gl <- rd("06_granularity_labs.csv"); dom <- rd("07_domain_coverage.csv"); ovr <- rd("08_overall_coverage.csv")
db_order <- cohort$database

# ---- heat-map helper (power-normalised colour scale, "—" for missing, "<0.1" for tiny values) ----------------------------------
heat <- function(M, rows, cols, ramp, vmax, fmt = "%.1f", gamma = 0.55) {
  d <- expand.grid(i = seq_along(rows), j = seq_along(cols)); d$v <- M[cbind(d$i, d$j)]
  d$norm <- ifelse(is.na(d$v), NA, pmin(d$v / vmax, 1)^gamma)
  d$lab <- ifelse(is.na(d$v), "—", ifelse(d$v > 0 & d$v < 0.05, "<0.1", sprintf(fmt, d$v)))
  d$dark <- !is.na(d$norm) & d$norm > 0.62
  ggplot(d, aes(j, i, fill = norm)) + geom_tile(colour = "white", linewidth = 0.7, width = 1, height = 1) +
    geom_text(aes(label = lab, colour = dark, fontface = ifelse(dark, "bold", "plain")), size = 7.6 / .pt, family = FONT, show.legend = FALSE) +
    scale_colour_manual(values = c(`TRUE` = "white", `FALSE` = INK), guide = "none") +
    scale_fill_gradientn(colours = ramp, limits = c(0, 1), na.value = "#F4F5F6", guide = "none") +
    scale_x_continuous(breaks = seq_along(cols), labels = cols, expand = c(0, 0)) +
    scale_y_reverse(breaks = seq_along(rows), labels = rows, expand = c(0, 0)) +
    theme_review() + theme(panel.grid = element_blank(), axis.line = element_blank(), axis.ticks = element_blank(),
                           axis.title = element_blank(), axis.text.x = element_text(angle = 38, hjust = 1, vjust = 1))
}
mat <- function(df, id) { m <- as.matrix(df[, setdiff(names(df), id), drop = FALSE]); storage.mode(m) <- "double"; m }

# ============================================================ Figure 1: cohort size ===============================================
figure1 <- function() {
  a <- cohort[order(cohort$cohort_size), ]; a$database <- factor(a$database, levels = a$database)
  pA <- ggplot(a, aes(y = database)) +
    geom_segment(aes(x = 1000, xend = cohort_size, colour = region), linewidth = 3.6, lineend = "butt") +
    geom_text(aes(x = cohort_size * 1.16, label = format(cohort_size, big.mark = ",", trim = TRUE)), hjust = 0, size = 8.2 / .pt, family = FONT) +
    scale_x_log10(limits = c(1000, 1.4e6), breaks = c(1e3, 1e4, 1e5, 1e6), labels = c("1,000", "10,000", "100,000", "1,000,000"), expand = c(0, 0)) +
    scale_colour_manual(values = REGION_COL, breaks = c("USA", "Asia", "Europe"), labels = c("United States", "Asia", "Europe"), name = "Region") +
    labs(x = "Cohort size (log scale)", y = NULL, title = ptitle("A", "Cohort size by database")) + theme_review() +
    theme(legend.position = c(0.97, 0.06), legend.justification = c(1, 0))
  agg <- aggregate(cohort_size ~ region, cohort, sum); agg <- agg[order(-agg$cohort_size), ]
  agg$lab_region <- c(USA = "United States", Asia = "Asia", Europe = "Europe")[agg$region]
  agg$names <- vapply(agg$region, function(r) paste(cohort$database[cohort$region == r], collapse = "\n"), "")
  agg$xlab <- paste0(agg$lab_region, "\n", agg$names); agg$xlab <- factor(agg$xlab, levels = agg$xlab)
  agg$n_db <- vapply(agg$region, function(r) sum(cohort$region == r), 1L)
  pB <- ggplot(agg, aes(xlab, cohort_size, fill = region)) + geom_col(width = 0.58) +
    geom_text(aes(label = paste0(format(cohort_size, big.mark = ",", trim = TRUE), "\n(", n_db, " databases)")), vjust = -0.3, size = 8.2 / .pt, family = FONT, lineheight = 0.95) +
    scale_fill_manual(values = REGION_COL, guide = "none") +
    scale_y_continuous(limits = c(0, 7e5), breaks = seq(0, 7e5, 1e5), labels = function(v) v / 1000, expand = c(0, 0)) +
    labs(x = NULL, y = "Patients (thousands)", title = ptitle("B", "Total patients by region")) + theme_review() +
    theme(axis.text.x = element_text(size = 7.4, lineheight = 1.2), panel.grid.major.x = element_blank(), panel.grid.major.y = element_line(colour = HAIR, linewidth = 0.25))
  save_fig(pA + pB + plot_layout(widths = c(1.32, 1)), "Figure_1", 7.2, 4.1)
}

# ============================================================ Figure 2: age and sex ===============================================
figure2 <- function() {
  d <- demo; d$setting <- SETTING_OF[d$database]
  a <- d[order(d$median_age_years), ]; a$database <- factor(a$database, levels = a$database)
  a$lab <- ifelse(a$database == "PIC", sprintf("%.1f [%s–%s]", a$median_age_years, a$iqr_low, a$iqr_high),
                  sprintf("%.0f [%.0f–%.0f]", a$median_age_years, a$iqr_low, a$iqr_high))
  a$lab <- ifelse(a$database == "MOVER", paste0(a$lab, "*"), a$lab)
  pA <- ggplot(a, aes(y = database)) + geom_col(aes(x = median_age_years, fill = setting), width = 0.62, orientation = "y") +
    geom_errorbar(aes(xmin = iqr_low, xmax = iqr_high), orientation = "y", width = 0.3, linewidth = 0.4, colour = INK) +
    geom_text(aes(x = iqr_high + 3, label = lab), hjust = 0, size = 7.9 / .pt, family = FONT) +
    scale_fill_manual(values = SETTING_COL, breaks = names(SETTING_LAB), labels = unname(SETTING_LAB), name = NULL) +
    scale_x_continuous(limits = c(0, 108), expand = c(0, 0)) +
    labs(x = "Age (years)", y = NULL, title = ptitle("A", "Median age with interquartile range")) + theme_review() +
    theme(legend.position = "bottom", legend.text = element_text(size = 7.2)) + guides(fill = guide_legend(nrow = 2))
  s <- demo[order(demo$percent_male), ]; s$database <- factor(s$database, levels = s$database)
  long <- rbind(data.frame(database = s$database, sex = "Male", v = s$percent_male, x = s$percent_male / 2),
                data.frame(database = s$database, sex = "Female", v = 100 - s$percent_male, x = s$percent_male + (100 - s$percent_male) / 2))
  long$sex <- factor(long$sex, levels = c("Female", "Male"))
  pB <- ggplot(long, aes(y = database, x = v, fill = sex)) + geom_col(width = 0.62, orientation = "y") +
    geom_text(aes(x = x, label = sprintf("%.1f", v)), colour = "white", fontface = "bold", size = 7.7 / .pt, family = FONT) +
    geom_vline(xintercept = 50, colour = "white", linetype = "dashed", linewidth = 0.3) +
    scale_fill_manual(values = c(Male = BLUE, Female = AMBER), breaks = c("Male", "Female"), name = NULL) +
    scale_x_continuous(limits = c(0, 100), expand = c(0, 0)) +
    labs(x = "Proportion of cohort (%)", y = NULL, title = ptitle("B", "Sex distribution")) + theme_review() + theme(legend.position = "bottom")
  save_fig(pA + pB + plot_layout(widths = c(1, 1)), "Figure_2", 7.2, 4.5)
}

# ============================================================ Figure 3: domain coverage ===========================================
figure3 <- function() {
  cols <- setdiff(names(dom), c("domain_group", "n_subdomains")); rows <- dom$domain_group
  M <- mat(dom, c("domain_group", "n_subdomains")); n_perioperative <- 3L
  M0 <- M; M0[is.na(M0)] <- 0; rowavg <- rowMeans(M0)
  ov <- ovr$percent_of_85[match(cols, ovr$database)]
  clus <- c(rep("per", n_perioperative), rep("icu", length(cols) - n_perioperative)); ccol <- ifelse(clus == "per", BLUE, RED)
  top <- ggplot(data.frame(x = seq_along(cols), v = ov, clus), aes(x, v, fill = clus)) + geom_col(width = 0.62) +
    geom_text(aes(label = sprintf("%.0f", v)), vjust = -0.4, size = 7.6 / .pt, family = FONT) +
    geom_vline(xintercept = n_perioperative + 0.5, colour = INK, linewidth = 0.4) +
    annotate("text", x = (n_perioperative + 1) / 2, y = 112, label = "PERIOPERATIVE", colour = BLUE, fontface = "bold", size = 8 / .pt, family = FONT) +
    annotate("text", x = n_perioperative + (length(cols) - n_perioperative + 1) / 2, y = 112, label = "CRITICAL CARE / ICU", colour = RED, fontface = "bold", size = 8 / .pt, family = FONT) +
    scale_fill_manual(values = c(per = BLUE, icu = RED), guide = "none") +
    scale_x_continuous(limits = c(0.4, length(cols) + 0.6), expand = c(0, 0)) + scale_y_continuous(breaks = c(0, 50, 100), limits = c(0, 118), expand = c(0, 0)) +
    labs(y = "Overall\ncoverage (%)", x = NULL) + theme_review() +
    theme(axis.text.x = element_blank(), axis.ticks.x = element_blank(), panel.grid.major.x = element_blank(), panel.grid.major.y = element_line(colour = HAIR, linewidth = 0.25))
  hm <- heat(M, rows, cols, SEQ_BLUE, 100, "%.0f", 0.55) + geom_vline(xintercept = n_perioperative + 0.5, colour = INK, linewidth = 0.5) +
    scale_x_continuous(breaks = seq_along(cols), labels = cols, expand = c(0, 0), limits = c(0.4, length(cols) + 0.6)) +
    theme(axis.text.x = element_text(angle = 38, hjust = 1, vjust = 1, colour = ccol, face = "bold"))
  rt <- ggplot(data.frame(i = seq_along(rows), v = rowavg), aes(i, v)) + geom_col(fill = "#8792A2", width = 0.62) +
    geom_text(aes(label = sprintf("%.0f", v)), hjust = -0.3, size = 7.2 / .pt, family = FONT) +
    scale_x_reverse(limits = c(length(rows) + 0.5, 0.5), expand = c(0, 0)) + scale_y_continuous(breaks = c(0, 50, 100), limits = c(0, 118), expand = c(0, 0)) +
    coord_flip() + labs(x = NULL, y = "Mean across\ndatabases (%)") + theme_review() +
    theme(axis.text.y = element_blank(), axis.ticks.y = element_blank(), panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = HAIR, linewidth = 0.25))
  p <- (top + plot_spacer() + hm + rt) + plot_layout(ncol = 2, widths = c(1, 0.2), heights = c(0.2, 1))
  save_fig(p, "Figure_3", 7.2, 7.4)
}

# ============================================================ Figure 4: mortality =================================================
figure4 <- function() {
  m <- mort; m$database <- factor(m$database, levels = db_order)
  hosp <- ifelse(!is.na(m$in_hospital_mortality_pct), m$in_hospital_mortality_pct, m$last_followup_mortality_pct)
  star <- ifelse(m$database == "AmsterdamUMCdb", "*", ifelse(m$database == "SICdb", "†", ""))
  d <- rbind(data.frame(database = m$database, type = "ICU mortality", v = m$icu_mortality_pct, star = ""),
             data.frame(database = m$database, type = "In-hospital or last-follow-up mortality", v = hosp, star = star))
  d$type <- factor(d$type, levels = c("ICU mortality", "In-hospital or last-follow-up mortality"))
  d$y <- ifelse(is.na(d$v), 0, d$v); d$lab <- ifelse(is.na(d$v), "NR", paste0(sprintf("%.1f", d$v), d$star))
  d$x <- as.integer(d$database) + ifelse(d$type == "ICU mortality", -0.19, 0.19)
  pA <- ggplot(d, aes(x, y, fill = type)) + geom_col(width = 0.38, data = d[!is.na(d$v), ]) +
    geom_text(aes(y = y + 0.6, label = lab, colour = is.na(v), fontface = ifelse(is.na(v), "italic", "plain")), angle = 90, hjust = 0, size = 7 / .pt, family = FONT) +
    scale_colour_manual(values = c(`TRUE` = "#9AA1A9", `FALSE` = INK), guide = "none") +
    scale_fill_manual(values = c(BLUE, AMBER), name = NULL) + scale_y_continuous(limits = c(0, 44), expand = c(0, 0)) +
    scale_x_continuous(breaks = seq_along(db_order), labels = db_order, expand = c(0.02, 0.02)) +
    labs(x = NULL, y = "Mortality (%)", title = ptitle("A", "ICU and in-hospital mortality")) + theme_review() +
    theme(axis.text.x = element_text(angle = 38, hjust = 1, vjust = 1), legend.position = c(0.02, 0.98), legend.justification = c(0, 1),
          panel.grid.major.x = element_blank(), panel.grid.major.y = element_line(colour = HAIR, linewidth = 0.25))
  ser <- c("Zigong (ZFPH)", "INSPIRE", "MIMIC-IV"); cols <- c(RED, BLUE, AMBER); shp <- c(16, 15, 17)
  tl <- data.frame()
  for (k in seq_along(ser)) { r <- m[m$database == ser[k], ]
    tl <- rbind(tl, data.frame(series = ser[k], x = 1:4, y = c(r$in_hospital_mortality_pct, r$day30_pct, r$day90_pct, r$year1_or_allcause_pct), off = ifelse(ser[k] == "MIMIC-IV", -3.4, 2))) }
  pB <- ggplot(tl, aes(x, y, colour = series, shape = series)) + geom_line(linewidth = 0.6) + geom_point(size = 2.4, stroke = 0.4) +
    geom_text(aes(y = y + off, label = sprintf("%.1f", y), vjust = ifelse(off > 0, 0, 1)), size = 7.4 / .pt, family = FONT, show.legend = FALSE) +
    scale_colour_manual(values = stats::setNames(cols, ser), name = NULL) + scale_shape_manual(values = stats::setNames(shp, ser), name = NULL) +
    scale_x_continuous(breaks = 1:4, labels = c("In-hospital", "30-day", "90-day", "1-year /\nall-cause"), limits = c(0.72, 4.28)) +
    scale_y_continuous(limits = c(-3, 56)) + labs(x = NULL, y = "Cumulative mortality (%)", title = ptitle("B", "Mortality trajectory")) + theme_review() +
    theme(legend.position = c(0.02, 0.98), legend.justification = c(0, 1), panel.grid.major.x = element_blank(), panel.grid.major.y = element_line(colour = HAIR, linewidth = 0.25))
  save_fig(pA + pB + plot_layout(widths = c(1.42, 1)), "Figure_4", 7.2, 4.4)
}

# ============================================================ Figure 5: organ support =============================================
figure5 <- function() {
  ord <- c("AmsterdamUMCdb", "HiRID", "Zigong (ZFPH)", "MIMIC-IV", "SICdb", "NWICU", "eICU-CRD")
  lab <- c("Mechanical ventilation", "Vasopressors or inotropes", "Renal replacement therapy")
  d <- data.frame()
  for (k in 1:3) { v <- org[[c("mechanical_ventilation_pct", "vasopressors_pct", "renal_replacement_pct")[k]]][match(ord, org$database)]
    d <- rbind(d, data.frame(database = factor(ord, levels = ord), type = factor(lab[k], levels = lab), v = v)) }
  d$y <- ifelse(is.na(d$v), 0, d$v); d$lab <- ifelse(is.na(d$v), "NR", as.character(d$v))
  d$x <- as.integer(d$database) + (as.integer(d$type) - 2) * 0.26
  p <- ggplot(d, aes(x, y, fill = type)) + geom_col(width = 0.234, data = d[!is.na(d$v), ]) +
    geom_text(aes(y = y + 1.1, label = lab, colour = is.na(v), fontface = ifelse(is.na(v), "italic", "plain"), angle = ifelse(is.na(v), 90, 0)),
              hjust = 0.5, vjust = 0, size = 7.4 / .pt, family = FONT) +
    scale_colour_manual(values = c(`TRUE` = "#9AA1A9", `FALSE` = INK), guide = "none") + scale_fill_manual(values = c(BLUE, AMBER, GREEN), name = NULL) +
    scale_x_continuous(breaks = seq_along(ord), labels = ord, expand = c(0.02, 0.02)) +
    scale_y_continuous(limits = c(0, 82), expand = c(0, 0)) + labs(x = NULL, y = "Proportion of cohort receiving support (%)") + theme_review() +
    theme(legend.position = c(0.99, 0.99), legend.justification = c(1, 1), panel.grid.major.x = element_blank(), panel.grid.major.y = element_line(colour = HAIR, linewidth = 0.25))
  save_fig(p, "Figure_5", 7.2, 3.9)
}

# ============================================================ Figure S2: granularity ==============================================
figure_s2 <- function() {
  if (identical(GRAN, "pipeline")) {
    pl <- c("SpO₂" = "spo2", "FiO₂" = "fio2", "PEEP" = "peep", "Heart rate" = "hr", "Systolic BP" = "sbp", "Cardiac output" = "co", "Medications" = "medications",
            "Fluids out" = "fluids_out", "Lactate" = "lactate", "PaO₂" = "pao2", "Sodium" = "sodium", "Hemoglobin" = "hemoglobin", "CRP" = "crp", "Creatinine" = "creatinine", "ALT" = "alt")
    ids <- c("MIMIC-IV" = "mimic_iv", "eICU-CRD" = "eicu_crd", "NWICU" = "nwicu", "HiRID" = "hirid", "SICdb" = "sicdb", "AmsterdamUMCdb" = "amsterdamumcdb", "Zigong (ZFPH)" = "zigong")
    g <- do.call(rbind, lapply(ids, function(i) { f <- file.path(REPO, "outputs", "tables", paste0(i, "_granularity.csv")); if (file.exists(f)) as.data.frame(data.table::fread(f, encoding = "UTF-8")) }))
    if (is.null(g)) stop("no outputs/tables/*_granularity.csv found: run scripts/run_granularity.R first")
    build <- function(template) { cols <- setdiff(names(template), "parameter"); M <- sapply(cols, function(cn) sapply(template$parameter, function(r) {
      v <- g$median[g$db_id == ids[[cn]] & g$parameter == pl[[r]]]; if (length(v) && !is.na(v)) v else NA_real_ })); list(M = M, rows = template$parameter, cols = cols) }
    V <- build(gv); L <- build(gl)
  } else { V <- list(M = mat(gv, "parameter"), rows = gv$parameter, cols = setdiff(names(gv), "parameter"))
           L <- list(M = mat(gl, "parameter"), rows = gl$parameter, cols = setdiff(names(gl), "parameter")) }
  pA <- heat(V$M, V$rows, V$cols, SEQ_BLUE, 57, "%.1f") + labs(title = ptitle("A", "Vital signs (records per hour)"))
  pB <- heat(L$M, L$rows, L$cols, SEQ_WARM, 8.2, "%.1f") + labs(title = ptitle("B", "Laboratory tests (records per day)"))
  save_fig(pA + pB + plot_layout(widths = c(1, 1)), "FigureS2_granularity", 7.2, 4.5)
}

# ============================================================ Figure S1: search flow ==============================================
figure_s1 <- function() {
  fc <- jsonlite::read_json(file.path(ROOT, "search_flow", "flow_counts.json"), simplifyVector = TRUE)
  reasons <- fc$reasons; if (is.matrix(reasons)) reasons <- data.frame(label = reasons[, 1], n = as.integer(reasons[, 2])) else reasons <- data.frame(label = reasons[[1]], n = as.integer(reasons[[2]]))
  n <- function(v) format(v, big.mark = ",", trim = TRUE)
  SLATE <- "#616E7C"; SIDEBG <- "#F3F5F7"; INCBG <- "#DCE6F2"; HAIRC <- "#B9C2CC"
  X_HI <- 100; Y_LO <- 16.5; Y_HI <- 99; UNIT <- 0.075; FIG_W <- X_HI * UNIT; FIG_H <- (Y_HI - Y_LO) * UNIT
  MAIN_X0 <- 10.5; MAIN_X1 <- 58; SIDE_X0 <- 61.5; SIDE_X1 <- 99; PAD <- 2.1; PITCH <- 2.5
  L <- MAIN_X0 + PAD; R <- MAIN_X1 - PAD; SL <- SIDE_X0 + PAD; SR <- SIDE_X1 - PAD; MID <- (MAIN_X0 + MAIN_X1) / 2
  g <- list()
  add <- function(x) g[[length(g) + 1L]] <<- x
  box <- function(x0, y1, x1, y0, fill = "white", edge = NAVY, lwd = 0.85, lty = "solid")
    add(annotation_custom(roundrectGrob(r = unit(0.8 * UNIT, "in"), gp = gpar(fill = fill, col = edge, lwd = lwd * 1.4, lty = lty)), xmin = x0, xmax = x1, ymin = y0, ymax = y1))
  txt <- function(x, y, s, size = 7.4, colour = INK, hjust = 0, bold = FALSE, italic = FALSE, angle = 0)
    add(annotate("text", x = x, y = y, label = s, size = size / .pt, colour = colour, hjust = hjust, fontface = if (bold && italic) "bold.italic" else if (bold) "bold" else if (italic) "italic" else "plain", angle = angle, family = FONT))
  row <- function(x0, x1, y, label, value = NULL, size = 7.4, colour = INK, bold = FALSE) { txt(x0, y, label, size, colour, 0, bold); if (!is.null(value)) txt(x1, y, value, size, colour, 1, bold) }
  down <- function(x, yt, yb, head = TRUE) add(annotate("segment", x = x, xend = x, y = yt, yend = yb, colour = NAVY, linewidth = 0.3, arrow = if (head) arrow(length = unit(1.6, "mm"), type = "closed") else NULL))
  across <- function(xf, xt, y) add(annotate("segment", x = xf, xend = xt, y = y, yend = y, colour = SLATE, linewidth = 0.3, arrow = arrow(length = unit(1.6, "mm"), type = "closed")))
  rail <- function(label, y1, y0) { add(annotation_custom(roundrectGrob(r = unit(0.8 * UNIT, "in"), gp = gpar(fill = NAVY, col = NA)), xmin = 1.6, xmax = 7.4, ymin = y0, ymax = y1))
    txt(4.5, (y0 + y1) / 2, toupper(label), 7.0, "white", 0.5, TRUE, angle = 90) }
  SOURCES <- list(c("PhysioNet repository, six topic filters", fc$repo_raw), c("PubMed, six title-phrase lines", fc$pubmed_raw), c("Web of Science Core Collection", fc$wos_raw),
                  c("Europe PMC preprint index, three queries", fc$epmc_raw), c("arXiv, two queries", fc$arxiv_raw), c("Prior reviews and citation chasing", fc$other_raw))
  # identification
  ID_Y1 <- 97; ID_H <- PAD + PITCH + 0.9 + length(SOURCES) * PITCH + PITCH - 0.5 + PAD; ID_Y0 <- ID_Y1 - ID_H
  box(MAIN_X0, ID_Y1, MAIN_X1, ID_Y0)
  y <- ID_Y1 - PAD - PITCH / 2; row(L, R, y, "Records identified from:", NULL, 8.2, NAVY, TRUE); y <- y - PITCH - 0.9
  for (s in SOURCES) { row(L + 1.4, R, y, s[1], n(as.numeric(s[2]))); y <- y - PITCH }
  rule_y <- y + PITCH / 2 + 0.15; add(annotate("segment", x = L + 1.4, xend = R, y = rule_y, yend = rule_y, colour = HAIRC, linewidth = 0.25))
  row(L + 1.4, R, y - 0.6, "Total records identified", paste0("n = ", n(fc$identified)), 7.4, NAVY, TRUE)
  repo_dupes <- fc$repo_dupes; epmc_dupes <- fc$epmc_dupes
  DUP_H <- PAD + PITCH + 1 + 2 * 2.3 + PAD; DUP_Y1 <- ID_Y1 - 5.5; DUP_Y0 <- DUP_Y1 - DUP_H
  box(SIDE_X0, DUP_Y1, SIDE_X1, DUP_Y0, SIDEBG, SLATE, 0.75)
  yy <- DUP_Y1 - PAD - PITCH / 2; row(SL, SR, yy, "Duplicate records removed", paste0("n = ", n(fc$dupes)), 7.8, SLATE, TRUE)
  yy <- yy - PITCH - 1; row(SL, SR, yy, "Across repository topic filters", n(repo_dupes), 7.1, SLATE); yy <- yy - 2.3
  row(SL, SR, yy, "Across preprint-index queries", n(epmc_dupes), 7.1, SLATE); across(MAIN_X1, SIDE_X0, (DUP_Y1 + DUP_Y0) / 2)
  # screening
  GAP <- 5.4; SC_Y1 <- ID_Y0 - GAP; SC_H <- PAD + PITCH + PAD; SC_Y0 <- SC_Y1 - SC_H
  down(MID, ID_Y0, SC_Y1); box(MAIN_X0, SC_Y1, MAIN_X1, SC_Y0)
  row(L, R, (SC_Y1 + SC_Y0) / 2, "Records screened on title and abstract", paste0("n = ", n(fc$screened)), 8.2, NAVY, TRUE)
  EX_H <- PAD + PITCH + 1 + 2.3 + PAD; EX_Y1 <- SC_Y1 + (EX_H - SC_H) / 2; EX_Y0 <- EX_Y1 - EX_H
  box(SIDE_X0, EX_Y1, SIDE_X1, EX_Y0, SIDEBG, SLATE, 0.75)
  yy <- EX_Y1 - PAD - PITCH / 2; row(SL, SR, yy, "Records excluded", paste0("n = ", n(fc$screen_excluded)), 7.8, SLATE, TRUE)
  yy <- yy - PITCH - 1; txt(SL, yy, "No named data resource described", 7.1, SLATE); across(MAIN_X1, SIDE_X0, (SC_Y1 + SC_Y0) / 2)
  # eligibility
  EL_Y1 <- SC_Y0 - GAP; EL_H <- PAD + PITCH + PAD; EL_Y0 <- EL_Y1 - EL_H
  down(MID, SC_Y0, EL_Y1); box(MAIN_X0, EL_Y1, MAIN_X1, EL_Y0)
  row(L, R, (EL_Y1 + EL_Y0) / 2, "Resources assessed at full-record level", paste0("n = ", n(fc$assessed)), 8.2, NAVY, TRUE)
  RS_H <- PAD + PITCH + 1.4 + nrow(reasons) * 2.45 + PAD; RS_Y1 <- EX_Y0 - 3.4; RS_Y0 <- RS_Y1 - RS_H
  box(SIDE_X0, RS_Y1, SIDE_X1, RS_Y0, SIDEBG, SLATE, 0.75)
  yy <- RS_Y1 - PAD - PITCH / 2; row(SL, SR, yy, "Resources excluded, with reasons", paste0("n = ", n(fc$excluded)), 7.8, SLATE, TRUE); yy <- yy - PITCH - 1.4
  for (i in seq_len(nrow(reasons))) { row(SL, SR, yy, reasons$label[i], n(reasons$n[i]), 7.1, SLATE); yy <- yy - 2.45 }
  across(MAIN_X1, SIDE_X0, (EL_Y1 + EL_Y0) / 2)
  # included
  JUNC <- EL_Y0 - 3; OUT_Y1 <- JUNC - 2.4; OUT_H <- PAD + PITCH + PITCH + 3.2 + 2.4 + PAD; OUT_Y0 <- OUT_Y1 - OUT_H
  INC_X0 <- MAIN_X0; INC_X1 <- 33; NC_X0 <- 35.5; NC_X1 <- MAIN_X1; inc_mid <- (INC_X0 + INC_X1) / 2; nc_mid <- (NC_X0 + NC_X1) / 2
  down(MID, EL_Y0, JUNC, FALSE); add(annotate("segment", x = inc_mid, xend = nc_mid, y = JUNC, yend = JUNC, colour = NAVY, linewidth = 0.3)); down(inc_mid, JUNC, OUT_Y1); down(nc_mid, JUNC, OUT_Y1)
  outcome <- function(x0, x1, l1, l2, value, caption, ...) { box(x0, OUT_Y1, x1, OUT_Y0, ...); yy <- OUT_Y1 - PAD - PITCH / 2
    txt(x0 + PAD, yy, l1, 8.2, NAVY, 0, TRUE); txt(x0 + PAD, yy - PITCH, l2, 8.2, NAVY, 0, TRUE); txt(x0 + PAD, yy - PITCH - 3.2, value, 11.5, NAVY, 0, TRUE)
    txt(x0 + PAD, yy - PITCH - 3.2 - 2.6, caption, 6.5, SLATE, 0, FALSE, TRUE) }
  outcome(INC_X0, INC_X1, "Resources included", "and charted", paste0("n = ", fc$included), "Tables 1–4; Figures 1–5", fill = INCBG, lwd = 1.25)
  outcome(NC_X0, NC_X1, "Meeting the criteria", "but not charted", paste0("n = ", fc$not_charted), "Additional file 3, Table S1", lty = "dashed", lwd = 0.85)
  S1 <- (ID_Y0 + SC_Y1) / 2; S2 <- (SC_Y0 + EL_Y1) / 2; S3 <- (EL_Y0 + OUT_Y1) / 2; G <- 0.8
  rail("Identification", ID_Y1, S1 + G / 2); rail("Screening", S1 - G / 2, S2 + G / 2); rail("Eligibility", S2 - G / 2, S3 + G / 2); rail("Included", S3 - G / 2, OUT_Y0)
  p <- ggplot() + g + scale_x_continuous(limits = c(0, X_HI), expand = c(0, 0)) + scale_y_continuous(limits = c(Y_LO, Y_HI), expand = c(0, 0)) +
    coord_fixed(ratio = 1) + theme_void() + theme(plot.margin = margin(0, 0, 0, 0), plot.background = element_rect(fill = "white", colour = NA))
  save_fig(p, "FigureS1_flow", FIG_W, FIG_H)
}

cat("Generating figures from", VALUES, "->", OUT, "\n")
figure1(); figure2(); figure3(); figure4(); figure5(); figure_s2(); figure_s1()
cat("Done\n")
