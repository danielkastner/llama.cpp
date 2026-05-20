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

echo "[entrypoint] sshpass -p ${SSH_PASSWORD} ssh -L 21434:localhost:11434 -p ${VAST_TCP_PORT_22} -o StrictHostKeyChecking=no ${SSH_USER}@${PUBLIC_IPADDR}"
echo "[entrypoint] ANTHROPIC_BASE_URL=\"http://${PUBLIC_IPADDR}:${VAST_TCP_PORT_8080}\" ANTHROPIC_API_KEY=${LLAMA_API_KEY} ANTHROPIC_CUSTOM_MODEL_OPTION=\"Qwen3-Coder-Next-UD-Q2_K_XL\" claude --model \"Qwen3-Coder-Next-UD-Q2_K_XL\""

# Send to a ntfy-server
curl \
  -H "Authorization: Bearer ${NTFY_TOKEN}" \
  -H "X-Title: SSH-Connection Details for ${CONTAINER_ID}" \
  -H "Markdown: yes" \
  -d "\`sshpass -p ${SSH_PASSWORD} ssh -L 21434:localhost:11434 -p ${VAST_TCP_PORT_22} -o StrictHostKeyChecking=no ${SSH_USER}@${PUBLIC_IPADDR}\`" \
  "${NTFY_URL}"
curl \
  -H "Authorization: Bearer ${NTFY_TOKEN}" \
  -H "X-Title: Claude Details for ${CONTAINER_ID}" \
  -H "Markdown: yes" \
  -d "\`ANTHROPIC_BASE_URL=\"http://${PUBLIC_IPADDR}:${VAST_TCP_PORT_8080}\" ANTHROPIC_API_KEY=${LLAMA_API_KEY} ANTHROPIC_CUSTOM_MODEL_OPTION=\"Qwen3-Coder-Next-UD-Q2_K_XL\" claude --model \"Qwen3-Coder-Next-UD-Q2_K_XL\"\`" \
  "${NTFY_URL}"

cd /app
./llama-server -m /models/unsloth/Qwen3-Coder-Next-UD-Q2_K_XL/Qwen3-Coder-Next-UD-Q2_K_XL.gguf --reasoning-format deepseek --api-key "${LLAMA_API_KEY}" --ctx-size 262144 --jinja --verbosity 3 --port 8080 --host 0.0.0.0 -n 512
