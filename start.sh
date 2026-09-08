#!/bin/bash
set -eu

export HOME=/home/steamuser
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-steamuser

# Force Wine 11's new WoW64 path. The prefix itself was created as 64-bit.
export WINEARCH=wow64
export WINEPREFIX=/data/taskbarhero-wine-v12

# No GPU and no audio are required for the management session.
export LIBGL_ALWAYS_SOFTWARE=1
export SDL_AUDIODRIVER=dummy
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
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

# First runtime only: copy an already-prepared Wine prefix.
# This is just file copying, not package installation.
if [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo "Preparing persistent Wine prefix..."
    rm -rf "$WINEPREFIX"
    mkdir -p "$WINEPREFIX"
    cp -a /opt/wineprefix-template/. "$WINEPREFIX/"
fi

if [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo "ERROR: persistent Wine prefix could not be prepared."
    exit 89
fi

echo "Wine prefix: $WINEPREFIX"

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

# Use VNC_PASSWORD from Northflank if configured; otherwise generate one.
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
echo "VNC URL: http://YOUR_NORTHFLANK_DOMAIN:6080/vnc.html?autoconnect=true&resize=remote"
echo "PASSWORD: $VNC_PASSWORD"

find_steam() {
    for p in \
        "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steam.exe" \
        "$WINEPREFIX/drive_c/Program Files/Steam/steam.exe" \
        "$WINEPREFIX/drive_c/Steam/steam.exe"
    do
        if [ -s "$p" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    done

    found="$(find "$WINEPREFIX/drive_c" -maxdepth 5 -type f -iname steam.exe -print -quit 2>/dev/null || true)"
    if [ -n "$found" ]; then
        printf '%s\n' "$found"
        return 0
    fi

    return 1
}

steam_running() {
    pgrep -u "$(id -u)" -f 'steam\.exe|steamwebhelper\.exe' >/dev/null 2>&1
}

installer_running() {
    pgrep -u "$(id -u)" -f 'SteamSetup\.exe' >/dev/null 2>&1
}

start_steam() {
    STEAM_EXE="$(find_steam || true)"
    if [ -z "$STEAM_EXE" ]; then
        return 1
    fi

    echo "Steam executable: $STEAM_EXE"
    echo "Starting Steam visible..."

    dbus-launch wine "$STEAM_EXE" \
        -no-cef-sandbox \
        -cef-disable-gpu \
        -cef-disable-gpu-compositing \
        >>/tmp/steam-wine.log 2>&1 &

    echo "Steam/Wine launcher PID: $!"
    return 0
}

start_installer() {
    echo "FIRST RUN: Steam is not installed yet."
    echo "Opening the official Steam installer in VNC."
    echo "Complete the installer visually. After it finishes, Steam will start automatically."

    dbus-launch wine /opt/steam-bootstrap/SteamSetup.exe \
        >>/tmp/steam-installer.log 2>&1 &

    echo "Steam installer PID: $!"
}

# Existing persistent installation: start it immediately.
if STEAM_EXE="$(find_steam || true)" && [ -n "$STEAM_EXE" ]; then
    start_steam
else
    # First boot only. This is intentionally interactive because unattended
    # SteamSetup under Wine proved fragile. The installer binary itself was
    # already downloaded during Docker build.
    start_installer
fi

# State machine:
# - while installer is visible, user completes it through VNC
# - once steam.exe appears and installer exits, Steam is launched
# - after that Steam is restarted if it genuinely crashes
while kill -0 "$XVFB_PID" 2>/dev/null; do
    sleep 5

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

    STEAM_EXE="$(find_steam || true)"

    if [ -n "$STEAM_EXE" ]; then
        if ! installer_running && ! steam_running; then
            echo "Steam installation detected."
            start_steam || true
            sleep 15
        fi
    else
        if ! installer_running; then
            echo "Steam is still not installed. Reopening installer in VNC..."
            echo "----- installer log -----"
            tail -80 /tmp/steam-installer.log 2>/dev/null || true
            start_installer
            sleep 10
        fi
    fi
done

echo "ERROR: Xvfb exited"
cat /tmp/xvfb.log || true
exit 96
