# Acquire AAD access token and run master SQL as Azure AD admin (no password shown).
# Usage: pwsh ./scripts/run-master-grant.ps1

# Ensure az CLI is logged in and uses the tenant/subscription that can manage the server.
$tokenJson = az account get-access-token --resource https://database.windows.net/ -o json 2>$null | ConvertFrom-Json
if (-not $tokenJson -or -not $tokenJson.accessToken) {
    Write-Error "Failed to obtain access token from az. Run 'az login' and try again."
    exit 1
}

$connStr = "Server=tcp:sql-zkpr3wsv3vvq6.database.windows.net;Database=master;Encrypt=True;TrustServerCertificate=False;"

# Use System.Data.SqlClient and set AccessToken
Add-Type -AssemblyName System.Data
$cn = New-Object System.Data.SqlClient.SqlConnection $connStr
$cn.AccessToken = $tokenJson.accessToken

$masterSql = @"
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'kozderek@gmail.com')
  CREATE LOGIN [kozderek@gmail.com] FROM EXTERNAL PROVIDER;
BEGIN TRY
  GRANT EXECUTE ON OBJECT::sys.sp_getapplock TO [kozderek@gmail.com];
END TRY
BEGIN CATCH
  PRINT 'Skipping sp_getapplock GRANT: ' + ERROR_MESSAGE();
END CATCH;
"@

try {
    $cn.Open()
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = $masterSql
    $cmd.CommandTimeout = 120
    $cmd.ExecuteNonQuery() | Out-Null
    Write-Host "Master block executed (CREATE LOGIN / GRANT)."

    # Verify server principal
    $cmd.CommandText = "SELECT name, principal_id, type_desc FROM sys.server_principals WHERE name = N'kozderek@gmail.com';"
    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        Write-Host ("Found principal: {0}  id={1}  type={2}" -f $reader["name"], $reader["principal_id"], $reader["type_desc"])
    }
    $reader.Close()
} catch {
    Write-Error "Error running master SQL: $($_.Exception.Message)"
    exit 1
} finally {
    if ($cn.State -eq 'Open') { $cn.Close() }
}