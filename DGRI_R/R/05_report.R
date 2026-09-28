# Reporting and visualization:
# Generates publication tables (Tables 2-5) and graphical figures (Figures 2-4).

report <- function(d, res, root, out) {
  tests <- read.csv(file.path(out, "tables/bootstrap_tests.csv"), check.names = FALSE)
  registry <- read.csv(file.path(out, "tables/model_registry.csv"), check.names = FALSE)

  select_rows <- function(keys) {
    rows <- lapply(seq_len(nrow(keys)), function(i) {
      key <- keys[i, ]
      b <- tests[tests$model == key$model & tests$test == key$test, ]
      r <- registry[registry$model == key$model, ]
      stopifnot(nrow(b) == 1, nrow(r) == 1)
      data.frame(
        panel = key$panel,
        model = key$model,
        term = key$label,
        estimate = b$estimate,
        cr1_se = b$cluster_se,
        ci95_low_t26 = b$ci95_low_t26,
        ci95_high_t26 = b$ci95_high_t26,
        p_t26 = b$p_t26,
        p_wcr11 = b$p_wcr11,
        n = r$n,
        clusters = r$clusters,
        partial_r2 = if (key$contrast) NA_real_ else r$r_squared_incremental_beyond_included_fixed_effects
      )
    })
    do.call(rbind, rows)
  }

  keys <- function(panel, model, test, label, contrast = FALSE) {
    data.frame(panel, model, test, label, contrast, stringsAsFactors = FALSE)
  }

  # Table 3: Core baseline models
  table3 <- rbind(
    keys("Core", "dgri_pooled", "dgri_sd", "DGRI pooled"),
    keys("Core", "dgri_twfe", "dgri_sd", "DGRI TWFE"),
    keys("Core", "dgri_mundlak", "dgri_sd_within", "DGRI Mundlak within"),
    keys("Core", "dgri_mundlak", "dgri_sd_between", "DGRI Mundlak between"),
    keys("Core", "dgri_mundlak", "within_minus_between", "Within minus between", TRUE)
  )
  write_csv(select_rows(table3), file.path(out, "tables/table3_core.csv"))

  # Table 4: Component and pillar regressions
  table4 <- rbind(
    keys("A", "egov_pooled", "egov_only_sd", "eGovernment only, pooled"),
    keys("A", "rol_pooled", "z_rule_of_law", "Rule of law only, pooled"),
    keys("A", "components_pooled", "egov_only_sd", "Joint components, pooled: eGovernment"),
    keys("A", "components_pooled", "z_rule_of_law", "Joint components, pooled: rule of law"),
    keys("A", "components_twfe", "egov_only_sd", "Joint components, TWFE: eGovernment"),
    keys("A", "components_twfe", "z_rule_of_law", "Joint components, TWFE: rule of law"),
    keys("B", "four_pillars_pooled", "z_user_centricity", "User Centricity"),
    keys("B", "four_pillars_pooled", "z_key_enablers", "Key Enablers"),
    keys("B", "four_pillars_pooled", "z_transparency", "Transparency"),
    keys("B", "four_pillars_pooled", "z_rule_of_law", "Rule of Law")
  )
  write_csv(select_rows(table4), file.path(out, "tables/table4_components.csv"))

  # Table 5: Efficiency and legitimacy conditions (H2, H3, H4)
  table5 <- rbind(
    keys("H2", "h2_pooled", "efficiency_conditions", "EFF, pooled"),
    keys("H2", "h2_pooled", "legitimacy_conditions", "LEG, pooled"),
    keys("H2", "h2_twfe", "efficiency_conditions", "EFF, TWFE"),
    keys("H2", "h2_twfe", "legitimacy_conditions", "LEG, TWFE"),
    keys("H3", "h3_twfe", "efficiency_conditions", "EFF, TWFE"),
    keys("H3", "h3_twfe", "legitimacy_conditions", "LEG, TWFE"),
    keys("H3", "h3_twfe", "efficiency_x_legitimacy", "EFF x LEG, TWFE"),
    keys("H4", "h4_twfe", "mean_conditions", "Mean conditions"),
    keys("H4", "h4_twfe", "gap_positive", "Positive gap"),
    keys("H4", "h4_twfe", "gap_negative", "Negative gap"),
    keys("H4", "h4_twfe", "delta_plus_plus_delta_minus", "Additional absolute-gap contrast", TRUE),
    keys("H4", "h4_twfe", "delta_plus_minus_delta_minus", "Equal-magnitude directional contrast", TRUE)
  )
  write_csv(select_rows(table5), file.path(out, "tables/table5_dimensions.csv"))

  # Table 2: Descriptive statistics and variance decomposition
  vd <- read.csv(file.path(out, "tables/variance_decomposition.csv"), check.names = FALSE)
  keep <- c(
    "trust_local_authorities_pct", "dgri_sd", "user_centricity", "key_enablers",
    "transparency", "rule_of_law", "efficiency_conditions", "legitimacy_conditions"
  )
  write_csv(vd[match(keep, vd$variable), ], file.path(out, "tables/table2_descriptive.csv"))
  file.copy(file.path(out, "tables/correlations.csv"), file.path(out, "tables/table2_correlations.csv"))

  # Export figure underlying datasets
  country <- aggregate(d[c("dgri_sd", Y)], list(country_iso2 = d$country_iso2), mean)
  write_csv(country, file.path(out, "figures/figure2_country_means.csv"))
  forest <- select_rows(table3[!table3$contrast, ])
  write_csv(forest, file.path(out, "figures/figure3_coefficients.csv"))
  support <- d[c("country_iso2", "survey_year", EFF, LEG, Y)]
  write_csv(support, file.path(out, "figures/figure4_conditions.csv"))

  # Helper function to render figures in PNG and SVG formats
  render <- function(name, fn) {
    grDevices::png(
      file.path(out, "figures", paste0(name, ".png")),
      width = 1800,
      height = 1200,
      res = 180,
      type = "cairo"
    )
    fn()
    grDevices::dev.off()

    grDevices::svg(
      file.path(out, "figures", paste0(name, ".svg")),
      width = 10,
      height = 6.67
    )
    fn()
    grDevices::dev.off()
  }

  # Figure 2: Country averages scatter plot
  render("figure2_country_means", function() {
    par(mar = c(6, 5, 3, 1))
    plot(
      country$dgri_sd,
      country[[Y]],
      pch = 19,
      col = "#235789",
      xlab = "Mean DGRI (full-sample SD)",
      ylab = "Mean local institutional trust (%)",
      main = "EU27 country means, 2022 to 2024"
    )
    text(country$dgri_sd, country[[Y]], labels = country$country_iso2, pos = 3, cex = 0.7)
    mtext("Descriptive country averages.", side = 1, line = 4.7, cex = 0.8)
  })

  # Figure 3: Coefficient estimates and confidence intervals
  render("figure3_coefficients", function() {
    par(mar = c(6, 10, 3, 2))
    y <- nrow(forest):1
    plot(
      forest$estimate,
      y,
      xlim = range(c(forest$ci95_low_t26, forest$ci95_high_t26)),
      ylim = c(0.5, nrow(forest) + 0.5),
      pch = 19,
      col = "#235789",
      yaxt = "n",
      xlab = "Trust percentage points per one DGRI SD",
      ylab = "",
      main = "Core associations and 95% confidence intervals"
    )
    segments(forest$ci95_low_t26, y, forest$ci95_high_t26, y, col = "#235789", lwd = 2)
    abline(v = 0, lty = 2, col = "grey50")
    axis(2, at = y, labels = forest$term, las = 1, cex.axis = 0.8)
    mtext("Country-clustered CR1 intervals using t(26).", side = 1, line = 4.7, cex = 0.8)
  })

  # Figure 4: Support for conditions gap
  render("figure4_conditions", function() {
    par(mar = c(6, 5, 3, 1))
    plot(
      d[[EFF]],
      d[[LEG]],
      pch = c(1, 16, 17)[match(d$survey_year, 2022:2024)],
      col = "#235789",
      xlab = "Efficiency-related conditions (EFF)",
      ylab = "Legitimacy-related conditions (LEG)",
      main = "Observed support for the conditions gap"
    )
    abline(a = 0, b = 1, lty = 2, col = "grey50")
    legend("topleft", legend = 2022:2024, pch = c(1, 16, 17), col = "#235789", bty = "n")
    mtext("Diagonal line indicates equal standardized scores (EFF = LEG).", side = 1, line = 4.7, cex = 0.8)
  })
}
