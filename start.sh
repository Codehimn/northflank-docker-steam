#!/bin/bash
set -e

echo "Starting Xvfb..."

Xvfb :99 \
    -screen 0 1024x768x16 \
    -ac \
    -noreset &

sleep 3

export DISPLAY=:99

echo "Starting Openbox..."

openbox &

sleep 2

echo "Starting VNC server..."

x11vnc \
    -display :99 \
    -rfbport 5900 \
    -forever \
    -shared \
    -noxdamage \
    -bg

sleep 3

echo "Starting noVNC..."

websockify \
    --web=/usr/share/novnc/ \
    6080 localhost:5900
