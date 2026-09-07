#!/bin/bash
set -e

export HOME=/home/steamuser
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-steamuser

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

mkdir -p "$HOME/.local/share"
rm -rf "$HOME/.local/share/Steam"
ln -s /data/Steam "$HOME/.local/share/Steam"

echo "Checking Steam binary..."
STEAM_BIN=$(command -v steam || true)

if [ -z "$STEAM_BIN" ]; then
    echo "ERROR: Steam binary not found"
    exit 1
fi

echo "Steam binary: $STEAM_BIN"

echo "Starting Xvfb..."
Xvfb :0 -screen 0 1280x720x24 -ac +extension GLX +render -noreset >/tmp/xvfb.log 2>&1 &

sleep 3

echo "Starting Openbox..."
openbox-session >/tmp/openbox.log 2>&1 &

sleep 2

echo "Starting dbus..."
dbus-launch --exit-with-session true >/dev/null 2>&1 || true

echo "Starting VNC..."
x11vnc -display :0 -forever -shared -nopw -rfbport 5900 >/tmp/x11vnc.log 2>&1 &

sleep 2

echo "Starting noVNC..."
websockify --web=/usr/share/novnc 6080 localhost:5900 >/tmp/novnc.log 2>&1 &

sleep 2

echo "READY"
echo "VNC URL: http://YOUR_NORTHFLANK_DOMAIN:6080/vnc.html"
echo "PASSWORD: none"

echo "Starting Steam..."

steam -silent >/tmp/steam.log 2>&1 &

STEAM_PID=$!
echo "Steam PID: $STEAM_PID"

while kill -0 $STEAM_PID 2>/dev/null; do
    sleep 30
done

echo "Steam exited. Last log:"
tail -50 /tmp/steam.log || true

while true; do
    sleep 60
done
