#!/bin/bash
set -e

# Get environment values
output=$(azd env get-values)

# Parse the output to get the resource names and the resource group
while IFS= read -r line; do
    if [[ $line == AZURE_SQL_SERVER_RESOURCE_NAME* ]]; then
        SqlServerName=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
    elif [[ $line == RESOURCE_GROUP_NAME* ]]; then
        ResourceGroup=$(echo "$line" | cut -d '=' -f 2 | tr -d '"')
    fi
done <<< "$output"

# Read the config.json file to see if vnet is enabled
ConfigFolder=$(echo "$ResourceGroup" | cut -d '-' -f 2-)
jsonContent=$(cat ".azure/$ConfigFolder/config.json")
EnableVirtualNetwork=$(echo "$jsonContent" | jq -r '.infra.parameters.vnetEnabled')

if [[ $EnableVirtualNetwork == "false" ]]; then
    echo "VNet is not enabled. Skipping adding the client IP to the network rule of the Azure SQL Database."
else
    echo "VNet is enabled. Adding the client IP to the firewall rule of the Azure SQL Database."

    # Get the client IP
    ClientIP=$(curl -s https://api.ipify.org)

    # Check if the firewall rule already exists for this IP
    # Echo the az command for listing firewall rules
    RuleExists=$(az sql server firewall-rule list --resource-group "$ResourceGroup" --server "$SqlServerName" --query "[?startIpAddress=='$ClientIP' && endIpAddress=='$ClientIP'] | [0]" -o tsv)

    if [[ -z $RuleExists ]]; then
        echo "Adding the client IP $ClientIP to the firewall rule of the Azure SQL Database server $SqlServerName"
        echo "az sql server firewall-rule create --resource-group '$ResourceGroup' --server '$SqlServerName' --name 'AllowMyIP' --start-ip-address '$ClientIP' --end-ip-address '$ClientIP'"
        az sql server firewall-rule create --resource-group "$ResourceGroup" --server "$SqlServerName" --name "AllowMyIP" --start-ip-address "$ClientIP" --end-ip-address "$ClientIP"  > /dev/null
    else
        echo "The client IP $ClientIP is already in the firewall rule of the Azure SQL Database server $SqlServerName"
    fi
fi
