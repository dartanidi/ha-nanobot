ARG BUILD_FROM=ghcr.io/hassio-addons/debian-base:9.1.0
FROM $BUILD_FROM

# Installazione dipendenze di sistema su base Debian
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-venv \
    python3-pip \
    python3-dev \
    build-essential \
    git \
    jq \
    curl \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Installazione Nanobot in un Venv di sistema interno al container (read-only)
RUN python3 -m venv /opt/nanobot \
    && /opt/nanobot/bin/pip install --no-cache-dir git+https://github.com/HKUDS/nanobot.git

COPY run.sh /
RUN chmod a+x /run.sh

EXPOSE 18790

WORKDIR /data
CMD [ "/run.sh" ]
