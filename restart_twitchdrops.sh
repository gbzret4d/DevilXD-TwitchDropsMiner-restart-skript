#!/bin/bash
#----------------------------------------------------
# run_twitch_miner.sh
# Läuft stabil als Systemd Service auf Display :1
#----------------------------------------------------

set -u

# --- KONFIGURATION ---
USER_HOME="/home/testuser"
PROGRAM_PATH="$USER_HOME/Desktop/devilxd/Twitch Drops Miner/Twitch Drops Miner (by DevilXD)"
DOWNLOAD_DIR="$USER_HOME/Downloads"
ZIP_URL="https://github.com/DevilXD/TwitchDropsMiner/releases/download/dev-build/Twitch.Drops.Miner.Linux.PyInstaller-x86_64.zip"
ZIP_NAME="$DOWNLOAD_DIR/update.zip"
TMP_DIR="/tmp/twitch_update"
TARGET_DIR="$USER_HOME/Desktop/devilxd/Twitch Drops Miner"

# WICHTIG: Wir zwingen das Display auf :1
export DISPLAY=:1
export PATH="/usr/local/bin:/usr/bin:/bin"

# Logging Funktion
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Update Logik
do_update() {
    log "Prüfe auf Updates / Starte Update Prozess..."
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"
    
    if wget -q -L -O "$ZIP_NAME" "$ZIP_URL"; then
        log "Download erfolgreich. Entpacke..."
        unzip -q -o "$ZIP_NAME" -d "$TMP_DIR"
        
        # Dateien rüberkopieren (Einstellungen behalten)
        if [ -d "$TMP_DIR/Twitch Drops Miner" ]; then
            rsync -a --exclude='cookies.jar' --exclude='settings.json' "$TMP_DIR/Twitch Drops Miner/" "$TARGET_DIR/"
        else
            rsync -a --exclude='cookies.jar' --exclude='settings.json' "$TMP_DIR/" "$TARGET_DIR/"
        fi
        
        rm -f "$ZIP_NAME"
        rm -rf "$TMP_DIR"
        chmod +x "$PROGRAM_PATH"
        log "Update abgeschlossen."
    else
        log "Download fehlgeschlagen. Starte alte Version."
    fi
}

# --- HAUPTABLAUF ---

# 1. Update versuchen
do_update

# 2. Programm starten (Im Vordergrund, damit Systemd es überwachen kann!)
log "Starte Miner auf Display :1..."

# xhost erlaubt Zugriff auf das Display
xhost +local: >> /dev/null 2>&1 || true

if [ -x "$PROGRAM_PATH" ]; then
    # Wir starten es NICHT mit nohup, sondern direkt, damit Systemd den Prozess "hält"
    exec "$PROGRAM_PATH"
else
    log "FEHLER: Datei nicht ausführbar: $PROGRAM_PATH"
    exit 1
fi