# Acquire AAD token and test sys.sp_getapplock as your AAD identity
# Usage: & .\scripts\test-spgetapplock.ps1

$tokenJson = az account get-access-token --resource https://database.windows.net/ -o json 2>$null | ConvertFrom-Json
if (-not $tokenJson -or -not $tokenJson.accessToken) {
    Write-Error "Failed to obtain access token from az. Run 'az login' and try again."
    exit 1
}

$connStr = "Server=tcp:sql-zkpr3wsv3vvq6.database.windows.net;Database=ToDo;Encrypt=True;TrustServerCertificate=False;"

Add-Type -AssemblyName System.Data
$cn = New-Object System.Data.SqlClient.SqlConnection $connStr
$cn.AccessToken = $tokenJson.accessToken

$testSql = @"
DECLARE @rc int;
EXEC @rc = sys.sp_getapplock @Resource = 'testlock_for_aad', @LockMode = 'Exclusive', @LockOwner = 'Session';
SELECT @rc AS LockResult;
IF @rc >= 0
    BEGIN
        EXEC sys.sp_releaseapplock @Resource = 'testlock_for_aad', @LockOwner = 'Session';
    END
"@

try {
    $cn.Open()
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = $testSql
    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        Write-Host "sp_getapplock result:" $reader["LockResult"]
    }
    $reader.Close()
    Write-Host "Test complete."
} catch {
    Write-Error "Error testing sp_getapplock: $($_.Exception.Message)"
    exit 1
} finally {
    if ($cn.State -eq 'Open') { $cn.Close() }
}