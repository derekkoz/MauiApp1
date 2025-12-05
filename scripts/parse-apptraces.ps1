<#
Parses an Exported Log Analytics JSON (apptraces.json) created by:
  az monitor log-analytics query ... -o json > apptraces.json
Also supports a top-level JSON array of objects exported by other tooling.

Creates:
  - .\apptraces-clean.csv     (all rows, mapped columns)
  - .\apptraces-sql.csv       (rows that mention SQL / CHANGE TRACKING / SqlException)

Usage:
  & .\scripts\parse-apptraces.ps1
  & .\scripts\parse-apptraces.ps1 -InputPath 'C:\full\path\to\apptraces.json'
#>

param(
    [string]$InputPath = (Join-Path (Get-Location) 'apptraces.json')
)

if (-not (Test-Path $InputPath)) {
    Write-Error "File not found: $InputPath`nRun the az query export and save to apptraces.json or pass -InputPath <fullpath>."
    Write-Host ""
    Write-Host "Example export command (replace workspace and query):"
    Write-Host "  az monitor log-analytics query -w <workspace-id> --analytics-query `"<your Kusto query>`" -o json > apptraces.json"
    exit 1
}

function Try-LoadJson([string]$path) {
    try {
        $raw = Get-Content $path -Raw -ErrorAction Stop
    } catch {
        throw "Failed to read file '$path': $($_.Exception.Message)"
    }

    if (Get-Command Test-Json -ErrorAction SilentlyContinue) {
        try { if (Test-Json -InputObject $raw) { return $raw | ConvertFrom-Json -ErrorAction Stop } } catch { }
    }

    try {
        return $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $firstError = $_
    }

    try {
        $lines = Get-Content $path -ErrorAction Stop
        foreach ($line in $lines) {
            $t = $line.Trim()
            if ($t -eq '') { continue }
            try { return $t | ConvertFrom-Json -ErrorAction Stop } catch {}
        }
    } catch {}

    if ($raw -match '^\s*"(.*)"\s*$') {
        $inner = $Matches[1]
        $inner = $inner -replace '\\r','\r' -replace '\\n','\n' -replace '\\t','\t' -replace '\\"','"' -replace '\\\\','\'
        try { return $inner | ConvertFrom-Json -ErrorAction Stop } catch {}
    }

    $trim = $raw.Trim()
    if ($trim -match '^\{') {
        $cand = ('[' + ($raw -replace '}\s*{', '},{') + ']')
        try { return $cand | ConvertFrom-Json -ErrorAction Stop } catch {}
    }

    $excerpt = if ($raw.Length -gt 1000) { $raw.Substring(0,1000) + "... (truncated)" } else { $raw }
    $msg = @(
        "Failed to parse JSON from '$path'.",
        "ConvertFrom-Json error: $($firstError.Exception.Message)",
        "",
        "Diagnostics:",
        "- File size: $((Get-Item $path).Length) bytes",
        "- Encoding: (PowerShell cannot reliably detect encoding here) try re-saving as UTF8 without BOM.",
        "- File excerpt (first 1000 chars):",
        $excerpt,
        "",
        "Suggestions:",
        "- Verify the file is a single valid JSON object with a 'tables' array (the script expects that), or a top-level JSON array of objects.",
        "- This script supports both shapes."
    ) -join "`n"
    throw $msg
}

try {
    $json = Try-LoadJson $InputPath
} catch {
    Write-Error "Failed to parse JSON: $($_ -join "`n")"
    exit 1
}

# Normalize-Value helper (used when converting complex fields to compact JSON/string)
function Normalize-Value($v) {
    if ($null -eq $v) { return $null }
    if ($v -is [System.Management.Automation.PSObject] -or $v -is [System.Collections.Hashtable] -or ($v -is [object] -and $v -isnot [string] -and $v -ne $null -and ($v.GetType().IsArray -or ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string]))))) {
        try { return ($v | ConvertTo-Json -Depth 10 -Compress) } catch { return "$v" }
    }
    return $v
}

# Support two JSON shapes:
# 1) Log Analytics export with "tables" array (original)
# 2) Top-level array of objects (your case)
$cols = @()
$rows = @()
if ($json -and $json.PSObject.Properties.Match('tables') -and $json.tables -and $json.tables.Count -gt 0) {
    # Existing Log Analytics shape
    $tableIndex = $null
    for ($i = 0; $i -lt $json.tables.Count; $i++) {
        if ($json.tables[$i].rows -and $json.tables[$i].rows.Count -gt 0) {
            $tableIndex = $i
            break
        }
    }
    if ($tableIndex -eq $null) {
        Write-Error "No table with rows found in the exported JSON."
        exit 1
    }
    $table = $json.tables[$tableIndex]
    if (-not $table.columns -or $table.columns.Count -eq 0) {
        Write-Error "Table has no column metadata."
        exit 1
    }
    $cols = $table.columns | ForEach-Object { $_.name }
    $rows = $table.rows
} elseif ($json -is [System.Array] -and $json.Count -gt 0) {
    # Top-level JSON array of objects: infer columns from first object (and include union of keys)
    $first = $json | Select-Object -First 1
    $cols = @()
    foreach ($p in $first.PSObject.Properties) { $cols += $p.Name }

    # also detect any additional keys present in other objects and append them
    foreach ($item in $json | Select-Object -Skip 1 -First 100) {
        foreach ($p in $item.PSObject.Properties) { if ($cols -notcontains $p.Name) { $cols += $p.Name } }
    }

    # Build rows as arrays aligned to $cols
    $rows = @()
    foreach ($item in $json) {
        $row = @()
        foreach ($c in $cols) {
            if ($item.PSObject.Properties.Match($c)) { $row += $item.$c } else { $row += $null }
        }
        $rows += ,$row
    }
} else {
    Write-Error "Unrecognized JSON shape. Expected 'tables' array or top-level array of objects."
    exit 1
}

Write-Host "Found data with $($cols.Count) columns and $($rows.Count) rows."

# Convert rows -> PSCustomObjects with normalized values
$objs = @()
foreach ($r in $rows) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) {
        $name = $cols[$i]
        $val = $null
        if ($i -lt $r.Count) { $val = $r[$i] }
        $o[$name] = Normalize-Value $val
    }
    $objs += [PSCustomObject]$o
}

# Export full CSV
$cleanCsv = Join-Path (Get-Location) 'apptraces-clean.csv'
$objs | Export-Csv $cleanCsv -NoTypeInformation -Force
Write-Host "Exported full CSV: $cleanCsv (`$($objs.Count) rows`)."

# Helper to get first present message-like field and robustly scan object
$msgCandidates = @('MessageText','message','Message','Trace','Text','customDimensions','details','MessageTemplate','Properties')
$pattern = 'CHANGE TRACKING|VIEW CHANGE TRACKING|SqlException|SqlClient|CHANGE_TRACKING|sp_getapplock|host.json|InvalidPackageContentException|Cannot find required host.json'

function Get-FirstMessage($obj) {
    foreach ($n in $msgCandidates) {
        if ($obj.PSObject.Properties.Match($n)) {
            $v = $obj.$n
            if ($v -ne $null -and "$v" -ne '') {
                # If field looks like JSON, try to parse and inspect inner values
                if ("$v".TrimStart().StartsWith('{') -or "$v".TrimStart().StartsWith('[')) {
                    try {
                        $inner = $v | ConvertFrom-Json -ErrorAction Stop
                        foreach ($pv in $inner.PSObject.Properties) {
                            if ($pv.Value -ne $null) {
                                $s = "$($pv.Value)"
                                if ($s -ne '' -and $s -match $pattern) { return $s }
                                if ($pv.Name -match 'message|error|exception|details|OriginalFormat') { return $s }
                            }
                        }
                    } catch {
                        if ("$v" -match $pattern) { return "$v" }
                        return "$v"
                    }
                } else {
                    if ("$v" -match $pattern) { return "$v" }
                    return "$v"
                }
            }
        }
    }

    foreach ($prop in $obj.PSObject.Properties) {
        $val = $prop.Value
        if ($null -eq $val) { continue }
        if (($val -is [string]) -and ($val.TrimStart().StartsWith('{') -or $val.TrimStart().StartsWith('['))) {
            try {
                $parsed = $val | ConvertFrom-Json -ErrorAction Stop
                $flat = $parsed | ConvertTo-Json -Depth 5 -Compress
                if ($flat -match $pattern) { return $flat }
            } catch {}
        }
        if ("$val" -match $pattern) { return "$val" }
    }

    try {
        $serialized = $obj | ConvertTo-Json -Depth 10 -Compress
        if ($serialized -match $pattern) { return $serialized }
    } catch {}

    return $null
}

# Filter SQL / change-tracking related rows — robust serialized search
$sqlRows = $objs | Where-Object {
    try {
        ($_ | ConvertTo-Json -Depth 10 -Compress) -match $pattern
    } catch {
        # fallback: join property values and search
        ($_.PSObject.Properties | ForEach-Object { if ($_.Value -ne $null) { "$($_.Value)" } }) -join ' ' -match $pattern
    }
}

$filteredCsv = Join-Path (Get-Location) 'apptraces-sql.csv'
if ($sqlRows.Count -gt 0) {
    $sqlRows | Export-Csv $filteredCsv -NoTypeInformation -Force
    Write-Host "Exported SQL-related rows: $filteredCsv (`$($sqlRows.Count) rows`)."
} else {
    Write-Host "No SQL/change-tracking rows found in the exported data."
}

# Preview top 10 filtered rows (timestamp + message if present)
$tsCandidates = @('TimeGenerated','timestamp','Timestamp','EventTime','StartTime')
function Get-FirstTimestamp($obj) {
    foreach ($n in $tsCandidates) {
        if ($obj.PSObject.Properties.Match($n)) {
            $v = $obj.$n
            if ($v -ne $null -and "$v" -ne '') { return "$v" }
        }
    }
    return $null
}

if ($sqlRows.Count -gt 0) {
    Write-Host "`nSample SQL-related entries (top 10):"
    $sqlRows | Select-Object @{Name='Timestamp';Expression={ Get-FirstTimestamp $_ }}, @{Name='Message';Expression={ Get-FirstMessage $_ }} |
        Select-Object -First 10 | Format-Table -AutoSize
}

Write-Host "`nDone."