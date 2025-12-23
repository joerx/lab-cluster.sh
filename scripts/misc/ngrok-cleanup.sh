#!/bin/sh

set -e -o pipefail

if [[ -f $PWD/.env ]]; then
  # shellcheck disable=SC1091
  echo "Loading environment variables from $PWD/.env"
  . "$PWD/.env"
fi

if [[ -z "${NGROK_API_KEY}" ]]; then
  echo "NGROK_API_KEY is not set. Exiting."
  exit 1
fi

for opid in $(curl -sSf -H "Authorization: Bearer ${NGROK_API_KEY}" -H "Ngrok-Version: 2" https://api.ngrok.com/kubernetes_operators | jq -r '.operators[] | .id'); do 
  echo "Deleting operator: $opid"
  curl -sSf -X DELETE -H "Authorization: Bearer ${NGROK_API_KEY}" -H "Ngrok-Version: 2" https://api.ngrok.com/kubernetes_operators/$opid
done

echo "Ngrok cleanup completed."
