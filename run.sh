#!/usr/bin/with-contenv bashio

# 1. DEFINIZIONE PERCORSI (Standard Home Assistant)
export HOME="/data"
NANOBOT_DIR="/data/.nanobot"
VENV_DIR="/data/venv"
WORK_DIR=$(bashio::config 'workspace_path')

bashio::log.info "Inizializzazione ambiente Nanobot v0.5.0..."
bashio::log.info "System Data (Hidden): $NANOBOT_DIR"
bashio::log.info "User Workspace (Public): $WORK_DIR"

mkdir -p "$WORK_DIR/skills"
mkdir -p "$WORK_DIR/media"
mkdir -p "$NANOBOT_DIR"

# Symlink sicuro: collega la cartella pubblica al sistema interno senza loop
ln -sfn "$WORK_DIR" "$NANOBOT_DIR/workspace"

# -------------------------------------------------------------------
# 2. VIRTUAL ENVIRONMENT
# -------------------------------------------------------------------
if [ ! -d "$VENV_DIR" ]; then
    bashio::log.info "Creazione Virtual Environment isolato..."
    python3 -m venv "$VENV_DIR"
fi
export PATH="$VENV_DIR/bin:/opt/nanobot/bin:$PATH"
export VIRTUAL_ENV="$VENV_DIR"

# -------------------------------------------------------------------
# 3. SINCRONIZZAZIONE SKILL DI DEFAULT
# -------------------------------------------------------------------
bashio::log.info "Sincronizzazione skill..."
BUILTIN_SKILLS_DIR=$(python3 -c "import nanobot, os; print(os.path.join(os.path.dirname(nanobot.__file__), 'skills'))" 2>/dev/null || echo "")

if [ -n "$BUILTIN_SKILLS_DIR" ] && [ -d "$BUILTIN_SKILLS_DIR" ]; then
    cp -rn "$BUILTIN_SKILLS_DIR"/. "$WORK_DIR/skills/" 2>/dev/null || true
fi

# -------------------------------------------------------------------
# 4. GENERAZIONE CONFIGURAZIONE BASE
# -------------------------------------------------------------------
bashio::log.info "Costruzione configurazione provider..."

PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
RESTRICT=$(bashio::config 'restrict_to_workspace')

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

# -------------------------------------------------------------------
# 5. GESTIONE FALLBACK LLM
# -------------------------------------------------------------------
if bashio::config.true 'fallback_enabled'; then
    if bashio::config.has_value 'fallback_provider' && bashio::config.has_value 'fallback_model'; then
        bashio::log.info "Fallback LLM attivato. Integrazione credenziali secondarie..."
        F_PROV=$(bashio::config 'fallback_provider')
        F_KEY=$(bashio::config 'fallback_api_key')
        F_MOD=$(bashio::config 'fallback_model')

        BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg fprov "$F_PROV" --arg fkey "$F_KEY" \
            '.providers[$fprov] = { "apiKey": $fkey }')
            
        MODEL="$MODEL,$F_MOD"
    else
        bashio::log.warning "Fallback abilitato ma parametri incompleti. Ignorato."
    fi
fi

# Inserimento modelli
BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg mod "$MODEL" \
    '.agents = { "defaults": { "model": $mod } }')

# -------------------------------------------------------------------
# 6. GESTIONE TELEGRAM
# -------------------------------------------------------------------
if bashio::config.true 'telegram_enabled'; then
    TG_TOKEN=$(bashio::config 'telegram_token')
    TG_USER=$(bashio::config 'telegram_allow_user')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg token "$TG_TOKEN" --arg user "$TG_USER" \
        '.channels.telegram = { "enabled": true, "token": $token, "allowFrom": [$user] }')
fi

# -------------------------------------------------------------------
# 7. GESTIONE ADVANCED CONFIG (File Esterno)
# -------------------------------------------------------------------
ADVANCED_FILE="$WORK_DIR/advanced_config.json"

if [ -f "$ADVANCED_FILE" ]; then
    bashio::log.info "Rilevato advanced_config.json, validazione in corso..."
    if jq . "$ADVANCED_FILE" >/dev/null 2>&1; then
        bashio::log.info "File JSON valido. Fusione configurazioni..."
        BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --slurpfile adv "$ADVANCED_FILE" '. * $adv[0]')
    else
        bashio::log.error "ERRORE DI SINTASSI in advanced_config.json! Verrà ignorato per prevenire crash."
    fi
else
    bashio::log.info "Creazione template advanced_config.json nel workspace..."
    echo "{}" > "$ADVANCED_FILE"
fi

# Salvataggio configurazione finale
echo "$BASE_CONFIG" > "$NANOBOT_DIR/config.json"

# -------------------------------------------------------------------
# 8. AVVIO
# -------------------------------------------------------------------
bashio::log.info "Modelli in uso (Primario -> Fallback): $MODEL"
bashio::log.info "Avvio di Nanobot Gateway..."
cd "$WORK_DIR"
exec nanobot gateway
