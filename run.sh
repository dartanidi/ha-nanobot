#!/usr/bin/with-contenv bashio

# 1. DEFINIZIONE PERCORSI (Standard Home Assistant)
export HOME="/data"
NANOBOT_DIR="/data/.nanobot"
VENV_DIR="/data/venv"
WORK_DIR=$(bashio::config 'workspace_path')

bashio::log.info "Inizializzazione ambiente..."
bashio::log.info "System Data (Hidden): $NANOBOT_DIR"
bashio::log.info "User Workspace (Public): $WORK_DIR"

mkdir -p "$WORK_DIR/skills"
mkdir -p "$WORK_DIR/media"
mkdir -p "$NANOBOT_DIR"

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

PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
RESTRICT=$(bashio::config 'restrict_to_workspace')

# A. Costruzione del blocco base
BASE_CONFIG=$(jq -n \
  --arg prov "$PROVIDER" \
  --arg key "$API_KEY" \
  --argjson rest "$RESTRICT" \
  '{
    "providers": { ($prov): { "apiKey": $key } },
    "tools": { "restrictToWorkspace": $rest },
    "channels": {} 
  }')

if bashio::config.has_value 'api_base'; then
    API_BASE=$(bashio::config 'api_base')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg base "$API_BASE" --arg prov "$PROVIDER" \
        '.providers[$prov].apiBase = $base')
fi

# B. Integrazione Fallback Provider
if bashio::config.true 'fallback_enabled'; then
    if bashio::config.has_value 'fallback_provider' && bashio::config.has_value 'fallback_model'; then
        bashio::log.info "Integrazione Fallback LLM in corso..."
        F_PROV=$(bashio::config 'fallback_provider')
        F_KEY=$(bashio::config 'fallback_api_key')
        F_MOD=$(bashio::config 'fallback_model')

        # Inserisce la chiave API del fallback nel blocco "providers"
        BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg fprov "$F_PROV" --arg fkey "$F_KEY" \
            '.providers[$fprov] = { "apiKey": $fkey }')
            
        # Concatena il modello primario con il modello di fallback
        MODEL="$MODEL,$F_MOD"
    else
        bashio::log.warning "Fallback abilitato ma parametri mancanti. Lo ignoro."
    fi
fi

# Applica la stringa dei modelli (primario o primario+fallback)
BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg mod "$MODEL" \
    '.agents = { "defaults": { "model": $mod } }')

# C. Integrazione Telegram
if bashio::config.true 'telegram_enabled'; then
    TG_TOKEN=$(bashio::config 'telegram_token')
    TG_USER=$(bashio::config 'telegram_allow_user')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg token "$TG_TOKEN" --arg user "$TG_USER" \
        '.channels.telegram = { "enabled": true, "token": $token, "allowFrom": [$user] }')
fi

# D. Integrazione "Additional Config" (Ora come dict!)
ADDITIONAL_JSON=$(bashio::config 'additional_config')
if [ -z "$ADDITIONAL_JSON" ] || [ "$ADDITIONAL_JSON" = "null" ]; then
    ADDITIONAL_JSON="{}"
fi

# Unione finale e salvataggio
echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add' > "$NANOBOT_DIR/config.json"

# -------------------------------------------------------------------
# 5. AVVIO
# -------------------------------------------------------------------
bashio::log.info "Modelli in uso (LiteLLM Routing): $MODEL"
bashio::log.info "Avvio di Nanobot Gateway..."
cd "$WORK_DIR"
exec nanobot gateway
