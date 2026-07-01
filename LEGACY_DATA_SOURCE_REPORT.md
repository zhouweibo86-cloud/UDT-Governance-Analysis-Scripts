# EU27 Citizen Trust Dataset Sources

## Core panel

The core outcome variables are extracted from the European Commission's
processed Standard Eurobarometer Volume A workbooks. These workbooks contain
weighted country-level percentages and cover all EU27 member states.

| Year | Wave | EU data portal | Direct Volume A download |
|---|---|---|---|
| 2022 | Standard Eurobarometer 97 | https://data.europa.eu/data/datasets/s2693_97_5_std97_eng?locale=en | https://webgate.ec.europa.eu/ebsm/api/public/odp/download?key=BFB9C0CCD4CDFA7AE9B5828600C2BCC7 |
| 2023 | Standard Eurobarometer 99 | https://data.europa.eu/data/datasets/s3052_99_4_std99_eng?locale=en | https://webgate.ec.europa.eu/ebsm/api/public/odp/download?key=0CCD7D6A9EDFF30E68F80A00649E91B6 |
| 2024 | Standard Eurobarometer 101 | https://data.europa.eu/data/datasets/s3216_101_3_std101_eng?locale=en | https://webgate.ec.europa.eu/ebsm/api/public/odp/download?key=202289A0E60356141402B692C20F5193 |
| 2025 | Standard Eurobarometer 103 | https://data.europa.eu/data/datasets/s3372_103_3_std103_eng?locale=en | https://webgate.ec.europa.eu/ebsm/api/public/odp/download?key=AF452C0A6DD70E5D13273C5DF2086956 |

Extracted outcomes:

- `trust_local_authorities_pct`
- `trust_national_government_pct`
- `trust_european_union_pct`
- `trust_european_commission_pct`

The wording "Tend to trust" is retained consistently across all four waves.
Question numbers vary by wave and are handled explicitly in
`build_trust_panel.ps1`.

Run the extraction and merge with:

```powershell
powershell -ExecutionPolicy Bypass -File .\build_trust_panel.ps1 `
  -ExistingPanel 'D:\path\to\panel_with_proxy.csv'
```

Without `-ExistingPanel`, the script generates only the standalone trust
panel.

## Statista traceability

Statista was used to locate and verify the original sources:

- 2022 trust in the EU by member country:
  https://www.statista.com/statistics/1640500/trust-european-union-by-member-country/
- 2024 trust in the European Commission:
  https://www.statista.com/statistics/1553228/trust-in-european-commission/
- 2025 confidence in the EU for selected countries:
  https://www.statista.com/statistics/1629893/confidence-rate-in-the-european-union-2025/

The third source is not used in the panel because it covers selected countries
and comes from the CEVIPOF Political Confidence Barometer rather than Standard
Eurobarometer.

## Supplementary sources not suitable for the core panel

These may support descriptive analysis or robustness discussion, but they
should not be merged as equivalent measures of citizen trust:

- Smart-device privacy attitudes, 2025:
  https://www.statista.com/statistics/1616757/data-privacy-smart-devices-europe/
  Coverage is limited to seven European countries.
- Trust in government handling of personal data, 2022:
  https://www.statista.com/statistics/1327932/trust-in-usa-managing-european-personal-data/
  Coverage and trust object are not aligned with the EU27 panel.
- Trust in the internet, 2021:
  https://www.statista.com/statistics/422787/europe-trust-in-the-internet-by-country/
  Outside the study period and measures generalized internet trust.

## Interpretation

The resulting dependent variables measure institutional trust, not direct
trust in Urban Digital Twin services. The strongest defensible specification
uses trust in regional or local public authorities as the main outcome, with
trust in national government, the EU, and the European Commission as
alternative outcomes.

## Generated files

- `output/EU27_citizen_trust_2022_2025.csv`: 108 observations and four trust
  outcomes.
- `output/EU27_UDT_readiness_trust_panel_2022_2025.csv`: the trust outcomes
  merged with the existing e-Government, rule-of-law, and corruption panel.
- `output/EU27_UDT_governance_readiness_analysis_2022_2025.csv`: final
  108-observation analysis file with UDT-GRI variables and controls.

## Eurostat control variables

- Real GDP per capita: `nama_10_pc`, `B1GQ`, `CLV20_EUR_HAB`
  https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/nama_10_pc
- Unemployment: `une_rt_a`, ages 15-74, total, percent of labour force
  https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/une_rt_a
- Inflation: `prc_hicp_aind`, all-items HICP, annual average rate of change
  https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/prc_hicp_aind
