#!/usr/bin/with-contenv bashio

# 1. Recupero percorsi dallo share (definiti nell'interfaccia dell'addon)
USER_WORKSPACE=$(bashio::config 'workspace_path')
USER_MEDIA=$(bashio::config 'media_path')

# 2. Definiamo la cartella di sistema FISICA nello share
# Qui Nanobot salverà il database e la configurazione
SYSTEM_DIR="$USER_WORKSPACE/system"
mkdir -p "$SYSTEM_DIR"
mkdir -p "$USER_WORKSPACE/skills"
mkdir -p "$USER_MEDIA"

# 3. Pulizia e Setup Percorsi Interni al Container
INTERNAL_ROOT="/root/.nanobot"
rm -rf "$INTERNAL_ROOT"
mkdir -p "$INTERNAL_ROOT"

# --- MAPPATURA SELETTIVA (Anti-Loop) ---
# Linkiamo il database fisicamente nello share
touch "$SYSTEM_DIR/nanobot.db"
ln -sfn "$SYSTEM_DIR/nanobot.db" "$INTERNAL_ROOT/nanobot.db"

# 4. Setup del Workspace per l'Agente
# Creiamo una cartella REALE che conterrà solo i link agli elementi dello share
INTERNAL_WORKSPACE="$INTERNAL_ROOT/workspace"
mkdir -p "$INTERNAL_WORKSPACE"

# Linkiamo selettivamente le cartelle dello share DENTRO il workspace interno
# In questo modo Nanobot vede i file ma non può "rientrare" in /system
ln -sfn "$USER_WORKSPACE/skills" "$INTERNAL_WORKSPACE/skills"

# --- IL FIX PER I DOCUMENTI TELEGRAM ---
# La cartella media DEVE essere dentro il workspace per essere letta dall'AI
ln -sfn "$USER_MEDIA" "$INTERNAL_WORKSPACE/media"
# Definiamo il percorso di download per il JSON di Telegram
INTERNAL_MEDIA_PATH="$INTERNAL_WORKSPACE/media"

bashio::log.info "Sistema avviato. Workspace: $INTERNAL_WORKSPACE | Media: $INTERNAL_MEDIA_PATH"

# ------------------------------------------------------------------------------
# 5. GENERAZIONE CONFIGURAZIONE JSON
# ------------------------------------------------------------------------------
PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
RESTRICT=$(bashio::config 'restrict_to_workspace')
ADDITIONAL_JSON=$(bashio::config 'additional_config_json')

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

# Telegram (Configurato per scaricare nel percorso visibile all'agente)
if bashio::config.true 'telegram_enabled'; then
    TG_TOKEN=$(bashio::config 'telegram_token')
    TG_USER=$(bashio::config 'telegram_allow_user')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg token "$TG_TOKEN" --arg user "$TG_USER" --arg media "$INTERNAL_MEDIA_PATH" \
        '.channels.telegram = {
            "enabled": true,
            "token": $token,
            "allowFrom": [$user],
            "downloadPath": $media
        }')
fi

# Salviamo il config.json fisicamente nello share, ma linkato internamente
FINAL_CONFIG=$(echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add')
echo "$FINAL_CONFIG" > "$SYSTEM_DIR/config.json"
ln -sfn "$SYSTEM_DIR/config.json" "$INTERNAL_ROOT/config.json"

# ------------------------------------------------------------------------------
# 6. AVVIO
# ------------------------------------------------------------------------------
bashio::log.info "Avvio Nanobot Gateway..."
exec nanobot gateway
