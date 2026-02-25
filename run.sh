#!/usr/bin/with-contenv bashio

# 1. PERCORSI BASE DALLA UI
BASE_DIR=$(bashio::config 'workspace_path')

bashio::log.info "Inizializzazione ambiente in $BASE_DIR"

# Definizione architettura a "Cartelle Fratello" (elimina il loop infinito)
SYSTEM_DIR="$BASE_DIR/system"
WORK_DIR="$BASE_DIR/workspace"

# Creazione della struttura fisica
mkdir -p "$SYSTEM_DIR"
mkdir -p "$WORK_DIR/skills"
mkdir -p "$WORK_DIR/media"

# 2. STRUTTURA DI SISTEMA
export HOME="$SYSTEM_DIR"
NANOBOT_DIR="$HOME/.nanobot"
mkdir -p "$NANOBOT_DIR"

# Il link punta alla cartella "fratello", prevenendo la ricorsione infinita
ln -sfn "$WORK_DIR" "$NANOBOT_DIR/workspace"

# -------------------------------------------------------------------
# SINCRONIZZAZIONE SKILL DI DEFAULT
# -------------------------------------------------------------------
bashio::log.info "Verifica e sincronizzazione delle skill di default..."
BUILTIN_SKILLS_DIR=$(/opt/nanobot/bin/python3 -c "import nanobot, os; print(os.path.join(os.path.dirname(nanobot.__file__), 'skills'))")

if [ -d "$BUILTIN_SKILLS_DIR" ]; then
    cp -rn "$BUILTIN_SKILLS_DIR"/. "$WORK_DIR/skills/" 2>/dev/null || true
    bashio::log.info "Skill di default sincronizzate con successo."
else
    bashio::log.warning "Cartella skill di default non trovata nel pacchetto originario."
fi

# 3. VIRTUAL ENVIRONMENT PERSISTENTE (Nascosto in system)
VENV_DIR="$SYSTEM_DIR/venv"
if [ ! -d "$VENV_DIR" ]; then
    bashio::log.info "Creazione Virtual Environment persistente in $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

export PATH="$VENV_DIR/bin:/opt/nanobot/bin:$PATH"
export VIRTUAL_ENV="$VENV_DIR"

# 4. GENERAZIONE CONFIGURAZIONE JSON
bashio::log.info "Generazione configurazione da interfaccia Home Assistant..."

PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
RESTRICT=$(bashio::config 'restrict_to_workspace')

export NVIDIA_NIM_API_KEY="$API_KEY"

ADDITIONAL_JSON=$(bashio::config 'additional_config_json')
if [ -z "$ADDITIONAL_JSON" ]; then
    ADDITIONAL_JSON="{}"
fi

if ! echo "$ADDITIONAL_JSON" | jq . >/dev/null 2>&1; then
    bashio::log.warning "Il JSON fornito in additional_config_json non e' valido. Verra' ignorato."
    ADDITIONAL_JSON="{}"
fi

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

if bashio::config.has_value 'api_base'; then
    API_BASE=$(bashio::config 'api_base')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg base "$API_BASE" --arg prov "$PROVIDER" \
        '.providers[$prov].apiBase = $base')
fi

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

echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add' > "$NANOBOT_DIR/config.json"

# 5. AVVIO
bashio::log.info "Avvio di Nanobot Gateway. Sandboxing: $RESTRICT"
cd "$WORK_DIR"
exec nanobot gateway
