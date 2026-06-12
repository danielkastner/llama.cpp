FROM ghcr.io/ggml-org/llama.cpp:server-cuda13
LABEL authors="daniel@daniel-kastner.ch"

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl tini \
      openssh-server sudo zstd \
      lshw aria2 jq \
    && rm -rf /var/lib/apt/lists/*

# OpenSSH runtime dirs + host keys
RUN mkdir -p /var/run/sshd \
 && ssh-keygen -A

# SSH hardening defaults
RUN sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?KbdInteractiveAuthentication .*/KbdInteractiveAuthentication no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config \
 && echo "UsePAM yes" >> /etc/ssh/sshd_config \
 && echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config

# User app + sudo group
ARG SSH_USER=app
RUN useradd -m -s /bin/bash "${SSH_USER}" \
 && usermod -aG sudo "${SSH_USER}"

# Optional (bequem, aber weniger sicher): sudo ohne Passwort
# Wenn du das NICHT willst, einfach diese Zeile entfernen.
RUN echo "${SSH_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-${SSH_USER} \
 && chmod 0440 /etc/sudoers.d/99-${SSH_USER}

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

EXPOSE 22 8080

VOLUME ["/root/.llama.cpp", "/models", "/cache"]

ENV WEBUI_HOST="0.0.0.0" \
    WEBUI_PORT="8080" \
    SSH_USER="app" \
    SSH_ENABLE_PASSWORD="0" \
    LLAMA_MODELS="/models" \
    LLAMA_CACHE="/cache" \
    LLAMA_API_KEY="not-set-or-not-required" \
    HF_MODEL_FILE="https://huggingface.co/mradermacher/Qwen3.6-27B-i1-GGUF/resolve/main/Qwen3.6-27B.i1-Q4_K_M.gguf" \
    HF_MEM_FILE="" \
    HF_MODEL="mradermacher/Qwen3.6-27B-i1-GGUF:Q4_K_M"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
COPY unload-model.sh /app/unload-model.sh
RUN chmod +x /app/unload-model.sh

#COPY aitools /aitools
#RUN chmod +x aitools/*.sh

#COPY environment/runpod/environment.sh /environment/runpod/environment.sh
#RUN chmod +x /environment/runpod/environment.sh
#COPY environment/vastai/environment.sh /environment/vastai/environment.sh
#RUN chmod +x /environment/vastai/environment.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
