#!/bin/bash
#----------------------------------------------------
# restart_twitchdrops.sh
# Zweck: Update, Neustart und Betrieb des Twitch Drops Miner
# Für dauerhafte xrdp-Sitzung mit dynamischer Display-Erkennung
# Kein systemd, Cron-fähig
#----------------------------------------------------

set -euo pipefail

USER=$(id -un)
USER_HOME=$(eval echo "~$USER")
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

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

rotate_log() {
  if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -gt "$MAX_LOG_SIZE" ]; then
    mv "$LOG_FILE" "$LOG_FILE.$(date '+%Y%m%d_%H%M%S')"
    log "Log rotiert."
    find "$TARGET_DIR" -maxdepth 1 -name 'twitchdropsminer.log.*' -mtime +"$LOG_DELETE_OLDER_THAN_DAYS" -exec rm -f {} +
    log "Alte Logs gelöscht."
  fi
}

get_rdp_display() {
  # Suche nach Xorg-Prozessen, die mit xrdp laufen, und filtere Display :10 bis :20
  local disp
  disp=$(ps aux | grep '[X]org' | grep 'xrdp' | grep -o ':[0-9]\+' | grep -E ':1[0-9]' | head -n1)
  if [ -z "$disp" ]; then
    disp=":12"  # Fallback
  fi
  echo "$disp"
}

stop_program() {
  local pids
  pids=$(pgrep -f "Twitch Drops Miner" || true)
  if [ -n "$pids" ]; then
    for pid in $pids; do
      kill "$pid" && log "SIGTERM an Prozess $pid gesendet." || {
        log "SIGTERM fehlgeschlagen, versuche SIGKILL an Prozess $pid."
        kill -9 "$pid" || log "Konnte Prozess $pid nicht töten."
      }
    done
    log "Alle Twitch Drops Miner Prozesse gestoppt."
  else
    log "Keine laufenden Twitch Drops Miner Prozesse gefunden."
  fi
}

start_program() {
  export DISPLAY=$(get_rdp_display)
  xhost +local: || true

  log "Starte Twitch Drops Miner mit DISPLAY=$DISPLAY"

  if [ ! -x "$PROGRAM_PATH" ]; then
    log "FEHLER: Programm nicht gefunden oder nicht ausführbar: $PROGRAM_PATH"
    exit 1
  fi

  nohup "$PROGRAM_PATH" >>"$LOG_FILE" 2>&1 &
  log "Twitch Drops Miner mit PID $! gestartet"
}

download_with_retry() {
  local url="$1" output="$2"
  local tries=3 count=0
  while [ $count -lt $tries ]; do
    log "Download Versuch $((count+1))/$tries: $url"
    if wget -O "$output" "$url"; then
      log "Download erfolgreich."
      return 0
    fi
    log "Download fehlgeschlagen, warte 5 Sekunden."
    sleep 5
    count=$((count+1))
  done
  log "FEHLER: Download nach $tries Versuchen fehlgeschlagen."
  return 1
}

update_and_restart() {
  log "Starte Update und Neustart."

  stop_program

  rotate_log

  rm -rf "$TMP_EXTRACT_DIR"
  mkdir -p "$TMP_EXTRACT_DIR"

  if ! download_with_retry "$ZIP_URL" "$ZIP_NAME"; then
    log "FEHLER: Download fehlgeschlagen, Abbruch."
    exit 1
  fi

  log "Entpacke Download..."
  unzip -q "$ZIP_NAME" -d "$TMP_EXTRACT_DIR"
  log "Entpackt."

  log "Kopiere Dateien..."
  rsync -a --exclude='cookies.jat' --exclude='settings.json' "$TMP_EXTRACT_DIR/Twitch Drops Miner/" "$TARGET_DIR/"
  log "Kopiert."

  rm -rf "$TMP_EXTRACT_DIR"
  rm -f "$ZIP_NAME"
  log "Bereinigt."

  start_program

  log "Update und Neustart abgeschlossen."
}

case "${1:-}" in
  start)
    start_program
    ;;
  stop)
    stop_program
    ;;
  restart)
    stop_program
    start_program
    ;;
  update_restart)
    update_and_restart
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|update_restart}"
    exit 1
    ;;
esac
