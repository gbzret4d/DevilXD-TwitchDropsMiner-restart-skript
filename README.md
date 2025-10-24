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
Run the script as the user running Twitch Drops Miner:

BASH
./restart_twitchdrops.sh
The script will:

Check for a new version of itself and update if necessary.
Terminate running Twitch Drops Miner processes gracefully.
Download and extract the latest Twitch Drops Miner release.
Backup existing application files.
Copy updated files.
Restart the Twitch Drops Miner application.
Setup
The script expects the Twitch Drops Miner installation folder to be under:

TEXT
~/Desktop/devilxd/Twitch Drops Miner
The downloaded archive will be stored temporarily in the user's Downloads folder before extraction.

Configuration
GitHub URLs

The script uses the following URLs. Update these if you fork or rename this repository:

BASH
GITHUB_REPO_RAW_URL="https://raw.githubusercontent.com/gbzret4d/DevilXD-TwitchDropsMiner-restart-skript/main/restart_twitchdrops.sh"
GITHUB_API_LATEST_COMMIT="https://api.github.com/repos/gbzret4d/DevilXD-TwitchDropsMiner-restart-skript/commits/main"
Required commands

Ensure wget, unzip, rsync, and sha1sum are installed and available in your PATH.
