#!/bin/bash
#----------------------------------------------------
# Script: restart_twitchdrops.sh
# Purpose: Update and restart Twitch Drops Miner by DevilXD
#          with self-update support from GitHub.
# Usage:
#   ./restart_twitchdrops.sh
# Requirements:
#   - wget, unzip, rsync, sha1sum installed
# Notes:
#   - Runs as current user without hardcoded username.
#   - Assumes Twitch Drops Miner installed at ~/Desktop/devilxd/Twitch Drops Miner
#----------------------------------------------------

set -euo pipefail
set -x  # Für Debugging, entferne bei produktivem Einsatz

# --- Variablen ---

USER=$(id -un)
USER_HOME=$(eval echo "~$USER")

SCRIPT_NAME=$(basename "$0")

GITHUB_REPO_RAW_URL="https://raw.githubusercontent.com/gbzret4d/DevilXD-TwitchDropsMiner-restart-skript/main/$SCRIPT_NAME"
GITHUB_API_LATEST_COMMIT="https://api.github.com/repos/gbzret4d/DevilXD-TwitchDropsMiner-restart-skript/commits/main"

PROGRAM_PATH="$USER_HOME/Desktop/devilxd/Twitch Drops Miner/Twitch Drops Miner (by DevilXD)"
DOWNLOAD_DIR="$USER_HOME/Downloads"
ZIP_URL="https://github.com/DevilXD/TwitchDropsMiner/releases/download/dev-build/Twitch.Drops.Miner.Linux.PyInstaller-x86_64.zip"
ZIP_NAME="$DOWNLOAD_DIR/Twitch.Drops.Miner.Linux.PyInstaller-x86_64.zip"
TMP_EXTRACT_DIR="/tmp/twitchdropsminer_update_tmp"
TARGET_DIR="$USER_HOME/Desktop/devilxd/Twitch Drops Miner"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

self_update() {
  log "Überprüfe auf neue Skript-Version..."

  local_sha=$(sha1sum "$0" | awk '{print $1}')
  remote_sha=$(wget -qO- "$GITHUB_API_LATEST_COMMIT" | grep -m1 '"sha"' | cut -d '"' -f4)

  if [ -z "$remote_sha" ]; then
    log "WARNUNG: Keine Remote-SHA erhalten, Self-Update übersprungen."
    return
  fi

  remote_tmp="/tmp/${SCRIPT_NAME}.remote"

  if ! wget -qO "$remote_tmp" "$GITHUB_REPO_RAW_URL"; then
    log "WARNUNG: Herunterladen der aktuellen Skriptversion fehlgeschlagen."
    rm -f "$remote_tmp"
    return
  fi

  remote_file_sha=$(sha1sum "$remote_tmp" | awk '{print $1}')

  if [ "$local_sha" != "$remote_file_sha" ]; then
    log "Neue Skript-Version gefunden, aktualisiere..."
    cp "$remote_tmp" "$0"
    chmod +x "$0"
    rm -f "$remote_tmp"
    log "Skript aktualisiert, starte neu..."
    exec "$0" "$@"
    # exec ersetzt den aktuellen Prozess, daher kein exit nötig
  else
    log "Skript ist aktuell."
    rm -f "$remote_tmp"
  fi
}

main() {
  self_update

  log "Starte Update-Prozess für Twitch Drops Miner..."

  # Prüfungen für benötigte Programme
  for cmd in wget unzip rsync sha1sum; do
    if ! command -v "$cmd" >/dev/null; then
      log "FEHLER: Erforderlicher Befehl '$cmd' nicht gefunden. Bitte installieren."
      exit 1
    fi
  done

  # Twitch Drops Miner Prozesse stoppen
  log "Beende laufende Twitch Drops Miner Prozesse..."
  pids=$(pgrep -f "Twitch Drops Mi" || true)

  if [ -n "$pids" ]; then
    for pid in $pids; do
      kill "$pid" && log "SIGTERM an Prozess $pid gesendet." || {
        log "SIGTERM fehlgeschlagen, versuche SIGKILL an Prozess $pid."
        kill -9 "$pid" || log "Konnte Prozess $pid nicht töten."
      }
    done

    # Warten bis Prozesse beendet sind (maximal 10 Sekunden)
    for i in $(seq 1 10); do
      if ! pgrep -f "Twitch Drops Mi" >/dev/null; then
        log "Alle Twitch Drops Miner Prozesse wurden beendet."
        break
      fi
      sleep 1
    done

    if pgrep -f "Twitch Drops Mi" >/dev/null; then
      log "Prozesse nach SIGTERM noch aktiv, wende SIGKILL an."
      pkill -9 -f "Twitch Drops Mi"
    fi
  else
    log "Keine laufenden Twitch Drops Miner Prozesse gefunden."
  fi

  # Temporäres Verzeichnis vorbereiten
  log "Erstelle temporäres Verzeichnis: $TMP_EXTRACT_DIR"
  rm -rf "$TMP_EXTRACT_DIR"
  mkdir -p "$TMP_EXTRACT_DIR"

  # ZIP herunterladen
  log "Lade neueste Twitch Drops Miner Version herunter..."
  wget -O "$ZIP_NAME" "$ZIP_URL" || { log "FEHLER: Download fehlgeschlagen!"; exit 1; }

  # Archiv entpacken
  log "Archive entpacken..."
  unzip -q "$ZIP_NAME" -d "$TMP_EXTRACT_DIR" || { log "FEHLER: Entpacken fehlgeschlagen!"; exit 1; }

  # Backup der bestehenden Installation vom Zielverzeichnis
  BACKUP_DIR="$TARGET_DIR/backup_$(date '+%Y%m%d_%H%M%S')"
  log "Backup der aktuellen Installation in: $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  rsync -a --exclude='cookies.jat' --exclude='settings.json' "$TARGET_DIR/" "$BACKUP_DIR/"

  # Neue Dateien kopieren (ohne cookies.jat & settings.json)
  log "Kopiere neue Dateien nach $TARGET_DIR"
  rsync -a --exclude='cookies.jat' --exclude='settings.json' "$TMP_EXTRACT_DIR/Twitch Drops Miner/" "$TARGET_DIR/"

  # Aufräumen
  log "Räume temporäre Dateien auf..."
  rm -rf "$TMP_EXTRACT_DIR"
  rm -f "$ZIP_NAME"

  # DISPLAY & XAUTHORITY ermitteln für GUI-Start
  DISPLAY=$(pgrep -u "$USER" -a | grep -o 'DISPLAY=:[0-9]\+' | head -n1 | cut -d= -f2 || true)
  if [ -z "$DISPLAY" ]; then
    pid_xorg=$(pgrep -u "$USER" Xorg | head -n1 || true)
    if [ -n "$pid_xorg" ]; then
      DISPLAY=$(tr '\0' '\n' < /proc/"$pid_xorg"/environ | grep "^DISPLAY=" | cut -d= -f2 || true)
    fi
  fi
  DISPLAY=${DISPLAY:-:12}

  XAUTHORITY="$USER_HOME/.Xauthority"
  if [ ! -f "$XAUTHORITY" ]; then
    log "WARNUNG: XAUTHORITY-Datei nicht gefunden: $XAUTHORITY"
  fi

  export DISPLAY
  export XAUTHORITY

  log "Starte Twitch Drops Miner mit DISPLAY=$DISPLAY und XAUTHORITY=$XAUTHORITY"

  if [ ! -x "$PROGRAM_PATH" ]; then
    log "FEHLER: Programm nicht gefunden oder nicht ausführbar: $PROGRAM_PATH"
    exit 1
  fi

  nohup "$PROGRAM_PATH" >> "$TARGET_DIR/twitchdropsminer.log" 2>&1 &

  log "Update- und Neustart-Prozess abgeschlossen."
}

main
