#!/usr/bin/with-contenv bashio

# 1. PERCORSI BASE DALLA UI
BASE_DIR=$(bashio::config 'workspace_path')
bashio::log.info "Inizializzazione ambiente in $BASE_DIR"

SYSTEM_DIR="$BASE_DIR/system"
WORK_DIR="$BASE_DIR/workspace"

mkdir -p "$SYSTEM_DIR"
mkdir -p "$WORK_DIR/skills"
mkdir -p "$WORK_DIR/media"

export HOME="$SYSTEM_DIR"
NANOBOT_DIR="$HOME/.nanobot"
mkdir -p "$NANOBOT_DIR"

ln -sfn "$WORK_DIR" "$NANOBOT_DIR/workspace"

# -------------------------------------------------------------------
# INIEZIONE PATCH: LITELLM NATIVE FALLBACK ROUTING
# Intercetta il flusso di Nanobot e abilita i fallback in tempo reale
# -------------------------------------------------------------------
bashio::log.info "Applicazione patch per Auto-Routing (LiteLLM)..."
INIT_FILE=$(ls /opt/nanobot/lib/python*/site-packages/nanobot/__init__.py | head -n 1)

if ! grep -q "_acompletion_with_fallback" "$INIT_FILE"; then
    cat << 'EOF' >> "$INIT_FILE"

# --- LITELLM FALLBACK MONKEY PATCH ---
import litellm
_orig_acompletion = litellm.acompletion
async def _acompletion_with_fallback(*args, **kwargs):
    model_str = kwargs.get("model", "")
    if isinstance(model_str, str) and "," in model_str:
        models = [m.strip() for m in model_str.split(",")]
        kwargs["model"] = models[0]
        kwargs["fallbacks"] = [{"model": m} for m in models[1:]]
    return await _orig_acompletion(*args, **kwargs)
litellm.acompletion = _acompletion_with_fallback
EOF
fi
# -------------------------------------------------------------------

bashio::log.info "Verifica e sincronizzazione delle skill di default..."
BUILTIN_SKILLS_DIR=$(/opt/nanobot/bin/python3 -c "import nanobot, os; print(os.path.join(os.path.dirname(nanobot.__file__), 'skills'))")
if [ -d "$BUILTIN_SKILLS_DIR" ]; then
    cp -rn "$BUILTIN_SKILLS_DIR"/. "$WORK_DIR/skills/" 2>/dev/null || true
else
    bashio::log.warning "Cartella skill di default non trovata."
fi

VENV_DIR="$SYSTEM_DIR/venv"
if [ ! -d "$VENV_DIR" ]; then
    bashio::log.info "Creazione Virtual Environment persistente..."
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

ADDITIONAL_JSON=$(bashio::config 'additional_config_json')
if [ -z "$ADDITIONAL_JSON" ]; then ADDITIONAL_JSON="{}"; fi
if ! echo "$ADDITIONAL_JSON" | jq . >/dev/null 2>&1; then
    bashio::log.warning "JSON aggiuntivo malformato. Verrà ignorato."
    ADDITIONAL_JSON="{}"
fi

# Base Provider JSON
# Aggiungiamo sempre il blocco "custom" per bypassare i controlli rigidi di Nanobot
# sulle API non native (come NVIDIA). LiteLLM userà le chiavi esportate in "export".
BASE_CONFIG=$(jq -n \
  --arg prov "$PROVIDER" \
  --arg key "$API_KEY" \
  --argjson rest "$RESTRICT" \
  '{
    "providers": { 
        ($prov): { "apiKey": $key },
        "custom": { "apiKey": "litellm-env-handled-key" }
    },
    "tools": { "restrictToWorkspace": $rest },
    "channels": {} 
  }')

if bashio::config.has_value 'api_base'; then
    API_BASE=$(bashio::config 'api_base')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg base "$API_BASE" --arg prov "$PROVIDER" \
        '.providers[$prov].apiBase = $base')
fi

# GESTIONE FALLBACK PROVIDER
if bashio::config.true 'fallback_enabled'; then
    if bashio::config.has_value 'fallback_provider' && bashio::config.has_value 'fallback_model'; then
        F_PROV=$(bashio::config 'fallback_provider')
        F_KEY=$(bashio::config 'fallback_api_key')
        F_MOD=$(bashio::config 'fallback_model')
        
        bashio::log.info "Routing di emergenza abilitato -> Fallback su: $F_PROV/$F_MOD"
        
        # Aggiungiamo il provider secondario alla configurazione
        BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg fprov "$F_PROV" --arg fkey "$F_KEY" \
            '.providers[$fprov] = { "apiKey": $fkey }')
            
        # Concateniamo i modelli (es. "openrouter/deepseek-r1,groq/llama3")
        # La nostra patch Python in alto catturerà la virgola per dividerli in Main/Fallback!
        MODEL="$MODEL,$F_PROV/$F_MOD"
    else
        bashio::log.warning "Fallback attivato ma mancano provider o modello. Verrà ignorato."
    fi
fi

# Scrittura modello primario/unito
BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg mod "$MODEL" \
    '.agents = { "defaults": { "model": $mod } }')

if bashio::config.true 'telegram_enabled'; then
    TG_TOKEN=$(bashio::config 'telegram_token')
    TG_USER=$(bashio::config 'telegram_allow_user')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg token "$TG_TOKEN" --arg user "$TG_USER" \
        '.channels.telegram = { "enabled": true, "token": $token, "allowFrom": [$user] }')
fi

echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add' > "$NANOBOT_DIR/config.json"

bashio::log.info "Avvio di Nanobot Gateway. Sandboxing: $RESTRICT"
cd "$WORK_DIR"
exec nanobot gateway
