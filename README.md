# Replication package: UDT governance readiness and institutional trust

## Purpose

This package reproduces the analysis dataset, model results and four figures for the EU27 country-year study covering 2022 to 2025. It is prepared for the Open Research Europe `Data and software availability` requirements. The packaged materials distinguish derived data, user-supplied intermediate data and externally published source data.

## Quick start

1. Install PowerShell 5.1 or later and Node.js 20 or later.
2. In this directory, install the JavaScript dependency: `npm install`.
3. Run `powershell -ExecutionPolicy Bypass -File .\scripts\run_all.ps1`.
4. Compare the newly generated contents of `output/` with the archival copies in `data/derived/` and `outputs/`.

The pipeline reads only the files included in this package. It does not download from the web.

## Package structure

| Path | Contents | Role |
|---|---|---|
| `data/input/user_supplied/` | Intermediate panel from the author's existing research project | Reproducible input containing eGovernment and rule-of-law variables used in the study |
| `data/input/eurobarometer/` | Four published Standard Eurobarometer Volume A workbooks | Source input for institutional-trust outcomes |
| `data/input/eurostat/` | Three published Eurostat JSON-stat extracts | Source input for annual controls |
| `data/derived/` | Trust panel, merged panel and final analysis dataset | Underlying derived data supporting the article |
| `scripts/` | Extraction, construction, analysis and figure-generation code | Software availability material |
| `outputs/` | Archived model results and figure files | Result verification material |
| `documentation/` | Variable dictionary and legacy source documentation | Interpretation and provenance |

## What is reproducible

`scripts/build_trust_panel.ps1` extracts four country-level trust outcomes from the included Eurobarometer workbooks. `scripts/build_analysis_dataset.ps1` merges the results with the user-supplied intermediate panel and Eurostat controls, then constructs UDT-GRI and its efficiency and legitimacy dimensions. `scripts/analysis_and_figures.mjs` estimates the reported models and renders four figures.

The final dataset contains 108 observations for 27 EU member states over four survey years. It measures national enabling conditions for UDT-oriented public services. It does not measure installed municipal digital twins or direct individual trust in a named UDT system.

## Source and reuse conditions

Full file-level provenance, including original local paths and official download links, is in `DATA_SOURCE_MANIFEST.csv`.
