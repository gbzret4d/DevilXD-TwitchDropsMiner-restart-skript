#!/bin/bash
#----------------------------------------------------
# restart_twitchdrops.sh
# Purpose: Master Controller & Script Configurator
# Features: Script GUI, Auto-Update, Backups, Log-Rotation
# Language: English
# Fix: Verbose Logging enabled to debug update issues
#----------------------------------------------------

set -u

# --- PATHS & VARIABLES ---
USER_HOME="/home/testuser"
SCRIPT_CONFIG="$USER_HOME/.config/twitch-script.conf"
SERVICE_FILE="/etc/systemd/system/twitchminer.service"
BACKUP_DIR="$USER_HOME/Backups"

# Miner Paths
MINER_DIR="$USER_HOME/Desktop/devilxd/Twitch Drops Miner"
MINER_EXEC="$MINER_DIR/Twitch Drops Miner (by DevilXD)"
MINER_LOG="$MINER_DIR/twitchdropsminer.log"

# Update Settings
DOWNLOAD_DIR="$USER_HOME/Downloads"
ZIP_URL="https://github.com/DevilXD/TwitchDropsMiner/releases/download/dev-build/Twitch.Drops.Miner.Linux.PyInstaller-x86_64.zip"
ZIP_NAME="$DOWNLOAD_DIR/update.zip"
TMP_DIR="/tmp/twitch_update"
TARGET_DIR="$MINER_DIR"

# Firefox
FIREFOX_ROOT="$USER_HOME/.mozilla/firefox-trunk"

export DISPLAY=:1
export PATH="/usr/local/bin:/usr/bin:/bin"

# --- LOG-ROTATION ---
if [ -f "$MINER_LOG" ]; then
    if [ $(stat -c%s "$MINER_LOG") -ge 5000000 ]; then
        mv "$MINER_LOG" "$MINER_LOG.old"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log rotated." > "$MINER_LOG"
    fi
fi

# --- LOAD CONFIGURATION ---
VNC_RES="1600x900"
ENABLE_UPDATE="true"

# Load config if exists
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

task_backup() {
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    log "Creating backup..."
    
    if [ -d "$MINER_DIR" ]; then
        tar -czf "$BACKUP_DIR/miner_cfg_$TIMESTAMP.tar.gz" -C "$MINER_DIR" "settings.json" "cookies.jar" 2>/dev/null
        find "$BACKUP_DIR" -name "miner_cfg_*.tar.gz" -mtime +7 -delete
        log "Backup saved to $BACKUP_DIR"
    fi
}

task_check_vnc() {
    if [ -e /tmp/.X11-unix/X1 ]; then
        log "VNC Session :1 found. Resuming..."
    else
        log "VNC Session :1 not found. Starting ($VNC_RES)..."
        rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
        vncserver :1 -geometry "$VNC_RES" -depth 24
    fi
}

task_update() {
    # Check Config Setting
    if [ "$ENABLE_UPDATE" != "true" ]; then
        log "WARNING: Auto-Update is DISABLED in config ($SCRIPT_CONFIG). Skipping."
        return
    fi

    log "Checking for updates..."
    rm -rf "$TMP_DIR" "$ZIP_NAME"
    mkdir -p "$TMP_DIR"
    
    # Removed -q (quiet) to see errors in log if download fails
    log "Downloading from GitHub..."
    if wget -nv -L -O "$ZIP_NAME" "$ZIP_URL" >> "$MINER_LOG" 2>&1; then
        log "Download finished. Extracting..."
        if unzip -q -o "$ZIP_NAME" -d "$TMP_DIR"; then
            if [ -d "$TMP_DIR/Twitch Drops Miner" ]; then
                SOURCE_PATH="$TMP_DIR/Twitch Drops Miner/"
            else
                SOURCE_PATH="$TMP_DIR/"
            fi
            
            task_backup
            
            # Sync files
            rsync -a --exclude='cookies.jar' --exclude='settings.json' "$SOURCE_PATH" "$TARGET_DIR/"
            
            # Fix Permissions explicitly
            chmod +x "$MINER_EXEC"
            
            rm -f "$ZIP_NAME"
            rm -rf "$TMP_DIR"
            log "Update successful."
        else
            log "ERROR: Unzip failed. Is 'unzip' installed?"
        fi
    else
        log "ERROR: Download failed. Check internet or GitHub URL."
    fi
}

task_start_firefox() {
    if pgrep -f "firefox-trunk" > /dev/null; then
        log "Firefox Nightly is already running. Skipping start."
    else
        PROFILE_DIR=$(find "$FIREFOX_ROOT" -maxdepth 1 -type d -name "*.default" | head -n 1)
        if [ -n "$PROFILE_DIR" ]; then
            log "Starting Firefox Nightly..."
            nohup firefox-trunk -profile "$PROFILE_DIR" >> /dev/null 2>&1 &
        else
            log "Starting Firefox Nightly (Generic)..."
            nohup firefox-trunk >> /dev/null 2>&1 &
        fi
    fi
}

task_start_miner() {
    log "Starting Twitch Drops Miner..."
    if [ -x "$MINER_EXEC" ]; then
        nohup "$MINER_EXEC" >> "$MINER_LOG" 2>&1 &
        log "Miner started."
    else
        log "ERROR: Miner executable not found at: $MINER_EXEC"
        exit 1
    fi
}

# --- GUI / SETTINGS MENU ---

menu_systemd_timer() {
    CURRENT_VAL=$(grep "RuntimeMaxSec=" "$SERVICE_FILE" | cut -d= -f2)
    [ -z "$CURRENT_VAL" ] && CURRENT_VAL="Not Set"
    
    NEW_VAL=$(whiptail --title "Systemd Restart Interval" --inputbox \
    "Current Value: $CURRENT_VAL\n\nEnter restart interval (e.g. 2h). This is REQUIRED for auto-updates!" \
    12 60 "$CURRENT_VAL" 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ]; then
        if (whiptail --title "Sudo Required" --yesno "Update systemd service file?" 8 60); then
            # If line exists, replace it. If not, append it to [Service] section.
            if grep -q "RuntimeMaxSec=" "$SERVICE_FILE"; then
                sudo sed -i "s/^RuntimeMaxSec=.*/RuntimeMaxSec=$NEW_VAL/" "$SERVICE_FILE"
            else
                # Insert after [Service]
                sudo sed -i "/\[Service\]/a RuntimeMaxSec=$NEW_VAL" "$SERVICE_FILE"
            fi
            sudo systemctl daemon-reload
            whiptail --title "Success" --msgbox "Interval set to $NEW_VAL.\nRestart required to activate timer." 8 60
        fi
    fi
}

menu_resolution() {
    NEW_RES=$(whiptail --title "VNC Resolution" --menu "Select Resolution" 15 60 5 \
    "1280x720" "720p" "1600x900" "900p" "1920x1080" "1080p" 3>&1 1>&2 2>&3)
    if [ $? -eq 0 ]; then
        VNC_RES="$NEW_RES"
        save_config
        whiptail --msgbox "Resolution saved." 8 60
    fi
}

menu_toggle_update() {
    [ "$ENABLE_UPDATE" == "true" ] && ENABLE_UPDATE="false" || ENABLE_UPDATE="true"
    save_config
    whiptail --msgbox "Auto-Update is now: $ENABLE_UPDATE" 8 40
}

show_main_menu() {
    while true; do
        CHOICE=$(whiptail --title "Twitch Miner Control" --menu "Status: Update=$ENABLE_UPDATE" 18 75 7 \
        "1" "TRIGGER SYSTEMD (Start & Keep Timer)" \
        "2" "Manual Backup" \
        "3" "Config: Restart Timer" \
        "4" "Config: Resolution ($VNC_RES)" \
        "5" "Config: Toggle Update" \
        "6" "View Logs" \
        "7" "Exit" 3>&1 1>&2 2>&3)

        case $CHOICE in
            1) 
                # NEUE LOGIK: Wir starten nicht manuell, sondern zwingen Systemd zum Neustart
                clear
                if (whiptail --title "Restart Service" --yesno "This will restart the background service immediately.\n\n- Updates will run\n- Timer will reset (2h)\n- Automation stays ACTIVE\n\nProceed?" 12 60); then
                    echo "Restarting twitchminer.service..."
                    # Hier passiert die Magie: Systemd wird neu gestartet
                    if sudo systemctl restart twitchminer.service; then
                        whiptail --title "Success" --msgbox "Service restarted successfully!\n\nThe miner is now running in the background via Systemd.\nThe 2h timer is active." 10 60
                    else
                        whiptail --title "Error" --msgbox "Failed to restart service. Check sudo permissions." 8 40
                    fi
                fi
                break 
                ;;
            2) task_backup; whiptail --msgbox "Backup created!" 8 40 ;;
            3) menu_systemd_timer ;;
            4) menu_resolution ;;
            5) menu_toggle_update ;;
            6) clear; tail -f "$MINER_LOG" ;;
            7) break ;;
            *) break ;;
        esac
    done
}

# --- MAIN ---

if [ "${IS_SYSTEMD_SERVICE:-}" == "true" ]; then
    task_update
    task_check_vnc
    xhost +local: >> /dev/null 2>&1 || true
    killall autocutsel 2>/dev/null; autocutsel -fork; autocutsel -selection PRIMARY -fork
    task_start_firefox
    exec "$MINER_EXEC"
else
    show_main_menu
fi