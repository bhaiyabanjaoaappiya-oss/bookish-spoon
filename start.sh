#!/usr/bin/env bash
set -euo pipefail

# ❗ Do not touch (as requested)
VNC_PASSWORD="${VNC_PASSWORD:-}"

# Your custom username/password
USERNAME="${USERNAME:-Sapna}"
PASSWORD="${PASSWORD:-Sapna}"

TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
GITHUB_RUN_ID="${GITHUB_RUN_ID:-$(date +%s)}"
ENABLE_VNC_FLAG=true   # VNC always ON

if [[ $EUID -ne 0 ]]; then
  echo "Run this script as root (sudo)."
  exit 1
fi

if [[ -z "$TAILSCALE_AUTHKEY" ]]; then
  echo "ERROR: TAILSCALE_AUTHKEY is missing."
  exit 1
fi

# Ensure Homebrew
if ! command -v brew >/dev/null 2>&1; then
  echo "[*] Installing Homebrew (if this fails, you may need to install manually)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
  export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
fi

# Create user if missing
if ! id -u "$USERNAME" >/dev/null 2>&1; then
  echo "[*] Creating user: $USERNAME"
  if command -v sysadminctl >/dev/null 2>&1; then
    sysadminctl -addUser "$USERNAME" -fullName "$USERNAME" -password "$PASSWORD" -admin || true
    createhomedir -c -u "$USERNAME" >/dev/null 2>&1 || true
  else
    HOME_DIR="/Users/$USERNAME"
    UID_NEW=$((1000 + RANDOM))
    dscl . -create /Users/"$USERNAME"
    dscl . -create /Users/"$USERNAME" UserShell /bin/bash
    dscl . -create /Users/"$USERNAME" RealName "$USERNAME"
    dscl . -create /Users/"$USERNAME" UniqueID "$UID_NEW"
    dscl . -create /Users/"$USERNAME" PrimaryGroupID 80
    dscl . -create /Users/"$USERNAME" NFSHomeDirectory "$HOME_DIR"
    dscl . -passwd /Users/"$USERNAME" "$PASSWORD"
    createhomedir -c -u "$USERNAME" >/dev/null 2>&1 || true
  fi
else
  echo "[*] User $USERNAME already exists."
fi

# Install Tailscale
if ! command -v tailscale >/dev/null 2>&1; then
  echo "[*] Installing Tailscale..."
  brew install --cask tailscale || brew install tailscale || true
fi

# Start tailscaled
if ! pgrep -x tailscaled >/dev/null 2>&1; then
  echo "[*] Starting tailscaled..."
  nohup tailscaled >/var/log/tailscaled.log 2>&1 &
  sleep 1
fi

TS_HOST="sapna-vm-${GITHUB_RUN_ID}"

echo "[*] Bringing Tailscale up (hostname: $TS_HOST)"
tailscale up \
  --authkey "${TAILSCALE_AUTHKEY}" \
  --hostname "${TS_HOST}" \
  --accept-routes \
  --accept-dns=false || true

TS_IP=$(tailscale ip -4 | head -n1 || true)
echo "[*] Tailscale IPv4: ${TS_IP:-none}"

# Export for GitHub Actions
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "CONNECTION_IP=${TS_IP}" >> "$GITHUB_ENV"
  echo "CONNECTION_TYPE=Tailscale" >> "$GITHUB_ENV"
fi

# Enable VNC (legacy) using PASSWORD (Sapna)
if [[ "$ENABLE_VNC_FLAG" = true ]]; then
  echo "[*] Enabling VNC / Apple Remote Desktop..."
  K="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"

  if [[ -x "$K" ]]; then
    sudo "$K" -configure -allowAccessFor -allUsers -privs -all
    sudo "$K" -configure -clientopts -setvnclegacy -vnclegacy yes

    # Set obfuscated VNC password = $PASSWORD (Sapna)
    echo -n "$PASSWORD" | \
      perl -we 'BEGIN { @k=unpack "C*",pack "H*","1734516E8BA8C5E2FF1C39567390ADCA"} $_=<>;chomp;@p=unpack"C*",substr($_,0,8);foreach(@k){printf"%02X",$_^(shift@p||0)}}' \
      | sudo tee /Library/Preferences/com.apple.VNCSettings.txt >/dev/null

    sudo "$K" -restart -agent -console
    sudo "$K" -activate
    echo "[*] VNC enabled. Username: $USERNAME  Password: $PASSWORD"
  else
    echo "WARNING: ARD kickstart tool not found; cannot enable VNC automatically."
  fi
fi

echo "[*] start.sh complete — Tailscale IP: ${TS_IP:-none}"
