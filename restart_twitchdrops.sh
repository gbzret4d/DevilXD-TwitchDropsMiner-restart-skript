#!/bin/bash
#----------------------------------------------------
# restart_twitchdrops.sh
# Purpose: Master Controller & Script Configurator
# Features: Script GUI Settings (Resolution, Timer, Updates)
# Language: English
#----------------------------------------------------

set -u

# --- PATHS & VARIABLES ---
USER_HOME="/home/testuser"
SCRIPT_CONFIG="$USER_HOME/.config/twitch-script.conf"
SERVICE_FILE="/etc/systemd/system/twitchminer.service"

# Miner Paths
MINER_DIR="$USER_HOME/Desktop/devilxd/Twitch Drops Miner/Twitch Drops Miner (by DevilXD)"
MINER_EXEC="$MINER_DIR/Twitch Drops Miner (by DevilXD)"
MINER_LOG="$USER_HOME/Desktop/devilxd/Twitch Drops Miner/twitchdropsminer.log"

# Update Settings
DOWNLOAD_DIR="$USER_HOME/Downloads"
ZIP_URL="https://github.com/DevilXD/TwitchDropsMiner/releases/download/dev-build/Twitch.Drops.Miner.Linux.PyInstaller-x86_64.zip"
ZIP_NAME="$DOWNLOAD_DIR/update.zip"
TMP_DIR="/tmp/twitch_update"

# Firefox
FIREFOX_ROOT="$USER_HOME/.mozilla/firefox-trunk"

export DISPLAY=:1
export PATH="/usr/local/bin:/usr/bin:/bin"

# --- LOAD CONFIGURATION ---
# Default values if config doesn't exist
VNC_RES="1600x900"
ENABLE_UPDATE="true"

if [ -f "$SCRIPT_CONFIG" ]; then
    source "$SCRIPT_CONFIG"
fi

# --- CORE FUNCTIONS ---

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$MINER_LOG"
}

save_config() {
    mkdir -p "$(dirname "$SCRIPT_CONFIG")"
    echo "VNC_RES=\"$VNC_RES\"" > "$SCRIPT_CONFIG"
    echo "ENABLE_UPDATE=\"$ENABLE_UPDATE\"" >> "$SCRIPT_CONFIG"
}

task_check_vnc() {
    if [ -e /tmp/.X11-unix/X1 ]; then
        log "VNC Session :1 found. Resuming..."
    else
        log "VNC Session :1 not found. Starting with resolution $VNC_RES..."
        rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
        vncserver :1 -geometry "$VNC_RES" -depth 24
    fi
}

task_update() {
    if [ "$ENABLE_UPDATE" != "true" ]; then
        log "Auto-Update is DISABLED in script settings. Skipping."
        return
    fi

    log "Checking for updates..."
    rm -rf "$TMP_DIR" "$ZIP_NAME"
    mkdir -p "$TMP_DIR"
    
    if wget -q -L -O "$ZIP_NAME" "$ZIP_URL"; then
        if unzip -q -o "$ZIP_NAME" -d "$TMP_DIR"; then
            # Handle folder structure
            if [ -d "$TMP_DIR/Twitch Drops Miner" ]; then
                SOURCE_PATH="$TMP_DIR/Twitch Drops Miner/"
            else
                SOURCE_PATH="$TMP_DIR/"
            fi
            # Update files but protect settings
            rsync -a --exclude='cookies.jar' --exclude='settings.json' "$SOURCE_PATH" "$MINER_DIR/"
            rm -f "$ZIP_NAME"
            rm -rf "$TMP_DIR"
            chmod +x "$MINER_EXEC"
            log "Update successful."
        else
            log "ERROR: Unzip failed."
        fi
    else
        log "ERROR: Download failed."
    fi
}

task_start_firefox() {
    # CHECK: Is it already running?
    if pgrep -f "firefox-trunk" > /dev/null; then
        log "Firefox Nightly is already running. Skipping start."
    else
        # Auto-detect profile ending in .default
        PROFILE_DIR=$(find "$FIREFOX_ROOT" -maxdepth 1 -type d -name "*.default" | head -n 1)

        if [ -n "$PROFILE_DIR" ]; then
            log "Starting Firefox Nightly (Profile: $(basename "$PROFILE_DIR"))..."
            nohup firefox-trunk -profile "$PROFILE_DIR" >> /dev/null 2>&1 &
        else
            log "WARNING: No .default profile found. Starting generic..."
            nohup firefox-trunk >> /dev/null 2>&1 &
        fi
    fi
}

task_start_miner() {
    log "Starting Twitch Drops Miner..."
    if [ -x "$MINER_EXEC" ]; then
        exec "$MINER_EXEC"
    else
        log "ERROR: Miner executable not found!"
        exit 1
    fi
}

# --- GUI / SETTINGS MENU ---

menu_systemd_timer() {
    CURRENT_VAL=$(grep "RuntimeMaxSec=" "$SERVICE_FILE" | cut -d= -f2)
    NEW_VAL=$(whiptail --title "Systemd Restart Interval" --inputbox \
    "The server automatically restarts the service after this time.\n\nCurrent Value: $CURRENT_VAL\nExamples: 2h, 6h, 1d, infinity (disabled)" \
    12 60 "$CURRENT_VAL" 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ]; then
        if (whiptail --title "Sudo Required" --yesno "Changing system files requires Root privileges.\nProceed with sudo?" 8 60); then
            sudo sed -i "s/^RuntimeMaxSec=.*/RuntimeMaxSec=$NEW_VAL/" "$SERVICE_FILE"
            sudo systemctl daemon-reload
            whiptail --title "Success" --msgbox "Interval changed to $NEW_VAL.\nWill take effect after the next service restart." 8 60
        fi
    fi
}

menu_resolution() {
    NEW_RES=$(whiptail --title "VNC Resolution" --menu "Select Screen Resolution for Display :1" 15 60 5 \
    "1280x720" "720p (Low RAM)" \
    "1600x900" "900p (Standard)" \
    "1920x1080" "1080p (FHD)" \
    "1024x768" "Old School" 3>&1 1>&2 2>&3)

    if [ $? -eq 0 ]; then
        VNC_RES="$NEW_RES"
        save_config
        whiptail --title "Saved" --msgbox "Resolution set to $VNC_RES.\nRestart the server/service to apply." 8 60
    fi
}

menu_toggle_update() {
    if [ "$ENABLE_UPDATE" == "true" ]; then
        if (whiptail --title "Auto-Update" --yesno "Auto-Update is currently ENABLED.\nDisable it?" 8 60); then
            ENABLE_UPDATE="false"
        fi
    else
        if (whiptail --title "Auto-Update" --yesno "Auto-Update is currently DISABLED.\nEnable it?" 8 60); then
            ENABLE_UPDATE="true"
        fi
    fi
    save_config
}

show_main_menu() {
    while true; do
        CHOICE=$(whiptail --title "Script Configuration & Control" --menu "Select an option:" 16 70 6 \
        "1" "START NOW (Run Automation)" \
        "2" "Config: Restart Interval (Systemd)" \
        "3" "Config: VNC Resolution ($VNC_RES)" \
        "4" "Config: Auto-Update ($ENABLE_UPDATE)" \
        "5" "View Live Logs" \
        "6" "Exit" 3>&1 1>&2 2>&3)

        case $CHOICE in
            1) 
                clear; 
                task_check_vnc
                xhost +local: >> /dev/null 2>&1 || true
                killall autocutsel 2>/dev/null; autocutsel -fork; autocutsel -selection PRIMARY -fork
                task_start_firefox
                task_start_miner
                break 
                ;;
            2) menu_systemd_timer ;;
            3) menu_resolution ;;
            4) menu_toggle_update ;;
            5) clear; echo "Press CTRL+C to exit logs..."; tail -f "$MINER_LOG"; ;;
            6) break ;;
            *) break ;;
        esac
    done
}

# --- MAIN EXECUTION ---

# If running via Systemd (Environment variable set) -> Run automated tasks
if [ "${IS_SYSTEMD_SERVICE:-}" == "true" ]; then
    task_update
    task_check_vnc
    xhost +local: >> /dev/null 2>&1 || true
    killall autocutsel 2>/dev/null; autocutsel -fork; autocutsel -selection PRIMARY -fork
    task_start_firefox
    task_start_miner
else
    # If running manually -> Show GUI
    show_main_menu
fi