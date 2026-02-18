#!/usr/bin/with-contenv bashio

# ------------------------------------------------------------------------------
# 1. SETUP PERSISTENZA GLOBALE
# ------------------------------------------------------------------------------
PERSISTENT_DIR="/data/nanobot_root"
INTERNAL_DIR="/root/.nanobot"

mkdir -p "$PERSISTENT_DIR"

# Link della root di nanobot (/root/.nanobot -> /data/nanobot_root)
if [ -d "$INTERNAL_DIR" ] && [ ! -L "$INTERNAL_DIR" ]; then
    rm -rf "$INTERNAL_DIR"
fi
ln -sfn "$PERSISTENT_DIR" "$INTERNAL_DIR"

# ------------------------------------------------------------------------------
# 2. CONFIGURAZIONE WORKSPACE (IL FIX)
# ------------------------------------------------------------------------------
# Recuperiamo il percorso desiderato dall'utente (es. /share/nanobot_workspace)
USER_WORKSPACE_PATH=$(bashio::config 'workspace_path')

# Questo è il percorso che Nanobot considera "sicuro"
INTERNAL_WORKSPACE_PATH="/root/.nanobot/workspace"

# 1. Assicuriamoci che la cartella dell'utente esista
mkdir -p "$USER_WORKSPACE_PATH/skills"

# 2. Rimuoviamo la cartella workspace interna se esiste (per far posto al link)
rm -rf "$INTERNAL_WORKSPACE_PATH"

# 3. Creiamo il collegamento: Quando il bot scrive in INTERNAL, finisce in USER
ln -sfn "$USER_WORKSPACE_PATH" "$INTERNAL_WORKSPACE_PATH"

bashio::log.info "Workspace collegato: $INTERNAL_WORKSPACE_PATH -> $USER_WORKSPACE_PATH"

# ------------------------------------------------------------------------------
# 3. RECUPERO ALTRE VARIABILI
# ------------------------------------------------------------------------------
PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
RESTRICT=$(bashio::config 'restrict_to_workspace')
ADDITIONAL_JSON=$(bashio::config 'additional_config_json')
API_BASE=$(bashio::config 'api_base')

# ------------------------------------------------------------------------------
# 4. INSTALLAZIONE SKILL DI SISTEMA (ClawHub)
# ------------------------------------------------------------------------------
INTERNAL_SKILLS_DIR="/root/.nanobot/skills"
mkdir -p "$INTERNAL_SKILLS_DIR/clawhub"

# Configuriamo ClawHub per usare il percorso INTERNO (che è symlinkato all'esterno)
cat <<EOF > "$INTERNAL_SKILLS_DIR/clawhub/SKILL.md"
---
name: clawhub
description: Search and install agent skills from ClawHub.
homepage: https://clawhub.ai
metadata: {"nanobot":{"emoji":"🦞"}}
---

# ClawHub

System tool to search and install new skills into the workspace.

## Search
\`\`\`bash
npx --yes clawhub@latest search "\$1" --limit 5
\`\`\`

## Install
\`\`\`bash
npx --yes clawhub@latest install "\$1" --workdir "$INTERNAL_WORKSPACE_PATH"
\`\`\`

## Update
\`\`\`bash
npx --yes clawhub@latest update --all --workdir "$INTERNAL_WORKSPACE_PATH"
\`\`\`

## List
\`\`\`bash
npx --yes clawhub@latest list --workdir "$INTERNAL_WORKSPACE_PATH"
\`\`\`
EOF

# ------------------------------------------------------------------------------
# 5. FIX WEATHER TOOL
# ------------------------------------------------------------------------------
cat <<EOF > /usr/bin/weather
#!/bin/sh
if [ -z "\$1" ]; then curl -s "wttr.in?format=3"; else curl -s "wttr.in/\$1?format=3"; fi
EOF
chmod +x /usr/bin/weather

# ------------------------------------------------------------------------------
# 6. GENERAZIONE CONFIGURAZIONE JSON
# ------------------------------------------------------------------------------
bashio::log.info "Generazione configurazione..."

# NOTA: Nel JSON impostiamo il workspace come quello INTERNO ($INTERNAL_WORKSPACE_PATH).
# Questo soddisfa il check di sicurezza restrictToWorkspace.
BASE_CONFIG=$(jq -n \
  --arg prov "$PROVIDER" \
  --arg key "$API_KEY" \
  --arg mod "$MODEL" \
  --arg restr "$RESTRICT" \
  --arg work "$INTERNAL_WORKSPACE_PATH" \
  '{
    "providers": { ($prov): { "apiKey": $key } },
    "agents": { "defaults": { "model": $mod } },
    "tools": { 
      "restrictToWorkspace": ($restr == "true"),
      "workspace": $work
    },
    "channels": {} 
  }')

if bashio::config.has_value 'api_base'; then
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg base "$API_BASE" --arg prov "$PROVIDER" \
        '.providers[$prov].apiBase = $base')
fi

# Configurazione Telegram
if bashio::config.true 'telegram_enabled'; then
    TG_TOKEN=$(bashio::config 'telegram_token')
    TG_USER=$(bashio::config 'telegram_allow_user')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg token "$TG_TOKEN" --arg user "$TG_USER" \
        '.channels.telegram = { "enabled": true, "token": $token, "allowFrom": [$user] }')
fi

# Configurazione Email
if bashio::config.true 'email_enabled'; then
    MAIL_USER=$(bashio::config 'email_username')
    MAIL_PASS=$(bashio::config 'email_password')
    MAIL_IMAP=$(bashio::config 'email_imap_server')
    MAIL_SMTP=$(bashio::config 'email_smtp_server')
    MAIL_ALLOW=$(bashio::config 'email_allow_from')
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq \
        --arg user "$MAIL_USER" \
        --arg pass "$MAIL_PASS" \
        --arg imap "$MAIL_IMAP" \
        --arg smtp "$MAIL_SMTP" \
        --arg allow "$MAIL_ALLOW" \
        '.channels.email = {
            "enabled": true,
            "consentGranted": true,
            "imapHost": $imap, "imapPort": 993, "imapUsername": $user, "imapPassword": $pass,
            "smtpHost": $smtp, "smtpPort": 587, "smtpUsername": $user, "smtpPassword": $pass,
            "fromAddress": $user,
            "allowFrom": ($allow | split(",") | map(gsub("^\\s+|\\s+$";""))) 
        }')
fi

FINAL_CONFIG=$(echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add')
echo "$FINAL_CONFIG" > "$INTERNAL_DIR/config.json"

# ------------------------------------------------------------------------------
# 7. AVVIO
# ------------------------------------------------------------------------------
bashio::log.info "Avvio Nanobot Gateway..."
exec nanobot gateway
