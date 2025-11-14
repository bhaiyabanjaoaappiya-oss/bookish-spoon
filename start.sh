#!/usr/bin/env bash
set -euo pipefail

# ❗ As per your demand – don't touch this style
VNC_PASSWORD="${VNC_PASSWORD:-}"

# Your chosen username/password
USERNAME="${USERNAME:-Sapna}"
PASSWORD="${PASSWORD:-Sapna}"

TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
GITHUB_RUN_ID="${GITHUB_RUN_ID:-$(date +%s)}"
ENABLE_VNC_FLAG=true

# Check Tailscale auth key
if [[ -z "$TAILSCALE_AUTHKEY" ]]; then
  echo "ERROR: TAILSCALE_AUTHKEY is missing."
  exit 1
fi

echo "[*] Running as user: $(whoami)"

# ---------------- Homebrew ensure (NO sudo here) ----------------
if ! command -v brew >/dev/null 2>&1; then
  echo "[*] Homebrew not found, trying to install..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
fi
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

# ---------------- Create user Sapna (with sudo) ----------------
if ! id -u "$USERNAME" >/dev/null 2>&1; then
  echo "[*] Creating user: $USERNAME"
  if command -v sysadminctl >/dev/null 2>&1; then
    sudo sysadminctl -addUser "$USERNAME" -fullName "$USERNAME" -password "$PASSWORD" -admin || true
    sudo createhomedir -c -u "$USERNAME" >/dev/null 2>&1 || true
  else
    HOME_DIR="/Users/$USERNAME"
    UID_NEW=$((1000 + RANDOM))
    sudo dscl . -create /Users/"$USERNAME"
    sudo dscl . -create /Users/"$USERNAME" UserShell /bin/bash
    sudo dscl . -create /Users/"$USERNAME" RealName "$USERNAME"
    sudo dscl . -create /Users/"$USERNAME" UniqueID "$UID_NEW"
    sudo dscl . -create /Users/"$USERNAME" PrimaryGroupID 80
    sudo dscl . -create /Users/"$USERNAME" NFSHomeDirectory "$HOME_DIR"
    sudo dscl . -passwd /Users/"$USERNAME" "$PASSWORD"
    sudo createhomedir -c -u "$USERNAME" >/dev/null 2>&1 || true
  fi
else
  echo "[*] User $USERNAME already exists."
fi

# ---------------- Install Tailscale (NO sudo) ----------------
if ! command -v tailscale >/dev/null 2>&1; then
  echo "[*] Installing Tailscale via Homebrew..."
  brew install --cask tailscale || brew install tailscale || {
    echo "ERROR: Failed to install Tailscale. Check Homebrew."
    exit 1
  }
else
  echo "[*] Tailscale already installed."
fi

# ---------------- Start tailscaled (WITH sudo, log to /tmp) ----------------
LOGFILE="/tmp/tailscaled.log"

if ! pgrep -x tailscaled >/dev/null 2>&1; then
  echo "[*] Starting tailscaled (sudo)... (log: $LOGFILE)"
  sudo nohup tailscaled >>"$LOGFILE" 2>&1 &
  sleep 2
else
  echo "[*] tailscaled already running."
fi

TS_HOST="sapna-vm-${GITHUB_RUN_ID}"

echo "[*] Bringing Tailscale up (hostname: $TS_HOST)"
sudo tailscale up \
  --authkey "${TAILSCALE_AUTHKEY}" \
  --hostname "${TS_HOST}" \
  --accept-routes \
  --accept-dns=false || true

TS_IP=$(tailscale ip -4 2>/dev/null | head -n1 || true)
echo "[*] Tailscale IPv4: ${TS_IP:-none}"

# Export for GitHub Actions
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "CONNECTION_IP=${TS_IP}" >> "$GITHUB_ENV"
  echo "CONNECTION_TYPE=Tailscale" >> "$GITHUB_ENV"
fi

# ---------------- Enable VNC (legacy) ----------------
if [[ "$ENABLE_VNC_FLAG" = true ]]; then
  echo "[*] Enabling VNC / Apple Remote Desktop..."
  K="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"

  if [[ -x "$K" ]]; then
    sudo "$K" -configure -allowAccessFor -allUsers -privs -all
    sudo "$K" -configure -clientopts -setvnclegacy -vnclegacy yes

    # ✅ Fixed perl line – obfuscate password for VNC
    echo -n "$PASSWORD" | \
      perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA" } $_ = <>; chomp; @p = unpack "C*", substr($_, 0, 8); foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }' \
      | sudo tee /Library/Preferences/com.apple.VNCSettings.txt >/dev/null

    sudo "$K" -restart -agent -console
    sudo "$K" -activate
    echo "[*] VNC enabled. Username: $USERNAME  Password: $PASSWORD"
  else
    echo "WARNING: ARD kickstart tool not found; cannot enable VNC."
  fi
fi

echo "[*] start.sh completed 🎉 — Tailscale IP: ${TS_IP:-none}"
echo "[*] tailscaled log: $LOGFILE (if needed)"
