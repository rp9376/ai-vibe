# syntax=docker/dockerfile:1
# AI VIBE image: one image for every agent (SPEC §4). Built by `vibe build` with the repo root as context.
ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}

ARG USER_UID=1000
ARG USER_GID=1000
ARG NODE_MAJOR=24
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
LABEL org.opencontainers.image.title="AI VIBE"

# 1 · Base tools (IMG-3). Deliberately absent: sudo, ssh/gpg agents.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bubblewrap ca-certificates curl git jq less procps \
      python3 python3-pip python3-venv ripgrep unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*

# 2 · Node.js: official build, checked against the release's SHASUMS256.txt.
#     NODE_MAJOR="" keeps the base image's own Node.
RUN set -eux; mkdir -p /opt/vibe; \
    if [ -n "$NODE_MAJOR" ]; then \
      case "$(dpkg --print-architecture)" in amd64) arch=x64 ;; arm64) arch=arm64 ;; *) echo "unsupported arch" >&2; exit 1 ;; esac; \
      url="https://nodejs.org/dist/latest-v${NODE_MAJOR}.x"; cd /tmp; \
      curl -fsSLO "$url/SHASUMS256.txt"; \
      file=$(grep -oE "node-v[0-9.]+-linux-${arch}\.tar\.xz" SHASUMS256.txt | head -n1); \
      curl -fsSLO "$url/$file"; \
      grep " ${file}\$" SHASUMS256.txt | sha256sum -c -; \
      mkdir -p /opt/node; tar -xJf "$file" -C /opt/node --strip-components=1 --no-same-owner; \
      rm -f "$file" SHASUMS256.txt; \
    fi
ENV PATH=/opt/node/bin:$PATH
RUN echo "node $(node --version)" > /opt/vibe/build-info

# 3 · Non-root user with the host user's UID/GID (IMG-4). Removes a conflicting user (e.g. 'ubuntu' on 24.04 bases).
RUN set -eux; \
    old=$(getent passwd "$USER_UID" | cut -d: -f1 || true); \
    if [ -n "$old" ]; then userdel -r "$old" 2>/dev/null || userdel "$old"; fi; \
    getent group "$USER_GID" >/dev/null || groupadd -g "$USER_GID" user; \
    useradd -m -u "$USER_UID" -g "$USER_GID" -s /bin/bash user; \
    for d in .config .cache .local .local/bin .local/share .local/state; do \
      install -d -o "$USER_UID" -g "$USER_GID" "/home/user/$d"; done; \
    install -d -o "$USER_UID" -g "$USER_GID" /workspaces

# 4 · Agents (AGT-1): every enabled folder in agents/. install.sh runs as root; rootfs/ is copied into /.
COPY agents/ /opt/vibe/agents/
RUN set -eu; cd /opt/vibe/agents; \
    for d in */; do d=${d%/}; \
      ( set -a; . "./$d/agent.conf"; set +a; \
        if [ "${AGENT_ENABLED:-yes}" = no ]; then echo ">> $d: disabled"; rm -rf "./$d"; exit 0; fi; \
        echo ">> $d: installing ${AGENT_VERSION:-latest}"; \
        if [ -f "./$d/install.sh" ]; then bash "./$d/install.sh"; fi; \
        if [ -d "./$d/rootfs" ]; then cp -r "./$d/rootfs/." /; rm -rf "./$d/rootfs"; fi; \
        for m in ${AGENT_STATE:-}; do install -d -o "$USER_UID" -g "$USER_GID" "${m#*:}"; done ); \
    done; \
    install -d -o "$USER_UID" -g "$USER_GID" /home/user/.vibe-git; \
    npm cache clean --force >/dev/null 2>&1 || true; rm -rf /root/.npm /root/.cache /tmp/*

# 5 · Shared bubble files: agent instructions (AGT-5), helpers, system git + shell config.
COPY image/AGENTS.md /opt/vibe/AGENTS.md
COPY image/bin/ /opt/vibe/bin/
COPY image/rootfs/ /opt/vibe/rootfs/
RUN set -eu; cp -r /opt/vibe/rootfs/. /; rm -rf /opt/vibe/rootfs; \
    for c in /opt/vibe/agents/*/agent.conf; do \
      dst=$(set +u; . "$c"; printf '%s' "${AGENT_INSTRUCTIONS:-}"); \
      if [ -n "$dst" ]; then mkdir -p "$(dirname "$dst")"; cp /opt/vibe/AGENTS.md "$dst"; chmod 0644 "$dst"; fi; \
    done; \
    chmod -R go-w /opt/vibe /etc/vibe; chmod 0755 /opt/vibe/bin/*; \
    printf '\n# AI VIBE\nfor f in /etc/vibe/bashrc.d/*.sh; do [ -r "$f" ] && . "$f"; done; unset f\n' >> /etc/bash.bashrc

# 6 · Runtime defaults. User-space installs land in ~/.local (IMG-6); updates come from `vibe build` (IMG-5).
ENV PATH=/home/user/.local/bin:$PATH \
    NPM_CONFIG_PREFIX=/home/user/.local \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    VIBE=1
USER user
WORKDIR /workspaces
CMD ["/opt/vibe/bin/vibe-init"]
# Format this image speaks (see VIBE_FORMAT in vibe). Last, so bumping it keeps the build cache.
LABEL vibe.format="2"
