Twitch Drops Miner - Linux Server Automation

This repository contains scripts and configuration to run the Twitch Drops Miner (by DevilXD) on a headless Linux server (Ubuntu/Debian) 24/7.

It creates a persistent graphical session (Display :1) that automatically starts the Miner and a Browser. You can disconnect and reconnect via RDP/VNC at any time without closing the applications.
🚀 Features

    24/7 Uptime: Runs as a Systemd service. Automatically restarts on crashes or server reboots.

    Persistent Session: Uses tightvncserver to keep the GUI running in the background.

    Auto-Update: Checks for the latest Dev-Build of the miner on every start.

    Firefox Nightly: Uses the Nightly build to allow unsigned extensions (e.g., auto-join scripts) via xpinstall.signatures.required = false.

    Clipboard Sync: Includes autocutsel to fix copy/paste between Windows/RDP and the Linux VNC session.

    Snap-Free: Avoids Ubuntu Snap issues by using the PPA version of Firefox.

📋 Prerequisites

    A Linux VPS/Server (Ubuntu 20.04/22.04/24.04 recommended).

    Root/Sudo access.

    xrdp (if you want to connect via Remote Desktop).

🛠️ Installation
1. Install Dependencies

Update your system and install necessary tools (VNC, git, unzip, clipboard tools).
Bash

sudo apt update && sudo apt upgrade -y
sudo apt install tightvncserver xrdp unzip rsync autocutsel -y

2. Install Firefox Nightly

We use the Nightly version to support specific extensions and bypass Snap limitations.
Bash

sudo add-apt-repository ppa:ubuntu-mozilla-daily/ppa -y
sudo apt update
sudo apt install firefox-trunk -y

3. Setup VNC

Start the VNC server once to set up your password.
Bash

vncserver :1
# Enter a secure password. Choose 'n' for view-only.
vncserver -kill :1

4. Deploy the Script

Download or create the restart_twitchdrops.sh script in your home directory (e.g., /home/youruser/).

Configuration in the script:

    Adjust USER_HOME to your home directory.

    Ensure PROGRAM_PATH points to the correct Miner executable location.

Make it executable:
Bash

chmod +x /home/youruser/restart_twitchdrops.sh

5. Setup Systemd Service

Create a service file to keep everything running.

sudo nano /etc/systemd/system/twitchminer.service
Ini, TOML

[Unit]
Description=Twitch Drops Miner Persistent Service
After=network.target

[Service]
Type=simple
User=YOUR_USERNAME
Group=YOUR_USERNAME
WorkingDirectory=/home/YOUR_USERNAME

# Environment
Environment=DISPLAY=:1
Environment=HOME=/home/YOUR_USERNAME

# Cleanup before start
ExecStartPre=-/usr/bin/vncserver -kill :1
ExecStartPre=/bin/rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Start VNC server, wait, then run the script
ExecStart=/bin/bash -c "/usr/bin/vncserver :1 -geometry 1600x900 -depth 24 && sleep 5 && /home/YOUR_USERNAME/restart_twitchdrops.sh"

# Cleanup on stop
ExecStop=/usr/bin/vncserver -kill :1

# Restart policy
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target

Replace YOUR_USERNAME with your actual Linux username!

Enable and start the service:
Bash

sudo systemctl daemon-reload
sudo systemctl enable twitchminer.service
sudo systemctl start twitchminer.service

🖥️ How to Connect (RDP)

To view the miner and change settings, connect via RDP (Remote Desktop Connection) using a specific configuration to attach to the existing session.

    Open Remote Desktop Connection on Windows.

    Connect to your Server IP.

    In the xrdp login screen, choose Session: vnc-any.

    IP: 127.0.0.1

    Port: 5901

    Password: Your VNC password (from Step 3).

⚙️ Firefox Configuration

To allow unsigned extensions (like "Autojoin for SteamGifts") in Firefox Nightly:

    Connect via RDP.

    Firefox should be open. Type about:config in the address bar.

    Search for xpinstall.signatures.required.

    Set it to false.

🐛 Troubleshooting

Copy & Paste not working? The script includes autocutsel to fix this. If it stops working, restart the service:
Bash

sudo systemctl restart twitchminer.service

Browser crashing / "Not a snap cgroup"? Ensure you are using firefox-trunk (Nightly) or the PPA version, not the default Ubuntu Snap Firefox.

Black screen on connection? Make sure you are connecting to Port 5901 and using vnc-any in the RDP menu.
📜 Credits

    Twitch Drops Miner: DevilXD