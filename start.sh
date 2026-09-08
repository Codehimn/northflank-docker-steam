#!/bin/bash
set -Eeuo pipefail

VERSION="V16-FINAL"

export HOME=/home/steamuser
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-steamuser

# Fresh persistent prefix. Never reuse state from v10-v15.
export WINEPREFIX=/data/taskbarhero-v16
unset WINEARCH || true

# No GPU/audio on the target node.
export LIBGL_ALWAYS_SOFTWARE=1
export SDL_AUDIODRIVER=dummy
export WINEDEBUG=-all

# Avoid optional synchronization features that can be problematic in restricted
# containers. They are not needed for Steam setup/login.
export WINEESYNC=0
export WINEFSYNC=0

XVFB_PID=""
OPENBOX_PID=""
VNC_PID=""
NOVNC_PID=""
INSTALLER_PID=""
STEAM_PID=""
DBUS_SESSION_BUS_PID="${DBUS_SESSION_BUS_PID:-}"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '[%s] %s\n' "$(ts)" "$*"; }

memory_log() {
    local avail total
    total="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo '?')"
    avail="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo '?')"
    log "MEMORY total=${total}kB available=${avail}kB"
}

diagnostics() {
    log "========== DIAGNOSTICS =========="
    log "Architecture: $(uname -m)"
    log "User: $(id)"
    log "Wine: $(wine --version 2>/dev/null || true)"
    memory_log

    log "--- listening ports ---"
    ss -lntp 2>/dev/null || true

    log "--- /data + /dev/shm ---"
    df -h /data /dev/shm 2>/dev/null || true

    log "--- top RSS ---"
    ps -eo pid,ppid,user,rss,%mem,stat,comm,args --sort=-rss | head -35 || true

    log "--- Steam files ---"
    find "$WINEPREFIX/drive_c" -maxdepth 6 -type f \
      \( -iname 'steam.exe' -o -iname 'steamwebhelper.exe' -o -iname 'SteamSetup.exe' \) \
      -print 2>/dev/null || true

    for f in /tmp/steam-installer.log /tmp/steam.log /tmp/xvfb.log \
             /tmp/openbox.log /tmp/x11vnc.log /tmp/novnc.log; do
        log "--- $f ---"
        tail -120 "$f" 2>/dev/null || true
    done

    log "======== END DIAGNOSTICS ========"
}

cleanup() {
    set +e
    wineserver -k >/dev/null 2>&1 || true
    for p in "${NOVNC_PID:-}" "${VNC_PID:-}" "${OPENBOX_PID:-}" "${XVFB_PID:-}" "${DBUS_SESSION_BUS_PID:-}"; do
        [ -n "$p" ] && kill "$p" >/dev/null 2>&1 || true
    done
}
trap cleanup TERM INT EXIT

log "==========================================="
log "=== TASKBARHERO NORTHFLANK ${VERSION} ==="
log "==========================================="
log "Runtime architecture: $(uname -m)"
log "Runtime user: $(id)"
log "Wine: $(wine --version)"
log "Persistent prefix: $WINEPREFIX"
memory_log

case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
        log "FATAL: x86_64 Northflank node required."
        diagnostics
        while true; do sleep 3600; done
        ;;
esac

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Verify the actual mounted /data, not Dockerfile ownership.
if ! mkdir -p "$WINEPREFIX" 2>/tmp/data-error.log; then
    log "FATAL: /data is not writable by steamuser."
    cat /tmp/data-error.log || true
    diagnostics
    while true; do sleep 3600; done
fi

# One D-Bus session for the whole container lifetime.
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
log "D-Bus: OK"

start_x() {
    Xvfb :0 \
        -screen 0 1024x640x24 \
        -ac \
        +extension GLX \
        +render \
        -noreset \
        >/tmp/xvfb.log 2>&1 &
    XVFB_PID=$!

    local ok=0
    for _ in $(seq 1 60); do
        if xdpyinfo -display :0 >/dev/null 2>&1; then
            ok=1
            break
        fi
        kill -0 "$XVFB_PID" 2>/dev/null || break
        sleep 0.25
    done

    if [ "$ok" -ne 1 ]; then
        log "FATAL: Xvfb did not become ready."
        diagnostics
        while true; do sleep 3600; done
    fi
    log "Xvfb: OK"
}

start_openbox() {
    openbox-session >/tmp/openbox.log 2>&1 &
    OPENBOX_PID=$!
    sleep 0.5

    if ! kill -0 "$OPENBOX_PID" 2>/dev/null; then
        log "FATAL: Openbox failed."
        diagnostics
        while true; do sleep 3600; done
    fi
    log "Openbox: OK"
}

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
        -listen 127.0.0.1 \
        -rfbport 5900 \
        -rfbauth "$VNC_PASSFILE" \
        >/tmp/x11vnc.log 2>&1 &
    VNC_PID=$!
}

start_novnc() {
    # Explicitly listen on all interfaces for the Northflank HTTP proxy.
    websockify \
        --web=/usr/share/novnc \
        0.0.0.0:6080 \
        127.0.0.1:5900 \
        >/tmp/novnc.log 2>&1 &
    NOVNC_PID=$!
}

verify_novnc() {
    local ok=0
    for _ in $(seq 1 30); do
        if curl -fsS --max-time 2 http://127.0.0.1:6080/vnc.html >/dev/null 2>&1; then
            ok=1
            break
        fi
        kill -0 "$NOVNC_PID" 2>/dev/null || break
        sleep 0.25
    done

    if [ "$ok" -eq 1 ]; then
        log "noVNC HTTP probe: OK"
        return 0
    fi

    log "noVNC HTTP probe: FAILED"
    return 1
}

log "Starting graphical stack..."
start_x
start_openbox
start_vnc
sleep 0.5

if ! kill -0 "$VNC_PID" 2>/dev/null; then
    log "FATAL: x11vnc failed."
    diagnostics
    while true; do sleep 3600; done
fi
log "VNC: OK"

start_novnc
sleep 0.5

if ! kill -0 "$NOVNC_PID" 2>/dev/null || ! verify_novnc; then
    log "FATAL: noVNC failed before Wine/Steam started."
    diagnostics
    while true; do sleep 3600; done
fi
log "noVNC: OK"

PUBLIC_URL="${PUBLIC_URL:-http://YOUR_NORTHFLANK_DOMAIN}"
log "READY"
log "VNC URL: ${PUBLIC_URL%/}/vnc.html?autoconnect=true&resize=remote"
log "PASSWORD: $VNC_PASSWORD"

find_steam() {
    local p found
    for p in \
        "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steam.exe" \
        "$WINEPREFIX/drive_c/Program Files/Steam/steam.exe" \
        "$WINEPREFIX/drive_c/Steam/steam.exe"
    do
        [ -s "$p" ] && { printf '%s\n' "$p"; return 0; }
    done

    found="$(find "$WINEPREFIX/drive_c" -maxdepth 6 -type f \
        -iname steam.exe -print -quit 2>/dev/null || true)"

    [ -n "$found" ] && [ -s "$found" ] && { printf '%s\n' "$found"; return 0; }
    return 1
}

steam_running() {
    pgrep -u "$(id -u)" -f 'steam\.exe|steamwebhelper\.exe' >/dev/null 2>&1
}

installer_running() {
    pgrep -u "$(id -u)" -f 'SteamSetup\.exe' >/dev/null 2>&1
}

start_installer() {
    log "FIRST RUN: launching official SteamSetup.exe directly."
    log "Wine will initialize the prefix automatically. No blocking wineboot step."
    log "The Steam installer should appear in VNC."

    : > /tmp/steam-installer.log

    # Suppress optional Wine Gecko/Mono and menu-builder prompts for installer.
    WINEDLLOVERRIDES="mscoree,mshtml=;winemenubuilder.exe=d" \
        wine /opt/steam-bootstrap/SteamSetup.exe \
        >>/tmp/steam-installer.log 2>&1 &
    INSTALLER_PID=$!

    log "Steam installer PID: $INSTALLER_PID"
}

start_steam() {
    local steam_exe
    steam_exe="$(find_steam || true)"
    [ -n "$steam_exe" ] && [ -s "$steam_exe" ] || return 1

    log "Steam executable: $steam_exe"

    if [ "${FARM_MODE:-0}" = "1" ]; then
        log "Starting farm mode + TaskbarHero AppID 3678970..."
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

    STEAM_PID=$!
    log "Steam launcher PID: $STEAM_PID"
}

# START THE SUPERVISOR STATE IMMEDIATELY.
# No synchronous wineboot/wineserver wait exists before this point.
INSTALL_RETRY_AT=0
STEAM_RETRY_AT=0
LAST_HEALTH=0

STEAM_EXE="$(find_steam || true)"
if [ -n "$STEAM_EXE" ]; then
    start_steam || true
else
    start_installer
fi

while true; do
    sleep 3
    NOW="$(date +%s)"

    # X must stay alive.
    if ! kill -0 "$XVFB_PID" 2>/dev/null; then
        log "FATAL: Xvfb exited."
        diagnostics
        while true; do sleep 3600; done
    fi

    # Recover x11vnc immediately.
    if ! kill -0 "$VNC_PID" 2>/dev/null; then
        log "x11vnc died. Restarting..."
        tail -80 /tmp/x11vnc.log || true
        start_vnc
        sleep 1
    fi

    # Recover noVNC immediately, even while Wine is initializing.
    if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
        log "noVNC died. Restarting..."
        tail -100 /tmp/novnc.log || true
        start_novnc
        sleep 1
    fi

    # If HTTP probe fails, recycle websockify instead of leaving Northflank
    # returning "upstream connect error / connection refused".
    if ! curl -fsS --max-time 1 http://127.0.0.1:6080/vnc.html >/dev/null 2>&1; then
        log "noVNC HTTP probe failed. Recycling websockify..."
        kill "$NOVNC_PID" >/dev/null 2>&1 || true
        start_novnc
        sleep 1
    fi

    STEAM_EXE="$(find_steam || true)"

    if [ -n "$STEAM_EXE" ]; then
        if ! installer_running && ! steam_running && [ "$NOW" -ge "$STEAM_RETRY_AT" ]; then
            log "Steam installed but not running. Starting/restarting..."
            tail -100 /tmp/steam.log 2>/dev/null || true
            start_steam || true
            STEAM_RETRY_AT=$((NOW + 30))
        fi
    else
        if ! installer_running && [ "$NOW" -ge "$INSTALL_RETRY_AT" ]; then
            log "SteamSetup is not running and steam.exe is absent."
            tail -120 /tmp/steam-installer.log 2>/dev/null || true
            log "Reopening installer..."
            start_installer
            INSTALL_RETRY_AT=$((NOW + 30))
        fi
    fi

    # Frequent health log for this decisive test.
    if [ "$NOW" -ge "$LAST_HEALTH" ]; then
        memory_log
        log "Processes top RSS:"
        ps -eo pid,rss,comm --sort=-rss | head -10 || true
        log "Ports:"
        ss -lnt 2>/dev/null | grep -E ':(6080|5900)\b' || true
        LAST_HEALTH=$((NOW + 60))
    fi
done
