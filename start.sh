#!/bin/bash
set -eu

export HOME=/home/steamuser
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-steamuser

# Force software rendering: Northflank free tier has no GPU.
export LIBGL_ALWAYS_SOFTWARE=1
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Persist Steam bootstrap/client/login/game files on Northflank's /data volume.
mkdir -p /data/Steam /data/.steam "$HOME/.local/share"

rm -rf "$HOME/.local/share/Steam" "$HOME/.steam"
ln -s /data/Steam "$HOME/.local/share/Steam"
ln -s /data/.steam "$HOME/.steam"

STEAM_BIN="$(command -v steam || true)"
if [ -z "$STEAM_BIN" ]; then
    echo "ERROR: Steam binary not found"
    exit 1
fi

echo "Steam binary: $STEAM_BIN"

echo "Starting Xvfb..."
Xvfb :0 \
    -screen 0 1280x720x24 \
    -ac \
    +extension GLX \
    +render \
    -noreset \
    >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!

sleep 2
if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    echo "ERROR: Xvfb failed"
    cat /tmp/xvfb.log || true
    exit 1
fi

echo "Starting Openbox..."
openbox-session >/tmp/openbox.log 2>&1 &

sleep 1

echo "Starting VNC..."
x11vnc \
    -display :0 \
    -forever \
    -shared \
    -nopw \
    -rfbport 5900 \
    >/tmp/x11vnc.log 2>&1 &

sleep 1

echo "Starting noVNC..."
websockify \
    --web=/usr/share/novnc \
    6080 localhost:5900 \
    >/tmp/novnc.log 2>&1 &

sleep 1

echo "READY"
echo "VNC URL: http://YOUR_NORTHFLANK_DOMAIN:6080/vnc.html?autoconnect=true"
echo "PASSWORD: none"

echo "Starting Steam visible..."
dbus-launch --exit-with-session \
    "$STEAM_BIN" \
    -cef-disable-gpu \
    -cef-disable-gpu-compositing \
    >/tmp/steam.log 2>&1 &
STEAM_PID=$!

echo "Steam PID: $STEAM_PID"

# If the launcher exits immediately, print useful diagnostics.
sleep 10
if ! kill -0 "$STEAM_PID" 2>/dev/null; then
    echo "Steam launcher exited or re-execed."
    echo "----- /tmp/steam.log -----"
    tail -120 /tmp/steam.log || true
fi

# Keep the graphical session alive.
while kill -0 "$XVFB_PID" 2>/dev/null; do
    sleep 60
done

echo "ERROR: Xvfb exited"
cat /tmp/xvfb.log || true
exit 1
