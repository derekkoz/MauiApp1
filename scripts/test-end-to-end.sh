#!/bin/sh
set -eu

# Run from repo root. Requires: curl, python3, sqlcmd (optional).
CONN=$(python3 - <<'PY'
import json
d=json.load(open("MauiApp1/local.settings.json"))
vals=d.get("Values",{})
print(vals.get("AZURE_SQL_CONNECTION_STRING_KEY") or vals.get("SqlConnectionString",""))
PY
)

if [ -z "$CONN" ]; then
  echo "ERROR: connection string not found in MauiApp1/local.settings.json"
  exit 1
fi
export AZURE_SQL_CONNECTION_STRING_KEY="$CONN"

ID=$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)

BODY=$(cat <<JSON
{"id":"$ID","order":1,"title":"it-test-trigger","url":"https://example.test","completed":false}
JSON
)

echo "POSTing test row Id=$ID to http://localhost:7071/api/httptrigger-sql-output"
curl -sS -X POST -H "Content-Type: application/json" -d "$BODY" http://localhost:7071/api/httptrigger-sql-output || true

# Poll DB (30s) using sqlcmd if available
SERVER="$(python3 - <<'PY'
import json
d=json.load(open("MauiApp1/local.settings.json"))
vals=d.get("Values",{})
cs = vals.get("AZURE_SQL_CONNECTION_STRING_KEY") or vals.get("SqlConnectionString","")
parts=[p for p in cs.split(';') if '=' in p]
kv={p.split('=',1)[0].strip():p.split('=',1)[1].strip() for p in parts}
server = kv.get('Server','').replace('tcp:','').split(',')[0]
db = kv.get('Initial Catalog', kv.get('Database',''))
print(server or "", db or "")
PY
)"

SERVER=$(echo "$SERVER" | awk '{print $1}')
DB=$(echo "$SERVER" | awk '{print $2}')
# fallback parse simpler:
SERVER="$(python3 - <<'PY'
import json
d=json.load(open("MauiApp1/local.settings.json"))
vals=d.get("Values",{})
cs = vals.get("AZURE_SQL_CONNECTION_STRING_KEY") or vals.get("SqlConnectionString","")
for part in cs.split(';'):
    if part.strip().lower().startswith('server=') or part.strip().lower().startswith('data source='):
        print(part.split('=',1)[1].replace('tcp:','').split(',')[0])
        break
PY
)"
DB="$(python3 - <<'PY'
import json
d=json.load(open("MauiApp1/local.settings.json"))
vals=d.get("Values",{})
cs = vals.get("AZURE_SQL_CONNECTION_STRING_KEY") or vals.get("SqlConnectionString","")
for part in cs.split(';'):
    if part.strip().lower().startswith('initial catalog=') or part.strip().lower().startswith('database='):
        print(part.split('=',1)[1])
        break
PY
)"

WAIT=30
END=$((SECONDS + WAIT))
while [ $SECONDS -lt $END ]; do
  if command -v sqlcmd >/dev/null 2>&1; then
    OUT=$(sqlcmd -S "tcp:${SERVER},1433" -d "${DB}" -G -h -1 -W -Q "SET NOCOUNT ON; SELECT CASE WHEN EXISTS(SELECT 1 FROM dbo.ToDo WHERE Id = '${ID}' AND completed = 1) THEN 1 ELSE 0 END;" 2>/dev/null || true)
    OUT=$(echo "$OUT" | tr -d '[:space:]')
    if [ "$OUT" = "1" ]; then
      echo "SUCCESS: row $ID marked completed."
      exit 0
    fi
  fi
  sleep 2
done

echo "TIMEOUT: row $ID not marked completed within ${WAIT}s."
echo "Check host logs for 'Raw item payload' and run this query in Azure Portal Query Editor:"
echo "  SELECT Id, completed, ModifiedAt FROM dbo.ToDo WHERE Id = '$ID';"
exit 2

# Cleanup test ACIs in rg-testprog (safe: does nothing if RG or groups are absent)
if [ "$(az group exists -n rg-testprog)" = "true" ]; then
  for cg in $(az container list --resource-group rg-testprog --query "[?starts_with(name, 'testprog-aci') || starts_with(name, 'debug-logs')].name" -o tsv); do
    [ -n "$cg" ] || continue
    echo "Deleting test container group: $cg"
    az container delete --resource-group rg-testprog --name "$cg" --yes || true
  done
fi