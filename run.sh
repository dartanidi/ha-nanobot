#!/usr/bin/with-contenv bashio

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
# 2. SELEZIONE MODELLO (Dropdown vs Custom)
# ------------------------------------------------------------------------------
DROPDOWN_MODEL=$(bashio::config 'model')
CUSTOM_MODEL=$(bashio::config 'custom_model')

# Se l'utente ha scritto un modello personalizzato, vince su quello del dropdown
if bashio::config.has_value 'custom_model'; then
    FINAL_MODEL="$CUSTOM_MODEL"
    bashio::log.info "Usando modello personalizzato: $FINAL_MODEL"
else
    FINAL_MODEL="$DROPDOWN_MODEL"
    bashio::log.info "Usando modello selezionato: $FINAL_MODEL"
fi

# ------------------------------------------------------------------------------
# 3. GENERAZIONE CONFIGURAZIONE
# ------------------------------------------------------------------------------
PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
RESTRICT=$(bashio::config 'restrict_to_workspace')
WORKSPACE=$(bashio::config 'workspace_path')
ADDITIONAL_JSON=$(bashio::config 'additional_config_json')
API_BASE=$(bashio::config 'api_base')

mkdir -p "$WORKSPACE"

bashio::log.info "Generazione configurazione..."

BASE_CONFIG=$(jq -n \
  --arg prov "$PROVIDER" \
  --arg key "$API_KEY" \
  --arg mod "$FINAL_MODEL" \
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

if bashio::config.has_value 'api_base'; then
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg base "$API_BASE" --arg prov "$PROVIDER" \
        '.providers[$prov].apiBase = $base')
fi

FINAL_CONFIG=$(echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add')

echo "$FINAL_CONFIG" > "$INTERNAL_DIR/config.json"

# ------------------------------------------------------------------------------
# 4. AVVIO
# ------------------------------------------------------------------------------
bashio::log.info "Avvio Nanobot Gateway..."
exec nanobot gateway
