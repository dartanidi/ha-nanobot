#!/usr/bin/with-contenv bashio

# ------------------------------------------------------------------------------
# 1. SETUP PERSISTENZA E LINKING
# --#!/usr/bin/with-contenv bashio

# ------------------------------------------------------------------------------
# 1. SETUP PERSISTENZA E LINKING
# ------------------------------------------------------------------------------
PERSISTENT_DIR="/data/nanobot_root"
INTERNAL_DIR="/root/.nanobot"

mkdir -p "$PERSISTENT_DIR"

if [ -d "$INTERNAL_DIR" ] && [ ! -L "$INTERNAL_DIR" ]; then
    rm -rf "$INTERNAL_DIR"
fi
ln -sfn "$PERSISTENT_DIR" "$INTERNAL_DIR"

# ------------------------------------------------------------------------------
# 2. GENERAZIONE CONFIGURAZIONE
# ------------------------------------------------------------------------------
PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')  # Ora è solo una stringa semplice
RESTRICT=$(bashio::config 'restrict_to_workspace')
WORKSPACE=$(bashio::config 'workspace_path')
ADDITIONAL_JSON=$(bashio::config 'additional_config_json')
API_BASE=$(bashio::config 'api_base')

# Creiamo la cartella workspace
mkdir -p "$WORKSPACE"

bashio::log.info "Generazione configurazione per provider: $PROVIDER con modello: $MODEL"

# Costruzione JSON Base
BASE_CONFIG=$(jq -n \
  --arg prov "$PROVIDER" \
  --arg key "$API_KEY" \
  --arg mod "$MODEL" \
  --arg restr "$RESTRICT" \
  --arg work "$WORKSPACE" \
  '{
    "providers": { ($prov): { "apiKey": $key } },
    "agents": { "defaults": { "model": $mod } },
    "tools": { 
      "restrictToWorkspace": ($restr == "true"),
      "workspace": $work
    }
  }')

# Iniezione API Base opzionale
if bashio::config.has_value 'api_base'; then
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg base "$API_BASE" --arg prov "$PROVIDER" \
        '.providers[$prov].apiBase = $base')
fi

# Merge con JSON addizionale
FINAL_CONFIG=$(echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add')

echo "$FINAL_CONFIG" > "$INTERNAL_DIR/config.json"

# ------------------------------------------------------------------------------
# 3. AVVIO
# ------------------------------------------------------------------------------
bashio::log.info "Avvio Nanobot Gateway..."
exec nanobot gateway
