ARG BUILD_FROM=ghcr.io/hassio-addons/debian-base:9.1.0
FROM $BUILD_FROM

# Install system dependencies (supports both Alpine/apk and Debian/apt-get base images)
RUN if command -v apk > /dev/null 2>&1; then \
      apk add --no-cache \
        python3 \
        py3-pip \
        py3-virtualenv \
        python3-dev \
        build-base \
        git \
        jq \
        curl \
        nodejs \
        npm; \
    else \
      apt-get update && apt-get install -y --no-install-recommends \
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
      && rm -rf /var/lib/apt/lists/*; \
    fi

# Install Nanobot in a system venv inside the container (read-only)
RUN python3 -m venv /opt/nanobot \
    && /opt/nanobot/bin/pip install --no-cache-dir git+https://github.com/HKUDS/nanobot.git

COPY run.sh /
RUN chmod a+x /run.sh

EXPOSE 18790

WORKDIR /data
CMD [ "/run.sh" ]
