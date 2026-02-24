#!/usr/bin/with-contenv bashio

# 1. PERCORSI FISICI E VARIABILI DALLA UI
USER_WORKSPACE=$(bashio::config 'workspace_path')
USER_MEDIA=$(bashio::config 'media_path')

bashio::log.info "Inizializzazione Workspace completo in $USER_WORKSPACE"

# Creazione della struttura fisica utente
mkdir -p "$USER_WORKSPACE/skills"
mkdir -p "$USER_MEDIA"

# 2. STRUTTURA DI SISTEMA (Tutto dentro /share)
# Creiamo una cartella "system" all'interno del workspace per ospitare i file di servizio
export HOME="$USER_WORKSPACE/system"
NANOBOT_DIR="$HOME/.nanobot"
mkdir -p "$NANOBOT_DIR"

# Risoluzione dell'errore di restrizione di sicurezza:
# Diciamo a Nanobot che il suo workspace interno punta alla radice del tuo workspace condiviso
ln -sfn "$USER_WORKSPACE" "$NANOBOT_DIR/workspace"

# 3. VIRTUAL ENVIRONMENT PERSISTENTE
VENV_DIR="$USER_WORKSPACE/venv"
if [ ! -d "$VENV_DIR" ]; then
    bashio::log.info "Creazione Virtual Environment persistente in $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

# ATTIVAZIONE VENV: Prioritizziamo i binari del venv persistente
export PATH="$VENV_DIR/bin:/opt/nanobot/bin:$PATH"
export VIRTUAL_ENV="$VENV_DIR"

# 4. GENERAZIONE CONFIGURAZIONE JSON
bashio::log.info "Generazione configurazione da interfaccia Home Assistant..."

PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
RESTRICT=$(bashio::config 'restrict_to_workspace')

ADDITIONAL_JSON=$(bashio::config 'additional_config_json')
if [ -z "$ADDITIONAL_JSON" ]; then
    ADDITIONAL_JSON="{}"
fi

# Validazione base del JSON per evitare crash
if ! echo "$ADDITIONAL_JSON" | jq . >/dev/null 2>&1; then
    bashio::log.warning "Il JSON fornito in additional_config_json non e' valido. Verra' ignorato."
    ADDITIONAL_JSON="{}"
fi

# Generazione JSON base
BASE_CONFIG=$(jq -n \
  --arg prov "$PROVIDER" \
  --arg key "$API_KEY" \
  --arg mod "$MODEL" \
  --argjson rest "$RESTRICT" \
  '{
    "providers": { ($prov): { "apiKey": $key } },
    "agents": { "defaults": { "model": $mod } },
    "tools": { 
      "restrictToWorkspace": $rest
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

# Unione con gli strumenti aggiuntivi e scrittura fisica nel workspace
echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add' > "$NANOBOT_DIR/config.json"

# 5. AVVIO
bashio::log.info "Avvio di Nanobot Gateway. Sandboxing: $RESTRICT"
cd "$USER_WORKSPACE"
exec nanobot gateway
