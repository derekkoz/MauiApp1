# Copies are done; this script configures logging and tails the Function App logs.
# Run this locally (not in Kudu) where Azure CLI is installed and you're logged in (az login).
param(
    [string]$LocalRepo = "C:\dev\Water_project_database",
    [string]$AppName = "mkrfunctapp-dotnet8",
    [string]$ResourceGroup = "rg-Water_project_database-dev"
)

if (-not (Test-Path $LocalRepo)) {
    Write-Error "Local repo not found: $LocalRepo"
    exit 1
}

Set-Location $LocalRepo

# ensure az is present
try { az --version > $null } catch { Write-Error "Azure CLI not found. Install and run 'az login'."; exit 1 }

Write-Host "Enabling filesystem logging and console level=Information..."
az webapp log config --name $AppName --resource-group $ResourceGroup --application-logging filesystem --detailed-error-messages true --failed-request-tracing true | Out-Null

az functionapp config appsettings set --name $AppName --resource-group $ResourceGroup --settings AzureFunctionsJobHost__logging__console__isEnabled=true AzureFunctionsJobHost__logging__console__loggingLevel__default=Information SCM_LOGSTREAM_TIMEOUT=3600 | Out-Null

Write-Host "Starting log tail (Ctrl+C to stop). If it disconnects, retry or use Portal Log stream."
az webapp log tail --name $AppName --resource-group $ResourceGroup# Copies are done; this script configures logging and tails the Function App logs.
# Run this locally (not in Kudu) where Azure CLI is installed and you're logged in (az login).
param(
    [string]$LocalRepo = "C:\dev\Water_project_database",
    [string]$AppName = "mkrfunctapp-dotnet8",
    [string]$ResourceGroup = "rg-Water_project_database-dev"
)

if (-not (Test-Path $LocalRepo)) {
    Write-Error "Local repo not found: $LocalRepo"
    exit 1
}

Set-Location $LocalRepo

# ensure az is present
try { az --version > $null } catch { Write-Error "Azure CLI not found. Install and run 'az login'."; exit 1 }

Write-Host "Enabling filesystem logging and console level=Information..."
az webapp log config --name $AppName --resource-group $ResourceGroup --application-logging filesystem --detailed-error-messages true --failed-request-tracing true | Out-Null

az functionapp config appsettings set --name $AppName --resource-group $ResourceGroup --settings AzureFunctionsJobHost__logging__console__isEnabled=true AzureFunctionsJobHost__logging__console__loggingLevel__default=Information SCM_LOGSTREAM_TIMEOUT=3600 | Out-Null

Write-Host "Starting log tail (Ctrl+C to stop). If it disconnects, retry or use Portal Log stream."
az webapp log tail --name $AppName --resource-group $ResourceGroup# Copies are done; this script configures logging and tails the Function App logs.
# Run this locally (not in Kudu) where Azure CLI is installed and you're logged in (az login).
param(
    [string]$LocalRepo = "C:\dev\Water_project_database",
    [string]$AppName = "mkrfunctapp-dotnet8",
    [string]$ResourceGroup = "rg-Water_project_database-dev"
)

if (-not (Test-Path $LocalRepo)) {
    Write-Error "Local repo not found: $LocalRepo"
    exit 1
}

Set-Location $LocalRepo

# ensure az is present
try { az --version > $null } catch { Write-Error "Azure CLI not found. Install and run 'az login'."; exit 1 }

Write-Host "Enabling filesystem logging and console level=Information..."
az webapp log config --name $AppName --resource-group $ResourceGroup --application-logging filesystem --detailed-error-messages true --failed-request-tracing true | Out-Null

az functionapp config appsettings set --name $AppName --resource-group $ResourceGroup --settings AzureFunctionsJobHost__logging__console__isEnabled=true AzureFunctionsJobHost__logging__console__loggingLevel__default=Information SCM_LOGSTREAM_TIMEOUT=3600 | Out-Null

Write-Host "Starting log tail (Ctrl+C to stop). If it disconnects, retry or use Portal Log stream."
az webapp log tail --name $AppName --resource-group $ResourceGroup# Copies are done; this script configures logging and tails the Function App logs.
# Run this locally (not in Kudu) where Azure CLI is installed and you're logged in (az login).
param(
    [string]$LocalRepo = "C:\dev\Water_project_database",
    [string]$AppName = "mkrfunctapp-dotnet8",
    [string]$ResourceGroup = "rg-Water_project_database-dev"
)

if (-not (Test-Path $LocalRepo)) {
    Write-Error "Local repo not found: $LocalRepo"
    exit 1
}

Set-Location $LocalRepo

# ensure az is present
try { az --version > $null } catch { Write-Error "Azure CLI not found. Install and run 'az login'."; exit 1 }

Write-Host "Enabling filesystem logging and console level=Information..."
az webapp log config --name $AppName --resource-group $ResourceGroup --application-logging filesystem --detailed-error-messages true --failed-request-tracing true | Out-Null

az functionapp config appsettings set --name $AppName --resource-group $ResourceGroup --settings AzureFunctionsJobHost__logging__console__isEnabled=true AzureFunctionsJobHost__logging__console__loggingLevel__default=Information SCM_LOGSTREAM_TIMEOUT=3600 | Out-Null

Write-Host "Starting log tail (Ctrl+C to stop). If it disconnects, retry or use Portal Log stream."
az webapp log tail --name $AppName --resource-group $ResourceGroup