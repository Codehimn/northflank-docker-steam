#!/bin/bash
set -e

export DISPLAY=:99

echo "=== TaskbarHero V6 starting ==="

if [ ! -f /root/.vnc/passwd ]; then
    x11vnc -storepasswd cambiar123 /root/.vnc/passwd
fi

echo "Starting Xvfb"
Xvfb :99 -screen 0 1280x720x16 -ac -nolisten tcp -noreset &

sleep 3

echo "Starting Openbox"
openbox &

sleep 2

echo "Starting VNC"
x11vnc \
-display :99 \
-rfbport 5900 \
-rfbauth /root/.vnc/passwd \
-forever \
-shared \
-noxdamage \
-bg

sleep 2

echo "Starting noVNC"
websockify --web=/usr/share/novnc/ 6080 localhost:5900 &

sleep 5

echo "Installing Steam if needed..."
/opt/taskbarhero/install-steam.sh || true

echo "Launching Steam..."
/opt/taskbarhero/start-steam.sh || true

tail -f /dev/null
