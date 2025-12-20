#!/bin/bash
#----------------------------------------------------
# restart_twitchdrops.sh
# Purpose: Updates/Starts Twitch Miner and Chrome on Display :1
# Context: Runs via Systemd Service (Persistent Session)
#----------------------------------------------------

set -u

# --- CONFIGURATION ---
USER_HOME="/home/testuser"
PROGRAM_PATH="$USER_HOME/Desktop/devilxd/Twitch Drops Miner/Twitch Drops Miner (by DevilXD)"
DOWNLOAD_DIR="$USER_HOME/Downloads"
ZIP_URL="https://github.com/DevilXD/TwitchDropsMiner/releases/download/dev-build/Twitch.Drops.Miner.Linux.PyInstaller-x86_64.zip"
ZIP_NAME="$DOWNLOAD_DIR/update.zip"
TMP_DIR="/tmp/twitch_update"
TARGET_DIR="$USER_HOME/Desktop/devilxd/Twitch Drops Miner"
LOG_FILE="$TARGET_DIR/twitchdropsminer.log"

# IMPORTANT: Force Display :1 (Persistent VNC Session)
export DISPLAY=:1
export PATH="/usr/local/bin:/usr/bin:/bin"

# --- FUNCTIONS ---

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

do_update() {
    log "Checking for updates..."
    rm -rf "$TMP_DIR" "$ZIP_NAME"
    mkdir -p "$TMP_DIR"
    
    if wget -q -L -O "$ZIP_NAME" "$ZIP_URL"; then
        log "Download successful. Extracting..."
        if unzip -q -o "$ZIP_NAME" -d "$TMP_DIR"; then
            log "Extraction successful. Installing..."
            
            if [ -d "$TMP_DIR/Twitch Drops Miner" ]; then
                SOURCE_PATH="$TMP_DIR/Twitch Drops Miner/"
            else
                SOURCE_PATH="$TMP_DIR/"
            fi

            rsync -a --exclude='cookies.jar' --exclude='settings.json' "$SOURCE_PATH" "$TARGET_DIR/"
            
            rm -f "$ZIP_NAME"
            rm -rf "$TMP_DIR"
            chmod +x "$PROGRAM_PATH"
            log "Update completed successfully."
        else
            log "ERROR: Unzip failed. Skipping update."
        fi
    else
        log "ERROR: Download failed. Starting existing version."
    fi
}

start_browser() {
    # Check if Chrome is already running
    if pgrep -f "chrome" > /dev/null; then
        log "Browser (Chrome) is already running."
    else
        log "Starting Google Chrome..."
        # --no-sandbox is important for stability in VNC/Systemd environments
        # --start-maximized ensures it covers the screen
        nohup google-chrome --no-sandbox --start-maximized >> /dev/null 2>&1 &
    fi
}

# --- MAIN EXECUTION ---

# 1. Update Miner
do_update

# 2. Grant Display Permissions
xhost +local: >> /dev/null 2>&1 || true

# 3. Start Browser (Chrome)
start_browser

# 4. Start Twitch Miner
log "Starting Twitch Drops Miner on Display $DISPLAY..."

if [ -x "$PROGRAM_PATH" ]; then
    exec "$PROGRAM_PATH"
else
    log "CRITICAL ERROR: Program not found or not executable: $PROGRAM_PATH"
    exit 1
fi