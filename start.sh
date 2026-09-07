#!/bin/bash
set -e

echo "=== TaskbarHero optimized container ==="

export DISPLAY=:99

# Create VNC password only if it does not exist
if [ ! -f /root/.vnc/passwd ]; then
    x11vnc -storepasswd cambiar123 /root/.vnc/passwd
fi

echo "Cleaning temporary cache..."
rm -rf /tmp/* || true


echo "Starting Xvfb..."
Xvfb :99 \
    -screen 0 1024x768x16 \
    -ac \
    -nolisten tcp \
    -noreset > /opt/taskbarhero/logs/xvfb.log 2>&1 &

sleep 3


echo "Starting Openbox..."
openbox > /opt/taskbarhero/logs/openbox.log 2>&1 &

sleep 2


echo "Starting x11vnc..."
x11vnc \
    -display :99 \
    -rfbport 5900 \
    -rfbauth /root/.vnc/passwd \
    -forever \
    -shared \
    -noxdamage \
    -cursor arrow \
    -bg > /opt/taskbarhero/logs/x11vnc.log 2>&1


sleep 3


echo "Starting noVNC..."
websockify \
    --web=/usr/share/novnc/ \
    6080 localhost:5900 > /opt/taskbarhero/logs/novnc.log 2>&1 &


sleep 3

echo "================================="
echo "READY"
echo "URL: /vnc.html"
echo "VNC PASSWORD: cambiar123"
echo "================================="


# Keep alive
tail -f /dev/null
