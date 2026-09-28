# DGRI R reproducibility package

This package reconstructs the EU27 country-year panel for 2022 to 2024 from eight archived source files and reproduces the paper's R analyses, tables, and statistical figures. The primary outcome is country-level trust in local or regional public authorities. DGRI serves as an aggregate index of national digital-governance and institutional conditions across EU member states.

## Files

| Path | Contents |
| --- | --- |
| `raw/` | eGovernment Benchmark and WJP workbooks, three Eurobarometer workbooks, and three Eurostat JSON-stat extracts |
| `source_inventory.csv` | Original source URLs, file sizes, and SHA-256 hashes |
| `R/01_build_data.R` | Source checks and construction of the 81-row panel and measurement crosswalk |
| `R/02_models.R` | Index construction, 28 models, and 44 wild-cluster bootstrap tests |
| `R/03_diagnostics.R` | Variance, precision, collinearity, and support diagnostics |
| `R/04_verify.R` | Checks against frozen R outputs and independent R estimator checks |
| `R/05_report.R` | Exports for Tables 2 to 5 and Figures 2 to 4 |
| `expected/` | Frozen R results used only to verify the rebuilt outputs |
| `DATA_DICTIONARY.md` | Panel variables and units |
| `METHODS_R.md` | Model definitions, inference settings, and verification procedures |
| `renv.lock`, `restore.R`, `run_all.R` | Package versions, dependency restoration, and the full run |
| `SHA256SUMS.txt` | Checksums for the packaged files |

The archived eGovernment and WJP workbooks came from the authors' existing data holdings. The Eurobarometer and Eurostat files are archived copies of the official sources listed in `source_inventory.csv`. The 2025 Eurobarometer workbook is not included because the analysed panel ends in 2024; the Eurostat JSON extracts retain their original 2022 to 2025 download window. No preconstructed analysis panel is used as an input. Third-party files remain subject to their respective source terms.

## Run

The tested environment is R 4.6.1 on Windows. From the extracted package directory, run:

```powershell
$env:LC_ALL = 'English_United States.utf8'
& 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe' --vanilla restore.R .
& 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe' --vanilla run_all.R . reproduced_output
```

On another platform, substitute the Rscript path. If packages are restored into `.R-library`, `run_all.R` will automatically discover and load them from the package root. Dependency restoration may require internet access; the analysis itself uses only packaged inputs. `reproduced_output` must be new or empty.

## Outputs and checks

The run writes the reconstructed panel to `reproduced_output/data/`, estimates the models in `models/`, exports full coefficients and Tables 2 to 5 in `tables/`, and writes figure data, PNG, and SVG files in `figures/`. The `audit/` directory contains the measurement crosswalk, source checks, software session information, and verification results. Figure 1 is conceptual and has no statistical output.

A clean source-to-results run of this package under the locked versions produced 81 observations, 28 models, 501 coefficient rows, and 44 bootstrap tests with 9,999 replications each. The output matched the frozen R reference files at exported CSV precision; 39 independent R estimator checks also passed. The run records its checks in `audit/verification.json`, `audit/frozen_R_comparison.csv`, and `audit/completion.json`.
