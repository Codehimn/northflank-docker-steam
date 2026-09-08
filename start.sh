#!/bin/bash
set -eu

export HOME=/home/steamuser
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-steamuser

# No GPU on the target service. Mesa/CEF must stay on software rendering.
export LIBGL_ALWAYS_SOFTWARE=1
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
export SDL_AUDIODRIVER=dummy

echo "Runtime architecture: $(uname -m)"

# Native Steam requires an x86_64 runtime.
case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
        echo "ERROR: Steam requires an x86/x86_64 Northflank deployment."
        echo "Set the Northflank service infrastructure architecture to x86."
        exit 86
        ;;
esac

# Steam's actual client bootstrap is still i386. Test this on the FINAL runtime,
# not during Docker build, because BuildKit can be cross-architecture.
if ! /lib/ld-linux.so.2 --help >/dev/null 2>&1; then
    echo "ERROR: this Northflank runtime cannot execute 32-bit i386 binaries."
    echo "Steam Linux cannot run natively on this node even though libc6:i386 is installed."
    echo "Use an x86 Northflank deployment/node with IA32 compatibility enabled."
    exit 87
fi

echo "32-bit runtime: OK"

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

if [ ! -w /data ]; then
    echo "ERROR: /data is not writable by steamuser (UID $(id -u))."
    exit 88
fi

mkdir -p /data/Steam /data/.steam "$HOME/.local/share"

# Clean ONLY old Steam client/bootstrap files once when upgrading from previous
# container revisions. Login/config/userdata and installed games are preserved.
IMAGE_REVISION="v8"
if [ ! -f "/data/.taskbarhero-image-${IMAGE_REVISION}" ]; then
    echo "Refreshing old Steam client bootstrap while preserving login/game data..."
    rm -rf \
        /data/Steam/ubuntu12_32 \
        /data/Steam/ubuntu12_64 \
        /data/Steam/package \
        /data/Steam/steam-runtime \
        /data/Steam/steam-runtime-heavy \
        2>/dev/null || true
    touch "/data/.taskbarhero-image-${IMAGE_REVISION}"
fi

# Persistent login/client/game data.
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
    exit 90
fi

echo "Starting Openbox..."
openbox-session >/tmp/openbox.log 2>&1 &
sleep 1

# Generate a temporary VNC password unless VNC_PASSWORD was supplied by
# Northflank as an environment variable.
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
    exit 91
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
    exit 92
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

sleep 25
if ! pgrep -u "$(id -u)" -f 'steam|steamwebhelper' >/dev/null 2>&1; then
    echo "WARNING: Steam is not running after initial startup."
    echo "----- /tmp/steam.log -----"
    tail -160 /tmp/steam.log || true
fi

# Keep X/VNC alive and restart Steam if the client fully exits.
while kill -0 "$XVFB_PID" 2>/dev/null; do
    sleep 60

    if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
        echo "ERROR: noVNC exited"
        tail -80 /tmp/novnc.log || true
        exit 93
    fi

    if ! pgrep -u "$(id -u)" -f 'steam|steamwebhelper' >/dev/null 2>&1; then
        echo "Steam stopped. Last log:"
        tail -100 /tmp/steam.log || true
        echo "Restarting Steam..."
        start_steam
    fi
done

echo "ERROR: Xvfb exited"
cat /tmp/xvfb.log || true
exit 94
