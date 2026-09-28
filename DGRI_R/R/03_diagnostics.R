# Model diagnostics:
# Computes variance decomposition, multicollinearity (VIFs), conditions support, and MDE precision.

diagnostics <- function(d, res, out) {
  # 1. Variance decomposition across panels and components
  variables <- c("dgri_sd", "user_centricity", "key_enablers", "transparency", "rule_of_law", Z, EFF, LEG, Y)
  rr <- lapply(variables, function(v) {
    x <- d[[v]]
    means <- tapply(x, d$country_iso2, mean)
    w <- x - ave(x, d$country_iso2, FUN = mean)
    tw <- resid(lm(x ~ factor(country_iso2) + factor(survey_year), data = d))
    ss <- sum((x - mean(x))^2)
    changes <- unlist(lapply(split(x, d$country_iso2), function(a) abs(diff(a))))
    data.frame(
      variable = v,
      n = 81,
      mean = mean(x),
      total_sd_ddof1 = sd(x),
      min = min(x),
      max = max(x),
      between_country_mean_sd_ddof1 = sd(means),
      within_residual_sd_ddof1 = sd(w),
      within_ss_share = sum(w^2) / ss,
      between_ss_share = 3 * sum((means - mean(x))^2) / ss,
      twfe_residual_sd_ddof1 = sd(tw),
      twfe_residual_ss_share = sum(tw^2) / ss,
      mean_absolute_annual_change = mean(changes),
      annual_changes_n = length(changes)
    )
  })
  write_csv(do.call(rbind, rr), file.path(out, "tables/variance_decomposition.csv"))

  # 2. Variance Inflation Factors (VIF) after absorbing fixed effects
  vr <- list()
  for (id in c("components_pooled", "components_twfe", "four_pillars_pooled", "h2_twfe", "h3_twfe", "h4_twfe")) {
    s <- res$specs[[id]]
    vs <- c(s$p, s$controls)
    a <- model.matrix(as.formula(paste("~ factor(survey_year)", if (s$fe) "+ factor(country_iso2)" else "")), d)
    xx <- qr.resid(qr(a), as.matrix(d[vs]))
    for (j in seq_along(vs)) {
      u <- qr.resid(qr(xx[, -j, drop = FALSE]), xx[, j])
      vif <- sum(xx[, j]^2) / sum(u^2)
      vr[[length(vr) + 1]] <- data.frame(
        model = id,
        term = vs[j],
        vif_after_included_fixed_effects = vif,
        absorption = if (s$fe) "country_and_year" else "intercept_and_year"
      )
    }
  }
  write_csv(do.call(rbind, vr), file.path(out, "tables/vif_diagnostics.csv"))

  # 3. Support checks for conditions gap (H4)
  support <- d[c("country_iso2", "survey_year", EFF, LEG, "gap_positive", "gap_negative")]
  support$gap_side <- ifelse(d$gap_positive > 0, "positive", ifelse(d$gap_negative > 0, "negative", "zero"))
  write_csv(support, file.path(out, "tables/h4_country_year_support.csv"))

  cs <- lapply(split(support, support$country_iso2), function(g) {
    data.frame(
      country_iso2 = g$country_iso2[1],
      positive_n = sum(g$gap_side == "positive"),
      negative_n = sum(g$gap_side == "negative"),
      crosses_zero = length(unique(g$gap_side)) > 1,
      gap_positive_within_sd = sd(g$gap_positive),
      gap_negative_within_sd = sd(g$gap_negative)
    )
  })
  write_csv(do.call(rbind, cs), file.path(out, "tables/h4_country_support.csv"))

  # 4. Conditional slopes across legitimacy quantiles (H3)
  conditional <- lapply(c(0.1, 0.25, 0.5, 0.75, 0.9), function(q) {
    l <- unname(quantile(d[[LEG]], q))
    r <- contrast(res$models$h3_twfe, setNames(c(1, l), c(EFF, "efficiency_x_legitimacy")))
    cbind(
      data.frame(
        legitimacy_quantile = q,
        legitimacy_value = l,
        leg_observed_min = min(d[[LEG]]),
        leg_observed_max = max(d[[LEG]])
      ),
      r
    )
  })
  write_csv(do.call(rbind, conditional), file.path(out, "tables/h3_conditional_associations.csv"))

  # 5. Approximate minimum detectable effect (MDE)
  se <- contrast(res$models$dgri_twfe, c(dgri_sd = 1))$cluster_se
  write_json(
    list(
      model = "dgri_twfe",
      cluster_se = se,
      alpha_two_sided = 0.05,
      target_power = 0.8,
      t_critical_df26 = qt(0.975, 26),
      z_power = qnorm(0.8),
      approximate_mde = (qt(0.975, 26) + qnorm(0.8)) * se,
      unit = "trust percentage points per full-main-sample SD of DGRI",
      formula = "(t_0.975,26+z_0.80)*SE",
      caution = "approximate precision diagnostic; not observed power or exact bootstrap power"
    ),
    file.path(out, "tables/precision_mde.json")
  )

  # 6. Bivariate correlation matrix
  cv <- cor(d[c("dgri_sd", "egov_only_sd", "z_rule_of_law", "pca_pc1_sd", "egov_official_sd", EFF, LEG, Y)])
  write_csv(data.frame(variable = rownames(cv), cv, check.names = FALSE, row.names = NULL), file.path(out, "tables/correlations.csv"))
}
