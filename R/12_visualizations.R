# =============================================================================
# 12_visualizations.R - publication-style figures (300-dpi PNG).
#
# Palette and theme follow the Jinhua reference script (04_JINHUA_figures.R):
# house teal/red, single-hue sequential ramps, direct n (%) labels so colour
# never carries identity alone.
# =============================================================================

PAL_CAT   <- c("#d62839", "#2a9d8f", "#e9a13b", "#3d6da8", "#5aa832", "#c2409b", "#a8682c", "#7b5cd6")
PAL_SEX   <- c(M = "#3d6da8", F = "#d62839")
SEQ_LOW   <- "#d6efec"; SEQ_HIGH <- "#14635c"
ONE_BAR   <- "#2a9d8f"

theme_ccdb <- function(base_size = 11) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      text = ggplot2::element_text(colour = "#1a1a2e"),
      plot.title = ggplot2::element_text(face = "bold", size = base_size + 2, margin = ggplot2::margin(b = 6)),
      plot.subtitle = ggplot2::element_text(size = base_size - 1, colour = "#555555", margin = ggplot2::margin(b = 10)),
      plot.caption = ggplot2::element_text(size = base_size - 3, colour = "#888888", hjust = 0),
      axis.title = ggplot2::element_text(size = base_size - 1, colour = "#333333"),
      axis.text = ggplot2::element_text(size = base_size - 2, colour = "#444444"),
      panel.grid.major = ggplot2::element_line(colour = "#e8e8e8", linewidth = 0.3),
      panel.grid.minor = ggplot2::element_blank(),
      legend.position = "bottom",
      plot.margin = ggplot2::margin(12, 16, 12, 12))
}

save_fig <- function(p, name, width = 9, height = 6, dir = ccdb_output_dir("figures")) {
  f <- file.path(dir, paste0(name, ".png"))
  ggplot2::ggsave(f, plot = p, width = width, height = height, dpi = 300, bg = "white")
  invisible(f)
}

#' Figures for one database. Only draws what the data supports.
plot_database_figures <- function(ds, results) {
  opt_pkg("ggplot2")
  db <- ds$meta$db_id
  nm <- ds$meta$display_name %||% db
  a <- data.table::copy(ds$admission)
  cap <- sprintf("%s %s. n = %s admissions, %s patients.", nm, ds$meta$version %||% "",
                 fmt_int(nrow(a)), fmt_int(data.table::uniqueN(a$patient_id)))
  files <- character()

  # 1. age distribution by sex
  if (any(!is.na(a$age_years))) {
    p <- ggplot2::ggplot(a[!is.na(age_years)], ggplot2::aes(age_years, fill = sex)) +
      ggplot2::geom_histogram(binwidth = if (diff(range(a$age_years, na.rm = TRUE)) < 25) 1 else 2.5,
                              colour = "white", linewidth = 0.1, boundary = 0) +
      ggplot2::scale_fill_manual(values = PAL_SEX, na.value = "#9aa0a6", name = "Sex") +
      ggplot2::labs(title = paste(nm, "- age at admission"), x = "Age, years", y = "Admissions", caption = cap) +
      theme_ccdb()
    files <- c(files, save_fig(p, paste0(db, "_fig_age")))
  }
  # 2. LOS distributions
  los <- data.table::rbindlist(list(
    a[!is.na(hosp_los_days) & hosp_los_days > 0, .(type = "Hospital LOS", days = hosp_los_days)],
    a[icu_flag == 1L & !is.na(icu_los_days) & icu_los_days > 0, .(type = "ICU LOS (per admission)", days = icu_los_days)]))
  if (nrow(los)) {
    med <- los[, .(m = stats::median(days)), by = type]
    p <- ggplot2::ggplot(los, ggplot2::aes(days)) +
      ggplot2::geom_histogram(bins = 50, fill = ONE_BAR, colour = "white", linewidth = 0.1) +
      ggplot2::geom_vline(data = med, ggplot2::aes(xintercept = m), colour = "#d62839", linetype = 2) +
      ggplot2::scale_x_log10(labels = function(x) format(x, scientific = FALSE, drop0trailing = TRUE)) +
      ggplot2::facet_wrap(~type, scales = "free_y") +
      ggplot2::labs(title = paste(nm, "- length of stay"), subtitle = "Dashed line = median; log10 axis",
                    x = "Days", y = "Admissions", caption = cap) + theme_ccdb()
    files <- c(files, save_fig(p, paste0(db, "_fig_los"), width = 10, height = 5))
  }
  # 3. outcome prevalence
  o <- results[stratum == "admission" & domain == "Mortality" & stat == "n_pct", .(variable, pct, n, denominator)]
  if (nrow(o)) {
    o[, lab := sprintf("%s (%.1f%%)", fmt_int(n), pct)]
    p <- ggplot2::ggplot(o, ggplot2::aes(stats::reorder(variable, pct), pct)) +
      ggplot2::geom_col(fill = ONE_BAR, width = 0.6) +
      ggplot2::geom_text(ggplot2::aes(label = lab), hjust = -0.05, size = 3.3) +
      ggplot2::coord_flip(clip = "off") +
      ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.25))) +
      ggplot2::labs(title = paste(nm, "- mortality (definitions differ; see table notes)"),
                    x = NULL, y = "% of denominator", caption = cap) + theme_ccdb()
    files <- c(files, save_fig(p, paste0(db, "_fig_mortality"), width = 9, height = 4))
  }
  # 4. comorbidities (ICD-coded or direct flags), all units
  cm <- results[stratum == "admission" & domain == "Comorbidities" & stat == "n_pct" &
                  availability == "available" & !grepl("Any coded", variable)]
  if (nrow(cm)) {
    cm <- head(cm[order(-pct)], 15)
    p <- ggplot2::ggplot(cm, ggplot2::aes(stats::reorder(variable, pct), pct)) +
      ggplot2::geom_col(fill = ONE_BAR, width = 0.7) +
      ggplot2::geom_text(ggplot2::aes(label = sprintf("%s (%.1f%%)", fmt_int(n), pct)), hjust = -0.05, size = 3) +
      ggplot2::coord_flip(clip = "off") +
      ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.3))) +
      ggplot2::labs(title = paste(nm, "- most prevalent comorbidity groups"), x = NULL,
                    y = "% of admissions (absent code = not present)", caption = cap) + theme_ccdb()
    files <- c(files, save_fig(p, paste0(db, "_fig_comorbidities"), width = 10, height = 6.5))
  }
  # 5. measurement coverage
  mc <- results[stratum == "admission" & domain %in% c("vital", "lab") & stat == "median_iqr" &
                  !grepl("measurements in window", variable) & availability == "available"]
  if (nrow(mc)) {
    p <- ggplot2::ggplot(mc, ggplot2::aes(stats::reorder(variable, pct), pct, fill = domain)) +
      ggplot2::geom_col(width = 0.7) +
      ggplot2::geom_text(ggplot2::aes(label = sprintf("%.0f%%", pct)), hjust = -0.1, size = 3) +
      ggplot2::coord_flip(clip = "off") +
      ggplot2::scale_fill_manual(values = c(vital = PAL_CAT[4], lab = PAL_CAT[2]), name = NULL) +
      ggplot2::scale_y_continuous(limits = c(0, 110), breaks = seq(0, 100, 25)) +
      ggplot2::labs(title = paste(nm, "- measurement coverage in the first window"),
                    x = NULL, y = "% of units with >= 1 valid value", caption = cap) + theme_ccdb()
    files <- c(files, save_fig(p, paste0(db, "_fig_measurement_coverage"), width = 9, height = 6.5))
  }
  invisible(files)
}

#' Cross-database coverage heat-map of vital/lab analytes (% of units measured).
plot_cross_coverage <- function(results_all) {
  opt_pkg("ggplot2")
  mc <- results_all[stratum == "admission" & domain %in% c("vital", "lab") & stat == "median_iqr" &
                      !grepl("measurements in window", variable)]
  if (!nrow(mc)) return(invisible(NULL))
  mc[, pct_show := data.table::fifelse(availability == "available", pct, NA_real_)]
  p <- ggplot2::ggplot(mc, ggplot2::aes(db_id, stats::reorder(variable, -match(variable, unique(variable))), fill = pct_show)) +
    ggplot2::geom_tile(colour = "white") +
    ggplot2::geom_text(ggplot2::aes(label = ifelse(is.na(pct_show), "—", sprintf("%.0f", pct_show))), size = 2.8) +
    ggplot2::scale_fill_gradient(low = SEQ_LOW, high = SEQ_HIGH, na.value = "#eeeeee", limits = c(0, 100), name = "% measured") +
    ggplot2::labs(title = "Measurement coverage in the first 24 h (harmonised definition)",
                  subtitle = "Grey = not extracted / not available. Denominator = units with a defined index time.",
                  x = NULL, y = NULL) + theme_ccdb() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
  save_fig(p, "cross_database_measurement_coverage", width = 11, height = 7)
}

#' Cross-database dot plot of in-hospital mortality (denominator unit shown).
plot_cross_mortality <- function(results_all) {
  opt_pkg("ggplot2")
  m <- results_all[stratum == "patient" & variable == "In-hospital death" & stat == "n_pct"]
  if (!nrow(m)) return(invisible(NULL))
  p <- ggplot2::ggplot(m, ggplot2::aes(pct, stats::reorder(db_id, pct))) +
    ggplot2::geom_point(size = 3.2, colour = PAL_CAT[1]) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.1f%%", pct)), nudge_x = 0.6, size = 3.2) +
    ggplot2::labs(title = "In-hospital mortality (first admission per patient)",
                  subtitle = "Ascertainment differs by database - see docs/data_limitations.md",
                  x = "% died in hospital", y = NULL) + theme_ccdb()
  save_fig(p, "cross_database_hospital_mortality", width = 8, height = 5)
}
