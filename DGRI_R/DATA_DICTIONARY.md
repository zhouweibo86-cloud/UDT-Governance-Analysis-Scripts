# Revision Data Dictionary

Unit: country-year. Main sample: EU27, 2022-2024, 81 observations. Each numeric field uses a decimal point. Blank source-status strings mean no flag was supplied, not missing numeric data. Greece uses EL, consistently with Eurostat and Eurobarometer. Country codes and dates are identifiers, not measures.

| Column | Definition and unit |
|---|---|
| survey_year | Calendar year of the selected Eurobarometer wave |
| country_iso2 | EU two-letter country identifier; EL for Greece |
| country_name_en | Country name in the original WJP workbook |
| user_centricity | eGovernment old-framework e_gov_1_UC, biennial national aggregate, 0-100 |
| transparency | eGovernment old-framework e_gov_2_TR, biennial national aggregate, 0-100 |
| key_enablers | eGovernment old-framework e_gov_3_KE, biennial national aggregate, 0-100 |
| egov_official_score | Official old-framework e_gov_0_score; includes cross-border services, unlike the three-pillar index; 0-100; PT reference 2021 has a documented source inconsistency |
| egov_reference_start_year | First reference year represented in the biennial life-event score |
| egov_reference_end_year | Last reference year; survey_year minus one |
| rule_of_law | WJP overall Rule of Law Index, original 0-1 score |
| wjp_index_year | Source index year, survey_year minus one; not the year of every underlying survey |
| trust_local_authorities_pct | Publisher-weighted percentage tending to trust regional or local public authorities; primary outcome |
| trust_national_government_pct | Publisher-weighted percentage tending to trust the national government; secondary outcome |
| trust_european_union_pct | Publisher-weighted percentage tending to trust the European Union; secondary outcome |
| trust_european_commission_pct | Publisher-weighted percentage tending to trust the European Commission; secondary outcome |
| trust_wave | EB97, EB99 or EB101 |
| trust_wave_season | Publisher's wave-season label; EB97 is Summer 2022 |
| trust_eu_window_start | Start of the EU-wide wave window; not a country-specific interview date |
| trust_eu_window_end | End of the EU-wide wave window; not a country-specific interview date |
| real_gdp_per_capita_eur | Eurostat nama_10_pc; annual B1GQ, CLV20_EUR_HAB; chain-linked 2020 euros per inhabitant |
| real_gdp_per_capita_eur_status | Source flags: p provisional, b break in time series; blank means no flag supplied |
| ln_real_gdp_per_capita | Natural logarithm of real_gdp_per_capita_eur |
| unemployment_rate_pct | Eurostat une_rt_a; Y15-74, total sex, PC_ACT; percentage of the labour force, not of the entire population |
| unemployment_rate_pct_status | Source flags: b break, d definition differs, bd both; blank means no flag supplied |
| hicp_inflation_pct | Eurostat prc_hicp_aind; CP00, RCH_A_AVG; annual average percentage change |
| hicp_inflation_pct_status | Observation-level flag supplied in the archived JSON; no flags on the retained observations |
| z_user_centricity | (UC minus main-sample mean) / main-sample SD, ddof=1 |
| z_key_enablers | (KE minus main-sample mean) / main-sample SD, ddof=1 |
| z_transparency | (TR minus main-sample mean) / main-sample SD, ddof=1 |
| z_rule_of_law | (ROL minus main-sample mean) / main-sample SD, ddof=1 |
| efficiency_conditions | Mean of z_user_centricity and z_key_enablers; not a unit-SD variable by itself |
| legitimacy_conditions | Mean of z_transparency and z_rule_of_law; not a unit-SD variable by itself |
| dgri_raw | Equal-weight mean of the four pillar z scores |
| dgri_sd | Standardised dgri_raw; one unit equals one main-sample SD; primary regression scale |
| dgri_0_100 | Min-max rescaling of dgri_raw within the main sample; descriptive display only |
| egov_only_raw | Equal-weight mean of UC, KE and TR z scores |
| egov_only_sd | Standardised egov_only_raw; one main-sample SD |
| egov_official_sd | Standardised official eGovernment overall score; one main-sample SD |
| efficiency_x_legitimacy | Product of the two original country-year condition scores; retain both main effects in H3 |
| mean_conditions | (efficiency_conditions + legitimacy_conditions) / 2; exactly dgri_raw; do not enter both in one model |
| signed_gap_descriptive | efficiency_conditions minus legitimacy_conditions; descriptive only, not an independent imbalance test |
| gap_positive | max(signed_gap_descriptive, 0); H4 positive-direction distance |
| gap_negative | max(-signed_gap_descriptive, 0); H4 negative-direction distance |

## Measurement Rules

The four trust outcomes retain the publisher's rounded national percentages. They are not recalculated from rounded weighted counts. The percentage denominator is all respondents, including those who answered do not know. Weighted table totals are retained in the crosswalk for audit only; they are not effective sample sizes and do not identify design effects.

All numerical explanatory measurements precede standardisation. No missing numeric value is converted to zero, no imputation is applied, and no author-created intermediate panel supplies the reconstructed values. Official biennial averaging is part of the source measurement, not author-imposed carry-forward.

The dates, source series, country-year keys, exact workbook cell or JSON position, source paths and source hashes appear in `measurement_crosswalk.csv`. The raw source inventory supplies original local paths and source URLs. Eurostat query links were reconstructed from archived dimension metadata; a fresh request may return revised values and is not a substitute for the frozen vintage.

## Scope

The panel measures national-level institutional readiness and aggregate public trust across EU member states. Indicators reflect macro-level administrative conditions and survey averages. Equality between EFF and LEG scores reflects parity on the standardized scale rather than an empirical optimum of public governance.
