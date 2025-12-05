# Republish the function for Windows and zip-deploy it to the Function App
# Run this locally in your repo root. Do NOT include secrets here.

$rg = 'rg-Water_project_database-dev'
$app = 'MKRFunctApp-dotnet8'
$publishDir = Join-Path $PSScriptRoot 'publish_win'
$zipPath = Join-Path $PSScriptRoot 'functionapp_win.zip'

# Clean
Remove-Item -Recurse -Force $publishDir -ErrorAction SilentlyContinue
Remove-Item -Force $zipPath -ErrorAction SilentlyContinue

# Build/publish for Windows runtime (framework dependent)
dotnet publish -c Release -r win-x64 --self-contained false -o $publishDir

# Confirm publish produced a Windows deps.json
Get-ChildItem -Path $publishDir -Filter '*.deps.json' | ForEach-Object {
  Write-Output "Inspecting $($_.FullName)"
  Select-String -Path $_.FullName -Pattern '"runtimeTarget"' -Context 0,2
}

# Zip and deploy
Compress-Archive -Path (Join-Path $publishDir '*') -DestinationPath $zipPath -Force
az functionapp deployment source config-zip --resource-group $rg --name $app --src $zipPath

# Restart and tail logs
az webapp restart --resource-group $rg --name $app
Start-Sleep -Seconds 20
az webapp log tail --resource-group $rg --name $app# Republish the function for Windows and zip-deploy it to the Function App
# Run this locally in your repo root. Do NOT include secrets here.

$rg = 'rg-Water_project_database-dev'
$app = 'MKRFunctApp-dotnet8'
$publishDir = Join-Path $PSScriptRoot 'publish_win'
$zipPath = Join-Path $PSScriptRoot 'functionapp_win.zip'

# Clean
Remove-Item -Recurse -Force $publishDir -ErrorAction SilentlyContinue
Remove-Item -Force $zipPath -ErrorAction SilentlyContinue

# Publish (Windows runtime)
dotnet publish -c Release -r win-x64 --self-contained false -o $publishDir

# Confirm .deps.json runtimeTarget contains win-x64
Get-ChildItem -Path $publishDir -Filter '*.deps.json' -File | ForEach-Object {
  Write-Output "Inspecting $($_.FullName)"
  Select-String -Path $_.FullName -Pattern '"runtimeTarget"' -Context 0,2
}

# Create zip and deploy
Compress-Archive -Path (Join-Path $publishDir '*') -DestinationPath $zipPath -Force
az functionapp deployment source config-zip --resource-group $ResourceGroup --name $AppName --src $zipPath

# Restart and stream logs
az webapp restart --resource-group $ResourceGroup --name $AppName
Start-Sleep -Seconds 20
az webapp log tail --resource-group $ResourceGroup --name $AppName