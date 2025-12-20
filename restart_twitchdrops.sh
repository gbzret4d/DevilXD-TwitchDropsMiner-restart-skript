#!/bin/bash
#----------------------------------------------------
# restart_twitchdrops.sh
# Purpose: Updates/Starts Twitch Miner and Firefox on Display :1
# Context: Runs via Systemd Service (Persistent Session)
# Features: Native Firefox, Copy/Paste Fix, Auto-Update
#----------------------------------------------------

set -u

# --- CONFIGURATION ---
USER_HOME="/home/testuser"
PROGRAM_PATH="$USER_HOME/Desktop/devilxd/Twitch Drops Miner/Twitch Drops Miner (by DevilXD)"
DOWNLOAD_DIR="$USER_HOME/Downloads"
# URL for the Linux x64 PyInstaller Build
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
    
    # Cleanup previous runs
    rm -rf "$TMP_DIR" "$ZIP_NAME"
    mkdir -p "$TMP_DIR"
    
    # Download with retry (following redirects)
    if wget -q -L -O "$ZIP_NAME" "$ZIP_URL"; then
        log "Download successful. Extracting..."
        
        if unzip -q -o "$ZIP_NAME" -d "$TMP_DIR"; then
            
            # Handle potential folder structure changes in zip
            if [ -d "$TMP_DIR/Twitch Drops Miner" ]; then
                SOURCE_PATH="$TMP_DIR/Twitch Drops Miner/"
            else
                SOURCE_PATH="$TMP_DIR/"
            fi

            # Sync new files but PRESERVE user settings/cookies
            rsync -a --exclude='cookies.jar' --exclude='settings.json' "$SOURCE_PATH" "$TARGET_DIR/"
            
            # Cleanup
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

setup_clipboard() {
    # Fixes Copy & Paste between Windows/MobaXterm and VNC
    log "Initializing Clipboard (autocutsel)..."
    killall autocutsel 2>/dev/null
    autocutsel -fork
    autocutsel -selection PRIMARY -fork
}

start_firefox() {
    # Check if Firefox is already running
    if pgrep -x "firefox" > /dev/null; then
        log "Firefox is already running."
    else
        log "Starting Firefox..."
        # Starting native Firefox in background
        nohup firefox >> /dev/null 2>&1 &
    fi
}

# --- MAIN EXECUTION ---

# 1. Update the Miner
do_update

# 2. Grant Display Permissions (prevents X11 errors)
xhost +local: >> /dev/null 2>&1 || true

# 3. Fix Copy & Paste
setup_clipboard

# 4. Start Browser (Firefox)
start_firefox

# 5. Start Twitch Miner
log "Starting Twitch Drops Miner on Display $DISPLAY..."

if [ -x "$PROGRAM_PATH" ]; then
    # exec replaces the shell with the miner, so Systemd monitors the miner directly
    exec "$PROGRAM_PATH"
else
    log "CRITICAL ERROR: Program not found or not executable: $PROGRAM_PATH"
    exit 1
fi