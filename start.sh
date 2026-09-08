#!/bin/bash
set -eu

export HOME=/home/steamuser
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-steamuser

# Northflank free tier: no GPU and no audio required.
export LIBGL_ALWAYS_SOFTWARE=1
export SDL_AUDIODRIVER=dummy

echo "Runtime architecture: $(uname -m)"
echo "Runtime user: $(id)"

case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
        echo "ERROR: Steam requires an x86/x86_64 Northflank deployment."
        echo "Select x86 architecture for the service."
        exit 86
        ;;
esac

# Test i386 execution only on the FINAL runtime.
if ! /lib/ld-linux.so.2 --help >/dev/null 2>&1; then
    echo "ERROR: this runtime cannot execute 32-bit i386 binaries."
    echo "Steam Linux requires IA32 compatibility on the x86_64 node."
    exit 87
fi

echo "32-bit runtime: OK"

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

if [ ! -w /data ]; then
    echo "ERROR: /data is not writable by steamuser."
    echo "steamuser UID=$(id -u) GID=$(id -g)"
    echo "The Northflank persistent volume must permit this non-root user to write."
    exit 88
fi

mkdir -p /data/Steam /data/.steam "$HOME/.local/share"

# Remove only stale Steam bootstrap/runtime files from previous image revisions.
# Preserve config, userdata, login state, steamapps and Proton prefixes.
IMAGE_REVISION="v9"
if [ ! -f "/data/.taskbarhero-image-${IMAGE_REVISION}" ]; then
    echo "Refreshing Steam bootstrap from previous container revisions..."
    rm -rf \
        /data/Steam/ubuntu12_32 \
        /data/Steam/ubuntu12_64 \
        /data/Steam/package \
        /data/Steam/steam-runtime \
        /data/Steam/steam-runtime-heavy \
        2>/dev/null || true
    touch "/data/.taskbarhero-image-${IMAGE_REVISION}"
fi

rm -rf "$HOME/.local/share/Steam" "$HOME/.steam"
ln -s /data/Steam "$HOME/.local/share/Steam"
ln -s /data/.steam "$HOME/.steam"

STEAM_BIN=/usr/games/steam
if [ ! -x "$STEAM_BIN" ]; then
    echo "ERROR: Steam launcher missing at $STEAM_BIN"
    exit 89
fi

echo "Steam binary: $STEAM_BIN"

echo "Starting Xvfb..."
Xvfb :0 \
    -screen 0 1024x640x24 \
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
    exit 90
fi

echo "Starting Openbox..."
openbox-session >/tmp/openbox.log 2>&1 &
OPENBOX_PID=$!

sleep 1
if ! kill -0 "$OPENBOX_PID" 2>/dev/null; then
    echo "ERROR: Openbox failed"
    cat /tmp/openbox.log || true
    exit 91
fi

# Use a Northflank VNC_PASSWORD env var if provided; otherwise generate one.
if [ -z "${VNC_PASSWORD:-}" ]; then
    VNC_PASSWORD="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
fi

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
VNC_PID=$!

sleep 1
if ! kill -0 "$VNC_PID" 2>/dev/null; then
    echo "ERROR: x11vnc failed"
    cat /tmp/x11vnc.log || true
    exit 92
fi

echo "Starting noVNC..."
websockify \
    --web=/usr/share/novnc \
    6080 localhost:5900 \
    >/tmp/novnc.log 2>&1 &
NOVNC_PID=$!

sleep 1
if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
    echo "ERROR: noVNC/websockify failed"
    cat /tmp/novnc.log || true
    exit 93
fi

echo "READY"
echo "VNC URL: http://YOUR_NORTHFLANK_DOMAIN:6080/vnc.html?autoconnect=true"
echo "PASSWORD: $VNC_PASSWORD"

start_steam() {
    echo "Starting Steam visible..."
    dbus-launch \
        "$STEAM_BIN" \
        -no-cef-sandbox \
        -cef-disable-gpu \
        -cef-disable-gpu-compositing \
        >>/tmp/steam.log 2>&1 &
    echo "Steam launcher PID: $!"
}

start_steam

# First Steam launch can download/update its client, so allow it time.
sleep 30
if ! pgrep -u "$(id -u)" -f 'steam|steamwebhelper' >/dev/null 2>&1; then
    echo "WARNING: no Steam process detected after startup."
    echo "----- /tmp/steam.log -----"
    tail -180 /tmp/steam.log || true
fi

# Keep graphical services alive and recover Steam if it fully exits.
while kill -0 "$XVFB_PID" 2>/dev/null; do
    sleep 60

    if ! kill -0 "$VNC_PID" 2>/dev/null; then
        echo "ERROR: x11vnc exited"
        tail -100 /tmp/x11vnc.log || true
        exit 94
    fi

    if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
        echo "ERROR: noVNC exited"
        tail -100 /tmp/novnc.log || true
        exit 95
    fi

    if ! pgrep -u "$(id -u)" -f 'steam|steamwebhelper' >/dev/null 2>&1; then
        echo "Steam stopped. Last log:"
        tail -120 /tmp/steam.log || true
        echo "Restarting Steam..."
        start_steam
    fi
done

echo "ERROR: Xvfb exited"
cat /tmp/xvfb.log || true
exit 96
