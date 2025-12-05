param(
  [string]$PublishDir = ".\publish",
  [string]$OutputZip  = ".\functionapp-azure.zip"
)

# Resolve and validate publish directory (must exist)
try {
  $publishPath = (Resolve-Path -Path $PublishDir -ErrorAction Stop).Path
} catch {
  Write-Error "Publish folder not found: $PublishDir. Run 'dotnet publish' first."
  exit 1
}

$metaPath = Join-Path $publishPath "functions.metadata"
if (-not (Test-Path $metaPath)) {
  Write-Error "functions.metadata not found at $metaPath"
  exit 1
}

# Read metadata
$metaJson = Get-Content $metaPath -Raw
$functions = $metaJson | ConvertFrom-Json

# Ensure .azurefunctions root inside the publish path
$azureRoot = Join-Path $publishPath ".azurefunctions"
if (Test-Path $azureRoot) { Remove-Item -LiteralPath $azureRoot -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -Path $azureRoot -ItemType Directory | Out-Null

# For each function, create function.json with scriptFile, entryPoint and bindings from metadata
foreach ($f in $functions) {
  $fnName = $f.name
  $fnDir = Join-Path $azureRoot $fnName
  New-Item -Path $fnDir -ItemType Directory -Force | Out-Null

  $out = [ordered]@{}
  if ($f.PSObject.Properties.Match("scriptFile")) { $out.scriptFile = $f.scriptFile }
  if ($f.PSObject.Properties.Match("entryPoint")) { $out.entryPoint = $f.entryPoint }
  $out.bindings = $f.bindings

  $out | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $fnDir "function.json") -Encoding UTF8
  Write-Host "Wrote .azurefunctions/$fnName/function.json"
}

# If a self-contained exe is present, update worker.config.json so the host will run the exe
$exeCandidate = Get-ChildItem -Path $publishPath -Filter "*.exe" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "functions-quickstart*" } |
                Select-Object -First 1

if ($exeCandidate) {
  $workerConfPath = Join-Path $publishPath "worker.config.json"
  if (Test-Path $workerConfPath) {
    try {
      $wc = Get-Content $workerConfPath -Raw | ConvertFrom-Json
      # Ensure a backslash separator after {WorkerRoot}
      $wc.description.defaultExecutablePath = "{WorkerRoot}\$($exeCandidate.Name)"
      $wc.description.defaultWorkerPath = $exeCandidate.Name
      $wc | ConvertTo-Json -Depth 10 | Out-File -FilePath $workerConfPath -Encoding UTF8
      Write-Host "Updated worker.config.json to prefer self-contained exe: $($exeCandidate.Name)"
    } catch {
      Write-Warning "Failed to update worker.config.json: $_"
    }
  } else {
    Write-Host "No worker.config.json found to update; skipping exe configuration."
  }
}

# Compute absolute OutputZip path WITHOUT requiring the file to exist
$cwd = (Get-Location).Path
if ([IO.Path]::IsPathRooted($OutputZip)) {
  $absOutputZip = [IO.Path]::GetFullPath($OutputZip)
} else {
  $absOutputZip = Join-Path $cwd $OutputZip
}
$absOutputZip = [IO.Path]::GetFullPath($absOutputZip)

# Ensure the destination directory for the zip exists
$zipParent = Split-Path -Path $absOutputZip -Parent
if (-not [string]::IsNullOrEmpty($zipParent) -and -not (Test-Path $zipParent)) {
  New-Item -ItemType Directory -Path $zipParent -Force | Out-Null
}

# Recreate zip including .azurefunctions and whole publish content
Push-Location $publishPath
try {
  if (Test-Path $absOutputZip) { Remove-Item -LiteralPath $absOutputZip -Force -ErrorAction SilentlyContinue }

  # Get top-level entries including dot-prefixed/hidden ones and compress them
  $topEntries = Get-ChildItem -Force | ForEach-Object { $_.Name }
  if (-not $topEntries) {
    throw "No files/folders found in publish directory: $publishPath"
  }

  Compress-Archive -LiteralPath $topEntries -DestinationPath $absOutputZip -Force
} catch {
  Write-Error "Failed to create package: $_"
  Pop-Location
  exit 1
} finally {
  Pop-Location
}

Write-Host "Created package: $absOutputZip"
Write-Host "Deploy with:"
Write-Host "  az functionapp deployment source config-zip --resource-group <rg> --name <app> --src `"$absOutputZip`"'
