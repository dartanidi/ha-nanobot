#!/usr/bin/with-contenv bashio

# 1. DEFINIZIONE PERCORSI (Standard Home Assistant)
# /data: Nascosto e persistente (DB, Config, Venv)
export HOME="/data"
NANOBOT_DIR="/data/.nanobot"
VENV_DIR="/data/venv"

# /share: Visibile all'utente (Impostato dalla UI, es. /share/nanobot)
WORK_DIR=$(bashio::config 'workspace_path')

bashio::log.info "Inizializzazione ambiente..."
bashio::log.info "System Data (Hidden): $NANOBOT_DIR"
bashio::log.info "User Workspace (Public): $WORK_DIR"

# Creazione struttura pubblica (visibile a te)
mkdir -p "$WORK_DIR/skills"
mkdir -p "$WORK_DIR/media"

# Creazione cartella di sistema (invisibile)
mkdir -p "$NANOBOT_DIR"

# IL PONTE SICURO: Nessun loop ricorsivo possibile perché sono su due mount separati
ln -sfn "$WORK_DIR" "$NANOBOT_DIR/workspace"

# -------------------------------------------------------------------
# 2. VIRTUAL ENVIRONMENT (Isolato in /data)
# -------------------------------------------------------------------
if [ ! -d "$VENV_DIR" ]; then
    bashio::log.info "Creazione Virtual Environment in $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi
export PATH="$VENV_DIR/bin:/opt/nanobot/bin:$PATH"
export VIRTUAL_ENV="$VENV_DIR"

# -------------------------------------------------------------------
# 3. SINCRONIZZAZIONE SKILL DI DEFAULT
# -------------------------------------------------------------------
bashio::log.info "Sincronizzazione skill nel workspace utente..."
BUILTIN_SKILLS_DIR=$(/opt/nanobot/bin/python3 -c "import nanobot, os; print(os.path.join(os.path.dirname(nanobot.__file__), 'skills'))")

if [ -d "$BUILTIN_SKILLS_DIR" ]; then
    cp -rn "$BUILTIN_SKILLS_DIR"/. "$WORK_DIR/skills/" 2>/dev/null || true
fi

# -------------------------------------------------------------------
# 4. GENERAZIONE CONFIGURAZIONE JSON
# -------------------------------------------------------------------
bashio::log.info "Generazione configurazione da UI..."

ROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
RESTRICT=$(bashio::config 'restrict_to_workspace')

ADDITIONAL_JSON=$(bashio::config 'additional_config_json')
if [ -z "$ADDITIONAL_JSON" ]; then ADDITIONAL_JSON="{}"; fi
if ! echo "$ADDITIONAL_JSON" | jq . >/dev/null 2>&1; then
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
    "tools": { "restrictToWorkspace": $rest },
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
        '.channels.telegram = { "enabled": true, "token": $token, "allowFrom": [$user] }')
fi

# Salviamo il file config.json al sicuro in /data
echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add' > "$NANOBOT_DIR/config.json"

# -------------------------------------------------------------------
# 5. AVVIO
# -------------------------------------------------------------------
bashio::log.info "Avvio di Nanobot Gateway..."
cd "$WORK_DIR"
exec nanobot gateway
