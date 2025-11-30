#!/usr/bin/env bash

set -euo pipefail

# Configuration (can be overridden via environment variables)
BASE_URL="${PRUSA_CONNECT_URL:-https://vapor:6443/api/v1}"
TOKEN="$(kwallet-query -f API-Tokens -r Prusa-Connect-Admin kdewallet)"
DEVICE_ID="${PRUSA_DEVICE_ID:-a7474b89-eb2f-401f-b414-62284909d9e2}"
STORAGE="${PRUSA_STORAGE:-local}"

BBF_FILE="${1:-build/products/coreone_release_emptyboot.bbf}"

if [[ ! -f "$BBF_FILE" ]]; then
  echo "Error: Firmware file not found: $BBF_FILE" >&2
  exit 1
fi

FILENAME="$(basename "$BBF_FILE")"
LOCAL_SHA256="$(sha256sum "$BBF_FILE" | awk '{print $1}')"

echo "==> 1. Uploading $FILENAME to temporary server storage..."
UPLOAD_RESP="$(curl -sS -X POST \
  "${BASE_URL}/storages/${STORAGE}/content?path=${FILENAME}&temporary=true" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@${BBF_FILE}" \
  --fail-with-body)"

TEMP_PATH="$(jq -r '.path' <<< "$UPLOAD_RESP")"
SERVER_SHA256="$(jq -r '.sha256' <<< "$UPLOAD_RESP")"
UPLOADED_BYTES="$(jq -r '.bytes' <<< "$UPLOAD_RESP")"

if [[ -z "$TEMP_PATH" || "$TEMP_PATH" == "null" ]]; then
  echo "Error: Upload did not return a temporary path:" >&2
  echo "$UPLOAD_RESP" | jq . >&2
  exit 1
fi

if [[ "$LOCAL_SHA256" != "$SERVER_SHA256" ]]; then
  echo "Error: SHA-256 mismatch! Local=$LOCAL_SHA256 Server=$SERVER_SHA256" >&2
  exit 1
fi

echo "    Uploaded ${UPLOADED_BYTES} bytes to '${TEMP_PATH}' (SHA-256 verified)"

echo "==> 2. Transferring '${TEMP_PATH}' to printer usb/${FILENAME}..."
TRANSFER_PAYLOAD="$(jq -n \
  --arg storage "$STORAGE" \
  --arg source "$TEMP_PATH" \
  --arg path "usb/${FILENAME}" \
  '{storage: $storage, source: $source, path: $path, replace: true}')"

TRANSFER_RESP="$(curl -sS -X POST \
  "${BASE_URL}/devices/${DEVICE_ID}/files" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$TRANSFER_PAYLOAD" \
  --fail-with-body)"

echo "$TRANSFER_RESP" | jq .

echo "==> 3. Triggering core.command.flash on /usb/${FILENAME}..."
FLASH_PAYLOAD="$(jq -n \
  --arg path "/usb/${FILENAME}" \
  '{verb: "core.command.flash", args: {path: $path}}')"

FLASH_RESP="$(curl -sS -X POST \
  "${BASE_URL}/devices/${DEVICE_ID}/commands" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$FLASH_PAYLOAD" \
  --fail-with-body)"

echo "$FLASH_RESP" | jq .
echo "==> Done! Printer should reboot and flash ${FILENAME}."
