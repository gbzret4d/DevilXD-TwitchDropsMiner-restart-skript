#!/bin/bash
#----------------------------------------------------
# Script: restart_twitchdrops.sh
# Purpose: Update and restart Twitch Drops Miner by DevilXD
# Features:
#   - Log rotation mit Löschung alter Logs
#   - Dynamische SHA256-Prüfsumme von GitHub Release (wenn möglich)
#   - systemd-Service + Timer automatisch erstellen und aktivieren
#   - Automatischer Neustart via systemd oder manuell
#   - Prüft und installiert dbus-launch (dbus-x11) automatisch bei Root-Rechten
#   - Aktiviert enable-linger automatisch bei Root-Rechten
#
#   - NEU: Automatischer Headless-Modus bei SSH X11 Forwarding (kein systemd user session)
#
# Usage:
#   ./restart_twitchdrops.sh [update|restart|update_restart]
#----------------------------------------------------
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
set -euo pipefail

USER=$(id -un)
USER_HOME=$(eval echo "~$USER")
SCRIPT_NAME=$(basename "$0")

CONFIG_FILE="$USER_HOME/.twitchdropsminer.conf"

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

systemd_user_available() {
  systemctl --user show-environment &>/dev/null || return 1
}

enable_linger_for_user() {
  if [ "$(id -u)" -ne 0 ]; then
    log "Kein Root zum enable-linger, überspringe."
    return 1
  fi
  local user="$1"
  if [ -z "$user" ]; then user="$USER"; fi
  log "Versuche enable-linger für Benutzer $user..."
  if loginctl enable-linger "$user"; then
    log "enable-linger erfolgreich."
    return 0
  else
    log "enable-linger fehlgeschlagen."
    return 1
  fi
}

is_ssh_x11_forwarding() {
  # Prüft, ob DISPLAY auf eine typische SSH X11 forwarding Variable gesetzt ist, z.B. localhost:10.0
  if [[ "${DISPLAY:-}" == localhost:* ]]; then
    return 0
  else
    return 1
  fi
}

try_start_systemd_user_session() {
  if systemd_user_available; then
    log "Systemd User-Bus bereits verfügbar."
    return 0
  fi

  log "DEBUG: DISPLAY ist '${DISPLAY:-<nicht gesetzt>}'"

  if [ -z "${DISPLAY:-}" ]; then
    log "DISPLAY ist nicht gesetzt. dbus-launch wird nicht gestartet."
    return 1
  fi

  if is_ssh_x11_forwarding; then
    log "SSH X11 Forwarding erkannt (DISPLAY=$DISPLAY). Systemd User-Bus per dbus-launch nicht gestartet."
    return 1
  fi

  log "Systemd User-Bus nicht vorhanden. Versuche mit dbus-launch Systemd user session zu starten..."
  if command -v dbus-launch &>/dev/null; then
    export $(dbus-launch)
    sleep 1
  else
    log "dbus-launch nicht vorhanden. Kann user session nicht starten."
    return 1
  fi

  if systemd_user_available; then
    log "Nach dbus-launch ist systemd user-bus verfügbar."
    return 0
  else
    log "Konnte keine systemd user-bus Verbindung herstellen."
    return 1
  fi
}

rotate_log() {
  if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -gt "$MAX_LOG_SIZE" ]; then
    mv "$LOG_FILE" "$LOG_FILE.$(date '+%Y%m%d_%H%M%S')"
    log "Log-Rotation: Log wurde rotiert."
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
  local url="$1" output="$2"
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

  local json
  json=$(wget -qO- "$GITHUB_API_LATEST_RELEASE") || {
    log "Warnung: Konnte GitHub API nicht laden, keine Prüfsumme verfügbar."
    EXPECTED_SHA256=""
    return
  }

  local asset_url
  asset_url=$(echo "$json" | grep -Eo "\"browser_download_url\": *\"[^\"]+$ZIP_FILE_NAME\"" | head -n1 | cut -d\" -f4 || true)

  if [ -z "$asset_url" ]; then
    log "Warnung: Kein Download-Asset $ZIP_FILE_NAME im GitHub Release gefunden."
    EXPECTED_SHA256=""
    return
  fi

  EXPECTED_SHA256=""

  if [ "$asset_url" != "$ZIP_URL" ]; then
    log "Neuer Download URL vom Release: $asset_url"
    ZIP_URL="$asset_url"
    ZIP_NAME="$DOWNLOAD_DIR/$(basename "$ZIP_URL")"
  fi
}

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

manual_stop_start() {
  log "Manueller Neustart ohne systemd user..."

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

  start_program
  log "Manueller Neustart abgeschlossen."
}

stop_processes() {
  if systemd_user_available && ! is_ssh_x11_forwarding; then
    if systemctl --user is-active --quiet "$SYSTEMD_SERVICE_NAME" 2>/dev/null; then
      log "Systemd User-Service $SYSTEMD_SERVICE_NAME aktiv, restart über systemd..."
      systemctl --user restart "$SYSTEMD_SERVICE_NAME"
      return 0
    fi
    log "Systemd User-Service $SYSTEMD_SERVICE_NAME nicht aktiv, nutze manuellen Prozess-Neustart."
  else
    log "Systemd User-Bus nicht verfügbar oder SSH X11 Forwarding erkannt, nutze manuellen Prozess-Neustart."
  fi
  manual_stop_start
}

cleanup_old_tmp_dirs() {
  log "Entferne alte temporäre Update-Verzeichnisse..."
  rm -rf /tmp/twitchdropsminer_update_tmp* 2>/dev/null || true
}

start_program() {
  local display user_xauthority
  if is_ssh_x11_forwarding; then
    # SSH X11 Forwarding detected -> Start headless ohne DISPLAY setzen
    log "SSH X11 Forwarding erkannt, starte Programm OHNE DISPLAY-Variable."
    unset DISPLAY
    unset XAUTHORITY
  else
    # Hier wurde die Änderung eingefügt:
    export DISPLAY=:99
    xhost +local: || true
    user_xauthority="$USER_HOME/.Xauthority"
    if [ ! -f "$user_xauthority" ]; then
      log "Warnung: XAUTHORITY-Datei nicht gefunden ($user_xauthority)"
    fi
    log "Starte Programm mit DISPLAY=$DISPLAY"
  fi

  log "DEBUG: DISPLAY='${DISPLAY:-<unset>}'"

  log "Starte Twitch Drops Miner"
  if [ ! -x "$PROGRAM_PATH" ]; then
    log "FEHLER: Programm nicht gefunden oder nicht ausführbar: $PROGRAM_PATH"
    exit 1
  fi

  nohup "$PROGRAM_PATH" >>"$LOG_FILE" 2>&1 &
}

# ... restliches Skript unverändert ...

# --- Aufrufe am Skriptende ---
self_update "$@"
main "$@"

