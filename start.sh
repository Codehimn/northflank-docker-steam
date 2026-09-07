#!/bin/bash
set -e

export HOME=/home/steamuser
export DISPLAY=:0

echo "Preparing Steam data..."

mkdir -p "$HOME/.local/share"

# Persistencia Steam
rm -rf "$HOME/.local/share/Steam"
ln -s /data/Steam "$HOME/.local/share/Steam"

echo "Starting Xvfb..."
Xvfb :0 \
    -screen 0 1280x720x24 \
    -ac \
    +extension GLX \
    +render \
    -noreset &

sleep 3

echo "Starting Openbox..."
openbox-session >/tmp/openbox.log 2>&1 &

sleep 2

echo "Starting VNC..."
x11vnc \
    -display :0 \
    -forever \
    -shared \
    -nopw \
    -rfbport 5900 >/tmp/x11vnc.log 2>&1 &

sleep 2

echo "Starting noVNC..."
websockify \
    --web=/usr/share/novnc/ \
    6080 localhost:5900 >/tmp/novnc.log 2>&1 &

sleep 2

echo "READY"
echo "VNC URL: http://YOUR_NORTHFLANK_DOMAIN:6080/vnc.html"
echo "PASSWORD: none"

echo "Starting Steam visible..."
steam -silent >/tmp/steam.log 2>&1 &

# Mantener contenedor vivo
while true; do
    sleep 60
done
