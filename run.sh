#!/usr/bin/with-contenv bashio

# ------------------------------------------------------------------------------
# 1. SETUP DELLE DIRECTORY (Struttura Share-Centrica)
# ------------------------------------------------------------------------------
# Recuperiamo i percorsi dallo share
USER_WORKSPACE=$(bashio::config 'workspace_path')
USER_MEDIA=$(bashio::config 'media_path')

# Definiamo la sottocartella di sistema nello share
# Qui finiranno db, log, config interne e skills interne
SYSTEM_DIR="$USER_WORKSPACE/system"

# Creiamo le cartelle fisiche nello share
mkdir -p "$SYSTEM_DIR/internal_data"
mkdir -p "$USER_WORKSPACE/skills"
mkdir -p "$USER_MEDIA"

# Percorsi interni che il container si aspetta
INTERNAL_ROOT="/root/.nanobot"
INTERNAL_WORKSPACE="/root/.nanobot/workspace"
INTERNAL_MEDIA="/root/.nanobot/media"

# ------------------------------------------------------------------------------
# 2. COLLEGAMENTO TOTALE (Symlinks)
# ------------------------------------------------------------------------------
# Pulizia dei percorsi interni esistenti
rm -rf "$INTERNAL_ROOT"

# Link 1: Il "cuore" del bot punta alla cartella system/internal_data nello share
ln -sfn "$SYSTEM_DIR/internal_data" "$INTERNAL_ROOT"

# Link 2: Il workspace dell'agente punta alla radice dello share (per vedere tutto)
mkdir -p "$INTERNAL_ROOT/workspace" # Placeholder necessario per il link successivo
rm -rf "$INTERNAL_WORKSPACE"
ln -sfn "$USER_WORKSPACE" "$INTERNAL_WORKSPACE"

# Link 3: La cartella media interna punta allo share media
rm -rf "$INTERNAL_MEDIA"
ln -sfn "$USER_MEDIA" "$INTERNAL_MEDIA"

bashio::log.info "Configurazione organizzata: Sistema -> $SYSTEM_DIR"

# ------------------------------------------------------------------------------
# 3. INSTALLAZIONE SKILL INTERNA (ClawHub)
# ------------------------------------------------------------------------------
# Creiamo la skill ClawHub dentro la cartella di sistema
mkdir -p "$INTERNAL_ROOT/skills/clawhub"
cat <<EOF > "$INTERNAL_ROOT/skills/clawhub/SKILL.md"
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
    BASE_CONFIG=$(echo "$BASE_CONFIG" | jq --arg token "$TG_TOKEN" --arg user "$TG_USER" --arg media "$INTERNAL_MEDIA" \
        '.channels.telegram = {
            "enabled": true,
            "token": $token,
            "allowFrom": [$user],
            "downloadPath": $media
        }')
fi

# Merge finale e salvataggio nel percorso di sistema
FINAL_CONFIG=$(echo "$BASE_CONFIG" | jq --argjson add "$ADDITIONAL_JSON" '. * $add')
echo "$FINAL_CONFIG" > "$INTERNAL_ROOT/config.json"

# ------------------------------------------------------------------------------
# 6. AVVIO
# ------------------------------------------------------------------------------
bashio::log.info "Avvio Nanobot Gateway..."
exec nanobot gateway
