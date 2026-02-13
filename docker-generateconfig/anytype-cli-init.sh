#!/bin/bash

set -e

echo "INFO: [anytype-cli-init] Starting initialization"

ANYTYPE_CONFIG_DIR="${ANYTYPE_CONFIG_DIR:=/root/.anytype}"
ANYTYPE_HOME="${ANYTYPE_HOME:=/root/.config/anytype}"
BOT_NAME="${ANYTYPE_BOT_NAME:=any-sync-bot}"
API_KEY_NAME="${ANYTYPE_API_KEY_NAME:=n8n-integration}"
NETWORK_CONFIG_FILE="${ANYTYPE_NETWORK_CONFIG:=/root/.config/anytype/network.yml}"
COORDINATOR_NETWORK_FILE="${1:=./storage/docker-generateconfig/nodesProcessed.yml}"

# Create required directories
mkdir -p "$ANYTYPE_CONFIG_DIR" "$ANYTYPE_HOME"

# Check if already initialized (config.json exists)
if [ -f "$ANYTYPE_CONFIG_DIR/config.json" ]; then
    echo "INFO: [anytype-cli-init] Already initialized, skipping account creation"
else
    echo "INFO: [anytype-cli-init] Creating bot account: $BOT_NAME"
    
    # Generate network YAML from coordinator network if it exists
    if [ -f "$COORDINATOR_NETWORK_FILE" ]; then
        echo "INFO: [anytype-cli-init] Generating network config from $COORDINATOR_NETWORK_FILE"
        cp "$COORDINATOR_NETWORK_FILE" "$NETWORK_CONFIG_FILE"
        
        # Create bot account with network config
        anytype --network-config "$NETWORK_CONFIG_FILE" auth create "$BOT_NAME" || {
            echo "ERROR: Failed to create bot account"
            return 1
        }
    else
        echo "WARN: [anytype-cli-init] Network config not found at $COORDINATOR_NETWORK_FILE"
        echo "INFO: [anytype-cli-init] Creating bot account without network config (will use default)"
        anytype auth create "$BOT_NAME" || {
            echo "ERROR: Failed to create bot account"
            return 1
        }
    fi
    
    echo "INFO: [anytype-cli-init] Bot account created successfully"
fi

# Generate API key if it doesn't exist
APIKEY_FILE="$ANYTYPE_CONFIG_DIR/.apikey-${API_KEY_NAME}"
if [ ! -f "$APIKEY_FILE" ]; then
    echo "INFO: [anytype-cli-init] Generating API key: $API_KEY_NAME"
    
    API_KEY=$(anytype auth apikey create "$API_KEY_NAME" 2>&1 | grep -oP '(?<=token:\s)\S+' || true)
    
    if [ -z "$API_KEY" ]; then
        echo "ERROR: Failed to generate API key"
        return 1
    fi
    
    # Store API key in file for reference
    echo "$API_KEY" > "$APIKEY_FILE"
    chmod 600 "$APIKEY_FILE"
    
    echo "INFO: [anytype-cli-init] API key created successfully"
    echo "INFO: [anytype-cli-init] API Key (save this for n8n): $API_KEY"
else
    API_KEY=$(cat "$APIKEY_FILE")
    echo "INFO: [anytype-cli-init] Using existing API key: $(echo $API_KEY | head -c 10)..."
fi

echo "INFO: [anytype-cli-init] Initialization complete"
echo "INFO: [anytype-cli-init] Use this in n8n:"
echo "  - Base URL: http://anytype-cli:31012"
echo "  - API Key: $API_KEY"

# Make initialization complete marker
touch "$ANYTYPE_CONFIG_DIR/.initialized"
