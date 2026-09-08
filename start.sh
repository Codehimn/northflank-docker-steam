#!/bin/bash
set -eu

export HOME=/home/steamuser
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-steamuser
export WINEPREFIX=/data/wineprefix
export WINEARCH=wow64

# No GPU/audio on the target service.
export LIBGL_ALWAYS_SOFTWARE=1
export SDL_AUDIODRIVER=dummy

# Avoid Wine Gecko/Mono prompts and unnecessary Start-menu integration.
export WINEDLLOVERRIDES="mscoree,mshtml=;winemenubuilder.exe=d"
export WINEDEBUG=-all

echo "Runtime architecture: $(uname -m)"
echo "Runtime user: $(id)"
echo "Wine: $(wine --version)"

case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
        echo "ERROR: this image requires an x86_64 Northflank node."
        exit 86
        ;;
esac

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

if [ ! -w /data ]; then
    echo "ERROR: /data is not writable by steamuser."
    echo "UID=$(id -u) GID=$(id -g)"
    exit 88
fi

# No installer is run at container startup.
# On the first boot we only copy the prefix already prepared during Docker build.
if [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo "Creating persistent Wine prefix from build-time template..."
    mkdir -p "$WINEPREFIX"
    cp -a /opt/wineprefix-template/. "$WINEPREFIX/"
fi

STEAM_EXE="$WINEPREFIX/drive_c/Program Files (x86)/Steam/steam.exe"
if [ ! -f "$STEAM_EXE" ]; then
    # Future Steam installers might choose Program Files instead.
    STEAM_EXE="$WINEPREFIX/drive_c/Program Files/Steam/steam.exe"
fi

if [ ! -f "$STEAM_EXE" ]; then
    echo "ERROR: Windows Steam executable was not found in the prepared prefix."
    find "$WINEPREFIX/drive_c" -maxdepth 5 -iname 'steam.exe' -print || true
    exit 89
fi

echo "Steam executable: $STEAM_EXE"

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
    echo "Starting Windows Steam through Wine 11 WoW64..."
    dbus-launch wine "$STEAM_EXE" \
        -no-cef-sandbox \
        -nochatui \
        -nofriendsui \
        >>/tmp/steam-wine.log 2>&1 &
    echo "Steam/Wine launcher PID: $!"
}

start_steam

# Steam may self-update and replace/restart its own processes.
sleep 35
if ! pgrep -u "$(id -u)" -f 'steam.exe|steamwebhelper|wineserver' >/dev/null 2>&1; then
    echo "WARNING: no Steam/Wine process detected after startup."
    echo "----- /tmp/steam-wine.log -----"
    tail -180 /tmp/steam-wine.log || true
fi

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

    if ! pgrep -u "$(id -u)" -f 'steam.exe|steamwebhelper|wineserver' >/dev/null 2>&1; then
        echo "Steam/Wine stopped. Last log:"
        tail -120 /tmp/steam-wine.log || true
        echo "Restarting Steam..."
        start_steam
    fi
done

echo "ERROR: Xvfb exited"
cat /tmp/xvfb.log || true
exit 96
