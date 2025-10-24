#!/bin/bash
#----------------------------------------------------
# Script: update_twitchdropsminer.sh
# Purpose: Download and update Twitch Drops Miner,
#          safely terminate existing processes,
#          restart the program,
#          & self-update from GitHub repo.
# Usage:
#   ./update_twitchdropsminer.sh
# Requirements:
#   - wget, unzip, rsync installed
# Note:
#   Runs actions for the user executing the script,
#   no hardcoded usernames.
#----------------------------------------------------

set -euo pipefail

# Automatically detect current user and home directory
USER=$(id -un)
USER_HOME=$(eval echo "~$USER")

SCRIPT_NAME=$(basename "$0")

GITHUB_REPO_RAW_URL="https://raw.githubusercontent.com/deinuser/twitchdropsminer-update/main/$SCRIPT_NAME"
GITHUB_API_LATEST_COMMIT="https://api.github.com/repos/deinuser/twitchdropsminer-update/commits/main"

PROGRAM_PATH="$USER_HOME/Desktop/devilxd/Twitch Drops Miner/Twitch Drops Miner (by DevilXD)"
DOWNLOAD_DIR="$USER_HOME/Downloads"
ZIP_URL="https://github.com/DevilXD/TwitchDropsMiner/releases/download/dev-build/Twitch.Drops.Miner.Linux.PyInstaller-x86_64.zip"
ZIP_NAME="$DOWNLOAD_DIR/Twitch.Drops.Miner.Linux.PyInstaller-x86_64.zip"
TMP_EXTRACT_DIR="/tmp/twitchdropsminer_update_tmp"
TARGET_DIR="$USER_HOME/Desktop/devilxd/Twitch Drops Miner"
BACKUP_DIR=""

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

self_update() {
  # 1. Check latest commit SHA on GitHub
  local local_sha remote_sha

  # Get local SHA of this script content
  local_sha=$(sha1sum "$0" | awk '{print $1}')

  # Get remote latest commit SHA from GitHub API
  remote_sha=$(wget -qO- "$GITHUB_API_LATEST_COMMIT" | grep -m1 '"sha"' | head -n1 | cut -d '"' -f4)

  if [ -z "$remote_sha" ]; then
    log "WARNING: Could not determine remote latest commit SHA, skipping self-update."
    return
  fi

  # Download remote script to temp file for SHA comparison
  local remote_tmp="/tmp/${SCRIPT_NAME}.remote"
  if ! wget -qO "$remote_tmp" "$GITHUB_REPO_RAW_URL"; then
    log "WARNING: Could not download latest script for self-update."
    rm -f "$remote_tmp"
    return
  fi

  local remote_file_sha=$(sha1sum "$remote_tmp" | awk '{print $1}')

  if [ "$local_sha" != "$remote_file_sha" ]; then
    log "Newer script version available on GitHub. Updating..."
    cp "$remote_tmp" "$0"
    chmod +x "$0"
    rm -f "$remote_tmp"
    log "Script updated – restarting..."
    exec "$0" "$@"
    exit 0
  else
    log "Script already up-to-date."
    rm -f "$remote_tmp"
  fi
}

self_update

log "Starting update process..."

# Check presence of required commands: wget, unzip, rsync, sha1sum
for cmd in wget unzip rsync sha1sum; do
  if ! command -v "$cmd" >/dev/null; then
    log "ERROR: Required command '$cmd' not found! Please install it."
    exit 1
  fi
done

# Gracefully stop Twitch Drops Miner processes
log "Stopping old Twitch Drops Miner processes..."

pids=$(pgrep -f "Twitch Drops Mi" || true)
if [ -n "$pids" ]; then
  for pid in $pids; do
    if kill "$pid"; then
      log "Sent SIGTERM to process $pid."
    else
      log "Warning: Could not send SIGTERM to process $pid, trying SIGKILL."
      kill -9 "$pid" || log "Failed to kill process $pid"
    fi
  done

  # Wait up to 10 seconds for processes to exit
  timeout=10
  for i in $(seq 1 $timeout); do
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
  log "No running Twitch Drops Miner processes found."
fi

# Prepare temporary directory in /tmp
log "Preparing temporary directory in /tmp..."
rm -rf "$TMP_EXTRACT_DIR"
mkdir -p "$TMP_EXTRACT_DIR"

log "Downloading archive..."
wget -O "$ZIP_NAME" "$ZIP_URL" || { log "Download failed!"; exit 1; }

log "Unpacking archive..."
unzip -q "$ZIP_NAME" -d "$TMP_EXTRACT_DIR" || { log "Unzip failed!"; exit 1; }

log "Backing up existing files before update..."
BACKUP_DIR="$TARGET_DIR/backup_$(date '+%Y%m%d_%H%M%S')"
mkdir -p "$BACKUP_DIR"
rsync -a --exclude='cookies.jat' --exclude='settings.json' "$TARGET_DIR/" "$BACKUP_DIR/"

log "Copying new files..."
rsync -a --exclude='cookies.jat' --exclude='settings.json' "$TMP_EXTRACT_DIR/Twitch Drops Miner/" "$TARGET_DIR/"

log "Cleaning up temporary files..."
rm -rf "$TMP_EXTRACT_DIR"
rm -f "$ZIP_NAME"

# Determine DISPLAY environment variable for starting the program GUI
DISPLAY=$(pgrep -u "$USER" -a | grep -o 'DISPLAY=:[0-9]\+' | head -n1 | cut -d= -f2 || true)
if [ -z "$DISPLAY" ]; then
  pid_xorg=$(pgrep -u "$USER" Xorg | head -n1 || true)
  if [ -n "$pid_xorg" ]; then
    DISPLAY=$(tr '\0' '\n' < /proc/${pid_xorg}/environ | grep "^DISPLAY=" | cut -d= -f2 || true)
  fi
fi
DISPLAY=${DISPLAY:-:12}

XAUTHORITY="$USER_HOME/.Xauthority"

if [ ! -f "$XAUTHORITY" ]; then
  log "Warning: XAUTHORITY file not found at $XAUTHORITY"
fi

export DISPLAY
export XAUTHORITY

log "Using DISPLAY=$DISPLAY"
log "Using XAUTHORITY=$XAUTHORITY"

if [ ! -x "$PROGRAM_PATH" ]; then
  log "ERROR: Program is not executable: $PROGRAM_PATH"
  exit 1
fi

log "Starting Twitch Drops Miner..."
nohup "$PROGRAM_PATH" >> "$TARGET_DIR/twitchdropsminer.log" 2>&1 &

log "Update and restart complete."
