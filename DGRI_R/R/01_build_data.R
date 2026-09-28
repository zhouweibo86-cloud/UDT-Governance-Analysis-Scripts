# Data construction pipeline:
# Builds the EU27 country-year panel (2022-2024) from official source files.

build_data <- function(root, out) {
  # 1. Verify integrity of raw input files
  inventory <- read.csv(file.path(root, "source_inventory.csv"), fileEncoding = "UTF-8-BOM", check.names = FALSE)
  raw <- inventory[startsWith(inventory$file, "raw/"), ]
  for (j in seq_len(nrow(raw))) {
    stopifnot(digest::digest(file = file.path(root, raw$file[j]), algo = "sha256") == raw$sha256[j])
  }

  # 2. Define EU27 country identifiers and panel grid
  countries <- strsplit("AT BE BG CY CZ DE DK EE EL ES FI FR HR HU IE IT LT LU LV MT NL PL PT RO SE SI SK", " ")[[1]]
  iso3 <- strsplit("AUT BEL BGR CYP CZE DEU DNK EST GRC ESP FIN FRA HRV HUN IRL ITA LTU LUX LVA MLT NLD POL PRT ROU SWE SVN SVK", " ")[[1]]
  names(iso3) <- countries

  d <- expand.grid(country_iso2 = countries, survey_year = 2022:2024, stringsAsFactors = FALSE)
  d <- d[c("survey_year", "country_iso2")]

  cross <- list()
  checks <- list()
  windows <- list()

  trace <- function(i, v, value, file, sheet, cell, code, period, transform) {
    info <- inventory[inventory$file == file, ]
    stopifnot(nrow(info) == 1)
    cross[[length(cross) + 1L]] <<- data.frame(
      country_iso2 = d$country_iso2[i],
      survey_year = d$survey_year[i],
      variable = v,
      source_value = value,
      packaged_source_file = file,
      worksheet = sheet,
      cell_or_json_key = cell,
      series_code = code,
      reference_period = period,
      transformation = transform,
      original_source_url = info$original_source_url,
      source_sha256 = info$sha256,
      stringsAsFactors = FALSE
    )
  }

  excel <- function(file, sheet) {
    x <- as.data.frame(readxl::read_excel(file.path(root, file), sheet = sheet, guess_max = 100000), check.names = FALSE)
    x$source_row <- seq_len(nrow(x)) + 1L
    x
  }

  # 3. Read and process eGovernment Benchmark data
  e <- excel("raw/egovernment.xlsx", "Machine readable format (2024)")
  e$Value <- suppressWarnings(as.numeric(e$Value))
  codes <- c(
    user_centricity = "e_gov_1_UC",
    transparency = "e_gov_2_TR",
    key_enablers = "e_gov_3_KE",
    egov_official_score = "e_gov_0_score"
  )
  for (v in names(codes)) {
    d[[v]] <- NA_real_
  }

  for (i in seq_len(nrow(d))) {
    cy <- d$country_iso2[i]
    sy <- d$survey_year[i] - 1L
    br <- if (cy == "AT" && sy == 2023) "EGOV_LIFE_EVENTS_2023" else "EGOV_LIFE_EVENTS"

    for (v in names(codes)) {
      ix <- which(e$Country == cy & e$year == sy & e$variable == codes[v] & e$brkdown == br)
      stopifnot(length(ix) == 1)
      r <- e[ix, ]
      value <- as.numeric(r$Value)
      stopifnot(is.finite(value), value >= 0, value <= 100)

      ev <- e[which(e$Country == cy & e$variable == codes[v] & e$year %in% c(sy - 1, sy) & grepl("^e_gov_EVENTS_[1-9]$", e$brkdown)), ]
      stopifnot(nrow(ev) == 9, length(unique(ev$brkdown)) == 9)
      delta <- mean(ev$Value) - value
      stopifnot(abs(delta) < 1e-9 || (cy == "PT" && sy == 2021 && v == "egov_official_score" && abs(delta - 0.6163194444444571) < 1e-9))

      checks[[length(checks) + 1]] <- data.frame(
        country_iso2 = cy,
        survey_year = d$survey_year[i],
        variable = v,
        official_value = value,
        nine_event_mean = mean(ev$Value),
        difference = delta,
        event_rows = paste(ev$source_row, collapse = ";")
      )
      d[[v]][i] <- value
      trace(
        i, v, value, "raw/egovernment.xlsx", "Machine readable format (2024)",
        paste0("F", r$source_row), codes[v], paste(sy - 1, sy, sep = "-"),
        "identity; official biennial score"
      )
    }
  }

  d$egov_reference_end_year <- d$survey_year - 1L
  d$egov_reference_start_year <- d$survey_year - 2L

  # 4. Extract World Justice Project Rule of Law Index
  w <- excel("raw/wjp.xlsx", "Historical Data")
  d$rule_of_law <- NA_real_
  d$country_name_en <- ""
  d$wjp_index_year <- d$survey_year - 1L

  for (i in seq_len(nrow(d))) {
    ix <- which(w[["Country Code"]] == iso3[d$country_iso2[i]] & as.character(w$Year) == as.character(d$survey_year[i] - 1L))
    stopifnot(length(ix) == 1)
    r <- w[ix, ]
    value <- as.numeric(r[["WJP Rule of Law Index: Overall Score"]])
    stopifnot(is.finite(value), value >= 0, value <= 1)

    d$rule_of_law[i] <- value
    d$country_name_en[i] <- r$Country
    trace(
      i, "rule_of_law", value, "raw/wjp.xlsx", "Historical Data",
      paste0("F", r$source_row), "WJP overall score", as.character(d$survey_year[i] - 1),
      "identity; index year, not common GPP/QRQ fieldwork year"
    )
  }

  # 5. Extract Eurobarometer institutional trust outcomes
  waves <- c(97, 99, 101)
  sheets <- list(
    c("QA6a_7", "QA6a_9", "QA6a_11", "QA10_2"),
    c("QA6_7", "QA6_9", "QA6_11", "QA11_2"),
    c("QA6_6", "QA6_8", "QA6_10", "QA10_2")
  )
  vars <- c("trust_local_authorities_pct", "trust_national_government_pct", "trust_european_union_pct", "trust_european_commission_pct")
  titles <- c("Regional or local public authorities", "Government", "European Union", "European Commission")
  starts <- c("2022-06-17", "2023-05-31", "2024-04-03")
  ends <- c("2022-07-17", "2023-06-21", "2024-04-28")
  seasons <- c("Summer 2022", "Spring 2023", "Spring 2024")

  col_letter <- function(n) {
    z <- ""
    while (n > 0) {
      n <- n - 1
      z <- paste0(LETTERS[n %% 26 + 1], z)
      n <- n %/% 26
    }
    z
  }

  for (v in vars) {
    d[[v]] <- NA_real_
  }

  for (j in seq_along(waves)) {
    y <- 2021 + j
    file <- sprintf("raw/eurobarometer/EB%d_%d_Volume_A.xlsx", waves[j], y)
    for (k in 1:4) {
      x <- as.matrix(readxl::read_excel(
        file.path(root, file),
        sheet = sheets[[j]][k],
        col_names = FALSE,
        col_types = "text",
        range = readxl::cell_limits(c(1, 1), c(NA, NA)),
        .name_repair = "minimal"
      ))
      stopifnot(grepl(titles[k], x[4, 8], ignore.case = TRUE, fixed = FALSE))

      header <- which(apply(x, 1, function(z) all(c("BE", "DE", "FR") %in% z)))
      trust <- which(x[, 2] == "Tend to trust")
      total <- which(x[, 2] == "Total")
      stopifnot(length(header) == 1, length(trust) == 1, length(total) == 1)

      for (cy in countries) {
        col <- which(x[header, ] == cy)
        stopifnot(length(col) == 1)
        value <- as.numeric(x[trust, col])
        stopifnot(is.finite(value), value >= 0, value <= 1)

        if (y <= 2024) {
          i <- which(d$country_iso2 == cy & d$survey_year == y)
          d[[vars[k]]][i] <- value * 100
          d$trust_wave[i] <- paste0("EB", waves[j])
          d$trust_wave_season[i] <- seasons[j]
          d$trust_eu_window_start[i] <- starts[j]
          d$trust_eu_window_end[i] <- ends[j]
          trace(
            i, vars[k], value, file, sheets[[j]][k], paste0(col_letter(col), trust),
            paste0(sheets[[j]][k], "|Tend to trust"), as.character(y),
            "publisher-weighted share multiplied by 100; all respondents"
          )
        }
      }
      windows[[length(windows) + 1]] <- data.frame(
        survey_year = y,
        wave = waves[j],
        variable = vars[k],
        sheet = sheets[[j]][k],
        institution = x[4, 8],
        question = x[3, 8],
        workbook_fieldwork_header = x[2, 8],
        eu_window_start = starts[j],
        eu_window_end = ends[j],
        season = seasons[j]
      )
    }
  }

  # 6. Extract Eurostat macroeconomic controls (JSON-stat)
  controls <- list(
    real_gdp_per_capita_eur = list("gdp_per_capita_real_2022_2025.json", c(freq = "A", unit = "CLV20_EUR_HAB", na_item = "B1GQ")),
    unemployment_rate_pct = list("unemployment_2022_2025.json", c(freq = "A", age = "Y15-74", unit = "PC_ACT", sex = "T")),
    hicp_inflation_pct = list("hicp_inflation_2022_2025.json", c(freq = "A", unit = "RCH_A_AVG", coicop = "CP00"))
  )

  for (v in names(controls)) {
    file <- paste0("raw/eurostat/", controls[[v]][[1]])
    sel <- controls[[v]][[2]]
    obj <- jsonlite::fromJSON(file.path(root, file), simplifyVector = FALSE)
    ids <- unlist(obj$id)
    sizes <- unlist(obj$size)

    for (n in names(sel)) {
      stopifnot(identical(names(obj$dimension[[n]]$category$index), unname(sel[n])))
    }

    for (i in seq_len(nrow(d))) {
      coords <- c(sel, geo = d$country_iso2[i], time = as.character(d$survey_year[i]))
      pos <- 0
      for (j in seq_along(ids)) {
        pos <- pos * sizes[j] + obj$dimension[[ids[j]]]$category$index[[coords[ids[j]]]]
      }
      value <- obj$value[[as.character(pos)]]
      stopifnot(length(value) == 1, is.finite(value))
      flag <- obj$status[[as.character(pos)]]
      if (is.null(flag)) flag <- ""
      d[[v]][i] <- value
      d[[paste0(v, "_status")]][i] <- flag
      trace(
        i, v, value, file, "JSON-stat", paste0("value[", pos, "]"),
        obj$extension$id, as.character(d$survey_year[i]),
        "identity; contemporaneous annual control includes post-interview months"
      )
    }
  }

  stopifnot(all(d$real_gdp_per_capita_eur > 0))
  d$ln_real_gdp_per_capita <- log(d$real_gdp_per_capita_eur)

  # 7. Standardize indicators and construct composite indices
  pars <- list()
  standardise <- function(source, target) {
    m <- mean(d[[source]])
    s <- sd(d[[source]])
    stopifnot(is.finite(s), s > 0)
    d[[target]] <<- (d[[source]] - m) / s
    pars[[length(pars) + 1]] <<- data.frame(
      source_variable = source,
      target_variable = target,
      n = 81,
      mean = m,
      sample_sd = s,
      sd_ddof = 1
    )
  }

  pillars <- c("user_centricity", "key_enablers", "transparency", "rule_of_law")
  for (v in pillars) {
    standardise(v, paste0("z_", v))
  }

  d$efficiency_conditions <- rowMeans(d[c("z_user_centricity", "z_key_enablers")])
  d$legitimacy_conditions <- rowMeans(d[c("z_transparency", "z_rule_of_law")])
  d$dgri_raw <- rowMeans(d[paste0("z_", pillars)])
  standardise("dgri_raw", "dgri_sd")

  d$dgri_0_100 <- 100 * (d$dgri_raw - min(d$dgri_raw)) / diff(range(d$dgri_raw))
  d$egov_only_raw <- rowMeans(d[paste0("z_", pillars[1:3])])
  standardise("egov_only_raw", "egov_only_sd")
  standardise("egov_official_score", "egov_official_sd")

  d$efficiency_x_legitimacy <- d$efficiency_conditions * d$legitimacy_conditions
  d$mean_conditions <- (d$efficiency_conditions + d$legitimacy_conditions) / 2
  d$signed_gap_descriptive <- d$efficiency_conditions - d$legitimacy_conditions
  d$gap_positive <- pmax(d$signed_gap_descriptive, 0)
  d$gap_negative <- pmax(-d$signed_gap_descriptive, 0)

  stopifnot(nrow(d) == 81, ncol(d) == 43, !anyNA(d), !anyDuplicated(d[c("country_iso2", "survey_year")]))

  # Audit the excluded current framework without using it in the main sample
  cur <- excel("raw/egovernment.xlsx", "Machine readable format")
  excluded <- list()
  for (cy in countries) {
    for (code in c("e_gov_1_OSD", "e_gov_3_UFP", "e_gov_2_IS", "DESI_tr")) {
      rr <- cur[which(cur$Country == cy & cur$year == 2024 & cur$variable == code & cur$brkdown == "EGOV_LIFE_EVENTS"), ]
      stopifnot(nrow(rr) == 1)
      excluded[[length(excluded) + 1]] <- data.frame(
        country_iso2 = cy,
        survey_year = 2025,
        source_code = code,
        source_value = rr$Value,
        source_cell = paste0("F", rr$source_row),
        included = FALSE,
        reason = "changed framework; excluded from standardisation and models"
      )
    }
  }

  # 8. Export built dataset and audit records
  write_csv(d, file.path(out, "data/main_panel_2022_2024.csv"))
  write_csv(do.call(rbind, pars), file.path(out, "data/standardisation_parameters.csv"))
  write_csv(do.call(rbind, cross), file.path(out, "audit/measurement_crosswalk.csv"))
  write_csv(do.call(rbind, checks), file.path(out, "audit/egov_biennial_reconstruction.csv"))
  write_csv(do.call(rbind, windows), file.path(out, "audit/survey_wave_metadata.csv"))
  write_csv(do.call(rbind, excluded), file.path(out, "audit/2025_excluded_framework.csv"))
  write_json(
    list(
      n = 81,
      countries = 27,
      years = 2022:2024,
      missing = 0,
      imputed = 0,
      source_files = nrow(raw),
      crosswalk_rows = length(cross),
      primary_pillar_aggregates_verified = 243,
      known_overall_anomaly = "PT 2021 retained official overall; DGRI unaffected"
    ),
    file.path(out, "audit/raw_rebuild.json")
  )

  d[order(d$country_iso2, d$survey_year), ]
}
