#!/bin/bash
set -e

export DISPLAY=:99

mkdir -p /root/.steam

# Download Steam installer first run
if [ ! -f /root/.steam/steamcmd.tar.gz ]; then
    echo "Downloading Steam installer..."
    wget -q https://steamcdn-a.akamaihd.net/client/installer/steam.deb -O /tmp/steam.deb
    dpkg -i /tmp/steam.deb || apt-get update && apt-get -f install -y
fi

echo "Starting Steam..."

steam >/tmp/steam.log 2>&1 || true

tail -f /tmp/steam.log
