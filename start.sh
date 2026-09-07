#!/bin/bash
set -e

export DISPLAY=:99
export HOME=/home/steamuser
export XDG_RUNTIME_DIR=/tmp/runtime-steam

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

echo "Starting Xvfb..."
Xvfb :99 -screen 0 1024x768x16 -ac -nolisten tcp &

sleep 3

echo "Starting Openbox..."
dbus-launch openbox &

sleep 3

echo "Starting VNC..."
mkdir -p ~/.vnc
x11vnc -storepasswd "$VNC_PASSWORD" ~/.vnc/passwd

x11vnc \
-display :99 \
-rfbauth ~/.vnc/passwd \
-forever \
-shared \
-rfbport 5900 &

sleep 2

echo "Starting noVNC..."
/opt/noVNC/utils/novnc_proxy \
--vnc localhost:5900 \
--listen 6080 &

sleep 5

echo "Starting Steam..."
steam -silent &

echo "READY"
echo "Open: /vnc.html"
echo "Password: $VNC_PASSWORD"

tail -f /dev/null
