# Thin layer over the official OpenClaw image. Nothing is compiled here: the
# upstream release (with Chromium baked in) is used as-is, and this image only
# adds what a Railway deploy needs that upstream leaves to the operator.
ARG OPENCLAW_VERSION=2026.11.3
FROM ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}-browser

USER root

# gosu: drop from root (needed to fix volume ownership) to the image's node user.
# build-essential/procps/file: what Homebrew needs to install bottles and build from source.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      gosu build-essential procps file \
 && rm -rf /var/lib/apt/lists/*

# Homebrew, installed as node so skills can `brew install` their CLIs without root.
# The boot script moves it onto the volume on first boot so installs survive redeploys.
RUN mkdir -p /home/linuxbrew/.linuxbrew && chown -R node:node /home/linuxbrew
USER node
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
 && /home/linuxbrew/.linuxbrew/bin/brew --version
USER root

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}" \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    HOMEBREW_NO_ANALYTICS=1 \
    OPENCLAW_DATA_DIR=/data \
    NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache

COPY --chmod=755 railway/ /usr/local/lib/openclaw-railway/
RUN ln -s /usr/local/lib/openclaw-railway/boot.sh /usr/local/bin/openclaw-railway-boot

EXPOSE 8080
ENTRYPOINT ["tini", "-s", "--", "/usr/local/bin/openclaw-railway-boot"]
