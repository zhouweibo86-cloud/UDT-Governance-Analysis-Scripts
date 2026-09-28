# Econometric modeling and inference:
# Estimates pooled OLS, TWFE, and Mundlak specifications, and performs Wild Cluster Bootstrap tests.

CONTROLS <- c("ln_real_gdp_per_capita", "unemployment_rate_pct", "hicp_inflation_pct")
Z <- c("z_user_centricity", "z_key_enablers", "z_transparency", "z_rule_of_law")
EFF <- "efficiency_conditions"
LEG <- "legitimacy_conditions"
Y <- "trust_local_authorities_pct"

canonical <- function(x) {
  x <- sub("^\\(Intercept\\)$", "Intercept", x)
  x <- sub("^factor\\(country_iso2\\)", "Country: ", x)
  sub("^factor\\(survey_year\\)", "Year: ", x)
}

std <- function(x) {
  (x - mean(x)) / sd(x)
}

decompose <- function(d, vars) {
  for (v in vars) {
    d[[paste0(v, "_between")]] <- ave(d[[v]], d$country_iso2, FUN = mean)
    d[[paste0(v, "_within")]] <- d[[v]] - d[[paste0(v, "_between")]]
  }
  d
}

prepare <- function(d, out) {
  pars <- list()

  # Construct leave-one-pillar indices
  for (z in Z) {
    v <- paste0("drop_", sub("^z_", "", z), "_sd")
    raw <- rowMeans(d[setdiff(Z, z)])
    d[[v]] <- std(raw)
    pars[[length(pars) + 1]] <- data.frame(
      variable = v,
      raw_mean = mean(raw),
      raw_sd = sd(raw),
      omitted_pillar = z
    )
  }

  # Principal Component Analysis on pillar z-scores
  pc <- prcomp(d[Z], center = TRUE, scale. = FALSE)
  if (cor(pc$x[, 1], d$dgri_sd) < 0) {
    pc$x[, 1] <- -pc$x[, 1]
    pc$rotation[, 1] <- -pc$rotation[, 1]
  }

  d$pca_pc1_sd <- std(pc$x[, 1])
  eig <- pc$sdev^2
  loadings <- do.call(rbind, lapply(1:4, function(k) {
    data.frame(
      component = k,
      pillar = Z,
      eigenvalue = eig[k],
      variance_share = eig[k] / sum(eig),
      eigenvector_weight = pc$rotation[, k],
      correlation_loading = pc$rotation[, k] * sqrt(eig[k]),
      row.names = NULL
    )
  }))

  pars[[length(pars) + 1]] <- data.frame(
    variable = "pca_pc1_sd",
    raw_mean = mean(pc$x[, 1]),
    raw_sd = sd(pc$x[, 1]),
    omitted_pillar = "none"
  )

  # Check official PT source consistency
  corrected <- d$egov_official_score
  ix <- d$country_iso2 == "PT" & d$survey_year == 2022
  stopifnot(sum(ix) == 1, abs(corrected[ix] - 78.3793392717169) < 1e-9)
  corrected[ix] <- 78.99565871616136
  d$official_pt_source_check_sd <- std(corrected)

  d <- decompose(d, c("dgri_sd", "pca_pc1_sd", CONTROLS))
  stopifnot(ncol(d) == 59, max(abs(d$drop_rule_of_law_sd - d$egov_only_sd)) < 1e-12)

  write_csv(d, file.path(out, "data/analysis_panel.csv"))
  write_csv(loadings, file.path(out, "tables/pca_loadings.csv"))
  write_csv(do.call(rbind, pars), file.path(out, "tables/derived_score_parameters.csv"))
  saveRDS(pc, file.path(out, "models/pca.rds"))

  d
}

register <- function() {
  specs <- list()
  add <- function(name, p, fe = FALSE, controls = CONTROLS, outcome = Y, role = "sensitivity") {
    specs[[name]] <<- list(p = p, fe = fe, controls = controls, outcome = outcome, role = role)
  }

  for (prefix in c("dgri", "pca")) {
    score <- if (prefix == "dgri") "dgri_sd" else "pca_pc1_sd"
    role <- if (prefix == "dgri") "core" else "sensitivity"
    add(paste0(prefix, "_pooled"), score, role = role)
    add(paste0(prefix, "_twfe"), score, TRUE, role = role)
    add(
      paste0(prefix, "_mundlak"),
      paste0(score, c("_within", "_between")),
      controls = unlist(lapply(CONTROLS, function(v) paste0(v, c("_within", "_between")))),
      role = role
    )
  }

  add("egov_pooled", "egov_only_sd", role = "component")
  add("rol_pooled", "z_rule_of_law", role = "component")
  add("components_pooled", c("egov_only_sd", "z_rule_of_law"), role = "component")
  add("components_twfe", c("egov_only_sd", "z_rule_of_law"), TRUE, role = "component")
  add("four_pillars_pooled", Z, role = "component_diagnostic")

  for (z in Z[1:3]) {
    add(paste0("leave_out_", sub("^z_", "", z)), paste0("drop_", sub("^z_", "", z), "_sd"), role = "component_diagnostic")
  }

  add("h2_pooled", c(EFF, LEG), role = "dimension_supplement")
  add("h2_twfe", c(EFF, LEG), TRUE, role = "dimension")
  add("h3_twfe", c(EFF, LEG, "efficiency_x_legitimacy"), TRUE, role = "secondary")
  add("h4_twfe", c("mean_conditions", "gap_positive", "gap_negative"), TRUE, role = "secondary")

  for (prefix in c("official", "official_pt_check")) {
    score <- if (prefix == "official") "egov_official_sd" else "official_pt_source_check_sd"
    add(paste0(prefix, "_pooled"), score)
    add(paste0(prefix, "_twfe"), score, TRUE)
  }

  for (label in c("national", "eu", "commission")) {
    outcome <- c(
      national = "trust_national_government_pct",
      eu = "trust_european_union_pct",
      commission = "trust_european_commission_pct"
    )[[label]]
    add(paste0(label, "_pooled"), "dgri_sd", outcome = outcome)
    add(paste0(label, "_twfe"), "dgri_sd", TRUE, outcome = outcome)
  }

  specs
}

form <- function(s, absorb = FALSE) {
  rhs <- paste(c(s$p, s$controls), collapse = " + ")
  if (absorb && s$fe) {
    as.formula(paste(s$outcome, "~", rhs, "| country_iso2 + survey_year"))
  } else {
    as.formula(paste(s$outcome, "~", rhs, if (s$fe) "+ factor(country_iso2)" else "", "+ factor(survey_year)"))
  }
}

SSC <- fixest::ssc(K.adj = TRUE, K.fixef = "full", K.exact = TRUE, G.adj = TRUE, G.df = "min", t.df = 26)

contrast <- function(m, r) {
  w <- setNames(rep(0, length(coef(m))), names(coef(m)))
  w[names(r)] <- r
  b <- sum(w * coef(m))
  se <- sqrt(drop(t(w) %*% vcov(m) %*% w))
  t <- b / se
  data.frame(
    estimate = b,
    cluster_se = se,
    t = t,
    p_t26 = 2 * pt(-abs(t), 26),
    ci95_low_t26 = b - qt(0.975, 26) * se,
    ci95_high_t26 = b + qt(0.975, 26) * se
  )
}

analyse <- function(d, out) {
  specs <- register()
  mods <- list()
  rows <- list()
  regs <- list()
  tests <- list()
  boots <- list()
  fits <- list()

  for (id in names(specs)) {
    s <- specs[[id]]
    f <- form(s)
    m <- fixest::feols(f, data = d, vcov = ~country_iso2, ssc = SSC, data.save = FALSE, notes = FALSE)
    mods[[id]] <- m

    X <- model.matrix(f, d)
    N <- nrow(X)
    K <- ncol(X)
    stopifnot(N == 81, qr(X)$rank == K, attr(vcov(m, attr = TRUE), "df.K") == K)

    y <- d[[s$outcome]]
    u <- resid(m)
    ss <- sum(u^2)

    fe_formula <- as.formula(paste(s$outcome, "~ factor(survey_year)", if (s$fe) "+ factor(country_iso2)" else ""))
    yr <- resid(lm(fe_formula, data = d))
    yw <- y - ave(y, d$country_iso2, FUN = mean)
    r2 <- 1 - ss / sum((y - mean(y))^2)

    regs[[id]] <- data.frame(
      model = id,
      role = s$role,
      outcome = s$outcome,
      n = N,
      countries = 27,
      clusters = 27,
      country_fe = s$fe,
      year_fe = TRUE,
      k_full_design = K,
      design_rank = qr(X)$rank,
      design_condition_number = kappa(X, exact = TRUE),
      residual_df = N - K,
      inference_df = 26,
      cr1_factor = 27 / 26 * (N - 1) / (N - K),
      r_squared_overall = r2,
      r_squared_adjusted_overall = 1 - (1 - r2) * (N - 1) / (N - K),
      within_r_squared_including_year_fit = if (s$fe) 1 - ss / sum(yw^2) else NA_real_,
      r_squared_incremental_beyond_included_fixed_effects = 1 - ss / sum(yr^2),
      formula = paste(deparse(f), collapse = " ")
    )

    cv <- as.data.frame(vcov(m))
    names(cv) <- canonical(names(cv))
    cv <- cbind(term = canonical(rownames(cv)), cv)
    rownames(cv) <- NULL
    write_csv(cv, file.path(out, paste0("models/", id, "_covariance.csv")))

    xx <- as.data.frame(X)
    names(xx) <- canonical(names(xx))
    write_csv(cbind(d[c("country_iso2", "survey_year")], xx), file.path(out, paste0("models/", id, "_design.csv")))

    for (v in names(coef(m))) {
      r <- contrast(m, setNames(1, v))
      term <- canonical(v)
      original <- sub("_(within|between)$", "", term)
      scale <- if (original %in% names(d)) sd(d[[original]]) else NA_real_
      rows[[length(rows) + 1]] <- cbind(
        data.frame(model = id, term = term),
        r,
        data.frame(
          effect_scale_full_sample_sd = scale,
          estimate_per_full_sample_sd = r$estimate * scale,
          ci95_low_per_full_sample_sd = r$ci95_low_t26 * scale,
          ci95_high_per_full_sample_sd = r$ci95_high_t26 * scale
        )
      )
    }

    fits[[id]] <- data.frame(model = id, d[c("country_iso2", "survey_year")], observed = y, fitted = fitted(m), residual = u)
    targets <- lapply(s$p, function(v) setNames(1, v))
    names(targets) <- s$p

    if (id == "h4_twfe") {
      targets$delta_plus_plus_delta_minus <- c(gap_positive = 1, gap_negative = 1)
      targets$delta_plus_minus_delta_minus <- c(gap_positive = 1, gap_negative = -1)
    }
    if (id == "dgri_mundlak") {
      targets$within_minus_between <- c(dgri_sd_within = 1, dgri_sd_between = -1)
    }

    for (label in names(targets)) {
      r <- targets[[label]]
      set.seed(20260918)
      dqrng::dqset.seed(20260918)
      b <- fwildclusterboot::boottest(
        m,
        param = names(r),
        R = unname(r),
        r = 0,
        B = 9999,
        clustid = "country_iso2",
        type = "rademacher",
        impose_null = TRUE,
        bootstrap_type = "fnw11",
        p_val_type = "two-tailed",
        conf_int = FALSE,
        engine = "R",
        nthreads = 1,
        sampling = "standard",
        getauxweights = TRUE,
        ssc = fwildclusterboot::boot_ssc(adj = TRUE, fixef.K = "full", cluster.adj = TRUE, cluster.df = "conventional")
      )

      cr <- contrast(m, r)
      stopifnot(abs(b$t_stat - cr$t) < 1e-5, b$boot_iter == 9999, all(is.finite(b$t_boot)))

      tests[[length(tests) + 1]] <- cbind(
        data.frame(model = id, test = label, restriction = jsonlite::toJSON(as.list(r), auto_unbox = TRUE)),
        cr,
        data.frame(
          p_wcr11 = b$p_val,
          bootstrap_mc_se = sqrt(b$p_val * (1 - b$p_val) / 9999),
          bootstrap_t_observed = unname(b$t_stat),
          bootstrap_reps = 9999,
          seed = 20260918,
          multiplicity_adjusted = FALSE
        )
      )
      boots[[paste(id, label, sep = "__")]] <- b
      cat(id, label, "estimate =", cr$estimate, "p(R bootstrap) =", b$p_val, "\n")
    }
  }

  write_csv(do.call(rbind, rows), file.path(out, "tables/all_coefficients.csv"))
  write_csv(do.call(rbind, regs), file.path(out, "tables/model_registry.csv"))
  write_csv(do.call(rbind, tests), file.path(out, "tables/bootstrap_tests.csv"))
  write_csv(do.call(rbind, fits), file.path(out, "models/fitted_values_residuals.csv"))
  saveRDS(mods, file.path(out, "models/fixest_models.rds"))
  saveRDS(boots, file.path(out, "models/bootstrap_objects.rds"), compress = "xz")

  list(models = mods, bootstrap = boots, specs = specs)
}
