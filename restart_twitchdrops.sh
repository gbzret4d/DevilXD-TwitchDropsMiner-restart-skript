#!/bin/bash
#----------------------------------------------------
# restart_twitchdrops.sh
# Purpose: Updates/Starts Twitch Miner and Firefox Nightly on Display :1
# Context: Handles MANUAL start and SYSTEMD service start.
# Fixes: Forces 'default' profile to keep settings/addons.
#----------------------------------------------------

set -u

# --- MANUAL START DETECTION ---
if [ -z "${IS_SYSTEMD_SERVICE:-}" ]; then
    echo ">> MANUAL START DETECTED <<"
    echo "Stopping background service (requires sudo)..."
    sudo systemctl stop twitchminer.service
    
    echo "Resetting VNC Session :1..."
    vncserver -kill :1 > /dev/null 2>&1
    rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
    
    echo "Starting VNC Server..."
    vncserver :1 -geometry 1600x900 -depth 24
    echo ">> Manual environment ready. <<"
fi

# --- CONFIGURATION ---
USER_HOME="/home/testuser"
PROGRAM_PATH="$USER_HOME/Desktop/devilxd/Twitch Drops Miner/Twitch Drops Miner (by DevilXD)"
DOWNLOAD_DIR="$USER_HOME/Downloads"
ZIP_URL="https://github.com/DevilXD/TwitchDropsMiner/releases/download/dev-build/Twitch.Drops.Miner.Linux.PyInstaller-x86_64.zip"
ZIP_NAME="$DOWNLOAD_DIR/update.zip"
TMP_DIR="/tmp/twitch_update"
TARGET_DIR="$USER_HOME/Desktop/devilxd/Twitch Drops Miner"
LOG_FILE="$TARGET_DIR/twitchdropsminer.log"

# PROFILE NAME: Change 'default' if your profile has a different name in Profile Manager
FIREFOX_PROFILE="default"

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
            log "ERROR: Unzip failed."
        fi
    else
        log "ERROR: Download failed."
    fi
}

setup_clipboard() {
    log "Initializing Clipboard (autocutsel)..."
    killall autocutsel 2>/dev/null
    autocutsel -fork
    autocutsel -selection PRIMARY -fork
}

start_firefox() {
    # Check if Firefox Nightly is already running
    if pgrep -f "firefox-trunk" > /dev/null; then
        log "Firefox Nightly is already running. Assuming it is on Display :1."
        log "NOTE: If you cannot see Firefox, run 'pkill -f firefox' manually to reset it."
    else
        log "Starting Firefox Nightly with profile '$FIREFOX_PROFILE'..."
        # -P forces the profile. -no-remote allows multiple instances if needed (but we avoid that here)
        nohup firefox-trunk -P "$FIREFOX_PROFILE" >> /dev/null 2>&1 &
    fi
}

# --- MAIN EXECUTION ---

do_update
xhost +local: >> /dev/null 2>&1 || true
setup_clipboard
start_firefox

log "Starting Twitch Drops Miner on Display $DISPLAY..."

if [ -x "$PROGRAM_PATH" ]; then
    exec "$PROGRAM_PATH"
else
    log "CRITICAL ERROR: Program not found: $PROGRAM_PATH"
    exit 1
fi