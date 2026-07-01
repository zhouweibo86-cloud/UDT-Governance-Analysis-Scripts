param(
    [string]$Workspace = $PSScriptRoot,
    [string]$InputPanel = ''
)

$ErrorActionPreference = 'Stop'

if (-not $InputPanel) {
    $InputPanel = Join-Path $Workspace 'output\EU27_UDT_readiness_trust_panel_2022_2025.csv'
}

$sourceDir = Join-Path $Workspace 'data\input\eurostat'
$outputDir = Join-Path $Workspace 'output'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$eu27 = @(
    'AT', 'BE', 'BG', 'CY', 'CZ', 'DE', 'DK', 'EE', 'EL',
    'ES', 'FI', 'FR', 'HR', 'HU', 'IE', 'IT', 'LT', 'LU',
    'LV', 'MT', 'NL', 'PL', 'PT', 'RO', 'SE', 'SI', 'SK'
)

function Get-JsonStatLookup {
    param(
        [string]$Path,
        [string]$VariableName
    )

    $json = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $ids = @($json.id)
    $sizes = @($json.size | ForEach-Object { [int]$_ })

    $positions = @{}
    foreach ($id in $ids) {
        $indexObject = $json.dimension.$id.category.index
        $map = @{}
        foreach ($property in $indexObject.PSObject.Properties) {
            $map[$property.Name] = [int]$property.Value
        }
        $positions[$id] = $map
    }

    $geoIndex = [array]::IndexOf($ids, 'geo')
    $timeIndex = [array]::IndexOf($ids, 'time')
    if ($geoIndex -lt 0 -or $timeIndex -lt 0) {
        throw "Dataset $Path does not contain geo and time dimensions."
    }

    $lookup = @{}
    foreach ($geo in $eu27) {
        if (-not $positions['geo'].ContainsKey($geo)) {
            continue
        }
        foreach ($year in 2022..2025) {
            $yearText = [string]$year
            if (-not $positions['time'].ContainsKey($yearText)) {
                continue
            }

            $coordinates = New-Object int[] $ids.Count
            $coordinates[$geoIndex] = $positions['geo'][$geo]
            $coordinates[$timeIndex] = $positions['time'][$yearText]

            $linearIndex = 0
            for ($i = 0; $i -lt $ids.Count; $i++) {
                $stride = 1
                for ($j = $i + 1; $j -lt $ids.Count; $j++) {
                    $stride *= $sizes[$j]
                }
                $linearIndex += $coordinates[$i] * $stride
            }

            $valueProperty = $json.value.PSObject.Properties |
                Where-Object { $_.Name -eq [string]$linearIndex } |
                Select-Object -First 1
            if ($valueProperty) {
                $lookup["$geo|$year"] = [double]$valueProperty.Value
            }
        }
    }

    return [pscustomobject]@{
        Name = $VariableName
        Values = $lookup
        Updated = $json.updated
        Label = $json.label
    }
}

function Get-Mean {
    param([double[]]$Values)
    return ($Values | Measure-Object -Average).Average
}

function Get-StandardDeviation {
    param([double[]]$Values)
    $mean = Get-Mean -Values $Values
    $sumSquares = 0.0
    foreach ($value in $Values) {
        $sumSquares += [math]::Pow($value - $mean, 2)
    }
    return [math]::Sqrt($sumSquares / $Values.Count)
}

function Add-ZScore {
    param(
        [object[]]$Rows,
        [string]$SourceProperty,
        [string]$TargetProperty
    )

    $values = @($Rows | ForEach-Object { [double]$_.$SourceProperty })
    $mean = Get-Mean -Values $values
    $sd = Get-StandardDeviation -Values $values

    foreach ($row in $Rows) {
        $row | Add-Member -NotePropertyName $TargetProperty `
            -NotePropertyValue (([double]$row.$SourceProperty - $mean) / $sd)
    }
}

$gdp = Get-JsonStatLookup `
    -Path (Join-Path $sourceDir 'gdp_per_capita_real_2022_2025.json') `
    -VariableName 'real_gdp_per_capita_eur'
$unemployment = Get-JsonStatLookup `
    -Path (Join-Path $sourceDir 'unemployment_2022_2025.json') `
    -VariableName 'unemployment_rate_pct'
$inflation = Get-JsonStatLookup `
    -Path (Join-Path $sourceDir 'hicp_inflation_2022_2025.json') `
    -VariableName 'hicp_inflation_pct'

$rows = foreach ($row in (Import-Csv -LiteralPath $InputPanel)) {
    $key = "$($row.country_iso2)|$($row.survey_year)"
    if (
        -not $gdp.Values.ContainsKey($key) -or
        -not $unemployment.Values.ContainsKey($key) -or
        -not $inflation.Values.ContainsKey($key)
    ) {
        Write-Warning "Incomplete controls for $key"
        continue
    }

    $ordered = [ordered]@{}
    foreach ($property in $row.PSObject.Properties) {
        $ordered[$property.Name] = $property.Value
    }

    $realGdp = [double]$gdp.Values[$key]
    $ordered['real_gdp_per_capita_eur'] = $realGdp
    $ordered['ln_real_gdp_per_capita'] = [math]::Log($realGdp)
    $ordered['unemployment_rate_pct'] = [double]$unemployment.Values[$key]
    $ordered['hicp_inflation_pct'] = [double]$inflation.Values[$key]
    [pscustomobject]$ordered
}

Add-ZScore -Rows $rows -SourceProperty 'egov_user_centricity' -TargetProperty 'z_user_centricity'
Add-ZScore -Rows $rows -SourceProperty 'egov_transparency' -TargetProperty 'z_transparency'
Add-ZScore -Rows $rows -SourceProperty 'egov_key_enablers' -TargetProperty 'z_key_enablers'

foreach ($row in $rows) {
    $row | Add-Member -NotePropertyName 'rule_of_law_100' `
        -NotePropertyValue ([double]$row.wjp_rule_of_law_overall * 100)
}
Add-ZScore -Rows $rows -SourceProperty 'rule_of_law_100' -TargetProperty 'z_rule_of_law'

foreach ($row in $rows) {
    $efficiency = ([double]$row.z_user_centricity + [double]$row.z_key_enablers) / 2
    $legitimacy = ([double]$row.z_transparency + [double]$row.z_rule_of_law) / 2
    $rawIndex = (
        [double]$row.z_user_centricity +
        [double]$row.z_transparency +
        [double]$row.z_key_enablers +
        [double]$row.z_rule_of_law
    ) / 4

    $row | Add-Member -NotePropertyName 'udt_efficiency_readiness_z' -NotePropertyValue $efficiency
    $row | Add-Member -NotePropertyName 'udt_legitimacy_readiness_z' -NotePropertyValue $legitimacy
    $row | Add-Member -NotePropertyName 'udt_efficiency_legitimacy_gap_z' `
        -NotePropertyValue ($efficiency - $legitimacy)
    $row | Add-Member -NotePropertyName 'udt_efficiency_x_legitimacy' `
        -NotePropertyValue ($efficiency * $legitimacy)
    $row | Add-Member -NotePropertyName 'udt_gri_raw_z' -NotePropertyValue $rawIndex
}

$rawValues = @($rows | ForEach-Object { [double]$_.udt_gri_raw_z })
$rawMin = ($rawValues | Measure-Object -Minimum).Minimum
$rawMax = ($rawValues | Measure-Object -Maximum).Maximum
foreach ($row in $rows) {
    $score = 100 * (([double]$row.udt_gri_raw_z - $rawMin) / ($rawMax - $rawMin))
    $row | Add-Member -NotePropertyName 'udt_governance_readiness_index' `
        -NotePropertyValue ([math]::Round($score, 3))
}

$outputPath = Join-Path $outputDir 'EU27_UDT_governance_readiness_analysis_2022_2025.csv'
$rows |
    Sort-Object survey_year, country_iso2 |
    Export-Csv -LiteralPath $outputPath -NoTypeInformation -Encoding UTF8

$metadata = [pscustomobject]@{
    generated_at = (Get-Date).ToString('s')
    observations = $rows.Count
    gdp_source_updated = $gdp.Updated
    unemployment_source_updated = $unemployment.Updated
    inflation_source_updated = $inflation.Updated
    index_definition = 'Equal-weight mean of pooled z-scores for UC, transparency, key enablers, and rule of law; min-max rescaled to 0-100.'
    efficiency_definition = 'Mean of pooled z-scores for user centricity and key enablers.'
    legitimacy_definition = 'Mean of pooled z-scores for transparency and rule of law.'
}
$metadata |
    ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $outputDir 'analysis_dataset_metadata.json') -Encoding UTF8

Write-Output "Created: $outputPath"
