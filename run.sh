#!/usr/bin/with-contenv bashio

# ------------------------------------------------------------------------------
# 1. SETUP PERSISTENZA E LINKING
# ------------------------------------------------------------------------------
PERSISTENT_DIR="/data/nanobot_root"
INTERNAL_DIR="/root/.nanobot"

mkdir -p "$PERSISTENT_DIR"

if [ -d "$INTERNAL_DIR" ] && [ ! -L "$INTERNAL_DIR" ]; then
    rm -rf "$INTERNAL_DIR"
fi
ln -sfn "$PERSISTENT_DIR" "$INTERNAL_DIR"

# ------------------------------------------------------------------------------
# 2. RECUPERO CONFIGURAZIONE CORE
# ------------------------------------------------------------------------------
PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
RESTRICT=$(bashio::config 'restrict_to_workspace')
WORKSPACE=$(bashio::config 'workspace_path')
ADDITIONAL_JSON=$(bashio::config 'additional_config_json')
API_BASE=$(bashio::config 'api_base')

mkdir -p "$WORKSPACE"

bashio::log.info "Generazione configurazione base..."

# Costruzione JSON Base
BASE_CONFIG=$(jq -n \
  --arg prov "$PROVIDER" \
  --arg key "$API_KEY" \
  --arg mod "$MODEL" \
  --arg restr "$RESTRICT" \
  --arg work "$WORKSPACE" \
  '{
    "providers": { ($prov): { "apiKey": $key } },
    "agents": { "defaults": { "model": $mod } },
    "tools": { 
      "restrictToWorkspace": ($restr == "true"),
      "workspace": $work
    },
    "channels": {} 
  }')

# Iniezione API Base opzionale
if bashio::config.has_value 'api_base'; then
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg base "$API_BASE" --arg prov "$PROVIDER" \
        '.providers[$prov].apiBase = $base')
fi

# ------------------------------------------------------------------------------
# 3. CONFIGURAZIONE TELEGRAM
# ------------------------------------------------------------------------------
if bashio::config.true 'telegram_enabled'; then
    TG_TOKEN=$(bashio::config 'telegram_token')
    TG_USER=$(bashio::config 'telegram_allow_user')
    
    bashio::log.info "Abilitazione canale Telegram per l'utente: $TG_USER"
    
    # Aggiungiamo il blocco telegram a .channels
    # Nota: allowFrom è un array, quindi usiamo gli brackets [] nel JSON
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg token "$TG_TOKEN" --arg user "$TG_USER" \
        '.channels.telegram = {
            "enabled": true,
            "token": $token,
            "allowFrom": [$user]
        }')
fi

# ------------------------------------------------------------------------------
# 4. CONFIGURAZIONE EMAIL
# ------------------------------------------------------------------------------
if bashio::config.true 'email_enabled'; then
    MAIL_USER=$(bashio::config 'email_username')
    MAIL_PASS=$(bashio::config 'email_password')
    MAIL_IMAP=$(bashio::config 'email_imap_server')
    MAIL_SMTP=$(bashio::config 'email_smtp_server')
    MAIL_ALLOW=$(bashio::config 'email_allow_from')
    
    bashio::log.info "Abilitazione canale Email ($MAIL_USER)..."
    
    # Creiamo il JSON per l'email.
    # Usiamo split(",") per convertire la stringa "email1, email2" in un array JSON reale
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq \
        --arg user "$MAIL_USER" \
        --arg pass "$MAIL_PASS" \
        --arg imap "$MAIL_IMAP" \
        --arg smtp "$MAIL_SMTP" \
        --arg allow "$MAIL_ALLOW" \
        '.channels.email = {
            "enabled": true,
            "consentGranted": true,
            "imapHost": $imap,
            "imapPort": 993,
            "imapUsername": $user,
            "imapPassword": $pass,
            "smtpHost": $smtp,
            "smtpPort": 587,
            "smtpUsername": $user,
            "smtpPassword": $pass,
            "fromAddress": $user,
            "allowFrom": ($allow | split(",") | map(gsub("^\\s+|\\s+$";""))) 
        }')
fi

# ------------------------------------------------------------------------------
# 5. MERGE FINALE E AVVIO
# ------------------------------------------------------------------------------

# Merge con JSON addizionale custom dell'utente
FINAL_CONFIG=$(echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add')

echo "$FINAL_CONFIG" > "$INTERNAL_DIR/config.json"

bashio::log.info "Avvio Nanobot Gateway..."
exec nanobot gateway
