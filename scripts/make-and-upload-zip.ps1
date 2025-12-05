# parse publish settings and extract ZipDeploy credentials
param(
 [string]$PublishSettingsPath = ".\MKRFunctApp-dotnet8.PublishSettings",
 [string]$ZipPath = ".\functionapp.zip",
 [string]$ResourceGroup = "",
 [string]$AppName = "",
 [string]$ProjectPath = "./functions-quickstart-dotnet-azd-sql.csproj",
 [string]$RuntimeIdentifier = "win-x64",   # set to empty "" for framework-dependent publish
 [switch]$SelfContained                   # pass -SelfContained to publish self-contained
)

if (-not (Test-Path $PublishSettingsPath)) {
 Write-Error "Publish settings not found: $PublishSettingsPath. Download from Azure Portal (Get publish profile) and place it here, or pass -PublishSettingsPath."
 exit 1
}

#1) build (framework-dependent, no linux RID)
# Use the provided project path so users can point to backups or other csproj locations
$publishArgs = @()
$publishArgs += $ProjectPath
$publishArgs += "-c"
$publishArgs += "Release"
$publishArgs += "-o"
$publishArgs += "./publish"

if ($RuntimeIdentifier -and $RuntimeIdentifier.Trim() -ne "") {
 $publishArgs += "-r"
 $publishArgs += $RuntimeIdentifier
}

if ($SelfContained.IsPresent) {
 $publishArgs += "--self-contained"
 $publishArgs += "true"
} else {
 $publishArgs += "--self-contained"
 $publishArgs += "false"
}

Write-Host "Running: dotnet publish $($publishArgs -join ' ')"
dotnet publish @publishArgs

#2) create zip
if (-not (Test-Path ".\publish")) {
 Write-Error "Publish output folder not found."
 exit 1
}
# If we published self-contained and produced an exe, update worker.config.json so Functions host launches the exe directly.
try {
 $exe = Get-ChildItem -Path .\publish -Recurse -Filter *.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1
 $workerConfigPath = Join-Path -Path ".\publish" -ChildPath "worker.config.json"
 if ($exe -and (Test-Path $workerConfigPath)) {
   Write-Host "Detected self-contained exe: $($exe.FullName). Patching worker.config.json to launch the exe."
   $json = Get-Content $workerConfigPath -Raw | ConvertFrom-Json

   # Set defaultExecutablePath to the exe name (relative) and clear defaultWorkerPath
   $json.description.defaultExecutablePath = $exe.Name
   $json.description.defaultWorkerPath = ""

   $json | ConvertTo-Json -Depth 10 | Out-File -FilePath $workerConfigPath -Encoding UTF8 -Force
 }
} catch {
 Write-Warning "Could not patch worker.config.json: $($_.Exception.Message)"
}

Set-Location -Path .\publish
Compress-Archive -Path * -DestinationPath ..\functionapp.zip -Force
Set-Location -Path ..

if (-not (Test-Path $ZipPath)) {
 Write-Error "Zip not found: $ZipPath"
 exit 1
}

# parse publish settings and extract ZipDeploy credentials
$xml = [xml](Get-Content $PublishSettingsPath)
$zipProfile = $xml.publishData.publishProfile | Where-Object { $_.publishMethod -eq "ZipDeploy" }
if (-not $zipProfile) {
 Write-Error "No ZipDeploy profile found in publish settings."
 exit 1
}

$pubUser = $zipProfile.userName
$pubPass = $zipProfile.userPWD
if ([string]::IsNullOrEmpty($pubUser) -or [string]::IsNullOrEmpty($pubPass)) {
 Write-Error "Publish credentials missing in the publish settings. Open the .PublishSettings and copy userName/userPWD manually."
 exit 1
}

$scmHost = ($zipProfile.publishUrl -replace ":443$","")
$uri = "https://$scmHost/api/zipdeploy"
Write-Host "Uploading $ZipPath -> $uri (user: $pubUser)"

# try Kudu zipdeploy first (basic auth)
$kuduSucceeded = $false
try {
 $securePass = ConvertTo-SecureString $pubPass -AsPlainText -Force
 $cred = New-Object System.Management.Automation.PSCredential($pubUser, $securePass)

 # Use Invoke-WebRequest so we can inspect response content if needed
 # NOTE: -TimeoutSec must have a space before the value
 $resp = Invoke-WebRequest -Uri $uri -Credential $cred -Method Post -InFile $ZipPath -ContentType 'application/zip' -TimeoutSec 600 -ErrorAction Stop

 $content = if ($resp -and $resp.Content) { $resp.Content } else { "" }

 # If response looks like an HTML login or generic HTML, treat as failure even if HTTP status is200
 if ($content -match '<!DOCTYPE|<html|Sign in to your account|IIS Detailed Error|HTTP Error') {
 Write-Warning "Kudu returned HTML content (likely an interactive login or server error). Will fall back to Azure CLI deployment."
 } elseif ($null -ne $resp.StatusCode -and ($resp.StatusCode -ge200 -and $resp.StatusCode -lt300)) {
 $kuduSucceeded = $true
 } else {
 Write-Warning "Kudu returned status $($resp.StatusCode). Will fall back to Azure CLI deployment."
 }
} catch {
 Write-Warning "Kudu upload attempt failed: $($_.Exception.Message)"
}

if ($kuduSucceeded) {
 Write-Host "Upload response:"
 if ($resp -and $resp.Content) { $resp.Content | Out-Host }
 Write-Host "Upload complete via Kudu. Restart the host (Kudu or Portal) and check logs."
 exit 0
}

# Fallback to Azure CLI zip deploy
Write-Host "Falling back to 'az functionapp deployment source config-zip'..."

# Determine app name if not provided
if ([string]::IsNullOrEmpty($AppName)) {
 $AppName = ($scmHost -replace '\.scm\.azurewebsites\.net$','')
}

# Try to resolve resource group if not provided (only if az is available)
if ([string]::IsNullOrEmpty($ResourceGroup)) {
 Write-Host "ResourceGroup not provided. Attempting to discover resource group using 'az' (requires you to be logged in)."

 $azCmd = Get-Command az -ErrorAction SilentlyContinue
 if ($azCmd) {
   try {
     $originalLocation = Get-Location
     Set-Location -Path $env:TEMP

     # note the space between -o tsv and 2>$null
     $rg = & az resource list --name $AppName --query "[?type=='Microsoft.Web/sites'].resourceGroup" -o tsv 2>$null
     if ($rg) { $ResourceGroup = $rg.Trim() }

     Set-Location -Path $originalLocation
   } catch {
     try { Set-Location -Path $originalLocation } catch { }
     # ignore
   }
 } else {
   Write-Host "Azure CLI 'az' not found in PATH; cannot auto-discover resource group. Provide -ResourceGroup to the script."
 }
}

# Ensure Azure CLI is available before attempting az deployment
$azCmd = Get-Command az -ErrorAction SilentlyContinue
if (-not $azCmd) {
 Write-Error "Azure CLI 'az' not found in PATH. Install Azure CLI or provide valid Kudu publish credentials."
 exit 1
}

if ([string]::IsNullOrEmpty($ResourceGroup)) {
 Write-Error "Resource group could not be determined. Provide -ResourceGroup <rg> to the script or run 'az functionapp deployment source config-zip' manually."
 exit 1
}

Write-Host "Deploying via Azure CLI: resource-group='$ResourceGroup' name='$AppName' src='$ZipPath'"

# If ZipPath is relative, resolve to absolute so we can copy it to temp
try {
    $zipFullPath = (Resolve-Path -LiteralPath $ZipPath -ErrorAction Stop).Path
} catch {
    try {
        $zipFullPath = (Get-Item -LiteralPath $ZipPath -ErrorAction Stop).FullName
    } catch {
        Write-Error "Could not resolve ZipPath '$ZipPath'. Ensure the file exists."
        exit 1
    }
}

# Execute az command from temp to avoid UNC issues. Copy zip to temp and reference that path.
$originalLocation = Get-Location
$tempZip = Join-Path -Path $env:TEMP -ChildPath ([IO.Path]::GetFileName($zipFullPath))
try {
 Copy-Item -LiteralPath $zipFullPath -Destination $tempZip -Force -ErrorAction Stop
 Set-Location -Path $env:TEMP
 & az functionapp deployment source config-zip --resource-group $ResourceGroup --name $AppName --src $tempZip
 $azExit = $LASTEXITCODE
} finally {
 # restore working dir and remove temp copy
 try { Set-Location -Path $originalLocation } catch { }
 try { Remove-Item -LiteralPath $tempZip -Force -Recurse -ErrorAction SilentlyContinue } catch { }
}

if ($azExit -ne0) {
 Write-Error "Azure CLI deployment failed (exit code $azExit). Check 'az login' and that you have permission to the subscription/resource group."
 exit 1
}

Write-Host "Azure CLI deployment succeeded. Restart the host in Portal if needed and check logs."
exit 0
