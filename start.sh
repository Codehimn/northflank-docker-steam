#!/bin/bash
set -Eeuo pipefail

VERSION="V14-DEFENSIVE"
export HOME=/home/steamuser
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-steamuser
export WINEPREFIX=/data/taskbarhero-v14

# Northflank target has no GPU/audio. Steam's own UI is forced to software mode.
export LIBGL_ALWAYS_SOFTWARE=1
export SDL_AUDIODRIVER=dummy

# Wine 11: create a normal 64-bit prefix first, then force new-WoW64 when
# executing 32-bit Windows components.
unset WINEARCH || true

XVFB_PID=""
OPENBOX_PID=""
VNC_PID=""
NOVNC_PID=""
DBUS_SESSION_BUS_PID="${DBUS_SESSION_BUS_PID:-}"

log() {
    printf '%s\n' "$*"
}

cleanup() {
    set +e
    log "Shutting down..."
    wineserver -k >/dev/null 2>&1 || true
    [ -n "${NOVNC_PID:-}" ] && kill "$NOVNC_PID" >/dev/null 2>&1 || true
    [ -n "${VNC_PID:-}" ] && kill "$VNC_PID" >/dev/null 2>&1 || true
    [ -n "${OPENBOX_PID:-}" ] && kill "$OPENBOX_PID" >/dev/null 2>&1 || true
    [ -n "${XVFB_PID:-}" ] && kill "$XVFB_PID" >/dev/null 2>&1 || true
    [ -n "${DBUS_SESSION_BUS_PID:-}" ] && kill "$DBUS_SESSION_BUS_PID" >/dev/null 2>&1 || true
}
trap cleanup TERM INT EXIT

hold_for_debug() {
    log "Container will stay alive so VNC/logs remain available for diagnosis."
    while true; do sleep 3600; done
}

log "=========================================="
log "=== TASKBARHERO NORTHFLANK ${VERSION} ==="
log "=========================================="
log "Runtime architecture: $(uname -m)"
log "Runtime user: $(id)"
log "Wine: $(wine --version)"
log "Prefix: $WINEPREFIX"
log "Memory:"
grep -E 'MemTotal|MemAvailable' /proc/meminfo || true
log "/dev/shm:"
df -h /dev/shm 2>/dev/null || true

case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
        log "FATAL: this image requires an x86_64 Northflank node."
        hold_for_debug
        ;;
esac

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# A mounted volume can hide the ownership set during Docker build, so verify the
# real runtime mount rather than assuming it is writable.
if ! mkdir -p "$WINEPREFIX" 2>/tmp/data-error.log; then
    log "FATAL: /data is not writable by steamuser."
    log "UID=$(id -u) GID=$(id -g)"
    cat /tmp/data-error.log || true
    hold_for_debug
fi

# One shared D-Bus session for Openbox and Wine. This avoids accumulating
# dbus-launch processes after Steam self-updates/restarts.
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
log "D-Bus session: OK"

log "Starting Xvfb..."
Xvfb :0 \
    -screen 0 1024x640x24 \
    -ac \
    +extension GLX \
    +render \
    -noreset \
    >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!

# Avoid fixed sleeps/races. Wait until X really accepts connections.
X_READY=0
for _ in $(seq 1 50); do
    if xdpyinfo -display :0 >/dev/null 2>&1; then
        X_READY=1
        break
    fi
    if ! kill -0 "$XVFB_PID" 2>/dev/null; then
        break
    fi
    sleep 0.2
done

if [ "$X_READY" -ne 1 ]; then
    log "FATAL: Xvfb did not become ready."
    cat /tmp/xvfb.log || true
    hold_for_debug
fi
log "Xvfb: OK"

log "Starting Openbox..."
openbox-session >/tmp/openbox.log 2>&1 &
OPENBOX_PID=$!

sleep 0.5
if ! kill -0 "$OPENBOX_PID" 2>/dev/null; then
    log "FATAL: Openbox failed."
    cat /tmp/openbox.log || true
    hold_for_debug
fi
log "Openbox: OK"

# VNC passwords are effectively 8 chars in classic VNC auth. Generate exactly 8.
if [ -z "${VNC_PASSWORD:-}" ]; then
    VNC_PASSWORD="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
else
    VNC_PASSWORD="${VNC_PASSWORD:0:8}"
fi

VNC_PASSFILE=/tmp/x11vnc.pass
x11vnc -storepasswd "$VNC_PASSWORD" "$VNC_PASSFILE" >/dev/null 2>&1
chmod 600 "$VNC_PASSFILE"

start_vnc() {
    x11vnc \
        -display :0 \
        -forever \
        -shared \
        -noxdamage \
        -rfbport 5900 \
        -rfbauth "$VNC_PASSFILE" \
        >/tmp/x11vnc.log 2>&1 &
    VNC_PID=$!
}

start_novnc() {
    websockify \
        --web=/usr/share/novnc \
        6080 localhost:5900 \
        >/tmp/novnc.log 2>&1 &
    NOVNC_PID=$!
}

log "Starting VNC..."
start_vnc
sleep 0.5
if ! kill -0 "$VNC_PID" 2>/dev/null; then
    log "FATAL: x11vnc failed."
    cat /tmp/x11vnc.log || true
    hold_for_debug
fi
log "VNC: OK"

log "Starting noVNC..."
start_novnc
sleep 0.5
if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
    log "FATAL: noVNC/websockify failed."
    cat /tmp/novnc.log || true
    hold_for_debug
fi
log "noVNC: OK"

PUBLIC_URL="${PUBLIC_URL:-http://YOUR_NORTHFLANK_DOMAIN}"
log "READY"
log "VNC URL: ${PUBLIC_URL%/}/vnc.html?autoconnect=true&resize=remote"
log "PASSWORD: $VNC_PASSWORD"

# Initialize Wine only after VNC is working, so any unexpected Wine dialog can
# actually be seen instead of leaving an apparently black session.
if [ ! -f "$WINEPREFIX/system.reg" ]; then
    log "FIRST RUN: creating clean Wine 64-bit prefix..."
    rm -rf "$WINEPREFIX"
    mkdir -p "$WINEPREFIX"

    if ! env -u WINEARCH \
        WINEDLLOVERRIDES="mscoree,mshtml=;winemenubuilder.exe=d" \
        wineboot -u >>/tmp/wineboot.log 2>&1; then
        log "FATAL: wineboot failed."
        tail -200 /tmp/wineboot.log || true
        hold_for_debug
    fi

    wineserver -w || true
fi

if [ ! -f "$WINEPREFIX/system.reg" ]; then
    log "FATAL: Wine prefix was not created."
    hold_for_debug
fi
log "Wine prefix: OK"

# This is the decisive test for the Northflank limitation we hit with native
# Steam Linux. It tests a 32-bit WINDOWS program, not a Linux i386 ELF.
export WINEARCH=wow64
if ! WINEDLLOVERRIDES="winemenubuilder.exe=d" \
    wine 'C:\windows\syswow64\cmd.exe' /c ver \
    >/tmp/wow64-test.log 2>&1; then
    log "FATAL: Wine 11 new-WoW64 could not run a 32-bit Windows component."
    tail -200 /tmp/wow64-test.log || true
    hold_for_debug
fi
log "Wine WoW64: OK"

find_steam() {
    local p found
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

    found="$(find "$WINEPREFIX/drive_c" -maxdepth 6 -type f -iname steam.exe -print -quit 2>/dev/null || true)"
    if [ -n "$found" ] && [ -s "$found" ]; then
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

start_installer() {
    log "FIRST RUN: Steam is not installed yet."
    log "Opening official SteamSetup.exe visibly in VNC."
    log "Complete the installer normally. Keep 'Run Steam' enabled if offered."

    WINEDLLOVERRIDES="winemenubuilder.exe=d" \
        wine /opt/steam-bootstrap/SteamSetup.exe \
        >>/tmp/steam-installer.log 2>&1 &

    log "Steam installer PID: $!"
}

start_steam() {
    local steam_exe
    steam_exe="$(find_steam || true)"

    if [ -z "$steam_exe" ] || [ ! -s "$steam_exe" ]; then
        return 1
    fi

    log "Steam executable: $steam_exe"

    if [ "${FARM_MODE:-0}" = "1" ]; then
        log "Starting Steam in low-RAM farm mode + TaskbarHero AppID 3678970..."
        WINEDLLOVERRIDES="winemenubuilder.exe=d" \
            wine "$steam_exe" \
            -silent \
            -no-browser \
            -nochatui \
            -nofriendsui \
            -no-cef-sandbox \
            -cef-disable-gpu \
            -cef-disable-gpu-compositing \
            -applaunch 3678970 \
            >>/tmp/steam.log 2>&1 &
    else
        log "Starting Steam visible for login/setup..."
        # These flags target the common CEF/container failure modes: no usable
        # sandbox and GPU compositing on a GPU-less node.
        WINEDLLOVERRIDES="winemenubuilder.exe=d" \
            wine "$steam_exe" \
            -nochatui \
            -nofriendsui \
            -no-cef-sandbox \
            -cef-disable-gpu \
            -cef-disable-gpu-compositing \
            -cef-disable-d3d11 \
            ${STEAM_EXTRA_FLAGS:-} \
            >>/tmp/steam.log 2>&1 &
    fi

    log "Steam launcher PID: $!"
}

STEAM_EXE="$(find_steam || true)"
if [ -n "$STEAM_EXE" ]; then
    start_steam || true
else
    start_installer
fi

INSTALL_RETRY_AT=0
STEAM_RETRY_AT=0

# Long-running supervisor. It does not exit merely because SteamSetup or Steam
# self-updates/restarts; this prevents Northflank restart loops.
while true; do
    sleep 5

    # Recover VNC/noVNC if either side dies.
    if ! kill -0 "$VNC_PID" 2>/dev/null; then
        log "x11vnc stopped. Restarting it..."
        tail -80 /tmp/x11vnc.log || true
        start_vnc
        sleep 1
    fi

    if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
        log "noVNC stopped. Restarting it..."
        tail -80 /tmp/novnc.log || true
        start_novnc
        sleep 1
    fi

    if ! kill -0 "$XVFB_PID" 2>/dev/null; then
        log "FATAL: Xvfb exited."
        tail -120 /tmp/xvfb.log || true
        hold_for_debug
    fi

    NOW="$(date +%s)"
    STEAM_EXE="$(find_steam || true)"

    if [ -n "$STEAM_EXE" ]; then
        # Do not interfere while the installer is still finishing.
        if ! installer_running && ! steam_running && [ "$NOW" -ge "$STEAM_RETRY_AT" ]; then
            log "Steam is installed but not running. Starting/restarting..."
            tail -100 /tmp/steam.log 2>/dev/null || true
            start_steam || true
            STEAM_RETRY_AT=$((NOW + 30))
        fi
    else
        if ! installer_running && [ "$NOW" -ge "$INSTALL_RETRY_AT" ]; then
            log "SteamSetup is not running and steam.exe is still absent."
            tail -100 /tmp/steam-installer.log 2>/dev/null || true
            log "Reopening installer in VNC..."
            start_installer
            INSTALL_RETRY_AT=$((NOW + 45))
        fi
    fi
done
