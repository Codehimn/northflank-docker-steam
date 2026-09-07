#!/bin/bash
set -e
export DISPLAY=:99
export HOME=/home/steamuser
export XDG_RUNTIME_DIR=/tmp/runtime-steam

mkdir -p $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR

Xvfb :99 -screen 0 1024x768x16 -ac -nolisten tcp &
sleep 3

dbus-launch openbox &
sleep 2

mkdir -p ~/.vnc
x11vnc -storepasswd "$VNC_PASSWORD" ~/.vnc/passwd

x11vnc -display :99 -rfbauth ~/.vnc/passwd -forever -shared -rfbport 5900 &

websockify --web=/usr/share/novnc 6080 localhost:5900 &

sleep 5
echo "Starting Steam..."
steam -silent &

tail -f /dev/null
