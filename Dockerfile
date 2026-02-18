ARG BUILD_FROM=ghcr.io/hassio-addons/base/alpine:latest
FROM $BUILD_FROM

# Installazione Python, Node.js (per ClawHub) e dipendenze di build
RUN apk add --no-cache \
    python3 \
    py3-pip \
    git \
    jq \
    curl \
    gcc \
    musl-dev \
    linux-headers \
    python3-dev \
    nodejs \
    npm

# Installazione Nanobot direttamente da GitHub
RUN pip3 install --no-cache-dir --break-system-packages git+https://github.com/HKUDS/nanobot.git

COPY run.sh /
RUN chmod a+x /run.sh

EXPOSE 18790

WORKDIR /data
CMD [ "/run.sh" ]
