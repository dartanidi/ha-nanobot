#!/usr/bin/with-contenv bashio

# 1. RECUPERO CONFIGURAZIONE UTENTE
USER_WORKSPACE=$(bashio::config 'workspace_path')
USER_MEDIA=$(bashio::config 'media_path')
SYSTEM_DIR="$USER_WORKSPACE/system"

# 2. CREAZIONE STRUTTURA FISICA SU SHARE
mkdir -p "$SYSTEM_DIR"
mkdir -p "$USER_WORKSPACE/skills"
mkdir -p "$USER_MEDIA"

# 3. SETUP AMBIENTE INTERNO (PULIZIA TOTALE)
INTERNAL_ROOT="/root/.nanobot"
INTERNAL_WORKSPACE="$INTERNAL_ROOT/workspace"

# Rimuoviamo tutto per evitare vecchi link orfani o loop
rm -rf "$INTERNAL_ROOT"
mkdir -p "$INTERNAL_ROOT"
mkdir -p "$INTERNAL_WORKSPACE"

# 4. MAPPATURA SELETTIVA (ANTI-RICORSIONE)
# Linkiamo il database e la config nella cartella system
touch "$SYSTEM_DIR/nanobot.db"
ln -sfn "$SYSTEM_DIR/nanobot.db" "$INTERNAL_ROOT/nanobot.db"

# Linkiamo le skill nel workspace
ln -sfn "$USER_WORKSPACE/skills" "$INTERNAL_WORKSPACE/skills"

# --- FIX DEFINITIVO MEDIA ---
# Creiamo il link media SOLO dentro workspace. 
# Se Nanobot scarica qui, l'agente vedrà i file come /root/.nanobot/workspace/media/...
ln -sfn "$USER_MEDIA" "$INTERNAL_WORKSPACE/media"
TG_DOWNLOAD_PATH="$INTERNAL_WORKSPACE/media"

bashio::log.info "Nanobot configurato. Workspace: $INTERNAL_WORKSPACE | Download Telegram: $TG_DOWNLOAD_PATH"

# 5. GENERAZIONE CONFIGURAZIONE JSON
PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
RESTRICT=$(bashio::config 'restrict_to_workspace')
ADDITIONAL_JSON=$(bashio::config 'additional_config_json')

# Costruzione JSON base
BASE_CONFIG=$(jq -n \
  --arg prov "$PROVIDER" \
  --arg key "$API_KEY" \
  --arg mod "$MODEL" \
  --arg restr "$RESTRICT" \
  --arg work "$INTERNAL_WORKSPACE" \
  '{
    "providers": { ($prov): { "apiKey": $key } },
    "agents": { "defaults": { "model": $mod } },
    "tools": { 
      "restrictToWorkspace": ($restr == "true"),
      "workspace": $work
    },
    "channels": {} 
  }')

# Aggiunta canale Telegram
if bashio::config.true 'telegram_enabled'; then
    TG_TOKEN=$(bashio::config 'telegram_token')
    TG_USER=$(bashio::config 'telegram_allow_user')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg token "$TG_TOKEN" --arg user "$TG_USER" --arg media "$TG_DOWNLOAD_PATH" \
        '.channels.telegram = {
            "enabled": true,
            "token": $token,
            "allowFrom": [$user],
            "downloadPath": $media
        }')
fi

# Merge con configurazioni extra e salvataggio
FINAL_CONFIG=$(echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add')
echo "$FINAL_CONFIG" > "$SYSTEM_DIR/config.json"
ln -sfn "$SYSTEM_DIR/config.json" "$INTERNAL_ROOT/config.json"

# 6. AVVIO
bashio::log.info "Lancio Nanobot Gateway..."
exec nanobot gateway
