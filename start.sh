#!/bin/bash
set -eu

VERSION="V13"
export HOME=/home/steamuser
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-steamuser

# New path means no stale v10/v11/v12 Wine prefix can interfere.
export WINEPREFIX=/data/taskbarhero-v13

# Wine 11 packages are already new-WoW64. Keep a normal 64-bit prefix and let
# Wine select the right Windows architecture for each executable.
unset WINEARCH || true

export LIBGL_ALWAYS_SOFTWARE=1
export SDL_AUDIODRIVER=dummy
export WINEDEBUG=-all

echo "======================================="
echo "=== TASKBARHERO NORTHFLANK ${VERSION} ==="
echo "======================================="
echo "Runtime architecture: $(uname -m)"
echo "Runtime user: $(id)"
echo "Wine: $(wine --version)"
echo "Persistent prefix: $WINEPREFIX"

case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
        echo "ERROR: V13 requires an x86_64 Northflank node."
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
echo "VNC URL: http://YOUR_NORTHFLANK_DOMAIN:6080/vnc.html?autoconnect=true&resize=remote"
echo "PASSWORD: $VNC_PASSWORD"

# Initialize the Wine prefix only after VNC is already available.
if [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo "FIRST RUN: initializing Wine 11 prefix..."
    mkdir -p "$WINEPREFIX"

    # Disable only Gecko/Mono prompts during prefix creation. Steam itself uses
    # Chromium/CEF, not Wine Gecko.
    WINEDLLOVERRIDES="mscoree,mshtml=;winemenubuilder.exe=d" \
        dbus-launch wineboot -u >>/tmp/wineboot.log 2>&1 || {
            echo "ERROR: wineboot failed"
            tail -150 /tmp/wineboot.log || true
            exit 94
        }

    wineserver -w || true
fi

if [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo "ERROR: Wine prefix was not created."
    exit 95
fi

echo "Wine prefix: OK"

# Prove on the actual Northflank runtime that 32-bit Windows execution works.
if ! WINEDLLOVERRIDES="winemenubuilder.exe=d" \
     wine 'C:\windows\syswow64\cmd.exe' /c exit \
     >/tmp/wow64-runtime-test.log 2>&1; then
    echo "ERROR: Wine new-WoW64 could not execute a 32-bit Windows component."
    tail -120 /tmp/wow64-runtime-test.log || true
    exit 96
fi

echo "Wine WoW64: OK"

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

    find "$WINEPREFIX/drive_c" \
        -maxdepth 6 \
        -type f \
        -iname steam.exe \
        -print -quit 2>/dev/null || true
}

steam_running() {
    pgrep -u "$(id -u)" -f 'steam\.exe|steamwebhelper\.exe' >/dev/null 2>&1
}

installer_running() {
    pgrep -u "$(id -u)" -f 'SteamSetup\.exe' >/dev/null 2>&1
}

start_installer() {
    echo "FIRST RUN: Steam is not installed."
    echo "Opening SteamSetup.exe visibly in VNC..."
    echo "Complete the Steam installer in the browser VNC window."

    WINEDLLOVERRIDES="winemenubuilder.exe=d" \
        dbus-launch wine /opt/steam-bootstrap/SteamSetup.exe \
        >>/tmp/steam-installer.log 2>&1 &

    echo "Steam installer PID: $!"
}

start_steam() {
    STEAM_EXE="$(find_steam)"
    if [ -z "$STEAM_EXE" ] || [ ! -s "$STEAM_EXE" ]; then
        return 1
    fi

    echo "Steam executable: $STEAM_EXE"
    echo "Starting Windows Steam visible..."

    WINEDLLOVERRIDES="winemenubuilder.exe=d" \
        dbus-launch wine "$STEAM_EXE" \
        -no-cef-sandbox \
        -cef-disable-gpu \
        -cef-disable-gpu-compositing \
        >>/tmp/steam.log 2>&1 &

    echo "Steam launcher PID: $!"
    return 0
}

STEAM_EXE="$(find_steam)"
if [ -n "$STEAM_EXE" ] && [ -s "$STEAM_EXE" ]; then
    start_steam
else
    start_installer
fi

# Installer/Steam state machine. Never kill the container just because the
# installer was closed: keep VNC alive and surface diagnostics.
INSTALL_RETRY_AT=0

while kill -0 "$XVFB_PID" 2>/dev/null; do
    sleep 5

    if ! kill -0 "$VNC_PID" 2>/dev/null; then
        echo "ERROR: x11vnc exited"
        tail -100 /tmp/x11vnc.log || true
        exit 97
    fi

    if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
        echo "ERROR: noVNC exited"
        tail -100 /tmp/novnc.log || true
        exit 98
    fi

    STEAM_EXE="$(find_steam)"

    if [ -n "$STEAM_EXE" ] && [ -s "$STEAM_EXE" ]; then
        if ! installer_running && ! steam_running; then
            echo "Steam installation detected."
            start_steam || true
            sleep 15
        fi
    else
        if ! installer_running; then
            NOW="$(date +%s)"
            if [ "$NOW" -ge "$INSTALL_RETRY_AT" ]; then
                echo "Steam is not installed yet."
                echo "Last installer log:"
                tail -80 /tmp/steam-installer.log 2>/dev/null || true
                echo "Reopening installer..."
                start_installer
                INSTALL_RETRY_AT=$((NOW + 30))
            fi
        fi
    fi
done

echo "ERROR: Xvfb exited"
cat /tmp/xvfb.log || true
exit 99
