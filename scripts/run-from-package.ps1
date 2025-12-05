param(
  [string] $AppName = "MKRFunctApp-dotnet8",
  [string] $ResourceGroup = "rg-Water_project_database-dev",
  [string] $ProjectPath = "./functions-quickstart-dotnet-azd-sql.csproj",
  [string] $PublishFolder = ".\\publish",
  [string] $ZipName = "functionapp.zip",
  [string] $StorageAccount = "",            # set if you know it, otherwise script will try to read AzureWebJobsStorage
  [string] $Container = "function-deployments",
  [int]    $SasHours = 48
)

# 1) build/publish the function project
dotnet publish $ProjectPath -c Release -o $PublishFolder

# 2) create zip
if (Test-Path $ZipName) { Remove-Item $ZipName -Force }
Compress-Archive -Path "$PublishFolder\*" -DestinationPath $ZipName -Force

# verify local ZIP exists (PowerShell)
if (-not (Test-Path ".\$ZipName")) {
    Write-Error "Local ZIP not found: .\$ZipName"
    exit 1
}

# 3) obtain storage account if not provided (reads AzureWebJobsStorage connection string)
if (-not $StorageAccount) {
  $azSetting = az functionapp config appsettings list --name $AppName --resource-group $ResourceGroup -o json | ConvertFrom-Json
  $cstr = ($azSetting | Where-Object { $_.name -eq "AzureWebJobsStorage" }).value
  if ($cstr -and $cstr -match "AccountName=([^;]+)") { $StorageAccount = $Matches[1] }
}
if (-not $StorageAccount) { Write-Error "Storage account not set and AzureWebJobsStorage not found. Set --StorageAccount."; exit 1 }

# 4) ensure container exists
az storage container create --account-name $StorageAccount --name $Container --auth-mode login | Out-Null

# 5) upload zip (uses your current az login; if you need to use account key, replace with --account-key)
az storage blob upload --account-name $StorageAccount --container-name $Container --name $ZipName --file $ZipName --overwrite --auth-mode login | Out-Null

# 6) generate read SAS for the blob
$expiry = (Get-Date).ToUniversalTime().AddHours($SasHours).ToString("yyyy-MM-ddTHH:mmZ")
$SAS = az storage blob generate-sas --account-name $StorageAccount --container-name $Container --name $ZipName --permissions r --expiry $expiry --auth-mode login -o tsv
if (-not $SAS) { Write-Error "Failed to generate SAS. Ensure you have Storage Blob Data Contributor or use account key."; exit 1 }
$blobUrl = "https://$StorageAccount.blob.core.windows.net/$Container/$ZipName`?$SAS"

# 7) point function app to package (mounts package)
az functionapp config appsettings set --name $AppName --resource-group $ResourceGroup --settings "WEBSITE_RUN_FROM_PACKAGE=$blobUrl" | Out-Null

# 8) verify and tail logs
az functionapp config appsettings list --name $AppName --resource-group $ResourceGroup --query "[?name=='WEBSITE_RUN_FROM_PACKAGE' || name=='FUNCTIONS_WORKER_RUNTIME']" -o json
Write-Host "Deployment set to Run-From-Package. Tailing logs..."
az webapp log tail --name $AppName --resource-group $ResourceGroup