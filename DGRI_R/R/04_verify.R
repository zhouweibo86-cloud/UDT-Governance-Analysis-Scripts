# Replication verification:
# Validates rebuilt panel and models against frozen references and independent OLS/sandwich estimators.

verify <- function(d, res, root, out) {
  # 1. Verify panel dataset structure and completeness
  stopifnot(
    nrow(d) == 81,
    length(unique(d$country_iso2)) == 27,
    identical(sort(unique(d$survey_year)), 2022:2024),
    !anyNA(d)
  )

  ref <- read.csv(file.path(root, "expected/main_panel_2022_2024.csv"), check.names = FALSE)
  ref <- ref[order(ref$country_iso2, ref$survey_year), ]
  for (v in grep("_status$", names(ref), value = TRUE)) {
    ref[[v]] <- as.character(ref[[v]])
    ref[[v]][is.na(ref[[v]])] <- ""
  }
  stopifnot(nrow(ref) == 81, setequal(names(ref), names(d)[names(d) %in% names(ref)]))
  for (v in names(ref)) {
    if (is.numeric(ref[[v]])) {
      stopifnot(max(abs(d[[v]] - ref[[v]])) < 1e-9)
    } else {
      stopifnot(identical(unname(as.character(d[[v]])), unname(as.character(ref[[v]]))))
    }
  }

  # 2. Check estimated coefficients and bootstrap inference against frozen outputs
  compare <- function(name, keys, fields, tolerance) {
    current <- read.csv(file.path(out, "tables", name), check.names = FALSE)
    frozen <- read.csv(file.path(root, "expected", name), check.names = FALSE)
    key <- function(x) do.call(paste, x[keys])
    ix <- match(key(current), key(frozen))
    stopifnot(nrow(current) == nrow(frozen), !anyNA(ix))
    delta <- vapply(fields, function(v) max(abs(current[[v]] - frozen[[v]][ix])), numeric(1))
    stopifnot(all(delta < tolerance))
    data.frame(file = name, field = names(delta), max_abs_difference = unname(delta))
  }

  comparisons <- rbind(
    compare(
      "all_coefficients.csv",
      c("model", "term"),
      c("estimate", "cluster_se", "ci95_low_t26", "ci95_high_t26", "p_t26"),
      1e-5
    ),
    compare(
      "bootstrap_tests.csv",
      c("model", "test"),
      c("estimate", "cluster_se", "p_t26", "p_wcr11"),
      1e-5
    )
  )
  write_csv(comparisons, file.path(out, "audit/frozen_R_comparison.csv"))

  # 3. Independent estimator cross-check: stats::lm + sandwich::vcovCL vs fixest
  independent <- list()
  for (id in names(res$models)) {
    s <- res$specs[[id]]
    main <- res$models[[id]]
    fitted_lm <- stats::lm(form(s), data = d)
    V <- sandwich::vcovCL(fitted_lm, cluster = d$country_iso2, type = "HC1", cadjust = TRUE)
    db <- max(abs(stats::coef(fitted_lm) - stats::coef(main)))
    ds <- max(abs(sqrt(diag(V)) - sqrt(diag(stats::vcov(main)))))
    stopifnot(db < 1e-5, ds < 1e-5)
    independent[[length(independent) + 1L]] <- data.frame(
      model = id,
      check = "lm plus sandwich clustered HC1",
      coefficient_difference = db,
      se_difference = ds
    )

    if (s$fe) {
      absorbed <- fixest::feols(form(s, TRUE), data = d, vcov = ~country_iso2, ssc = SSC, fixef.tol = 1e-10, notes = FALSE)
      terms <- c(s$p, s$controls)
      db <- max(abs(stats::coef(absorbed)[terms] - stats::coef(main)[terms]))
      ds <- max(abs(sqrt(diag(stats::vcov(absorbed)))[terms] - sqrt(diag(stats::vcov(main)))[terms]))
      stopifnot(db < 1e-5, ds < 1e-5)
      independent[[length(independent) + 1L]] <- data.frame(
        model = id,
        check = "fixest absorbed versus explicit effects",
        coefficient_difference = db,
        se_difference = ds
      )
    }
  }
  checks <- do.call(rbind, independent)
  write_csv(checks, file.path(out, "audit/independent_R_estimator_checks.csv"))

  # 4. Bootstrap empirical distribution validation
  for (b in res$bootstrap) {
    stopifnot(length(b$t_boot) == 9999)
    p <- mean(abs(b$t_boot) > abs(b$t_stat))
    stopifnot(abs(p - b$p_val) < 1e-12)
  }

  # 5. Check mathematical equivalence under alternative H4 parameterisation
  alt <- d
  alt$signed_gap <- d[[EFF]] - d[[LEG]]
  alt$absolute_gap <- abs(alt$signed_gap)
  s <- res$specs$h4_twfe
  s$p <- c("mean_conditions", "signed_gap", "absolute_gap")
  other <- fixest::feols(form(s), data = alt, vcov = ~country_iso2, ssc = SSC)
  stopifnot(max(abs(stats::fitted(other) - stats::fitted(res$models$h4_twfe))) < 1e-7)

  write_json(
    list(
      passed = TRUE,
      raw_panel_rows = 81,
      models = length(res$models),
      coefficient_rows = nrow(read.csv(file.path(out, "tables/all_coefficients.csv"))),
      bootstrap_tests = length(res$bootstrap),
      independent_R_checks = nrow(checks),
      compared_to = "expected_reference_outputs",
      h4_alternative_parameterisation_passed = TRUE
    ),
    file.path(out, "audit/verification.json")
  )
}
