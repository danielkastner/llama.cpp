#!/bin/bash

LICENSE_KEY="${NEW_RELIC_LICENSE_KEY}"
ENDPOINT="${NEW_RELIC_ENDPOINT:-https://log-api.eu.newrelic.com/log/v1}"

MESSAGE="${1:-Testnachricht}"

HOSTNAME="vastai-${CONTAINER_ID:-unknown}"

curl -sS -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -H "Api-Key: $LICENSE_KEY" \
  -d "[
    {
      \"message\": \"$MESSAGE\",
      \"hostname\": \"$HOSTNAME\",
      \"service\": \"${NEW_RELIC_SERVICE:-llama-server}\",
      \"level\": \"INFO\",
      \"timestamp\": $(($(date +%s%N)/1000000))
    }
  ]"