# R methods and inference

## Estimating equations

Let \(Y_{it}\) denote the published country-level percentage tending to trust local or regional public authorities, \(D_{it}\) the Digital Governance Readiness Index (DGRI) in full-sample standard-deviation units, and \(X_{it}\) a vector containing log real GDP per capita, the unemployment rate, and annual HICP inflation. The specifications are:

\[
Y_{it}=a+\beta D_{it}+\gamma'X_{it}+\lambda_t+u_{it}\quad\text{(pooled OLS)},
\]

\[
Y_{it}=a+\alpha_i+\lambda_t+\beta_W D_{it}+\gamma'X_{it}+u_{it}\quad\text{(two-way fixed effects)},
\]

\[
Y_{it}=a+\lambda_t+\beta_W(D_{it}-\bar D_i)+\beta_B\bar D_i+
\gamma_W'(X_{it}-\bar X_i)+\gamma_B'\bar X_i+u_{it}\quad\text{(within-between OLS)}.
\]

The Mundlak specification is a single OLS within-between parameterisation, not a random-intercept GLS model. The fixed sample contains 81 equally weighted country-year observations from 27 countries in 2022 to 2024. Every model includes year indicators; two-way fixed-effects models also include country indicators. The main `fixest` implementation uses explicit indicators. An absorbed-effects fit checks the substantive coefficients and clustered standard errors.

## Indices and dimension models

User Centricity (UC), Key Enablers (KE), Transparency (TR), and Rule of Law (ROL) are each standardised using the 81-observation mean and sample standard deviation (denominator \(n-1\)). The unscaled composite \(C\) is the arithmetic mean of the four resulting z-scores; DGRI is \(C\) standardised to one full-sample standard deviation. Efficiency-related conditions are \(E=(z_{UC}+z_{KE})/2\), and legitimacy-related conditions are \(L=(z_{TR}+z_{ROL})/2\). Neither \(E\) nor \(L\) is subsequently standardised. Leave-one-pillar scores retain the original pillar z-scores and standardise the mean of the remaining pillars. The score omitting ROL equals the eGovernment-only index.

H2 includes \(E\) and \(L\). H3 includes \(E\), \(L\), and their product \(EL\), formed from the observed country-year values before within transformation. At \(L=\ell\), the conditional \(E\) slope is \(\beta_E+\theta\ell\). Its standard error uses the full coefficient covariance matrix. Reported conditional slopes are evaluated across five quantiles within the observed empirical support to document conditional associations across varying institutional baselines.

For H4, define \(M=(E+L)/2\), \(D^+=\max(E-L,0)\), and \(D^-=\max(L-E,0)\). The piecewise model enters \(M\), \(D^+\), and \(D^-\), without also entering \(E\) or \(L\). It tests \(\delta_+=0\), \(\delta_++\delta_-=0\), and \(\delta_+-\delta_-=0\) separately. At fixed \(M\), \(\delta_+\) is the positive-gap slope; it is not the marginal association of increasing \(E\) while holding \(L\) fixed. The parameterisation satisfies

\[
\delta_+D^++\delta_-D^-=
\frac{\delta_+-\delta_-}{2}(E-L)+
\frac{\delta_++\delta_-}{2}|E-L|.
\]

The sum contrast tests the additional absolute-gap component, or kink. The difference contrast compares equal-magnitude deviations in opposite directions at the same mean level of conditions. A zero gap reflects statistical parity between the two condition dimensions on the standardized metric rather than an optimal governance target. The analysis exports design-rank checks, support on both sides of zero, and the number of countries crossing zero.

The PCA sensitivity score uses `stats::prcomp` on the four centred pillar z-scores without further scaling. The sign of the first component is aligned with DGRI. Component weights are not replaced by their absolute values. Consistent with the empirical design, DGRI captures macro-level digital readiness and institutional conditions rather than micro-level local deployment.

## Clustered and bootstrap inference

The country-clustered CR1 covariance estimator is

\[
\widehat V_{CR1}=\frac{G}{G-1}\frac{N-1}{N-K}(X'X)^{-1}
\left(\sum_g X_g'\hat u_g\hat u_g'X_g\right)(X'X)^{-1}.
\]

Here \(G=27\), \(N=81\), and \(K\) is the rank of the full design, including the intercept, controls, substantive regressors, and all applicable country and year indicators. The `fixest` settings are `ssc(K.adj=TRUE, K.fixef="full", K.exact=TRUE, G.adj=TRUE, G.df="min", t.df=26)`. Conventional confidence intervals and p-values use a \(t(26)\) reference distribution.

The wild-cluster bootstrap uses `fwildclusterboot` 0.14.3 with `engine="R"`, `bootstrap_type="fnw11"`, `B=9999`, `type="rademacher"`, `impose_null=TRUE`, `p_val_type="two-tailed"`, `sampling="standard"`, `conf_int=FALSE`, and `nthreads=1`. Both `set.seed(20260918)` and `dqrng::dqset.seed(20260918)` are called before each test. The bootstrap small-sample settings are `boot_ssc(adj=TRUE, fixef.K="full", cluster.adj=TRUE, cluster.df="conventional")`. Explicit indicators align parameter counting with the main model.

The `fnw11` option implements the WCR11 fast wild-cluster algorithm for a single linear restriction. Each p-value is the proportion of the 9,999 random replications satisfying \(|t^*|>|t|\). The all-one weight column represents the original statistic and is not counted as a random replication. Conventional intervals are reported alongside bootstrap p-values; bootstrap intervals are not computed. All 44 tests are stored, and p-values are not adjusted for multiple comparisons.

## Diagnostics and verification

The total standard deviation uses \(n-1\) over 81 observations. The between-country standard deviation uses \(n-1\) over 27 country means. The within-country standard deviation uses \(n-1\) over 81 country-demeaned observations. The sums of squares satisfy \(SS_{total}=SS_{within}+3\sum_i(\bar x_i-\bar x)^2\); the two reported standard deviations cannot be added in quadrature. Two-way fixed-effects residual variation also removes common year effects.

`within_r_squared_including_year_fit` is \(1-SSE/\sum_{it}(Y_{it}-\bar Y_i)^2\). `r_squared_incremental_beyond_included_fixed_effects` is \(1-SSE/SS(Y\text{ residualised on included fixed effects})\). The latter removes country and year effects for two-way fixed-effects models, and the intercept and year effects for pooled and Mundlak models. It does not attribute the variation explained by country indicators to the substantive regressor.

VIF diagnostics regress each substantive predictor on the other substantive predictors after removing the effects included in its model. The approximate minimum detectable effect is \((t_{0.975,26}+z_{0.80})SE\), a two-sided 5% and target 80% precision diagnostic. It is neither observed power nor an exact bootstrap power calculation.

`R/04_verify.R` compares the rebuilt panel and numerical results with the frozen R reference files. For all 28 specifications, it independently checks coefficients and clustered standard errors with `stats::lm` and `sandwich::vcovCL(type="HC1", cadjust=TRUE)`; fixed-effects specifications are also checked against absorbed `fixest` fits. It verifies the 9,999 saved bootstrap statistics per test, their p-values, and fitted-value equivalence under an alternative H4 parameterisation. These checks verify numerical precision and consistency across estimator implementations.

The construction code documents the eGovernment reference-period pairing, the Eurobarometer question and wave windows, and the timing limitation of same-year controls. A single anomalous PT official-score cell is changed only in a source-check sensitivity model, not in the main panel. The 2025 survey is outside the analysed panel. All estimated relationships concern national-level conditional associations.

## Software documentation

The implemented interfaces are documented in [fixest small-sample corrections](https://lrberge.github.io/fixest/reference/ssc.html), the [fwildclusterboot method for `fixest`](https://s3alfisc.github.io/fwildclusterboot/reference/boottest.fixest.html), and [fwildclusterboot installation and engines](https://s3alfisc.github.io/fwildclusterboot/). These are software references, not substitutes for the paper's theoretical literature. Package versions and executed calls, rather than future online defaults, define the reproducible specification.
