#!/usr/bin/env bash
set -euo pipefail

device_id="${1:?Usage: $0 <physical-iPhone-UDID>}"
service="smooth-markdown-deepseek-dev"
api_key="$(security find-generic-password -a "$USER" -s "$service" -w)"
if [[ -z "$api_key" ]]; then
  echo "DeepSeek development Key is missing from macOS Keychain service $service" >&2
  exit 1
fi

# devicectl forwards DEVICECTL_CHILD_* to the launched app. The Key never
# appears in command arguments, Git files, or the app's persistent storage.
export DEVICECTL_CHILD_DEEPSEEK_API_KEY="$api_key"
unset api_key
exec xcrun devicectl device process launch --terminate-existing --device "$device_id" \
  com.jackcaow.smoothmarkdown.demo
