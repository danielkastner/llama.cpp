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
mkdir -p mradermacher/Qwen3.6-27B-i1-GGUF
cd mradermacher/Qwen3.6-27B-i1-GGUF
aria2c -x8 -s8 -o Qwen3.6-27B.i1-Q4_K_M.gguf https://huggingface.co/mradermacher/Qwen3.6-27B-i1-GGUF/resolve/main/Qwen3.6-27B.i1-Q4_K_M.gguf
aria2c -x8 -s8 -o mmproj-BF16.gguf https://huggingface.co/unsloth/Qwen3.6-27B-GGUF/resolve/main/mmproj-BF16.gguf

cd /app
./llama-server -m /models/mradermacher/Qwen3.6-27B-i1-GGUF/Qwen3.6-27B.i1-Q4_K_M.gguf --mmproj /models/mradermacher/Qwen3.6-27B-i1-GGUF/mmproj-BF16.gguf --reasoning-format deepseek --ctx-size 262144 --jinja --verbosity 3 --port 8080 --host 0.0.0.0 -n 512
