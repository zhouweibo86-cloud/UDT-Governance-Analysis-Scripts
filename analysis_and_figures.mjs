import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const inferredRoot = fs.existsSync(path.join(moduleDirectory, "output"))
  ? moduleDirectory
  : path.dirname(moduleDirectory);
const root =
  (typeof process !== "undefined" && process.env.UDT_WORKSPACE) ||
  inferredRoot;
const input = path.join(
  root,
  "output",
  "EU27_UDT_governance_readiness_analysis_2022_2025.csv"
);
// Codex writes to a temporary directory, while a standard Node.js run writes
// directly to the local output directory beside this script.
const outDir =
  typeof nodeRepl !== "undefined"
    ? path.join(nodeRepl.tmpDir, "udt_paper_output")
    : path.join(root, "output");
const figureDir = path.join(outDir, "figures");
fs.mkdirSync(outDir, { recursive: true });
fs.mkdirSync(figureDir, { recursive: true });

function parseCSV(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    if (quoted) {
      if (char === '"' && text[i + 1] === '"') {
        field += '"';
        i += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        field += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n") {
      row.push(field.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += char;
    }
  }
  if (field.length || row.length) {
    row.push(field.replace(/\r$/, ""));
    rows.push(row);
  }
  const headers = rows.shift();
  headers[0] = headers[0].replace(/^\uFEFF/, "");
  return rows
    .filter((values) => values.length === headers.length)
    .map((values) =>
      Object.fromEntries(headers.map((header, index) => [header, values[index]]))
    );
}

const data = parseCSV(fs.readFileSync(input, "utf8"));
const textFields = new Set([
  "country_iso2",
  "country_name_en",
  "trust_source_wave",
  "egov_overall_score_source",
  "agg_method",
  "dimension_proxy_note",
  "uc_tr_ke_source_type",
  "source_dataset",
  "year_label"
]);
for (const row of data) {
  for (const [key, value] of Object.entries(row)) {
    if (!textFields.has(key) && value !== "") {
      const number = Number(value);
      if (!Number.isNaN(number)) {
        row[key] = number;
      }
    }
  }
  row.gri10 = row.udt_governance_readiness_index / 10;
}

function dot(a, b) {
  return a.reduce((sum, value, index) => sum + value * b[index], 0);
}

function invert(matrix) {
  const n = matrix.length;
  const augmented = matrix.map((row, i) =>
    row.concat(Array.from({ length: n }, (_, j) => (i === j ? 1 : 0)))
  );
  for (let i = 0; i < n; i += 1) {
    let pivot = i;
    for (let r = i + 1; r < n; r += 1) {
      if (Math.abs(augmented[r][i]) > Math.abs(augmented[pivot][i])) {
        pivot = r;
      }
    }
    if (Math.abs(augmented[pivot][i]) < 1e-10) {
      throw new Error(`Singular matrix at column ${i}`);
    }
    [augmented[i], augmented[pivot]] = [augmented[pivot], augmented[i]];
    const divisor = augmented[i][i];
    for (let j = 0; j < 2 * n; j += 1) {
      augmented[i][j] /= divisor;
    }
    for (let r = 0; r < n; r += 1) {
      if (r === i) continue;
      const factor = augmented[r][i];
      for (let j = 0; j < 2 * n; j += 1) {
        augmented[r][j] -= factor * augmented[i][j];
      }
    }
  }
  return augmented.map((row) => row.slice(n));
}

function multiplyMatrixVector(matrix, vector) {
  return matrix.map((row) => dot(row, vector));
}

function logGamma(z) {
  const coefficients = [
    0.9999999999998099,
    676.5203681218851,
    -1259.1392167224028,
    771.3234287776531,
    -176.6150291621406,
    12.507343278686905,
    -0.13857109526572012,
    9.984369578019571e-6,
    1.5056327351493116e-7
  ];
  if (z < 0.5) {
    return (
      Math.log(Math.PI) -
      Math.log(Math.sin(Math.PI * z)) -
      logGamma(1 - z)
    );
  }
  const shifted = z - 1;
  let x = coefficients[0];
  for (let i = 1; i < coefficients.length; i += 1) {
    x += coefficients[i] / (shifted + i);
  }
  const t = shifted + coefficients.length - 1.5;
  return (
    0.5 * Math.log(2 * Math.PI) +
    (shifted + 0.5) * Math.log(t) -
    t +
    Math.log(x)
  );
}

function betaContinuedFraction(a, b, x) {
  const tiny = 3e-14;
  const qab = a + b;
  const qap = a + 1;
  const qam = a - 1;
  let c = 1;
  let d = 1 - (qab * x) / qap;
  if (Math.abs(d) < tiny) d = tiny;
  d = 1 / d;
  let h = d;
  for (let m = 1; m <= 200; m += 1) {
    const m2 = 2 * m;
    let aa = (m * (b - m) * x) / ((qam + m2) * (a + m2));
    d = 1 + aa * d;
    if (Math.abs(d) < tiny) d = tiny;
    c = 1 + aa / c;
    if (Math.abs(c) < tiny) c = tiny;
    d = 1 / d;
    h *= d * c;
    aa = (-(a + m) * (qab + m) * x) / ((a + m2) * (qap + m2));
    d = 1 + aa * d;
    if (Math.abs(d) < tiny) d = tiny;
    c = 1 + aa / c;
    if (Math.abs(c) < tiny) c = tiny;
    d = 1 / d;
    const delta = d * c;
    h *= delta;
    if (Math.abs(delta - 1) < 3e-10) break;
  }
  return h;
}

function incompleteBeta(x, a, b) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  const term = Math.exp(
    logGamma(a + b) -
      logGamma(a) -
      logGamma(b) +
      a * Math.log(x) +
      b * Math.log(1 - x)
  );
  if (x < (a + 1) / (a + b + 2)) {
    return (term * betaContinuedFraction(a, b, x)) / a;
  }
  return 1 - (term * betaContinuedFraction(b, a, 1 - x)) / b;
}

function twoSidedTPValue(t, degreesOfFreedom) {
  const x = degreesOfFreedom / (degreesOfFreedom + t * t);
  return incompleteBeta(x, degreesOfFreedom / 2, 0.5);
}

function designMatrix(
  sample,
  dependent,
  predictors,
  {
    controls = [
      "ln_real_gdp_per_capita",
      "unemployment_rate_pct",
      "hicp_inflation_pct"
    ],
    countryFE = true,
    yearFE = true
  } = {}
) {
  const countries = [...new Set(sample.map((row) => row.country_iso2))].sort();
  const years = [...new Set(sample.map((row) => row.survey_year))].sort();
  const countryDummies = countryFE ? countries.slice(1) : [];
  const yearDummies = yearFE ? years.slice(1) : [];
  const names = [
    "Intercept",
    ...predictors,
    ...controls,
    ...countryDummies.map((country) => `Country: ${country}`),
    ...yearDummies.map((year) => `Year: ${year}`)
  ];
  const X = sample.map((row) => [
    1,
    ...predictors.map((name) => row[name]),
    ...controls.map((name) => row[name]),
    ...countryDummies.map((country) => (row.country_iso2 === country ? 1 : 0)),
    ...yearDummies.map((year) => (row.survey_year === year ? 1 : 0))
  ]);
  const y = sample.map((row) => row[dependent]);
  return { X, y, names, countries };
}

function ordinaryLeastSquares(X, y) {
  const n = X.length;
  const k = X[0].length;
  const xtx = Array.from({ length: k }, () => Array(k).fill(0));
  const xty = Array(k).fill(0);
  for (let i = 0; i < n; i += 1) {
    for (let a = 0; a < k; a += 1) {
      xty[a] += X[i][a] * y[i];
      for (let b = 0; b < k; b += 1) {
        xtx[a][b] += X[i][a] * X[i][b];
      }
    }
  }
  const bread = invert(xtx);
  const beta = multiplyMatrixVector(bread, xty);
  const residuals = y.map((value, i) => value - dot(X[i], beta));
  const sigma2 = dot(residuals, residuals) / (n - k);
  const standardErrors = bread.map((row, i) =>
    Math.sqrt(Math.max(0, row[i] * sigma2))
  );
  return { beta, residuals, bread, standardErrors, n, k };
}

function clusteredRegression(sample, dependent, predictors, options = {}) {
  const design = designMatrix(sample, dependent, predictors, options);
  const { X, y, names, countries } = design;
  const fit = ordinaryLeastSquares(X, y);
  const { beta, residuals, bread, n, k } = fit;
  const meat = Array.from({ length: k }, () => Array(k).fill(0));
  for (const country of countries) {
    const score = Array(k).fill(0);
    for (let i = 0; i < n; i += 1) {
      if (sample[i].country_iso2 !== country) continue;
      for (let a = 0; a < k; a += 1) {
        score[a] += X[i][a] * residuals[i];
      }
    }
    for (let a = 0; a < k; a += 1) {
      for (let b = 0; b < k; b += 1) {
        meat[a][b] += score[a] * score[b];
      }
    }
  }
  const temp = Array.from({ length: k }, (_, i) =>
    Array.from({ length: k }, (_, j) =>
      dot(
        bread[i],
        meat.map((row) => row[j])
      )
    )
  );
  const variance = Array.from({ length: k }, () => Array(k).fill(0));
  const groups = countries.length;
  const correction = (groups / (groups - 1)) * ((n - 1) / (n - k));
  for (let i = 0; i < k; i += 1) {
    for (let j = 0; j < k; j += 1) {
      variance[i][j] =
        dot(
          temp[i],
          bread.map((row) => row[j])
        ) * correction;
    }
  }
  const standardErrors = variance.map((row, i) =>
    Math.sqrt(Math.max(0, row[i]))
  );
  const t = beta.map((value, i) => value / standardErrors[i]);
  const p = t.map((value) => twoSidedTPValue(Math.abs(value), groups - 1));
  const meanY = y.reduce((sum, value) => sum + value, 0) / n;
  const sse = dot(residuals, residuals);
  const sst = y.reduce((sum, value) => sum + (value - meanY) ** 2, 0);
  const r2 = 1 - sse / sst;
  const adjustedR2 = 1 - (1 - r2) * ((n - 1) / (n - k));
  return {
    names,
    beta,
    standardErrors,
    t,
    p,
    n,
    k,
    r2,
    adjustedR2,
    residuals
  };
}

function coefficient(model, name) {
  const index = model.names.indexOf(name);
  return {
    term: name,
    estimate: model.beta[index],
    standardError: model.standardErrors[index],
    t: model.t[index],
    p: model.p[index],
    lower95: model.beta[index] - 1.96 * model.standardErrors[index],
    upper95: model.beta[index] + 1.96 * model.standardErrors[index]
  };
}

function addWithinBetween(sample, variables) {
  const groups = new Map();
  for (const row of sample) {
    if (!groups.has(row.country_iso2)) groups.set(row.country_iso2, []);
    groups.get(row.country_iso2).push(row);
  }
  for (const row of sample) {
    for (const variable of variables) {
      const countryRows = groups.get(row.country_iso2);
      const mean =
        countryRows.reduce((sum, item) => sum + item[variable], 0) /
        countryRows.length;
      row[`${variable}_between`] = mean;
      row[`${variable}_within`] = row[variable] - mean;
    }
  }
}

addWithinBetween(data, [
  "gri10",
  "udt_efficiency_readiness_z",
  "udt_legitimacy_readiness_z",
  "udt_efficiency_x_legitimacy",
  "udt_efficiency_legitimacy_gap_z",
  "ln_real_gdp_per_capita",
  "unemployment_rate_pct",
  "hicp_inflation_pct"
]);

const controls = [
  "ln_real_gdp_per_capita",
  "unemployment_rate_pct",
  "hicp_inflation_pct"
];
const creControls = [
  "ln_real_gdp_per_capita_within",
  "ln_real_gdp_per_capita_between",
  "unemployment_rate_pct_within",
  "unemployment_rate_pct_between",
  "hicp_inflation_pct_within",
  "hicp_inflation_pct_between"
];

const outcomes = [
  "trust_local_authorities_pct",
  "trust_national_government_pct",
  "trust_european_union_pct",
  "trust_european_commission_pct"
];

const models = {
  pooledReadiness: clusteredRegression(
    data,
    "trust_local_authorities_pct",
    ["gri10"],
    { controls, countryFE: false, yearFE: true }
  ),
  fixedEffectsReadiness: clusteredRegression(
    data,
    "trust_local_authorities_pct",
    ["gri10"],
    { controls, countryFE: true, yearFE: true }
  ),
  fixedEffectsDimensions: clusteredRegression(
    data,
    "trust_local_authorities_pct",
    ["udt_efficiency_readiness_z", "udt_legitimacy_readiness_z"],
    { controls, countryFE: true, yearFE: true }
  ),
  fixedEffectsInteraction: clusteredRegression(
    data,
    "trust_local_authorities_pct",
    [
      "udt_efficiency_readiness_z",
      "udt_legitimacy_readiness_z",
      "udt_efficiency_x_legitimacy"
    ],
    { controls, countryFE: true, yearFE: true }
  ),
  fixedEffectsGap: clusteredRegression(
    data,
    "trust_local_authorities_pct",
    ["udt_efficiency_readiness_z", "udt_efficiency_legitimacy_gap_z"],
    { controls, countryFE: true, yearFE: true }
  ),
  mundlakReadiness: clusteredRegression(
    data,
    "trust_local_authorities_pct",
    ["gri10_within", "gri10_between", ...creControls],
    { controls: [], countryFE: false, yearFE: true }
  ),
  mundlakDimensions: clusteredRegression(
    data,
    "trust_local_authorities_pct",
    [
      "udt_efficiency_readiness_z_within",
      "udt_efficiency_readiness_z_between",
      "udt_legitimacy_readiness_z_within",
      "udt_legitimacy_readiness_z_between",
      ...creControls
    ],
    { controls: [], countryFE: false, yearFE: true }
  )
};

function feasibleGLS(sample, dependent, predictors) {
  const ordered = sample
    .slice()
    .sort(
      (a, b) =>
        a.country_iso2.localeCompare(b.country_iso2) ||
        a.survey_year - b.survey_year
    );
  const design = designMatrix(ordered, dependent, predictors, {
    controls,
    countryFE: false,
    yearFE: true
  });
  const initial = ordinaryLeastSquares(design.X, design.y);
  let numerator = 0;
  let denominator = 0;
  for (let i = 1; i < ordered.length; i += 1) {
    if (ordered[i].country_iso2 === ordered[i - 1].country_iso2) {
      numerator += initial.residuals[i] * initial.residuals[i - 1];
      denominator += initial.residuals[i - 1] ** 2;
    }
  }
  const rho = Math.max(-0.9, Math.min(0.9, numerator / denominator));
  const transformedX = [];
  const transformedY = [];
  const countryIds = [];
  for (let i = 0; i < ordered.length; i += 1) {
    const first =
      i === 0 || ordered[i].country_iso2 !== ordered[i - 1].country_iso2;
    if (first) {
      const factor = Math.sqrt(1 - rho * rho);
      transformedX.push(design.X[i].map((value) => value * factor));
      transformedY.push(design.y[i] * factor);
    } else {
      transformedX.push(
        design.X[i].map(
          (value, j) => value - rho * design.X[i - 1][j]
        )
      );
      transformedY.push(design.y[i] - rho * design.y[i - 1]);
    }
    countryIds.push(ordered[i].country_iso2);
  }
  let fit = ordinaryLeastSquares(transformedX, transformedY);
  for (let iteration = 0; iteration < 4; iteration += 1) {
    const panelSigma = new Map();
    for (const country of new Set(countryIds)) {
      const residuals = fit.residuals.filter(
        (_, index) => countryIds[index] === country
      );
      const sigma = Math.sqrt(
        residuals.reduce((sum, value) => sum + value * value, 0) /
          residuals.length
      );
      panelSigma.set(country, sigma || 1);
    }
    const weightedX = transformedX.map((row, index) =>
      row.map((value) => value / panelSigma.get(countryIds[index]))
    );
    const weightedY = transformedY.map(
      (value, index) => value / panelSigma.get(countryIds[index])
    );
    fit = ordinaryLeastSquares(weightedX, weightedY);
  }
  const t = fit.beta.map((value, index) => value / fit.standardErrors[index]);
  const p = t.map((value) =>
    twoSidedTPValue(Math.abs(value), fit.n - fit.k)
  );
  return {
    names: design.names,
    beta: fit.beta,
    standardErrors: fit.standardErrors,
    t,
    p,
    n: fit.n,
    k: fit.k,
    rho
  };
}

models.fglsReadiness = feasibleGLS(
  data,
  "trust_local_authorities_pct",
  ["gri10"]
);
models.fglsDimensions = feasibleGLS(
  data,
  "trust_local_authorities_pct",
  ["udt_efficiency_readiness_z", "udt_legitimacy_readiness_z"]
);
models.fglsInteraction = feasibleGLS(
  data,
  "trust_local_authorities_pct",
  [
    "udt_efficiency_readiness_z",
    "udt_legitimacy_readiness_z",
    "udt_efficiency_x_legitimacy"
  ]
);
models.fglsGap = feasibleGLS(
  data,
  "trust_local_authorities_pct",
  ["udt_efficiency_readiness_z", "udt_efficiency_legitimacy_gap_z"]
);

const alternativeOutcomes = outcomes.map((outcome) => {
  const pooled = clusteredRegression(data, outcome, ["gri10"], {
    controls,
    countryFE: false,
    yearFE: true
  });
  const fixedEffects = clusteredRegression(data, outcome, ["gri10"], {
    controls,
    countryFE: true,
    yearFE: true
  });
  return {
    outcome,
    pooled: coefficient(pooled, "gri10"),
    fixedEffects: coefficient(fixedEffects, "gri10")
  };
});

const pre2025 = data.filter((row) => row.survey_year <= 2024);
const sensitivity = {
  exclude2025: outcomes.map((outcome) => {
    const pooled = clusteredRegression(pre2025, outcome, ["gri10"], {
      controls,
      countryFE: false,
      yearFE: true
    });
    const fixedEffects = clusteredRegression(pre2025, outcome, ["gri10"], {
      controls,
      countryFE: true,
      yearFE: true
    });
    return {
      outcome,
      pooled: coefficient(pooled, "gri10"),
      fixedEffects: coefficient(fixedEffects, "gri10")
    };
  }),
  officialBenchmark: {
    pooled: coefficient(
      clusteredRegression(
        data,
        "trust_local_authorities_pct",
        ["egov_overall_score"],
        { controls, countryFE: false, yearFE: true }
      ),
      "egov_overall_score"
    ),
    fixedEffects: coefficient(
      clusteredRegression(
        data,
        "trust_local_authorities_pct",
        ["egov_overall_score"],
        { controls, countryFE: true, yearFE: true }
      ),
      "egov_overall_score"
    )
  }
};

function mean(values) {
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function standardDeviation(values) {
  const average = mean(values);
  return Math.sqrt(
    values.reduce((sum, value) => sum + (value - average) ** 2, 0) /
      (values.length - 1)
  );
}

function correlation(a, b) {
  const meanA = mean(a);
  const meanB = mean(b);
  const numerator = a.reduce(
    (sum, value, i) => sum + (value - meanA) * (b[i] - meanB),
    0
  );
  const denominator = Math.sqrt(
    a.reduce((sum, value) => sum + (value - meanA) ** 2, 0) *
      b.reduce((sum, value) => sum + (value - meanB) ** 2, 0)
  );
  return numerator / denominator;
}

const descriptiveVariables = [
  "trust_local_authorities_pct",
  "trust_national_government_pct",
  "trust_european_union_pct",
  "trust_european_commission_pct",
  "udt_governance_readiness_index",
  "udt_efficiency_readiness_z",
  "udt_legitimacy_readiness_z",
  "udt_efficiency_legitimacy_gap_z",
  "real_gdp_per_capita_eur",
  "unemployment_rate_pct",
  "hicp_inflation_pct"
];
const descriptives = descriptiveVariables.map((variable) => {
  const values = data.map((row) => row[variable]);
  return {
    variable,
    n: values.length,
    mean: mean(values),
    standardDeviation: standardDeviation(values),
    minimum: Math.min(...values),
    maximum: Math.max(...values)
  };
});
const correlationVariables = [
  "trust_local_authorities_pct",
  "udt_governance_readiness_index",
  "udt_efficiency_readiness_z",
  "udt_legitimacy_readiness_z",
  "udt_efficiency_legitimacy_gap_z",
  "ln_real_gdp_per_capita",
  "unemployment_rate_pct",
  "hicp_inflation_pct"
];
const correlations = correlationVariables.map((rowVariable) => ({
  variable: rowVariable,
  values: correlationVariables.map((columnVariable) =>
    correlation(
      data.map((row) => row[rowVariable]),
      data.map((row) => row[columnVariable])
    )
  )
}));

function maxVIF(sample, variables) {
  const results = [];
  for (const target of variables) {
    const predictors = variables.filter((variable) => variable !== target);
    const design = designMatrix(sample, target, predictors, {
      controls: [],
      countryFE: false,
      yearFE: false
    });
    const fit = ordinaryLeastSquares(design.X, design.y);
    const average = mean(design.y);
    const sse = dot(fit.residuals, fit.residuals);
    const sst = design.y.reduce(
      (sum, value) => sum + (value - average) ** 2,
      0
    );
    const r2 = 1 - sse / sst;
    results.push({ variable: target, vif: 1 / (1 - r2) });
  }
  return results;
}

const vif = maxVIF(data, [
  "udt_efficiency_readiness_z",
  "udt_legitimacy_readiness_z",
  "udt_efficiency_x_legitimacy",
  ...controls
]);

const compactModels = Object.fromEntries(
  Object.entries(models).map(([name, model]) => [
    name,
    {
      n: model.n,
      r2: model.r2,
      adjustedR2: model.adjustedR2,
      rho: model.rho,
      coefficients: model.names.map((term, index) => ({
        term,
        estimate: model.beta[index],
        standardError: model.standardErrors[index],
        t: model.t[index],
        p: model.p[index]
      }))
    }
  ])
);

const results = {
  generatedAt: new Date().toISOString(),
  sample: {
    observations: data.length,
    countries: new Set(data.map((row) => row.country_iso2)).size,
    years: [...new Set(data.map((row) => row.survey_year))].sort()
  },
  descriptives,
  correlationVariables,
  correlations,
  vif,
  models: compactModels,
  alternativeOutcomes,
  sensitivity
};
fs.writeFileSync(
  path.join(outDir, "model_results.json"),
  JSON.stringify(results, null, 2),
  "utf8"
);

const escapeXML = (value) =>
  String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
const palette = {
  navy: "#153A5B",
  blue: "#2D6A9F",
  teal: "#2B8C84",
  gold: "#C9972E",
  red: "#A84A44",
  ink: "#24313D",
  grey: "#687782",
  light: "#E8EEF2",
  white: "#FFFFFF"
};
const svgFrame = (width, height, content) => `<?xml version="1.0"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <rect width="100%" height="100%" fill="${palette.white}"/>
  <style>
    text { font-family: Arial, Helvetica, sans-serif; fill: ${palette.ink}; }
    .title { font-size: 28px; font-weight: 700; }
    .subtitle { font-size: 16px; fill: ${palette.grey}; }
    .axis { font-size: 14px; fill: ${palette.grey}; }
    .label { font-size: 14px; }
    .small { font-size: 12px; fill: ${palette.grey}; }
  </style>
  ${content}
</svg>`;

async function saveSVG(name, svg) {
  fs.writeFileSync(path.join(figureDir, `${name}.svg`), svg, "utf8");
  await sharp(Buffer.from(svg))
    .png({ quality: 95 })
    .toFile(path.join(figureDir, `${name}.png`));
}

const arrowMarker = `
<defs>
  <marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto">
    <path d="M0,0 L0,6 L9,3 z" fill="${palette.navy}"/>
  </marker>
</defs>`;
const conceptual = svgFrame(
  1400,
  820,
  `${arrowMarker}
  <text x="700" y="55" text-anchor="middle" class="title">Conceptual framework for UDT governance readiness and institutional trust</text>
  <text x="700" y="85" text-anchor="middle" class="subtitle">National enabling conditions for UDT-oriented public services</text>
  <rect x="90" y="190" width="350" height="190" rx="16" fill="#E7F0F8" stroke="${palette.blue}" stroke-width="2"/>
  <text x="265" y="235" text-anchor="middle" font-size="22" font-weight="700">Efficiency readiness</text>
  <text x="265" y="285" text-anchor="middle" font-size="17">User centricity</text>
  <text x="265" y="320" text-anchor="middle" font-size="17">Key digital enablers</text>
  <rect x="90" y="470" width="350" height="190" rx="16" fill="#E5F3F0" stroke="${palette.teal}" stroke-width="2"/>
  <text x="265" y="515" text-anchor="middle" font-size="22" font-weight="700">Legitimacy readiness</text>
  <text x="265" y="565" text-anchor="middle" font-size="17">Transparency</text>
  <text x="265" y="600" text-anchor="middle" font-size="17">Rule of law</text>
  <rect x="560" y="300" width="330" height="240" rx="18" fill="#F4F6F8" stroke="${palette.navy}" stroke-width="3"/>
  <text x="725" y="355" text-anchor="middle" font-size="23" font-weight="700">UDT governance</text>
  <text x="725" y="390" text-anchor="middle" font-size="23" font-weight="700">readiness</text>
  <text x="725" y="445" text-anchor="middle" font-size="16">Equal-weight composite</text>
  <text x="725" y="475" text-anchor="middle" font-size="16">Efficiency-legitimacy balance</text>
  <rect x="1030" y="300" width="290" height="240" rx="18" fill="#FBF3DF" stroke="${palette.gold}" stroke-width="3"/>
  <text x="1175" y="365" text-anchor="middle" font-size="23" font-weight="700">Institutional trust</text>
  <text x="1175" y="420" text-anchor="middle" font-size="16">Regional or local authorities</text>
  <text x="1175" y="455" text-anchor="middle" font-size="16">National government</text>
  <text x="1175" y="490" text-anchor="middle" font-size="16">European institutions</text>
  <line x1="440" y1="285" x2="560" y2="360" stroke="${palette.navy}" stroke-width="3" marker-end="url(#arrow)"/>
  <line x1="440" y1="565" x2="560" y2="480" stroke="${palette.navy}" stroke-width="3" marker-end="url(#arrow)"/>
  <line x1="890" y1="420" x2="1030" y2="420" stroke="${palette.navy}" stroke-width="3" marker-end="url(#arrow)"/>
  <path d="M265 380 C265 420, 265 430, 265 470" fill="none" stroke="${palette.red}" stroke-width="2" stroke-dasharray="8 6"/>
  <text x="285" y="430" class="label" fill="${palette.red}">Complementarity or imbalance</text>
  <text x="700" y="755" text-anchor="middle" class="small">The framework is associational and does not treat the index as a measure of installed municipal digital twins.</text>`
);
await saveSVG("figure_1_conceptual_framework", conceptual);

const countries = [...new Set(data.map((row) => row.country_iso2))].sort();
const countryMeans = countries.map((country) => {
  const rows = data.filter((row) => row.country_iso2 === country);
  return {
    country,
    gri: mean(rows.map((row) => row.udt_governance_readiness_index)),
    trust: mean(rows.map((row) => row.trust_local_authorities_pct)),
    efficiency: mean(rows.map((row) => row.udt_efficiency_readiness_z)),
    legitimacy: mean(rows.map((row) => row.udt_legitimacy_readiness_z))
  };
});
const xMin = Math.floor(Math.min(...countryMeans.map((d) => d.gri)) / 5) * 5;
const xMax = Math.ceil(Math.max(...countryMeans.map((d) => d.gri)) / 5) * 5;
const yMin = Math.floor(Math.min(...countryMeans.map((d) => d.trust)) / 5) * 5;
const yMax = Math.ceil(Math.max(...countryMeans.map((d) => d.trust)) / 5) * 5;
const scatterWidth = 1200;
const scatterHeight = 820;
const margin = { left: 110, right: 60, top: 110, bottom: 100 };
const sx = (value) =>
  margin.left +
  ((value - xMin) / (xMax - xMin)) *
    (scatterWidth - margin.left - margin.right);
const sy = (value) =>
  scatterHeight -
  margin.bottom -
  ((value - yMin) / (yMax - yMin)) *
    (scatterHeight - margin.top - margin.bottom);
const meanX = mean(countryMeans.map((d) => d.gri));
const meanY = mean(countryMeans.map((d) => d.trust));
const slope =
  countryMeans.reduce(
    (sum, d) => sum + (d.gri - meanX) * (d.trust - meanY),
    0
  ) /
  countryMeans.reduce((sum, d) => sum + (d.gri - meanX) ** 2, 0);
const intercept = meanY - slope * meanX;
let scatterElements = `
  <text x="600" y="48" text-anchor="middle" class="title">Country-average UDT governance readiness and local institutional trust</text>
  <text x="600" y="78" text-anchor="middle" class="subtitle">EU27 averages, 2022-2025</text>`;
for (let tick = xMin; tick <= xMax; tick += 10) {
  scatterElements += `<line x1="${sx(tick)}" y1="${margin.top}" x2="${sx(
    tick
  )}" y2="${
    scatterHeight - margin.bottom
  }" stroke="${palette.light}"/><text x="${sx(tick)}" y="${
    scatterHeight - margin.bottom + 28
  }" text-anchor="middle" class="axis">${tick}</text>`;
}
for (let tick = yMin; tick <= yMax; tick += 10) {
  scatterElements += `<line x1="${margin.left}" y1="${sy(
    tick
  )}" x2="${scatterWidth - margin.right}" y2="${sy(
    tick
  )}" stroke="${palette.light}"/><text x="${margin.left - 18}" y="${
    sy(tick) + 5
  }" text-anchor="end" class="axis">${tick}</text>`;
}
scatterElements += `
  <line x1="${margin.left}" y1="${
    scatterHeight - margin.bottom
  }" x2="${scatterWidth - margin.right}" y2="${
    scatterHeight - margin.bottom
  }" stroke="${palette.ink}" stroke-width="1.5"/>
  <line x1="${margin.left}" y1="${margin.top}" x2="${
    margin.left
  }" y2="${scatterHeight - margin.bottom}" stroke="${
    palette.ink
  }" stroke-width="1.5"/>
  <line x1="${sx(xMin)}" y1="${sy(
    intercept + slope * xMin
  )}" x2="${sx(xMax)}" y2="${sy(
    intercept + slope * xMax
  )}" stroke="${palette.gold}" stroke-width="4"/>`;
for (const point of countryMeans) {
  scatterElements += `<circle cx="${sx(point.gri)}" cy="${sy(
    point.trust
  )}" r="7" fill="${palette.blue}" opacity="0.9"/><text x="${
    sx(point.gri) + 9
  }" y="${sy(point.trust) - 9}" class="small">${escapeXML(
    point.country
  )}</text>`;
}
scatterElements += `
  <text x="${scatterWidth / 2}" y="${
    scatterHeight - 28
  }" text-anchor="middle" font-size="17">UDT Governance Readiness Index (0-100)</text>
  <text x="30" y="${
    scatterHeight / 2
  }" transform="rotate(-90 30 ${scatterHeight / 2})" text-anchor="middle" font-size="17">Trust in regional or local public authorities (%)</text>
  <text x="${scatterWidth - 70}" y="110" text-anchor="end" class="small">Descriptive country means; fitted line is unadjusted.</text>`;
await saveSVG(
  "figure_2_country_readiness_trust",
  svgFrame(scatterWidth, scatterHeight, scatterElements)
);

const coefficientWidth = 1250;
const coefficientHeight = 760;
const coefficientRows = alternativeOutcomes.flatMap((item, index) => [
  {
    label: [
      "Local authorities",
      "National government",
      "European Union",
      "European Commission"
    ][index],
    model: "Pooled panel",
    ...item.pooled
  },
  {
    label: [
      "Local authorities",
      "National government",
      "European Union",
      "European Commission"
    ][index],
    model: "Country fixed effects",
    ...item.fixedEffects
  }
]);
const cMin = -4;
const cMax = 4;
const cx = (value) => 330 + ((value - cMin) / (cMax - cMin)) * 820;
let coefficientElements = `
  <text x="625" y="50" text-anchor="middle" class="title">Association of a ten-point increase in UDT governance readiness with institutional trust</text>
  <text x="625" y="80" text-anchor="middle" class="subtitle">Point estimates and 95% confidence intervals</text>`;
for (let tick = cMin; tick <= cMax; tick += 1) {
  coefficientElements += `<line x1="${cx(tick)}" y1="120" x2="${cx(
    tick
  )}" y2="650" stroke="${
    tick === 0 ? palette.ink : palette.light
  }" stroke-width="${tick === 0 ? 2 : 1}"/><text x="${cx(
    tick
  )}" y="680" text-anchor="middle" class="axis">${tick}</text>`;
}
for (let i = 0; i < 4; i += 1) {
  const baseY = 170 + i * 120;
  coefficientElements += `<text x="30" y="${
    baseY + 12
  }" font-size="17">${escapeXML(coefficientRows[i * 2].label)}</text>`;
  for (let j = 0; j < 2; j += 1) {
    const item = coefficientRows[i * 2 + j];
    const y = baseY + (j === 0 ? -14 : 28);
    const colour = j === 0 ? palette.blue : palette.red;
    coefficientElements += `<line x1="${cx(
      item.lower95
    )}" y1="${y}" x2="${cx(
      item.upper95
    )}" y2="${y}" stroke="${colour}" stroke-width="4"/><circle cx="${cx(
      item.estimate
    )}" cy="${y}" r="7" fill="${colour}"/>`;
  }
}
coefficientElements += `
  <circle cx="445" cy="720" r="7" fill="${palette.blue}"/><text x="460" y="725" class="label">Pooled panel with year effects</text>
  <circle cx="760" cy="720" r="7" fill="${palette.red}"/><text x="775" y="725" class="label">Country and year fixed effects</text>`;
await saveSVG(
  "figure_3_coefficient_plot",
  svgFrame(coefficientWidth, coefficientHeight, coefficientElements)
);

const balanceWidth = 1200;
const balanceHeight = 840;
const balanceMargin = { left: 110, right: 70, top: 110, bottom: 105 };
const eMin =
  Math.floor(
    Math.min(...countryMeans.map((d) => d.efficiency), -2) * 2
  ) / 2;
const eMax =
  Math.ceil(Math.max(...countryMeans.map((d) => d.efficiency), 2) * 2) / 2;
const lMin =
  Math.floor(
    Math.min(...countryMeans.map((d) => d.legitimacy), -2) * 2
  ) / 2;
const lMax =
  Math.ceil(Math.max(...countryMeans.map((d) => d.legitimacy), 2) * 2) / 2;
const bx = (value) =>
  balanceMargin.left +
  ((value - eMin) / (eMax - eMin)) *
    (balanceWidth - balanceMargin.left - balanceMargin.right);
const by = (value) =>
  balanceHeight -
  balanceMargin.bottom -
  ((value - lMin) / (lMax - lMin)) *
    (balanceHeight - balanceMargin.top - balanceMargin.bottom);
const trustMin = Math.min(...countryMeans.map((d) => d.trust));
const trustMax = Math.max(...countryMeans.map((d) => d.trust));
const colourForTrust = (value) => {
  const t = (value - trustMin) / (trustMax - trustMin);
  const r = Math.round(168 + (45 - 168) * t);
  const g = Math.round(74 + (140 - 74) * t);
  const b = Math.round(68 + (132 - 68) * t);
  return `rgb(${r},${g},${b})`;
};
let balanceElements = `
  <text x="600" y="48" text-anchor="middle" class="title">Efficiency and legitimacy readiness across EU27 countries</text>
  <text x="600" y="78" text-anchor="middle" class="subtitle">Country averages, 2022-2025; point colour indicates local institutional trust</text>`;
for (let tick = Math.ceil(eMin); tick <= eMax; tick += 1) {
  balanceElements += `<line x1="${bx(tick)}" y1="${
    balanceMargin.top
  }" x2="${bx(tick)}" y2="${
    balanceHeight - balanceMargin.bottom
  }" stroke="${palette.light}"/><text x="${bx(tick)}" y="${
    balanceHeight - balanceMargin.bottom + 28
  }" text-anchor="middle" class="axis">${tick}</text>`;
}
for (let tick = Math.ceil(lMin); tick <= lMax; tick += 1) {
  balanceElements += `<line x1="${balanceMargin.left}" y1="${by(
    tick
  )}" x2="${balanceWidth - balanceMargin.right}" y2="${by(
    tick
  )}" stroke="${palette.light}"/><text x="${
    balanceMargin.left - 18
  }" y="${by(tick) + 5}" text-anchor="end" class="axis">${tick}</text>`;
}
balanceElements += `
  <line x1="${bx(0)}" y1="${balanceMargin.top}" x2="${bx(0)}" y2="${
    balanceHeight - balanceMargin.bottom
  }" stroke="${palette.grey}" stroke-width="2"/>
  <line x1="${balanceMargin.left}" y1="${by(0)}" x2="${
    balanceWidth - balanceMargin.right
  }" y2="${by(0)}" stroke="${palette.grey}" stroke-width="2"/>
  <line x1="${bx(Math.max(eMin, lMin))}" y1="${by(
    Math.max(eMin, lMin)
  )}" x2="${bx(Math.min(eMax, lMax))}" y2="${by(
    Math.min(eMax, lMax)
  )}" stroke="${palette.gold}" stroke-width="2" stroke-dasharray="8 6"/>`;
for (const point of countryMeans) {
  balanceElements += `<circle cx="${bx(point.efficiency)}" cy="${by(
    point.legitimacy
  )}" r="9" fill="${colourForTrust(
    point.trust
  )}" stroke="${palette.white}" stroke-width="2"/><text x="${
    bx(point.efficiency) + 11
  }" y="${by(point.legitimacy) - 10}" class="small">${escapeXML(
    point.country
  )}</text>`;
}
balanceElements += `
  <text x="${balanceWidth / 2}" y="${
    balanceHeight - 28
  }" text-anchor="middle" font-size="17">Efficiency readiness (pooled z-score)</text>
  <text x="30" y="${
    balanceHeight / 2
  }" transform="rotate(-90 30 ${balanceHeight / 2})" text-anchor="middle" font-size="17">Legitimacy readiness (pooled z-score)</text>
  <text x="${balanceWidth - 90}" y="120" text-anchor="end" class="small">Dashed line denotes equal efficiency and legitimacy readiness.</text>`;
await saveSVG(
  "figure_4_efficiency_legitimacy_balance",
  svgFrame(balanceWidth, balanceHeight, balanceElements)
);

console.log(
  JSON.stringify(
    {
      resultFile: path.join(outDir, "model_results.json"),
      figures: fs
        .readdirSync(figureDir)
        .filter((name) => name.endsWith(".png"))
        .sort()
    },
    null,
    2
  )
);
