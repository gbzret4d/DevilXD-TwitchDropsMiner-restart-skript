#!/bin/bash
#----------------------------------------------------
# restart_twitchdrops.sh
# Purpose: Updates/Starts Twitch Miner and Firefox Nightly on Display :1
# Feature: Auto-detects Profile & Resumes existing VNC session
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

export DISPLAY=:1
export PATH="/usr/local/bin:/usr/bin:/bin"

# --- FUNCTIONS ---

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

check_vnc() {
    # Check if VNC Lockfile for Display :1 exists
    if [ -e /tmp/.X11-unix/X1 ]; then
        echo ">> VNC Session :1 is already running. Using it. <<"
    else
        echo ">> VNC Session :1 not found. Starting it... <<"
        # Clean up potential dead locks
        rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
        vncserver :1 -geometry 1600x900 -depth 24
    fi
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
    # Only restart autocutsel if VNC is running
    log "Refreshing Clipboard (autocutsel)..."
    killall autocutsel 2>/dev/null
    autocutsel -fork
    autocutsel -selection PRIMARY -fork
}

start_firefox() {
    # 1. Check if Firefox is running
    if pgrep -f "firefox-trunk" > /dev/null; then
        log "Firefox Nightly is already running. Leaving it alone."
    else
        # 2. Dynamic Profile Detection
        # Finds the first directory ending in .default inside the firefox-trunk folder
        # This automatically picks 'cl9wal0s.default' and ignores 'knpmkjww.default-beta'
        PROFILE_DIR=$(find "$USER_HOME/.mozilla/firefox-trunk" -maxdepth 1 -type d -name "*.default" | head -n 1)

        if [ -n "$PROFILE_DIR" ]; then
            log "Starting Firefox Nightly with auto-detected profile: $PROFILE_DIR"
            nohup firefox-trunk -profile "$PROFILE_DIR" >> /dev/null 2>&1 &
        else
            log "WARNING: No .default profile found! Starting Firefox without specific profile..."
            nohup firefox-trunk >> /dev/null 2>&1 &
        fi
    fi
}

# --- MAIN EXECUTION ---

# 1. Smart VNC Handling (Only important if started manually)
if [ -z "${IS_SYSTEMD_SERVICE:-}" ]; then
    # Manual Mode: Check/Start VNC, but don't kill it if it runs.
    check_vnc
fi

# 2. Update logic
do_update

# 3. Permissions & Clipboard
xhost +local: >> /dev/null 2>&1 || true
setup_clipboard

# 4. Start Browser
start_firefox

# 5. Start Miner
log "Starting Twitch Drops Miner on Display $DISPLAY..."

if [ -x "$PROGRAM_PATH" ]; then
    exec "$PROGRAM_PATH"
else
    log "CRITICAL ERROR: Program not found: $PROGRAM_PATH"
    exit 1
fi