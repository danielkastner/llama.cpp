#!/usr/bin/env bash
set -euo pipefail

curl -s -X POST http://localhost:8080/models/unload \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen3-Coder-Next-UD-Q2_K_XL.gguf"}' \
  | jq