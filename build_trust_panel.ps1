param(
    [string]$Workspace = $PSScriptRoot,
    [string]$ExistingPanel = ''
)

Add-Type -AssemblyName System.IO.Compression.FileSystem

$sourceDir = Join-Path $Workspace 'data\input\eurobarometer'
$outputDir = Join-Path $Workspace 'output'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$waves = @(
    @{
        Year = 2022
        File = 'EB97_2022_Volume_A.xlsx'
        Local = 'QA6a_7'
        Government = 'QA6a_9'
        EU = 'QA6a_11'
        Commission = 'QA10_2'
    },
    @{
        Year = 2023
        File = 'EB99_2023_Volume_A.xlsx'
        Local = 'QA6_7'
        Government = 'QA6_9'
        EU = 'QA6_11'
        Commission = 'QA11_2'
    },
    @{
        Year = 2024
        File = 'EB101_2024_Volume_A.xlsx'
        Local = 'QA6_6'
        Government = 'QA6_8'
        EU = 'QA6_10'
        Commission = 'QA10_2'
    },
    @{
        Year = 2025
        File = 'EB103_2025_Volume_A.xlsx'
        Local = 'QA6_6'
        Government = 'QA6_10'
        EU = 'QA6_12'
        Commission = 'QA10_2'
    }
)

$eu27 = @(
    'AT', 'BE', 'BG', 'CY', 'CZ', 'DE', 'DK', 'EE', 'EL',
    'ES', 'FI', 'FR', 'HR', 'HU', 'IE', 'IT', 'LT', 'LU',
    'LV', 'MT', 'NL', 'PL', 'PT', 'RO', 'SE', 'SI', 'SK'
)

function Read-ZipXml {
    param(
        [System.IO.Compression.ZipArchive]$Zip,
        [string]$EntryName
    )

    $entry = $Zip.GetEntry($EntryName)
    if (-not $entry) {
        throw "Missing XLSX entry: $EntryName"
    }

    $reader = [System.IO.StreamReader]::new($entry.Open())
    try {
        return [xml]$reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }
}

function Get-SharedStrings {
    param([System.IO.Compression.ZipArchive]$Zip)

    $xml = Read-ZipXml -Zip $Zip -EntryName 'xl/sharedStrings.xml'
    return @(
        $xml.sst.si | ForEach-Object {
            if ($null -ne $_.t) {
                [string]$_.t
            }
            else {
                ($_.r | ForEach-Object { $_.t }) -join ''
            }
        }
    )
}

function Convert-CellValue {
    param(
        $Cell,
        [string[]]$SharedStrings
    )

    if ($Cell.t -eq 's') {
        return $SharedStrings[[int]$Cell.v]
    }
    if ($Cell.t -eq 'inlineStr') {
        if ($null -ne $Cell.is.t) {
            return [string]$Cell.is.t
        }
        return ($Cell.is.r | ForEach-Object { $_.t }) -join ''
    }
    return [string]$Cell.v
}

function Get-ColumnName {
    param([string]$CellReference)
    return ([regex]::Match($CellReference, '^[A-Z]+')).Value
}

function Get-TrustByCountry {
    param(
        [string]$Path,
        [string]$SheetName
    )

    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $sharedStrings = Get-SharedStrings -Zip $zip
        $workbook = Read-ZipXml -Zip $zip -EntryName 'xl/workbook.xml'
        $sheet = $workbook.workbook.sheets.sheet |
            Where-Object { $_.name -eq $SheetName } |
            Select-Object -First 1

        if (-not $sheet) {
            throw "Sheet '$SheetName' not found in $Path"
        }

        $sheetXml = Read-ZipXml -Zip $zip -EntryName "xl/worksheets/sheet$($sheet.sheetId).xml"
        $rows = @($sheetXml.worksheet.sheetData.row)

        $decodedRows = foreach ($row in $rows) {
            $cells = @{}
            foreach ($cell in $row.c) {
                $cells[(Get-ColumnName -CellReference $cell.r)] =
                    Convert-CellValue -Cell $cell -SharedStrings $sharedStrings
            }
            [pscustomobject]@{
                RowNumber = [int]$row.r
                Cells = $cells
            }
        }

        $trustRow = $decodedRows |
            Where-Object { $_.Cells['B'] -eq 'Tend to trust' } |
            Select-Object -First 1
        if (-not $trustRow) {
            throw "'Tend to trust' row not found in $SheetName"
        }

        $headerRow = $decodedRows |
            Where-Object { $_.RowNumber -lt $trustRow.RowNumber } |
            Sort-Object RowNumber -Descending |
            Where-Object {
                $values = @($_.Cells.Values)
                ($values -contains 'BE') -and ($values -contains 'DE') -and ($values -contains 'FR')
            } |
            Select-Object -First 1
        if (-not $headerRow) {
            throw "Country header row not found in $SheetName"
        }

        $result = @{}
        foreach ($column in $headerRow.Cells.Keys) {
            $country = [string]$headerRow.Cells[$column]
            if ($eu27 -contains $country) {
                $raw = [string]$trustRow.Cells[$column]
                if ($raw -and $raw -ne '-') {
                    $result[$country] = [math]::Round(([double]$raw * 100), 1)
                }
            }
        }
        return $result
    }
    finally {
        $zip.Dispose()
    }
}

$trustRows = foreach ($wave in $waves) {
    $path = Join-Path $sourceDir $wave.File
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Source file not found: $path"
    }

    $local = Get-TrustByCountry -Path $path -SheetName $wave.Local
    $government = Get-TrustByCountry -Path $path -SheetName $wave.Government
    $eu = Get-TrustByCountry -Path $path -SheetName $wave.EU
    $commission = Get-TrustByCountry -Path $path -SheetName $wave.Commission

    foreach ($country in $eu27) {
        [pscustomobject]@{
            country_iso2 = $country
            survey_year = $wave.Year
            trust_local_authorities_pct = $local[$country]
            trust_national_government_pct = $government[$country]
            trust_european_union_pct = $eu[$country]
            trust_european_commission_pct = $commission[$country]
            eurobarometer_wave = [System.IO.Path]::GetFileNameWithoutExtension($wave.File)
        }
    }
}

$trustPath = Join-Path $outputDir 'EU27_citizen_trust_2022_2025.csv'
$trustRows |
    Sort-Object survey_year, country_iso2 |
    Export-Csv -LiteralPath $trustPath -NoTypeInformation -Encoding UTF8

if ($ExistingPanel -and (Test-Path -LiteralPath $ExistingPanel)) {
    $trustLookup = @{}
    foreach ($row in $trustRows) {
        $trustLookup["$($row.country_iso2)|$($row.survey_year)"] = $row
    }

    $merged = foreach ($row in (Import-Csv -LiteralPath $ExistingPanel)) {
        if ([int]$row.survey_year -lt 2022) {
            continue
        }
        $trust = $trustLookup["$($row.country_iso2)|$($row.survey_year)"]
        if (-not $trust) {
            continue
        }

        $ordered = [ordered]@{}
        foreach ($property in $row.PSObject.Properties) {
            $ordered[$property.Name] = $property.Value
        }
        $ordered['trust_local_authorities_pct'] = $trust.trust_local_authorities_pct
        $ordered['trust_national_government_pct'] = $trust.trust_national_government_pct
        $ordered['trust_european_union_pct'] = $trust.trust_european_union_pct
        $ordered['trust_european_commission_pct'] = $trust.trust_european_commission_pct
        $ordered['trust_source_wave'] = $trust.eurobarometer_wave
        [pscustomobject]$ordered
    }

    $mergedPath = Join-Path $outputDir 'EU27_UDT_readiness_trust_panel_2022_2025.csv'
    $merged |
        Sort-Object survey_year, country_iso2 |
        Export-Csv -LiteralPath $mergedPath -NoTypeInformation -Encoding UTF8
}

Write-Output "Created: $trustPath"
if ($mergedPath) {
    Write-Output "Created: $mergedPath"
}
