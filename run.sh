#!/usr/bin/with-contenv bashio

# ------------------------------------------------------------------------------
# 1. SETUP PERSISTENZA E LINKING ROOT
# ------------------------------------------------------------------------------
PERSISTENT_DIR="/data/nanobot_root"
INTERNAL_DIR="/root/.nanobot"

mkdir -p "$PERSISTENT_DIR"

if [ -d "$INTERNAL_DIR" ] && [ ! -L "$INTERNAL_DIR" ]; then
    rm -rf "$INTERNAL_DIR"
fi
ln -sfn "$PERSISTENT_DIR" "$INTERNAL_DIR"

# ------------------------------------------------------------------------------
# 2. CONFIGURAZIONE WORKSPACE E MEDIA (Il Fix dei Symlink)
# ------------------------------------------------------------------------------
USER_WORKSPACE=$(bashio::config 'workspace_path')
USER_MEDIA=$(bashio::config 'media_path')

# Percorsi interni che Nanobot usa di default
INTERNAL_WORKSPACE="/root/.nanobot/workspace"
INTERNAL_DEFAULT_MEDIA="/root/.nanobot/media"

# Creazione cartelle fisiche nello share
mkdir -p "$USER_WORKSPACE/skills"
mkdir -p "$USER_MEDIA"

# FIX 1: Colleghiamo il Workspace
rm -rf "$INTERNAL_WORKSPACE"
ln -sfn "$USER_WORKSPACE" "$INTERNAL_WORKSPACE"

# FIX 2: Colleghiamo la cartella media interna a quella dello share
# Questo risolve il problema del file che finisce in /root/.nanobot/media/
rm -rf "$INTERNAL_DEFAULT_MEDIA"
ln -sfn "$USER_MEDIA" "$INTERNAL_DEFAULT_MEDIA"

bashio::log.info "Symlinks attivi: Media -> $USER_MEDIA"

# ------------------------------------------------------------------------------
# 3. INSTALLAZIONE SKILL INTERNA: CLAWHUB
# ------------------------------------------------------------------------------
INTERNAL_SKILLS_DIR="/root/.nanobot/skills"
mkdir -p "$INTERNAL_SKILLS_DIR/clawhub"

cat <<EOF > "$INTERNAL_SKILLS_DIR/clawhub/SKILL.md"
---
name: clawhub
description: Search and install agent skills from ClawHub.
metadata: {"nanobot":{"emoji":"🦞"}}
---
# ClawHub
## Search
\`\`\`bash
npx --yes clawhub@latest search "\$1" --limit 5
\`\`\`
## Install
\`\`\`bash
npx --yes clawhub@latest install "\$1" --workdir "$INTERNAL_WORKSPACE"
\`\`\`
EOF

# ------------------------------------------------------------------------------
# 4. WEATHER TOOL FIX
# ------------------------------------------------------------------------------
cat <<EOF > /usr/bin/weather
#!/bin/sh
if [ -z "\$1" ]; then curl -s "wttr.in?format=3"; else curl -s "wttr.in/\$1?format=3"; fi
EOF
chmod +x /usr/bin/weather

# ------------------------------------------------------------------------------
# 5. GENERAZIONE CONFIGURAZIONE JSON
# ------------------------------------------------------------------------------
PROVIDER=$(bashio::config 'provider')
API_KEY=$(bashio::config 'api_key')
MODEL=$(bashio::config 'model')
RESTRICT=$(bashio::config 'restrict_to_workspace')
ADDITIONAL_JSON=$(bashio::config 'additional_config_json')
API_BASE=$(bashio::config 'api_base')

BASE_CONFIG=$(jq -n \
  --arg prov "$PROVIDER" \
  --arg key "$API_KEY" \
  --arg mod "$MODEL" \
  --arg restr "$RESTRICT" \
  --arg work "$INTERNAL_WORKSPACE" \
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

# Telegram
if bashio::config.true 'telegram_enabled'; then
    TG_TOKEN=$(bashio::config 'telegram_token')
    TG_USER=$(bashio::config 'telegram_allow_user')
    # Puntiamo al percorso interno che ora è linkato allo share
    TG_DOWNLOAD_PATH="/root/.nanobot/media"
    
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg token "$TG_TOKEN" --arg user "$TG_USER" --arg media "$TG_DOWNLOAD_PATH" \
        '.channels.telegram = {
            "enabled": true,
            "token": $token,
            "allowFrom": [$user],
            "downloadPath": $media
        }')
fi

# Email
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

FINAL_CONFIG=$(echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add')
echo "$FINAL_CONFIG" > "$INTERNAL_DIR/config.json"

# ------------------------------------------------------------------------------
# 6. AVVIO
# ------------------------------------------------------------------------------
bashio::log.info "Avvio Nanobot Gateway..."
exec nanobot gateway
