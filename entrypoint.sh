#!/usr/bin/env bash
set -euo pipefail

# ----- SSH user setup -----
SSH_USER="${SSH_USER:-app}"
USER_HOME="$(getent passwd "$SSH_USER" | cut -d: -f6 || true)"
if [[ -z "${USER_HOME}" ]]; then
  echo "[entrypoint] SSH_USER '$SSH_USER' not found. Creating..."
  useradd -m -s /bin/bash "$SSH_USER"
  USER_HOME="$(getent passwd "$SSH_USER" | cut -d: -f6)"
fi

# Authorized keys (recommended)
if [[ -n "${SSH_PUBLIC_KEY:-}" ]]; then
  echo "[entrypoint] Configuring SSH authorized_keys for ${SSH_USER}"
  install -d -m 700 -o "$SSH_USER" -g "$SSH_USER" "${USER_HOME}/.ssh"
  printf '%s\n' "${SSH_PUBLIC_KEY}" > "${USER_HOME}/.ssh/authorized_keys"
  chown "$SSH_USER:$SSH_USER" "${USER_HOME}/.ssh/authorized_keys"
  chmod 600 "${USER_HOME}/.ssh/authorized_keys"
fi

# Optional password auth (off by default)
if [[ -n "${SSH_PASSWORD:-}" ]]; then
  echo "[entrypoint] Setting SSH password for ${SSH_USER}"
  echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd
fi

if [[ "${SSH_ENABLE_PASSWORD:-0}" == "1" ]]; then
  echo "[entrypoint] Enabling SSH password authentication"
  sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  sed -i 's/^KbdInteractiveAuthentication .*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config
else
  sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^KbdInteractiveAuthentication .*/KbdInteractiveAuthentication no/' /etc/ssh/sshd_config
fi

# Start sshd (background)
echo "[entrypoint] Starting sshd..."
/usr/sbin/sshd -D -e &
SSHD_PID=$!

cd /models
mkdir -p unsloth/Qwen3-Coder-Next-UD-Q2_K_XL
cd unsloth/Qwen3-Coder-Next-UD-Q2_K_XL
aria2c -x8 -s8 -o Qwen3-Coder-Next-UD-Q2_K_XL.gguf https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/resolve/main/Qwen3-Coder-Next-UD-Q2_K_XL.gguf

# Get public IP Address, Port and so on
# First check for public IP on Vast.ai
PUBLIC_IP="UNDEFINED"
if [ -n "${PUBLIC_IPADDR:-}" ]; then
    PUBLIC_IP="${PUBLIC_IPADDR:-UNDEFINED}"
fi
# Then for public IP on Runpod.io
if [ -n "${RUNPOD_PUBLIC_IP:-}" ]; then
    PUBLIC_IP="${RUNPOD_PUBLIC_IP:-UNDEFINED}"
fi
# First check for public TCP Port 22 on Vast.ai
PUBLIC_PORT_22="UNDEFINED"
if [ -n "${VAST_TCP_PORT_22:-}" ]; then
    PUBLIC_PORT_22="${VAST_TCP_PORT_22:-UNDEFINED}"
fi
# Then for public TCP Port 22 on Runpod.io
if [ -n "${RUNPOD_TCP_PORT_22:-}" ]; then
    PUBLIC_PORT_22="${RUNPOD_TCP_PORT_22:-UNDEFINED}"
fi
# First check for public TCP Port 8080 on Vast.ai
PUBLIC_PORT_8080="UNDEFINED"
if [ -n "${VAST_TCP_PORT_8080:-}" ]; then
    PUBLIC_PORT_8080="${VAST_TCP_PORT_8080:-UNDEFINED}"
fi
# Then for public TCP Port 8080 on Runpod.io
if [ -n "${RUNPOD_TCP_PORT_8080:-}" ]; then
    PUBLIC_PORT_8080="${RUNPOD_TCP_PORT_8080:-UNDEFINED}"
fi
# Check if we're on Runpod.io and store Pod ID into CONTAINER_ID
if [ -n "${RUNPOD_POD_ID:-}" ]; then
    CONTAINER_ID="${RUNPOD_POD_ID:-UNDEFINED}"
fi
# First check if on Vast.AI for creating ANTHROPIC_BASE_URL
ANTHROPIC_BASE_URL="UNDEFINED"
if [ -n "${PUBLIC_IPADDR:-}" ]; then
    ANTHROPIC_BASE_URL="http://${PUBLIC_IPADDR}:${PUBLIC_PORT_8080}"
fi
# Then for public IP on Runpod.io
if [ -n "${RUNPOD_PUBLIC_IP:-}" ]; then
    ANTHROPIC_BASE_URL="https://${RUNPOD_POD_ID}-8080.proxy.runpod.net"
fi

echo "[entrypoint] sshpass -p ${SSH_PASSWORD} ssh -p ${PUBLIC_PORT_22} -o StrictHostKeyChecking=no ${SSH_USER}@${PUBLIC_IP}"
echo "[entrypoint] ANTHROPIC_BASE_URL=\"${ANTHROPIC_BASE_URL}\" ANTHROPIC_API_KEY=${LLAMA_API_KEY} ANTHROPIC_CUSTOM_MODEL_OPTION=\"Qwen3-Coder-Next-UD-Q2_K_XL\" claude --model \"Qwen3-Coder-Next-UD-Q2_K_XL\""

# Send to a ntfy-server
curl \
  -H "Authorization: Bearer ${NTFY_TOKEN}" \
  -H "X-Title: SSH-Connection Details for ${CONTAINER_ID}" \
  -H "Markdown: yes" \
  -d "\`sshpass -p ${SSH_PASSWORD} ssh -p ${PUBLIC_PORT_22} -o StrictHostKeyChecking=no ${SSH_USER}@${PUBLIC_IP}\`" \
  "${NTFY_URL}"
curl \
  -H "Authorization: Bearer ${NTFY_TOKEN}" \
  -H "X-Title: Claude Details for ${CONTAINER_ID}" \
  -H "Markdown: yes" \
  -d "\`ANTHROPIC_BASE_URL=\"${ANTHROPIC_BASE_URL}\" ANTHROPIC_API_KEY=${LLAMA_API_KEY} ANTHROPIC_CUSTOM_MODEL_OPTION=\"Qwen3-Coder-Next-UD-Q2_K_XL\" claude --model \"Qwen3-Coder-Next-UD-Q2_K_XL\"\`" \
  "${NTFY_URL}"

cd /app
./llama-server -m /models/unsloth/Qwen3-Coder-Next-UD-Q2_K_XL/Qwen3-Coder-Next-UD-Q2_K_XL.gguf --reasoning-format deepseek --api-key "${LLAMA_API_KEY}" --ctx-size 262144 --jinja --verbosity 3 --port 8080 --host 0.0.0.0 -n 512 2>&1 | tee llama-server.log
