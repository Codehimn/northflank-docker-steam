#!/bin/bash
set -eu

export HOME=/home/steamuser
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-steamuser

# Northflank has no GPU. Let Mesa use software rendering.
export LIBGL_ALWAYS_SOFTWARE=1

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# /data must be the Northflank persistent volume.
if [ ! -w /data ]; then
    echo "ERROR: /data is not writable by steamuser"
    echo "Configure the Northflank persistent volume so UID $(id -u) can write to /data."
    exit 1
fi

mkdir -p /data/Steam /data/.steam "$HOME/.local/share"

# Persist Steam client, login session, games and Proton files.
rm -rf "$HOME/.local/share/Steam" "$HOME/.steam"
ln -s /data/Steam "$HOME/.local/share/Steam"
ln -s /data/.steam "$HOME/.steam"

STEAM_BIN=/usr/games/steam

if [ ! -x "$STEAM_BIN" ]; then
    echo "ERROR: Steam launcher missing at $STEAM_BIN"
    exit 1
fi

# Runtime checks for the exact failure seen previously.
if [ ! -e /lib/ld-linux.so.2 ] || [ ! -e /lib/i386-linux-gnu/libc.so.6 ]; then
    echo "ERROR: required 32-bit libc runtime is missing"
    exit 1
fi

if ! /lib/ld-linux.so.2 --help >/dev/null 2>&1; then
    echo "ERROR: the host cannot execute i386 binaries"
    exit 1
fi

echo "32-bit runtime: OK"
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

# A random VNC password is printed to Northflank logs at every container start.
# It avoids exposing a logged-in Steam account on a public noVNC endpoint.
VNC_PASSWORD="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
VNC_PASSFILE=/tmp/x11vnc.pass
x11vnc -storepasswd "$VNC_PASSWORD" "$VNC_PASSFILE" >/dev/null 2>&1
chmod 600 "$VNC_PASSFILE"

echo "Starting VNC..."
x11vnc \
    -display :0 \
    -forever \
    -shared \
    -rfbport 5900 \
    -rfbauth "$VNC_PASSFILE" \
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
echo "PASSWORD: $VNC_PASSWORD"

start_steam() {
    echo "Starting Steam visible..."
    # -no-cef-sandbox avoids a common steamwebhelper failure in restricted
    # container runtimes where unprivileged user namespaces are unavailable.
    dbus-launch \
        "$STEAM_BIN" \
        -no-cef-sandbox \
        -cef-disable-gpu \
        -cef-disable-gpu-compositing \
        >>/tmp/steam.log 2>&1 &
    echo "Steam launcher PID: $!"
}

start_steam

# Give Steam time to bootstrap/update. If it fails, surface the useful log
# instead of leaving a mysterious black VNC screen.
sleep 20
if ! pgrep -u "$(id -u)" -f 'steam|steamwebhelper' >/dev/null 2>&1; then
    echo "WARNING: no Steam process detected after startup."
    echo "----- /tmp/steam.log -----"
    tail -150 /tmp/steam.log || true
fi

# Keep the container alive and recover if Steam fully crashes.
while kill -0 "$XVFB_PID" 2>/dev/null; do
    sleep 60

    if ! pgrep -u "$(id -u)" -f 'steam|steamwebhelper' >/dev/null 2>&1; then
        echo "Steam is not running. Last Steam log:"
        tail -80 /tmp/steam.log || true
        echo "Restarting Steam..."
        start_steam
    fi
done

echo "ERROR: Xvfb exited"
cat /tmp/xvfb.log || true
exit 1
