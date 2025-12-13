#!/bin/sh
set -euo pipefail

# Run from repo root (where MauiApp1/local.settings.json lives)

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
echo "Exported AZURE_SQL_CONNECTION_STRING_KEY (len=${#AZURE_SQL_CONNECTION_STRING_KEY})"

# Try to parse SERVER/DB (best-effort); if parsing fails set them manually
SERVER=$(python3 - <<'PY'
import json
d=json.load(open("MauiApp1/local.settings.json"))
vals=d.get("Values",{})
cs = vals.get("AZURE_SQL_CONNECTION_STRING_KEY") or vals.get("SqlConnectionString","")
parts=[p for p in cs.split(';') if '=' in p]
kv={}
for p in parts:
    k,v=p.split('=',1)
    kv[k.strip()]=v.strip()
server=kv.get('Server','').replace('tcp:','').split(',')[0]
db=kv.get('Initial Catalog', kv.get('Database',''))
if not server:
    server=kv.get('Data Source','').replace('tcp:','').split(',')[0]
print(server or "")
PY
)
DB=$(python3 - <<'PY'
import json
d=json.load(open("MauiApp1/local.settings.json"))
vals=d.get("Values",{})
cs = vals.get("AZURE_SQL_CONNECTION_STRING_KEY") or vals.get("SqlConnectionString","")
parts=[p for p in cs.split(';') if '=' in p]
kv={}
for p in parts:
    k,v=p.split('=',1)
    kv[k.strip()]=v.strip()
db=kv.get('Initial Catalog', kv.get('Database',''))
print(db or "")
PY
)

if [ -n "$SERVER" ] && [ -n "$DB" ]; then
  export SERVER DB
  echo "SERVER=$SERVER"
  echo "DB=$DB"
else
  echo "Couldn't parse SERVER/DB automatically. Set them manually if you need sqlcmd checks:"
  echo "  export SERVER='<your-server>'"
  echo "  export DB='<your-database>'"
fi