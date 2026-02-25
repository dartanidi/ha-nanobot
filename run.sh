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
# Trasforma LiteLLM in un client puro per bypassare i bug di routing
# -------------------------------------------------------------------
bashio::log.info "Applicazione patch 'Dumb Pipe' per Auto-Routing (LiteLLM)..."
INIT_FILE=$(ls /opt/nanobot/lib/python*/site-packages/nanobot/__init__.py | head -n 1)

if ! grep -q "_acompletion_with_fallback" "$INIT_FILE"; then
    cat << 'EOF' >> "$INIT_FILE"

# --- LITELLM FALLBACK MONKEY PATCH ---
import litellm
_orig_acompletion = litellm.acompletion
async def _acompletion_with_fallback(*args, **kwargs):
    model_str = kwargs.get("model", "")
    
    # 1. Pulisce i prefissi inutili inseriti da Nanobot
    for p in ["openai/", "custom/", "openrouter/"]:
        if model_str.startswith(p):
            model_str = model_str[len(p):]
            break
            
    models = [m.strip() for m in model_str.split(",") if m.strip()]
    
    if models:
        primary = models[0]
        
        # LA MAGIA È QUI: Se c'è un api_base (es. NVIDIA), forziamo "custom_openai/".
        # Questo disattiva tutti i riconoscimenti interni buggati (es. ZaiException, 
        # MinimaxException) e trasforma LiteLLM in un tubo pulitissimo.
        if kwargs.get("api_base"):
            kwargs["model"] = "custom_openai/" + primary
        else:
            kwargs["model"] = primary
            
        # 2. Configura il fallback isolandolo
        if len(models) > 1:
            fallbacks = []
            for m in models[1:]:
                fallbacks.append({
                    "model": m,
                    "api_base": None,
                    "custom_llm_provider": None
                })
            kwargs["fallbacks"] = fallbacks
            
    return await _orig_acompletion(*args, **kwargs)

litellm.acompletion = _acompletion_with_fallback
EOF
fi
# -------------------------------------------------------------------

bashio::log.info "Verifica e sincronizzazione delle skill di default..."
BUILTIN_SKILLS_DIR=$(/opt/nanobot/bin/python3 -c "import nanobot, os; print(os.path.join(os.path.dirname(nanobot.__file__), 'skills'))")
if [ -d "$BUILTIN_SKILLS_DIR" ]; then
    cp -rn "$BUILTIN_SKILLS_DIR"/. "$WORK_DIR/skills/" 2>/dev/null || true
fi

# 2. VIRTUAL ENVIRONMENT PERSISTENTE
VENV_DIR="$SYSTEM_DIR/venv"
if [ ! -d "$VENV_DIR" ]; then
    bashio::log.info "Creazione Virtual Environment in $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi
export PATH="$VENV_DIR/bin:/opt/nanobot/bin:$PATH"
export VIRTUAL_ENV="$VENV_DIR"

# 3. LETTURA CONFIGURAZIONE DA HOME ASSISTANT
bashio::log.info "Generazione configurazione e variabili d'ambiente..."

PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
RESTRICT=$(bashio::config 'restrict_to_workspace')

# Esportiamo la chiave globale
export $(echo "$PROVIDER" | tr 'a-z-' 'A-Z_')_API_KEY="$API_KEY"

ADDITIONAL_JSON=$(bashio::config 'additional_config_json')
if [ -z "$ADDITIONAL_JSON" ]; then ADDITIONAL_JSON="{}"; fi

# Base Provider JSON
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

# 4. GESTIONE FALLBACK PROVIDER
if bashio::config.true 'fallback_enabled'; then
    if bashio::config.has_value 'fallback_provider' && bashio::config.has_value 'fallback_model'; then
        F_PROV=$(bashio::config 'fallback_provider')
        F_KEY=$(bashio::config 'fallback_api_key')
        F_MOD=$(bashio::config 'fallback_model')
        
        # Esporta la chiave del fallback
        export $(echo "$F_PROV" | tr 'a-z-' 'A-Z_')_API_KEY="$F_KEY"

        BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg fprov "$F_PROV" --arg fkey "$F_KEY" \
            '.providers[$fprov] = { "apiKey": $fkey }')
            
        MODEL="$MODEL,$F_PROV/$F_MOD"
    fi
fi

# Scrittura modello unito
BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg mod "$MODEL" \
    '.agents = { "defaults": { "model": $mod } }')

# 5. GESTIONE TELEGRAM
if bashio::config.true 'telegram_enabled'; then
    TG_TOKEN=$(bashio::config 'telegram_token')
    TG_USER=$(bashio::config 'telegram_allow_user')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg token "$TG_TOKEN" --arg user "$TG_USER" \
        '.channels.telegram = { "enabled": true, "token": $token, "allowFrom": [$user] }')
fi

echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add' > "$NANOBOT_DIR/config.json"

bashio::log.info "Avvio di Nanobot Gateway. Sandboxing: $RESTRICT"
bashio::log.info "Modelli in uso: $MODEL"
cd "$WORK_DIR"
exec nanobot gateway
