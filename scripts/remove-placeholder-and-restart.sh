#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-mkrfunctapp-dotnet8}"
RG="${RG:-rg-Water_project_database-dev}"
SETTING="${SETTING:-WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED}"

# Fail fast if az is not available
if ! command -v az >/dev/null 2>&1; then
  echo "ERROR: Azure CLI 'az' not found. Run this script in Azure Cloud Shell or on a machine with Azure CLI installed."
  exit 1
fi

# Ensure logged in (interactive if needed)
if ! az account show >/dev/null 2>&1; then
  echo "Logging into Azure..."
  az login --only-show-errors
fi

echo "Deleting app setting '$SETTING' from $APP_NAME in $RG..."
az functionapp config appsettings delete \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --setting-names "$SETTING" \
  --only-show-errors

echo "Restarting function app '$APP_NAME'..."
az functionapp restart --name "$APP_NAME" --resource-group "$RG" --only-show-errors

# By default do NOT tail logs (tailing blocks IDEs). Make tailing opt-in.
TAIL_LOGS="${TAIL_LOGS:-false}"
TAIL_SECONDS="${TAIL_SECONDS:-30}"

if [ "$TAIL_LOGS" = "true" ]; then
  echo "Tailing logs for ${TAIL_SECONDS}s..."
  if command -v timeout >/dev/null 2>&1; then
    timeout "${TAIL_SECONDS}s" az webapp log tail --name "$APP_NAME" --resource-group "$RG"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${TAIL_SECONDS}s" az webapp log tail --name "$APP_NAME" --resource-group "$RG"
  else
    # Fallback: run in background and ensure we kill it after TAIL_SECONDS
    az webapp log tail --name "$APP_NAME" --resource-group "$RG" &
    tail_pid=$!
    trap 'kill "$tail_pid" 2>/dev/null || true' EXIT
    sleep "$TAIL_SECONDS"
    kill "$tail_pid" 2>/dev/null || true
    trap - EXIT
  fi
else
  echo "Skipping 'az webapp log tail'. To enable, run with: TAIL_LOGS=true TAIL_SECONDS=60 ./scripts/remove-placeholder-and-restart.sh"
fi