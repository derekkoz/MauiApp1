Param(
  [string]$App = "mkrfunctapp-dotnet8",
  [string]$Rg = "rg-Water_project_database-dev",
  [string]$ProjectDir = ".",
  [string]$PublishDir = ".\publish",
  [string]$ZipFile = "functionapp.zip",
  [int]$LogTailSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Output "Checking prerequisites..."
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
  Write-Error "dotnet CLI not found. Run this script on a machine with .NET 8 SDK installed."
  exit 1
}
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  Write-Error "Azure CLI 'az' not found. Install Azure CLI or run in Cloud Shell."
  exit 1
}

Write-Output "Restoring and publishing project to '$PublishDir'..."
dotnet restore $ProjectDir
dotnet publish $ProjectDir -c Release -o $PublishDir

Write-Output "Verifying publish metadata..."
if (-not (Test-Path (Join-Path $PublishDir ".azurefunctions"))) {
  Write-Error "ERROR: '$PublishDir/.azurefunctions' not found. Ensure this is an Azure Functions (.NET isolated) project and Microsoft.NET.Sdk.Functions is referenced in the function project csproj."
  Write-Output "Publish folder contents (first 200 entries):"
  Get-ChildItem -Path $PublishDir -Recurse | Select-Object -First 200 | ForEach-Object { $_.FullName }
  exit 1
}

Write-Output "Creating ZIP package '$ZipFile'..."
if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
# Compress all files from publish root into the zip
Compress-Archive -Path (Join-Path $PublishDir '*') -DestinationPath $ZipFile -Force

Write-Output "Deploying $ZipFile to $App in $Rg..."
az functionapp deployment source config-zip --name $App --resource-group $Rg --src $ZipFile

Write-Output "Restarting function app..."
az functionapp restart --name $App --resource-group $Rg

Write-Output "Deployment finished. To view logs run:"
Write-Output "  az webapp log tail --name $App --resource-group $Rg"
Write-Output "Or download logs:"
Write-Output "  az webapp log download --name $App --resource-group $Rg --log-file /tmp/fa-logs.zip"

# Optional: try to tail logs if running interactively
try {
  Write-Output "Tailing logs for $LogTailSeconds seconds (press Ctrl+C to cancel)..."
  Start-Process -NoNewWindow -FilePath az -ArgumentList "webapp log tail --name $App --resource-group $Rg" -PassThru | Out-Null
  Write-Output "If you prefer bounded tailing, run the following in Bash:"
  Write-Output "  timeout $LogTailSeconds az webapp log tail --name $App --resource-group $Rg"
} catch {
  # non-fatal
}