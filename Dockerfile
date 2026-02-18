ARG BUILD_FROM=ghcr.io/hassio-addons/base/alpine:latest
FROM $BUILD_FROM

# Installazione Python, pip e dipendenze di sistema
# gcc, musl-dev, linux-headers servono per compilare le dipendenze
RUN apk add --no-cache \
    python3 \
    py3-pip \
    git \
    jq \
    curl \
    gcc \
    musl-dev \
    linux-headers \
    python3-dev

# Installazione Nanobot direttamente da GitHub
# Il pacchetto su PyPI non esiste, quindi lo preleviamo dal source code
RUN pip3 install --no-cache-dir --break-system-packages git+https://github.com/HKUDS/nanobot.git

COPY run.sh /
RUN chmod a+x /run.sh

# Esponiamo la porta standard (interna)
EXPOSE 18790

WORKDIR /data
CMD [ "/run.sh" ]
