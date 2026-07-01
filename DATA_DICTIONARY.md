# Data Dictionary

## Identification

| Variable | Definition |
|---|---|
| `country_iso2` | EU country code used in the existing panel; Greece is `EL`. |
| `survey_year` | Eurobarometer fieldwork year, 2022-2025. |
| `trust_source_wave` | Standard Eurobarometer source workbook. |

## Candidate dependent variables

All four variables are weighted percentages answering "Tend to trust".

| Variable | Trust object | Recommended use |
|---|---|---|
| `trust_local_authorities_pct` | Regional or local public authorities | Main outcome; closest institutional level to urban governance |
| `trust_national_government_pct` | National government | Robustness outcome |
| `trust_european_union_pct` | European Union | Supranational legitimacy outcome |
| `trust_european_commission_pct` | European Commission | Supranational institutional trust outcome |

## Existing explanatory variables

| Variable | Interpretation |
|---|---|
| `egov_user_centricity` | User-facing efficiency and accessibility |
| `egov_transparency` | Transparency of digital public services |
| `egov_key_enablers` | Technical and institutional digital enablers |
| `wjp_rule_of_law_overall` | Overall rule-of-law environment |
| `wjp_factor3_open_government` | Open government |
| `wjp_factor6_regulatory_enforcement` | Regulatory enforcement |
| `middleware_proxy_avg_TR_KE` | Existing transparency/key-enabler proxy |
| `digital_red_tape_index_UC_minus_middleware` | Existing efficiency-legitimacy imbalance proxy |

## UDT governance readiness variables

| Variable | Definition |
|---|---|
| `udt_governance_readiness_index` | Equal-weight mean of pooled z-scores for UC, KE, transparency, and rule of law, rescaled to 0-100 |
| `udt_efficiency_readiness_z` | Mean of standardized UC and KE |
| `udt_legitimacy_readiness_z` | Mean of standardized transparency and rule of law |
| `udt_efficiency_legitimacy_gap_z` | Efficiency readiness minus legitimacy readiness |
| `udt_efficiency_x_legitimacy` | Product term used to test conditional complementarity |

The index measures national enabling conditions for UDT-oriented governance.
It does not measure actual municipal UDT deployment.

## Macroeconomic controls

| Variable | Definition | Eurostat dataset |
|---|---|---|
| `real_gdp_per_capita_eur` | GDP per capita in chain-linked 2020 euros | `nama_10_pc` |
| `ln_real_gdp_per_capita` | Natural log of real GDP per capita | Derived |
| `unemployment_rate_pct` | Unemployment rate, total population aged 15-74 | `une_rt_a` |
| `hicp_inflation_pct` | Annual average rate of change in all-items HICP | `prc_hicp_aind` |

## Important timing note

The existing merged panel aligns each trust survey with the most recently
available e-Government benchmark:

| Trust survey year | e-Government source year |
|---|---|
| 2022 | 2021 |
| 2023 | 2022 |
| 2024 | 2023 |
| 2025 | 2024 |

For 2025, UC/TR/KE are mapped from the revised benchmark dimensions
`OSD/UFP/IS`. Models should report a sensitivity analysis excluding 2025 and
an alternative specification using the official overall e-Government score.
