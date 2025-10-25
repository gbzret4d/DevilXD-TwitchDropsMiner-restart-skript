#!/bin/bash
#----------------------------------------------------
# Script: restart_twitchdrops.sh
# Purpose: Update and restart Twitch Drops Miner by DevilXD
# Features:
#   - Log rotation with deletion (Logs >7 Tage alt werden entfernt)
#   - SHA256 Checksumme wird dynamisch von GitHub Release bezogen (wenn möglich)
#   - Systemd-Service + Timer wird automatisch eingerichtet für 4h Intervalle
#   - Automatischer Neustart via systemd oder manuell
# Usage:
#   ./restart_twitchdrops.sh [update|restart|update_restart]
#----------------------------------------------------

set -euo pipefail

USER=$(id -un)
USER_HOME=$(eval echo "~$USER")
SCRIPT_NAME=$(basename "$0")

CONFIG_FILE="$USER_HOME/.twitchdropsminer.conf"

# Standardwerte (überschreibbar via Config-File)
GITHUB_REPO_RAW_URL="https://raw.githubusercontent.com/gbzret4d/DevilXD-TwitchDropsMiner-restart-skript/main/$SCRIPT_NAME"
GITHUB_API_LATEST_RELEASE="https://api.github.com/repos/DevilXD/TwitchDropsMiner/releases/latest"

PROGRAM_PATH="$USER_HOME/Desktop/devilxd/Twitch Drops Miner/Twitch Drops Miner (by DevilXD)"
DOWNLOAD_DIR="$USER_HOME/Downloads"
ZIP_BASE_URL="https://github.com/DevilXD/TwitchDropsMiner/releases/download/dev-build"
ZIP_FILE_NAME="Twitch.Drops.Miner.Linux.PyInstaller-x86_64.zip"
ZIP_URL="$ZIP_BASE_URL/$ZIP_FILE_NAME"
ZIP_NAME="$DOWNLOAD_DIR/$ZIP_FILE_NAME"
TMP_EXTRACT_DIR="/tmp/twitchdropsminer_update_tmp"
TARGET_DIR="$USER_HOME/Desktop/devilxd/Twitch Drops Miner"
LOG_FILE="$TARGET_DIR/twitchdropsminer.log"
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10 MB
LOG_DELETE_OLDER_THAN_DAYS=7

SYSTEMD_SERVICE_NAME="twitchdropsminer.service"
SYSTEMD_TIMER_NAME="twitchdropsminer.timer"

EXPECTED_SHA256=""  # wird dynamisch befüllt

# --- Funktionen ---

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

rotate_log() {
  # Log rotation bei Überschreiten der max Größe
  if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -gt "$MAX_LOG_SIZE" ]; then
    mv "$LOG_FILE" "$LOG_FILE.$(date '+%Y%m%d_%H%M%S')"
    log "Log-Rotation: Log wurde rotiert."

    # Alte Logs löschen, älter als X Tage
    find "$TARGET_DIR" -maxdepth 1 -name 'twitchdropsminer.log.*' -mtime +"$LOG_DELETE_OLDER_THAN_DAYS" -exec rm -f {} + \
      && log "Alte Logs (älter als $LOG_DELETE_OLDER_THAN_DAYS Tage) wurden gelöscht."
  fi
}

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    log "Lade Konfiguration aus $CONFIG_FILE"
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
  else
    log "Keine Konfigurationsdatei gefunden: $CONFIG_FILE"
  fi
}

download_with_retry() {
  local url="$1"; local output="$2"
  local tries=3 count=0
  while [ $count -lt $tries ]; do
    log "Download: Versuch $((count+1))/$tries - $url"
    if wget -O "$output" "$url"; then
      log "Download erfolgreich"
      return 0
    fi
    log "Download fehlgeschlagen, warte 5 Sekunden"
    sleep 5
    count=$((count+1))
  done
  log "FEHLER: Download nach $tries Versuchen fehlgeschlagen"
  return 1
}

get_sha256_from_github() {
  log "Versuche SHA256 Prüfsumme von der GitHub-API zu lesen..."

  # Hole latest release Infos mit wget (keine jq vorausgesetzt), extrahiere URL und SHA256 falls verfügbar
  local json
  json=$(wget -qO- "$GITHUB_API_LATEST_RELEASE") || {
    log "Warnung: Konnte GitHub API nicht laden, keine Prüfsumme verfügbar."
    EXPECTED_SHA256=""
    return
  }

  # Finde Asset die unser ZIP_FILE_NAME entspricht
  local asset_url asset_sha256
  # GitHub API liefert assets mit URL und evtl. "label" oder "name" -> leider SHA256 selten vorhanden
  # Daher nur Bestimmung der neuesten ZIP URL und zur Sicherheit SHA256 leer
  asset_url=$(echo "$json" | grep -Eo "\"browser_download_url\": *\"[^\"]+$ZIP_FILE_NAME\"" | head -n1 | cut -d\" -f4 || true)

  if [ -z "$asset_url" ]; then
    log "Warnung: Kein Download-Asset $ZIP_FILE_NAME im GitHub Release gefunden."
    EXPECTED_SHA256=""
    return
  fi

  # Für TwitchDropsMiner gibt es scheinbar keine SHA256 Checksums in API-Assets
  # Du kannst hier Erweiterung einfügen, falls es die mal gibt, z.B. in .sha256 Datei im Release

  EXPECTED_SHA256=""  # saubere Prüfung fällt weg wenn keine Info vorhanden

  # Setze den Download URL falls im Release abweichend
  if [ "$asset_url" != "$ZIP_URL" ]; then
    log "Neuer Download URL vom Release: $asset_url"
    ZIP_URL="$asset_url"
    ZIP_NAME="$DOWNLOAD_DIR/$(basename "$ZIP_URL")"
  fi
}

stop_processes() {
  # Prüfe systemd Service
  if systemctl --user is-active --quiet "$SYSTEMD_SERVICE_NAME" 2>/dev/null; then
    log "Systemd User-Service $SYSTEMD_SERVICE_NAME aktiv, restart über systemd..."
    systemctl --user restart "$SYSTEMD_SERVICE_NAME"
    return 0
  fi

  log "Stoppe Twitch Drops Miner Prozesse manuell..."
  local pids
  pids=$(pgrep -f "Twitch Drops Mi" || true)

  if [ -n "$pids" ]; then
    for pid in $pids; do
      kill "$pid" && log "SIGTERM an Prozess $pid gesendet." || {
        log "SIGTERM fehlgeschlagen, versuche SIGKILL an Prozess $pid."
        kill -9 "$pid" || log "Konnte Prozess $pid nicht töten."
      }
    done

    for i in $(seq 1 10); do
      if ! pgrep -f "Twitch Drops Mi" >/dev/null; then
        log "Alle Prozesse beendet."
        break
      fi
      sleep 1
    done

    if pgrep -f "Twitch Drops Mi" >/dev/null; then
      log "Prozesse noch aktiv, wende SIGKILL an."
      pkill -9 -f "Twitch Drops Mi"
    fi
  else
    log "Keine laufenden Prozesse gefunden."
  fi
}

cleanup_old_tmp_dirs() {
  log "Entferne alte temporäre Update-Verzeichnisse..."
  rm -rf /tmp/twitchdropsminer_update_tmp* 2>/dev/null || true
}

start_program() {
  local display user_xauthority
  display=$(pgrep -u "$USER" -a | grep -o 'DISPLAY=:[0-9]\+' | head -n1 | cut -d= -f2 || true)
  if [ -z "$display" ]; then
    local pid_xorg
    pid_xorg=$(pgrep -u "$USER" Xorg | head -n1 || true)
    if [ -n "$pid_xorg" ]; then
      display=$(tr '\0' '\n' < /proc/"$pid_xorg"/environ | grep "^DISPLAY=" | cut -d= -f2 || true)
    fi
  fi
  display=${display:-:12}
  user_xauthority="$USER_HOME/.Xauthority"
  if [ ! -f "$user_xauthority" ]; then
    log "Warnung: XAUTHORITY-Datei nicht gefunden ($user_xauthority)"
  fi

  export DISPLAY="$display"
  export XAUTHORITY="$user_xauthority"

  log "Starte Twitch Drops Miner (DISPLAY=$display)"
  if [ ! -x "$PROGRAM_PATH" ]; then
    log "FEHLER: Programm nicht gefunden oder nicht ausführbar: $PROGRAM_PATH"
    exit 1
  fi

  nohup "$PROGRAM_PATH" >>"$LOG_FILE" 2>&1 &
}

create_systemd_service_and_timer() {
  log "Prüfe systemd User-Service und -Timer..."

  SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_DIR"

  SERVICE_FILE="$SYSTEMD_DIR/$SYSTEMD_SERVICE_NAME"
  TIMER_FILE="$SYSTEMD_DIR/$SYSTEMD_TIMER_NAME"

  local service_changed=0
  local timer_changed=0

  # Schreibe Service-Datei falls nicht vorhanden oder anders
  if [ ! -f "$SERVICE_FILE" ] || ! cmp -s <(generate_service_content) "$SERVICE_FILE"; then
    generate_service_content > "$SERVICE_FILE"
    systemctl --user daemon-reload
    systemctl --user enable "$SYSTEMD_SERVICE_NAME"
    service_changed=1
    log "Systemd Service $SYSTEMD_SERVICE_NAME neu installiert/aktualisiert."
  fi

  # Schreibe Timer-Datei falls nicht vorhanden oder anders
  if [ ! -f "$TIMER_FILE" ] || ! cmp -s <(generate_timer_content) "$TIMER_FILE"; then
    generate_timer_content > "$TIMER_FILE"
    systemctl --user daemon-reload
    systemctl --user enable "$SYSTEMD_TIMER_NAME"
    timer_changed=1
    log "Systemd Timer $SYSTEMD_TIMER_NAME neu installiert/aktualisiert."
  fi

  # Timer starten falls nicht bereits aktiv
  if ! systemctl --user is-active --quiet "$SYSTEMD_TIMER_NAME"; then
    systemctl --user start "$SYSTEMD_TIMER_NAME"
    log "Systemd Timer $SYSTEMD_TIMER_NAME gestartet."
  fi

  if [ $service_changed -eq 0 ] && [ $timer_changed -eq 0 ]; then
    log "Systemd Service und Timer sind aktuell und aktiv."
  fi
}

generate_service_content() {
  cat <<EOF
[Unit]
Description=Twitch Drops Miner by DevilXD

[Service]
Type=simple
ExecStart=$PROGRAM_PATH
Restart=on-failure
RestartSec=10
Environment=DISPLAY=:0
Environment=XAUTHORITY=$USER_HOME/.Xauthority
WorkingDirectory=$(dirname "$PROGRAM_PATH")

[Install]
WantedBy=default.target
EOF
}

generate_timer_content() {
  cat <<EOF
[Unit]
Description=4h Timer zum Update und Neustart von Twitch Drops Miner

[Timer]
OnBootSec=2min
OnUnitActiveSec=4h
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

self_update() {
  log "Prüfe Skript-Update..."
  local_sha=$(sha1sum "$0" | awk '{print $1}')
  tmp_file="/tmp/$SCRIPT_NAME.remote"
  if ! wget -qO "$tmp_file" "$GITHUB_REPO_RAW_URL"; then
    log "Warnung: Konnte neues Skript nicht herunterladen."
    rm -f "$tmp_file" 2>/dev/null || true
    return
  fi
  remote_sha=$(sha1sum "$tmp_file" | awk '{print $1}')
  if [ "$local_sha" != "$remote_sha" ]; then
    log "Neues Skript gefunden, update..."
    cp "$tmp_file" "$0"
    chmod +x "$0"
    rm -f "$tmp_file"
    log "Skript aktualisiert, starte neu..."
    exec "$0" "$@"
  else
    rm -f "$tmp_file"
    log "Skript ist aktuell."
  fi
}

main() {
  rotate_log
  load_config
  create_systemd_service_and_timer

  local mode="${1:-update_restart}"

  for cmd in wget unzip rsync sha1sum sha256sum systemctl; do
    if ! command -v "$cmd" &>/dev/null; then
      log "FEHLER: Befehl '$cmd' nicht gefunden."
      exit 1
    fi
  done

  if [[ "$mode" == "restart" ]]; then
    log "Nur Neustart wird ausgeführt..."
    stop_processes
    start_program
    return 0
  fi

  if [[ "$mode" =~ ^(update|update_restart)$ ]]; then
    log "Starte Update..."

    stop_processes
    cleanup_old_tmp_dirs

    get_sha256_from_github

    mkdir -p "$TMP_EXTRACT_DIR"
    rm -rf "$TMP_EXTRACT_DIR"/* || true

    if ! download_with_retry "$ZIP_URL" "$ZIP_NAME"; then
      log "FEHLER: Download fehlgeschlagen, Abbruch."
      exit 1
    fi

    if [ -n "$EXPECTED_SHA256" ]; then
      if ! validate_checksum; then
        log "FEHLER: Prüfsummenprüfung fehlgeschlagen."
        exit 2
      fi
    else
      log "Keine SHA256 Prüfsumme gesetzt, überspringe Validierung."
    fi

    log "Entpacke Download..."
    unzip -q "$ZIP_NAME" -d "$TMP_EXTRACT_DIR"

    log "Kopiere Dateien zum Ziel (ausgenommen cookies.jat & settings.json)..."
    rsync -a --exclude='cookies.jat' --exclude='settings.json' "$TMP_EXTRACT_DIR/Twitch Drops Miner/" "$TARGET_DIR/"

    rm -rf "$TMP_EXTRACT_DIR"
    rm -f "$ZIP_NAME"

    if [[ "$mode" == "update_restart" ]]; then
      start_program
      log "Update und Neustart abgeschlossen."
    else
      log "Update abgeschlossen, Neustart nicht ausgeführt."
    fi
  fi
}

# Prüfsummenfunktion ausgelagert, da noch in main gebraucht
validate_checksum() {
  log "Prüfe SHA256-Prüfsumme..."
  local computed_sha
  computed_sha=$(sha256sum "$ZIP_NAME" | awk '{print $1}')
  if [ "$computed_sha" != "$EXPECTED_SHA256" ]; then
    log "FEHLER: Prüfsumme stimmt nicht. Erwartet: $EXPECTED_SHA256 Berechnet: $computed_sha"
    return 1
  fi
  log "Prüfsumme korrekt."
  return 0
}

self_update "$@"
main "$@"
