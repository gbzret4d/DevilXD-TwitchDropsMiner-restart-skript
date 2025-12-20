#!/bin/bash
#----------------------------------------------------
# restart_twitchdrops.sh
# Purpose: Master Controller & GUI Configurator
# Features: JSON-Editor (jq), Firefox-Check, Auto-Update
#----------------------------------------------------

set -u

# --- VARIABLEN ---
USER_HOME="/home/testuser"
# Pfade
MINER_DIR="$USER_HOME/Desktop/devilxd/Twitch Drops Miner/Twitch Drops Miner (by DevilXD)"
MINER_EXEC="$MINER_DIR/Twitch Drops Miner (by DevilXD)"
MINER_SETTINGS="$USER_HOME/Desktop/devilxd/Twitch Drops Miner/settings.json"
# Firefox Profil-Pfad (wird automatisch gesucht)
FIREFOX_ROOT="$USER_HOME/.mozilla/firefox-trunk"

# Update Einstellungen
DOWNLOAD_DIR="$USER_HOME/Downloads"
ZIP_URL="https://github.com/DevilXD/TwitchDropsMiner/releases/download/dev-build/Twitch.Drops.Miner.Linux.PyInstaller-x86_64.zip"
ZIP_NAME="$DOWNLOAD_DIR/update.zip"
TMP_DIR="/tmp/twitch_update"
TARGET_DIR="$USER_HOME/Desktop/devilxd/Twitch Drops Miner"
LOG_FILE="$TARGET_DIR/twitchdropsminer.log"
SERVICE_FILE="/etc/systemd/system/twitchminer.service"

export DISPLAY=:1
export PATH="/usr/local/bin:/usr/bin:/bin"

# --- CORE FUNCTIONS ---

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

task_check_vnc() {
    if [ -e /tmp/.X11-unix/X1 ]; then
        log "VNC Session :1 gefunden. Nutze existierende Session."
    else
        log "VNC Session :1 nicht gefunden. Starte neu..."
        rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
        vncserver :1 -geometry 1600x900 -depth 24
    fi
}

task_update() {
    log "Prüfe auf Updates..."
    rm -rf "$TMP_DIR" "$ZIP_NAME"
    mkdir -p "$TMP_DIR"
    
    if wget -q -L -O "$ZIP_NAME" "$ZIP_URL"; then
        if unzip -q -o "$ZIP_NAME" -d "$TMP_DIR"; then
            if [ -d "$TMP_DIR/Twitch Drops Miner" ]; then
                SOURCE_PATH="$TMP_DIR/Twitch Drops Miner/"
            else
                SOURCE_PATH="$TMP_DIR/"
            fi
            # Update durchführen, aber settings.json schützen
            rsync -a --exclude='cookies.jar' --exclude='settings.json' "$SOURCE_PATH" "$TARGET_DIR/"
            rm -f "$ZIP_NAME"
            rm -rf "$TMP_DIR"
            chmod +x "$MINER_EXEC"
            log "Update erfolgreich."
        else
            log "FEHLER: Entpacken fehlgeschlagen."
        fi
    else
        log "FEHLER: Download fehlgeschlagen."
    fi
}

task_start_firefox() {
    # HIER IST DER CHECK:
    if pgrep -f "firefox-trunk" > /dev/null; then
        log "Firefox Nightly läuft bereits. Überspringe Start."
    else
        # Suche automatisch nach dem Profilordner, der auf .default endet
        PROFILE_DIR=$(find "$FIREFOX_ROOT" -maxdepth 1 -type d -name "*.default" | head -n 1)

        if [ -n "$PROFILE_DIR" ]; then
            log "Starte Firefox Nightly (Profil: $(basename "$PROFILE_DIR"))..."
            nohup firefox-trunk -profile "$PROFILE_DIR" >> /dev/null 2>&1 &
        else
            log "WARNUNG: Kein .default Profil gefunden. Starte generisch..."
            nohup firefox-trunk >> /dev/null 2>&1 &
        fi
    fi
}

task_start_miner() {
    log "Starte Twitch Drops Miner..."
    if [ -x "$MINER_EXEC" ]; then
        exec "$MINER_EXEC"
    else
        log "FEHLER: Miner Datei nicht gefunden!"
        exit 1
    fi
}

# --- GUI / SETTINGS EDITOR ---

ensure_jq() {
    if ! command -v jq &> /dev/null; then
        whiptail --title "Fehler" --msgbox "Das Tool 'jq' fehlt!\nBitte installieren: sudo apt install jq" 8 60
        exit 1
    fi
}

menu_edit_priority() {
    ensure_jq
    # Liest das aktuelle Array und macht daraus einen String "Game1, Game2"
    CURRENT_PRIO=$(jq -r '.priority | join(", ")' "$MINER_SETTINGS")
    
    NEW_PRIO=$(whiptail --title "Spiele Priorität" --inputbox \
    "Liste deine Spiele, getrennt durch Komma:\n(Zuerst genannt = Höhere Prio)" \
    10 70 "$CURRENT_PRIO" 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ]; then
        # Schreibt den String zurück als JSON Array
        # Wir nutzen eine temporäre Datei, um Datenverlust zu vermeiden
        jq --arg input "$NEW_PRIO" '.priority = ($input | split(", ") | map(select(length > 0)))' "$MINER_SETTINGS" > "$MINER_SETTINGS.tmp" && mv "$MINER_SETTINGS.tmp" "$MINER_SETTINGS"
        whiptail --title "Gespeichert" --msgbox "Prioritäten aktualisiert!" 8 40
    fi
}

menu_edit_single_value() {
    ensure_jq
    # Zeigt alle Keys an
    KEYS=$(jq -r 'keys[]' "$MINER_SETTINGS")
    # Formatiere für Whiptail Menu (Key Description)
    MENU_ITEMS=()
    while read -r line; do
        MENU_ITEMS+=("$line" "")
    done <<< "$KEYS"

    CHOSEN_KEY=$(whiptail --title "Wähle Einstellung" --menu "Welchen Wert ändern?" 20 60 10 "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ]; then
        CURRENT_VAL=$(jq -r --arg k "$CHOSEN_KEY" '.[$k]' "$MINER_SETTINGS")
        
        NEW_VAL=$(whiptail --title "Wert ändern: $CHOSEN_KEY" --inputbox \
        "Aktueller Wert: $CURRENT_VAL\n\n(Für True/False bitte klein schreiben: true / false)" \
        10 60 "$CURRENT_VAL" 3>&1 1>&2 2>&3)
        
        if [ $? -eq 0 ]; then
             # Versuche zu erraten, ob es Zahl, Bool oder String ist (jq magic)
             # Wenn es als Zahl/Bool parsbar ist, nimm es, sonst als String
             jq --arg v "$NEW_VAL" --arg k "$CHOSEN_KEY" '.[$k] = ($v | fromjson? // $v)' "$MINER_SETTINGS" > "$MINER_SETTINGS.tmp" && mv "$MINER_SETTINGS.tmp" "$MINER_SETTINGS"
             whiptail --title "Erfolg" --msgbox "Gespeichert: $CHOSEN_KEY = $NEW_VAL" 8 40
        fi
    fi
}

menu_systemd_timer() {
    CURRENT_VAL=$(grep "RuntimeMaxSec=" "$SERVICE_FILE" | cut -d= -f2)
    NEW_VAL=$(whiptail --title "Neustart Intervall" --inputbox \
    "Server startet automatisch neu nach:\n(Aktuell: $CURRENT_VAL)\n\nEingabe z.B.: 2h, 6h, infinity" \
    10 60 "$CURRENT_VAL" 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ]; then
        if (whiptail --title "Sudo benötigt" --yesno "System-Datei ändern erfordert Passwort. Fortfahren?" 8 60); then
            sudo sed -i "s/^RuntimeMaxSec=.*/RuntimeMaxSec=$NEW_VAL/" "$SERVICE_FILE"
            sudo systemctl daemon-reload
            whiptail --title "Erfolg" --msgbox "Intervall auf $NEW_VAL gesetzt.\nWirksam nach nächstem Neustart." 8 60
        fi
    fi
}

show_main_menu() {
    while true; do
        CHOICE=$(whiptail --title "Twitch Miner Control Panel" --menu "Wähle eine Option:" 18 70 7 \
        "1" "STARTEN (Normaler Modus)" \
        "2" "Einstellungen: Spiele-Priorität ändern" \
        "3" "Einstellungen: Alle Werte (Erweitert)" \
        "4" "System: Neustart-Intervall (2h/4h...)" \
        "5" "Logs anzeigen" \
        "6" "Update erzwingen" \
        "7" "Beenden" 3>&1 1>&2 2>&3)

        case $CHOICE in
            1) 
                clear; task_check_vnc; xhost +local: >> /dev/null 2>&1 || true; 
                killall autocutsel 2>/dev/null; autocutsel -fork; autocutsel -selection PRIMARY -fork;
                task_start_firefox; task_start_miner; break ;;
            2) menu_edit_priority ;;
            3) menu_edit_single_value ;;
            4) menu_systemd_timer ;;
            5) clear; tail -f "$LOG_FILE"; ;;
            6) clear; task_update; echo "Enter drücken..."; read ;;
            7) break ;;
            *) break ;;
        esac
    done
}

# --- AUSFÜHRUNG ---

# Wenn Systemd startet (Variable gesetzt) -> Sofort loslegen
if [ "${IS_SYSTEMD_SERVICE:-}" == "true" ]; then
    task_update
    task_check_vnc
    xhost +local: >> /dev/null 2>&1 || true
    killall autocutsel 2>/dev/null; autocutsel -fork; autocutsel -selection PRIMARY -fork
    task_start_firefox
    task_start_miner
else
    # Wenn User startet -> GUI anzeigen
    show_main_menu
fi