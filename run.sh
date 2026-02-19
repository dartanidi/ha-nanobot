#!/usr/bin/with-contenv bashio

# 1. PERCORSI REALI (Nativi del container HA)
USER_WORKSPACE=$(bashio::config 'workspace_path') # Es. /share/nanobot_workspace
USER_MEDIA=$(bashio::config 'media_path')         # Es. /share/nanobot_workspace/media
SYSTEM_DIR="$USER_WORKSPACE/system"

# 2. CREAZIONE STRUTTURA FISICA
mkdir -p "$SYSTEM_DIR"
mkdir -p "$USER_WORKSPACE/skills"
mkdir -p "$USER_MEDIA"

# 3. SETUP CORE NANOBOT (Solo DB e Config)
INTERNAL_ROOT="/root/.nanobot"
rm -rf "$INTERNAL_ROOT"
mkdir -p "$INTERNAL_ROOT"

# Il DB rimane in system ma viene linkato alla root dove Nanobot lo cerca
touch "$SYSTEM_DIR/nanobot.db"
ln -sfn "$SYSTEM_DIR/nanobot.db" "$INTERNAL_ROOT/nanobot.db"

# 4. GENERAZIONE CONFIGURAZIONE JSON
bashio::log.info "Configurazione diretta su path assoluti: $USER_WORKSPACE"

PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
RESTRICT=$(bashio::config 'restrict_to_workspace')
ADDITIONAL_JSON=$(bashio::config 'additional_config_json')

# Diciamo a Nanobot che il suo Workspace UFFICIALE è direttamente lo Share!
BASE_CONFIG=$(jq -n \
  --arg prov "$PROVIDER" \
  --arg key "$API_KEY" \
  --arg mod "$MODEL" \
  --arg restr "$RESTRICT" \
  --arg work "$USER_WORKSPACE" \
  '{
    "providers": { ($prov): { "apiKey": $key } },
    "agents": { "defaults": { "model": $mod } },
    "tools": { 
      "restrictToWorkspace": ($restr == "true"),
      "workspace": $work
    },
    "channels": {} 
  }')

# Diciamo a Telegram di scaricare DIRETTAMENTE nello share
if bashio::config.true 'telegram_enabled'; then
    TG_TOKEN=$(bashio::config 'telegram_token')
    TG_USER=$(bashio::config 'telegram_allow_user')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg token "$TG_TOKEN" --arg user "$TG_USER" --arg media "$USER_MEDIA" \
        '.channels.telegram = {
            "enabled": true,
            "token": $token,
            "allowFrom": [$user],
            "downloadPath": $media
        }')
fi

# Salvataggio Config
FINAL_CONFIG=$(echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add')
echo "$FINAL_CONFIG" > "$SYSTEM_DIR/config.json"
ln -sfn "$SYSTEM_DIR/config.json" "$INTERNAL_ROOT/config.json"

# 5. AVVIO
exec nanobot gateway
