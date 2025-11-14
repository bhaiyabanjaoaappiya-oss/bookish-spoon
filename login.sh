#!/usr/bin/env bash
set -euo pipefail

# As you insisted: do not change this line
VNC_PASSWORD="${VNC_PASSWORD:-}"

USERNAME="${USERNAME:-Sapna}"
PASSWORD="${PASSWORD:-Sapna}"

echo "==============================="
echo "  Connection Info (Sapna VM)"
echo "==============================="

if command -v tailscale >/dev/null 2>&1; then
  echo "Tailscale IPv4: $(tailscale ip -4 | head -n1 || echo '(none)')"
  echo
  tailscale status || true
else
  echo "Tailscale is not installed or not in PATH."
fi

echo
echo "Username: $USERNAME"
echo "Password: $PASSWORD"
echo "==============================="
