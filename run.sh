#!/usr/bin/with-contenv bashio

# 1. PERCORSI FISICI E VARIABILI DALLA UI
USER_WORKSPACE=$(bashio::config 'workspace_path')
USER_MEDIA=$(bashio::config 'media_path')
SYSTEM_DIR="$USER_WORKSPACE/system"

# Creazione della struttura fisica nello share di Home Assistant
mkdir -p "$SYSTEM_DIR"
mkdir -p "$USER_WORKSPACE/skills"
mkdir -p "$USER_MEDIA"

# 2. SETUP E PULIZIA DELL'AMBIENTE INTERNO
INTERNAL_ROOT="/root/.nanobot"
rm -rf "$INTERNAL_ROOT"
mkdir -p "$INTERNAL_ROOT"

# 3. CREAZIONE PONTI (LINK SIMBOLICI)
# Linkiamo il database
touch "$SYSTEM_DIR/nanobot.db"
ln -sfn "$SYSTEM_DIR/nanobot.db" "$INTERNAL_ROOT/nanobot.db"

# Il workspace dell'agente punta interamente allo share
ln -sfn "$USER_WORKSPACE" "$INTERNAL_ROOT/workspace"

# La cartella media dove Telegram salva i file punta allo share
ln -sfn "$USER_MEDIA" "$INTERNAL_ROOT/media"

bashio::log.info "Struttura creata. Restrizione Workspace disabilitata con successo."

# 4. GENERAZIONE CONFIGURAZIONE JSON
PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
ADDITIONAL_JSON=$(bashio::config 'additional_config_json')

# Generazione JSON base con restrictToWorkspace forzato a false
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

# Aggiunta API Base (opzionale)
if bashio::config.has_value 'api_base'; then
    API_BASE=$(bashio::config 'api_base')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg base "$API_BASE" --arg prov "$PROVIDER" \
        '.providers[$prov].apiBase = $base')
fi

# Aggiunta configurazione Telegram
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

# Unione con gli strumenti aggiuntivi (additional_config_json)
FINAL_CONFIG=$(echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add')

# Salvataggio fisico della configurazione
echo "$FINAL_CONFIG" > "$SYSTEM_DIR/config.json"
ln -sfn "$SYSTEM_DIR/config.json" "$INTERNAL_ROOT/config.json"

# 5. AVVIO
bashio::log.info "Lancio Nanobot Gateway..."
exec nanobot gateway
