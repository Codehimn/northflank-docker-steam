#!/bin/bash
set -Eeuo pipefail

VERSION="V15"
export HOME=/home/steamuser
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-steamuser

# New prefix so no stale Wine state from v10-v14 can interfere.
export WINEPREFIX=/data/taskbarhero-v15

# IMPORTANT:
# Do NOT force WINEARCH=wow64.
# Wine 11 new-WoW64 selects the proper Windows architecture itself.
unset WINEARCH || true

# Northflank target has no GPU/audio.
export LIBGL_ALWAYS_SOFTWARE=1
export SDL_AUDIODRIVER=dummy
export WINEDEBUG=-all

XVFB_PID=""
OPENBOX_PID=""
VNC_PID=""
NOVNC_PID=""
DBUS_SESSION_BUS_PID="${DBUS_SESSION_BUS_PID:-}"

ts() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    printf '[%s] %s\n' "$(ts)" "$*"
}

diagnostics() {
    log "===== DIAGNOSTICS BEGIN ====="
    log "Architecture: $(uname -m)"
    log "User: $(id)"
    log "Wine: $(wine --version 2>/dev/null || true)"
    log "DISPLAY=$DISPLAY"
    log "WINEPREFIX=$WINEPREFIX"

    log "--- memory ---"
    grep -E 'MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree' /proc/meminfo || true

    log "--- filesystem ---"
    df -h /data /dev/shm 2>/dev/null || true

    log "--- processes ---"
    ps -eo pid,ppid,user,%mem,rss,stat,comm,args --sort=-rss | head -40 || true

    log "--- Steam candidates ---"
    find "$WINEPREFIX/drive_c" -maxdepth 6 -type f \
        \( -iname 'steam.exe' -o -iname 'steamwebhelper.exe' -o -iname 'SteamSetup.exe' \) \
        -print 2>/dev/null || true

    log "--- Wine prefix top-level ---"
    ls -la "$WINEPREFIX" 2>/dev/null || true

    log "--- /tmp/wineboot.log ---"
    tail -80 /tmp/wineboot.log 2>/dev/null || true

    log "--- /tmp/steam-installer.log ---"
    tail -120 /tmp/steam-installer.log 2>/dev/null || true

    log "--- /tmp/steam.log ---"
    tail -120 /tmp/steam.log 2>/dev/null || true

    log "--- /tmp/xvfb.log ---"
    tail -50 /tmp/xvfb.log 2>/dev/null || true

    log "--- /tmp/openbox.log ---"
    tail -50 /tmp/openbox.log 2>/dev/null || true

    log "--- /tmp/x11vnc.log ---"
    tail -50 /tmp/x11vnc.log 2>/dev/null || true

    log "--- /tmp/novnc.log ---"
    tail -50 /tmp/novnc.log 2>/dev/null || true

    log "===== DIAGNOSTICS END ====="
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
    diagnostics
    log "Container will stay alive for VNC/log inspection."
    while true; do sleep 3600; done
}

log "===================================="
log "=== TASKBARHERO NORTHFLANK V15 ==="
log "===================================="
log "Runtime architecture: $(uname -m)"
log "Runtime user: $(id)"
log "Wine: $(wine --version)"
log "Persistent prefix: $WINEPREFIX"

case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
        log "FATAL: this image requires an x86_64 Northflank node."
        hold_for_debug
        ;;
esac

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# A mounted /data volume can hide Dockerfile ownership, so test the real mount.
if ! mkdir -p "$WINEPREFIX" 2>/tmp/data-error.log; then
    log "FATAL: /data is not writable by steamuser."
    cat /tmp/data-error.log || true
    hold_for_debug
fi

# One shared D-Bus session for all Wine/Steam processes.
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
log "D-Bus: OK"

log "Starting Xvfb..."
Xvfb :0 \
    -screen 0 1024x640x24 \
    -ac \
    +extension GLX \
    +render \
    -noreset \
    >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!

# Wait for X to actually become ready.
X_READY=0
for _ in $(seq 1 60); do
    if xdpyinfo -display :0 >/dev/null 2>&1; then
        X_READY=1
        break
    fi
    if ! kill -0 "$XVFB_PID" 2>/dev/null; then
        break
    fi
    sleep 0.25
done

if [ "$X_READY" -ne 1 ]; then
    log "FATAL: Xvfb did not become ready."
    hold_for_debug
fi
log "Xvfb: OK"

log "Starting Openbox..."
openbox-session >/tmp/openbox.log 2>&1 &
OPENBOX_PID=$!

sleep 0.5
if ! kill -0 "$OPENBOX_PID" 2>/dev/null; then
    log "FATAL: Openbox failed."
    hold_for_debug
fi
log "Openbox: OK"

# Classic VNC auth effectively uses 8 chars.
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
    hold_for_debug
fi
log "VNC: OK"

log "Starting noVNC..."
start_novnc
sleep 0.5
if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
    log "FATAL: noVNC/websockify failed."
    hold_for_debug
fi
log "noVNC: OK"

PUBLIC_URL="${PUBLIC_URL:-http://YOUR_NORTHFLANK_DOMAIN}"
log "READY"
log "VNC URL: ${PUBLIC_URL%/}/vnc.html?autoconnect=true&resize=remote"
log "PASSWORD: $VNC_PASSWORD"

# Initialize Wine only after VNC is already working.
if [ ! -f "$WINEPREFIX/system.reg" ]; then
    log "FIRST RUN: creating clean Wine prefix..."
    rm -rf "$WINEPREFIX"
    mkdir -p "$WINEPREFIX"

    # Suppress Gecko/Mono prompts only during wineboot. Steam itself uses CEF.
    if ! WINEDLLOVERRIDES="mscoree,mshtml=;winemenubuilder.exe=d" \
        wineboot -u >>/tmp/wineboot.log 2>&1; then
        log "FATAL: wineboot failed."
        hold_for_debug
    fi

    wineserver -w || true
fi

if [ ! -f "$WINEPREFIX/system.reg" ]; then
    log "FATAL: Wine prefix was not created."
    hold_for_debug
fi
log "Wine prefix: OK"

# V15 deliberately removes the fake syswow64\cmd.exe test from V14.
# SteamSetup.exe itself is the real-world WoW64 test.

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

    found="$(find "$WINEPREFIX/drive_c" -maxdepth 6 -type f \
        -iname steam.exe -print -quit 2>/dev/null || true)"

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
    log "Launching the REAL WoW64 test: official SteamSetup.exe"
    log "The Steam installer should now appear visibly in VNC."
    log "Complete it normally and leave 'Run Steam' enabled if offered."

    : > /tmp/steam-installer.log

    WINEDLLOVERRIDES="winemenubuilder.exe=d" \
        wine /opt/steam-bootstrap/SteamSetup.exe \
        >>/tmp/steam-installer.log 2>&1 &

    local pid=$!
    log "Steam installer PID: $pid"

    # Give it a few seconds. If it dies immediately, expose useful evidence.
    sleep 5
    if ! kill -0 "$pid" 2>/dev/null && ! installer_running; then
        log "WARNING: SteamSetup exited very quickly."
        log "This is the next diagnostic point if no installer appeared in VNC."
        diagnostics
    else
        log "SteamSetup process: RUNNING"
    fi
}

start_steam() {
    local steam_exe
    steam_exe="$(find_steam || true)"

    if [ -z "$steam_exe" ] || [ ! -s "$steam_exe" ]; then
        return 1
    fi

    log "Steam executable: $steam_exe"

    if [ "${FARM_MODE:-0}" = "1" ]; then
        log "Starting Steam farm mode + TaskbarHero AppID 3678970..."
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
    return 0
}

STEAM_EXE="$(find_steam || true)"
if [ -n "$STEAM_EXE" ]; then
    start_steam || true
else
    start_installer
fi

INSTALL_RETRY_AT=0
STEAM_RETRY_AT=0
LAST_HEALTH_LOG=0

while true; do
    sleep 5
    NOW="$(date +%s)"

    # Recover VNC/noVNC if either dies.
    if ! kill -0 "$VNC_PID" 2>/dev/null; then
        log "x11vnc stopped. Restarting..."
        tail -80 /tmp/x11vnc.log || true
        start_vnc
        sleep 1
    fi

    if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
        log "noVNC stopped. Restarting..."
        tail -80 /tmp/novnc.log || true
        start_novnc
        sleep 1
    fi

    if ! kill -0 "$XVFB_PID" 2>/dev/null; then
        log "FATAL: Xvfb exited."
        hold_for_debug
    fi

    STEAM_EXE="$(find_steam || true)"

    if [ -n "$STEAM_EXE" ]; then
        if ! installer_running && ! steam_running && [ "$NOW" -ge "$STEAM_RETRY_AT" ]; then
            log "Steam is installed but not running. Starting/restarting..."
            tail -100 /tmp/steam.log 2>/dev/null || true
            start_steam || true
            STEAM_RETRY_AT=$((NOW + 30))
        fi
    else
        if ! installer_running && [ "$NOW" -ge "$INSTALL_RETRY_AT" ]; then
            log "SteamSetup is not running and steam.exe is still absent."
            tail -120 /tmp/steam-installer.log 2>/dev/null || true
            log "Reopening SteamSetup in VNC..."
            start_installer
            INSTALL_RETRY_AT=$((NOW + 45))
        fi
    fi

    # Lightweight health log every 5 minutes, useful for spotting OOM pressure.
    if [ "$NOW" -ge "$LAST_HEALTH_LOG" ]; then
        MEM_AVAIL="$(awk '/MemAvailable:/ {print $2 " kB"}' /proc/meminfo 2>/dev/null || true)"
        RSS_TOP="$(ps -eo rss,comm --sort=-rss 2>/dev/null | head -6 | tr '\n' ';' || true)"
        log "HEALTH MemAvailable=${MEM_AVAIL:-unknown}; topRSS=${RSS_TOP:-unknown}"
        LAST_HEALTH_LOG=$((NOW + 300))
    fi
done
