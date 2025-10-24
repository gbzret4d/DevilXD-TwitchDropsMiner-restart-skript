# DevilXD Twitch Drops Miner Restart Script

This repository contains a Bash script to update and restart the Twitch Drops Miner application by DevilXD. The script safely terminates any running Twitch Drops Miner processes, downloads the latest release, backs up existing files, updates the application, and restarts it. Additionally, the script can self-update automatically by fetching its latest version from this GitHub repository.

---

## Features

- Graceful process termination with escalation to force kill if needed
- Automatic download and unpacking of the latest Twitch Drops Miner Linux release
- Backup of existing files before overwriting
- Self-updating script based on the latest commit in this repo
- Runs for the user who executes the script; no hardcoded usernames
- Requires `wget`, `unzip`, `rsync`, and `sha1sum` commands installed

---

## Usage

1. Clone or download this repository.

2. Make sure the script is executable:

   ```bash
   chmod +x restart_twitchdrops.sh
