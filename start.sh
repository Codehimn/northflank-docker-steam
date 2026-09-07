#!/bin/bash
set -e

export HOME=/home/steamuser
export DISPLAY=:0

mkdir -p /data
mkdir -p "$HOME/.steam"
mkdir -p "$HOME/.local/share"

# Use persistent Steam data
if [ -d /data/Steam ]; then
    ln -sfn /data/Steam "$HOME/.local/share/Steam"
else
    mkdir -p /data/Steam
    ln -sfn /data/Steam "$HOME/.local/share/Steam"
fi

echo "Starting Xvfb..."
Xvfb :0 -screen 0 1280x720x24 -ac +extension GLX +render -noreset &

sleep 2

echo "Starting Openbox..."
openbox-session >/tmp/openbox.log 2>&1 &

sleep 2

echo "Starting VNC..."
x11vnc -display :0 -forever -shared -nopw -rfbport 5900 >/tmp/x11vnc.log 2>&1 &

echo "Starting noVNC..."
websockify --web=/usr/share/novnc/ 6080 localhost:5900 >/tmp/novnc.log 2>&1 &

echo "READY"
echo "VNC URL: http://YOUR_NORTHFLANK_DOMAIN:6080/vnc.html"
echo "PASSWORD: none"

# First run: login manually through noVNC.
# Steam login/session remains under /data/Steam.
steam >/tmp/steam.log 2>&1 &

while true; do
    sleep 60
done
