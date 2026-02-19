#!/usr/bin/with-contenv bashio

# 1. PERCORSI FISICI
USER_WORKSPACE=$(bashio::config 'workspace_path')
USER_MEDIA=$(bashio::config 'media_path')
SYSTEM_DIR="$USER_WORKSPACE/system"

mkdir -p "$SYSTEM_DIR"
mkdir -p "$USER_WORKSPACE/skills"
mkdir -p "$USER_MEDIA"

# 2. SETUP E PULIZIA
INTERNAL_ROOT="/root/.nanobot"
rm -rf "$INTERNAL_ROOT"
mkdir -p "$INTERNAL_ROOT"

# 3. LINK SIMBOLICI LINEARI (Nessun inganno, solo ponti diretti)
touch "$SYSTEM_DIR/nanobot.db"
ln -sfn "$SYSTEM_DIR/nanobot.db" "$INTERNAL_ROOT/nanobot.db"

# Il workspace dell'agente punta allo share
ln -sfn "$USER_WORKSPACE" "$INTERNAL_ROOT/workspace"

# La cartella media di Telegram punta allo share media
ln -sfn "$USER_MEDIA" "$INTERNAL_ROOT/media"

bashio::log.info "Ponti creati. Restrizione Workspace: DISABILITATA."

# 4. CONFIGURAZIONE JSON (Bypass Sicurezza)
PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
ADDITIONAL_JSON=$(bashio::config 'additional_config_json')

# IMPORTANTE: "restrictToWorkspace": false sblocca la lettura dei media
BASE_CONFIG=$(jq -n \
  --arg prov "$PROVIDER" \
  --arg key "$API_KEY" \
  --arg mod "$MODEL" \
  '{
    "providers": { ($prov): { "apiKey": $key } },
    "agents": { "defaults": { "model": $mod } },
    "tools": { 
      "restrictToWorkspace": false
    },
    "channels": {} 
  }')

if bashio::config.true 'telegram_enabled'; then
    TG_TOKEN=$(bashio::config 'telegram_token')
    TG_USER=$(bashio::config 'telegram_allow_user')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg token "$TG_TOKEN" --arg user "$TG_USER" \
        '.channels.telegram = {
            "enabled": true,
            "token": $token,
            "allowFrom": [$user]
        }')
fi

FINAL_CONFIG=$(echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add')
echo "$FINAL_CONFIG" > "$INTERNAL_ROOT/config.json"

# 5. AVVIO
exec nanobot gateway
