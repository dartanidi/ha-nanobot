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

PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
RESTRICT=$(bashio::config 'restrict_to_workspace')

# Lettura del nuovo campo Dict per l'additional config
ADDITIONAL_JSON=$(bashio::config 'additional_config')
if [ -z "$ADDITIONAL_JSON" ] || [ "$ADDITIONAL_JSON" = "null" ]; then
    ADDITIONAL_JSON="{}"
fi

# Costruiamo la base dei provider
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

# Integrazione Fallback
if bashio::config.true 'fallback_enabled'; then
    if bashio::config.has_value 'fallback_provider' && bashio::config.has_value 'fallback_model'; then
        bashio::log.info "Integrazione Fallback LLM attiva."
        F_PROV=$(bashio::config 'fallback_provider')
        F_KEY=$(bashio::config 'fallback_api_key')
        F_MOD=$(bashio::config 'fallback_model')

        # Aggiunge le credenziali del provider di fallback
        BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg fprov "$F_PROV" --arg fkey "$F_KEY" \
            '.providers[$fprov] = { "apiKey": $fkey }')
            
        # Concatena i modelli in formato LiteLLM (es. openai/gpt,anthropic/claude)
        MODEL="$MODEL,$F_MOD"
    else
        bashio::log.warning "Fallback attivato ma mancano provider o modello. Lo ignoro."
    fi
fi

# Inserimento del blocco 'agents' con il modello (o i modelli concatenati)
BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg mod "$MODEL" \
    '.agents = { "defaults": { "model": $mod } }')

# Integrazione Telegram
if bashio::config.true 'telegram_enabled'; then
    TG_TOKEN=$(bashio::config 'telegram_token')
    TG_USER=$(bashio::config 'telegram_allow_user')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg token "$TG_TOKEN" --arg user "$TG_USER" \
        '.channels.telegram = { "enabled": true, "token": $token, "allowFrom": [$user] }')
fi

# Unione finale con l'additional config e salvataggio
echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add' > "$NANOBOT_DIR/config.json"

# -------------------------------------------------------------------
# 5. AVVIO
# -------------------------------------------------------------------
bashio::log.info "Modelli in uso (LiteLLM Routing): $MODEL"
bashio::log.info "Avvio di Nanobot Gateway..."
cd "$WORK_DIR"
exec nanobot gateway
