#!/bin/bash
#----------------------------------------------------
# Script: restart_twitchdrops.sh
# Purpose: Update and restart Twitch Drops Miner by DevilXD
#          with self-update support from GitHub.
# Usage:
#   ./restart_twitchdrops.sh
# Requirements:
#   - wget, unzip, rsync, sha1sum installed
# Notes:
#   - Runs as current user without hardcoded username.
#   - Assumes Twitch Drops Miner installed at ~/Desktop/devilxd/Twitch Drops Miner
#----------------------------------------------------

set -euo pipefail

# Detect current user and home directory
USER=$(id -un)
USER_HOME=$(eval echo "~$USER")

SCRIPT_NAME=$(basename "$0")

# --- GITHUB URLs ---
GITHUB_REPO_RAW_URL="https://raw.githubusercontent.com/gbzret4d/DevilXD-TwitchDropsMiner-restart-skript/main/$SCRIPT_NAME"
GITHUB_API_LATEST_COMMIT="https://api.github.com/repos/gbzret4d/DevilXD-TwitchDropsMiner-restart-skript/commits/main"

# Paths and URLs
PROGRAM_PATH="$USER_HOME/Desktop/devilxd/Twitch Drops Miner/Twitch Drops Miner (by DevilXD)"
DOWNLOAD_DIR="$USER_HOME/Downloads"
ZIP_URL="https://github.com/DevilXD/TwitchDropsMiner/releases/download/dev-build/Twitch.Drops.Miner.Linux.PyInstaller-x86_64.zip"
ZIP_NAME="$DOWNLOAD_DIR/Twitch.Drops.Miner.Linux.PyInstaller-x86_64.zip"
TMP_EXTRACT_DIR="/tmp/twitchdropsminer_update_tmp"
TARGET_DIR="$USER_HOME/Desktop/devilxd/Twitch Drops Miner"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

self_update() {
  # Calculate local script SHA1
  local_sha=$(sha1sum "$0" | awk '{print $1}')

  # Get latest commit SHA from GitHub API
  remote_sha=$(wget -qO- "$GITHUB_API_LATEST_COMMIT" | grep -m1 '"sha"' | cut -d '"' -f4)

  if [ -z "$remote_sha" ]; then
    log "WARNING: Could not get remote latest commit SHA; skipping self-update."
    return
  fi

  # Download remote script for SHA comparison
  remote_tmp="/tmp/${SCRIPT_NAME}.remote"
  if ! wget -qO "$remote_tmp" "$GITHUB_REPO_RAW_URL"; then
    log "WARNING: Could not download latest script for self-update."
    rm -f "$remote_tmp"
    return
  fi

  remote_file_sha=$(sha1sum "$remote_tmp" | awk '{print $1}')

  if [ "$local_sha" != "$remote_file_sha" ]; then
    log "Newer script version found on GitHub. Updating script..."
    cp "$remote_tmp" "$0"
    chmod +x "$0"
    rm -f "$remote_tmp"
    log "Script updated, restarting..."
    exec "$0" "$@"
    exit 0
  else
    log "Script already up to date."
    rm -f "$remote_tmp"
  fi
}

self_update

log "Starting Twitch Drops Miner update process..."

# Check for required commands
for cmd in wget unzip rsync sha1sum; do
  if ! command -v "$cmd" >/dev/null; then
    log "ERROR: Required command '$cmd' not found. Please install it."
    exit 1
  fi
done

# Stop running Twitch Drops Miner processes gracefully
log "Stopping running Twitch Drops Miner processes..."
pids=$(pgrep -f "Twitch Drops Mi" || true)

if [ -n "$pids" ]; then
  for pid in $pids; do
    kill "$pid" && log "Sent SIGTERM to process $pid." || {
      log "Failed SIGTERM, trying SIGKILL on process $pid."
      kill -9 "$pid" || log "Failed killing process $pid."
    }
  done

  # Wait up to 10 seconds for processes to exit
  for i in $(seq 1 10); do
    if ! pgrep -f "Twitch Drops Mi" >/dev/null; then
      log "All Twitch Drops Miner processes terminated."
      break
    fi
    sleep 1
  done

  if pgrep -f "Twitch Drops Mi" >/dev/null; then
    log "Processes still alive after SIGTERM, applying SIGKILL."
    pkill -9 -f "Twitch Drops Mi"
  fi
else
  log "No Twitch Drops Miner processes found."
fi

# Prepare temporary directory for extraction
log "Creating temporary directory: $TMP_EXTRACT_DIR"
rm -rf "$TMP_EXTRACT_DIR"
mkdir -p "$TMP_EXTRACT_DIR"

# Download latest Twitch Drops Miner ZIP archive
log "Downloading latest Twitch Drops Miner release..."
wget -O "$ZIP_NAME" "$ZIP_URL" || { log "ERROR: Download failed!"; exit 1; }

# Extract archive to temporary directory
log "Unpacking archive..."
unzip -q "$ZIP_NAME" -d "$TMP_EXTRACT_DIR" || { log "ERROR: Unzip failed!"; exit 1; }

# Backup existing installation files (except cookies.jat & settings.json)
BACKUP_DIR="$TARGET_DIR/backup_$(date '+%Y%m%d_%H%M%S')"
log "Backing up existing files to $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
rsync -a --exclude='cookies.jat' --exclude='settings.json' "$TARGET_DIR/" "$BACKUP_DIR/"

# Copy new files into target directory excluding cookies/settings
log "Copying new files to $TARGET_DIR"
rsync -a --exclude='cookies.jat' --exclude='settings.json' "$TMP_EXTRACT_DIR/Twitch Drops Miner/" "$TARGET_DIR/"

# Clean up
log "Cleaning up temporary files and downloads..."
rm -rf "$TMP_EXTRACT_DIR"
rm -f "$ZIP_NAME"

# Determine DISPLAY and XAUTHORITY for starting GUI app
DISPLAY=$(pgrep -u "$USER" -a | grep -o 'DISPLAY=:[0-9]\+' | head -n1 | cut -d= -f2 || true)
if [ -z "$DISPLAY" ]; then
  pid_xorg=$(pgrep -u "$USER" Xorg | head -n1 || true)
  if [ -n "$pid_xorg" ]; then
    DISPLAY=$(tr '\0' '\n' < /proc/"$pid_xorg"/environ | grep "^DISPLAY=" | cut -d= -f2 || true)
  fi
fi
DISPLAY=${DISPLAY:-:12}

XAUTHORITY="$USER_HOME/.Xauthority"
if [ ! -f "$XAUTHORITY" ]; then
  log "WARNING: XAUTHORITY file not found ($XAUTHORITY)"
fi

export DISPLAY
export XAUTHORITY

log "Starting Twitch Drops Miner with DISPLAY=$DISPLAY and XAUTHORITY=$XAUTHORITY"

if [ ! -x "$PROGRAM_PATH" ]; then
  log "ERROR: Program executable not found or not executable: $PROGRAM_PATH"
  exit 1
fi

nohup "$PROGRAM_PATH" >> "$TARGET_DIR/twitchdropsminer.log" 2>&1 &

log "Update and restart process complete."
