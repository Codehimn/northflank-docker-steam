#!/bin/bash
set -Eeuo pipefail

VERSION="V17"

export HOME=/home/steamuser
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-steamuser
export WINEPREFIX=/data/taskbarhero-v17

# Prefix is created normally as 64-bit. WineHQ 26.04 packages use new-WoW64.
unset WINEARCH || true

# No physical GPU or audio required.
export LIBGL_ALWAYS_SOFTWARE=1
export SDL_AUDIODRIVER=dummy
export WINEDEBUG=-all
export WINEESYNC=0
export WINEFSYNC=0

XVFB_PID=""
OPENBOX_PID=""
VNC_PID=""
NOVNC_PID=""
WINEBOOT_PID=""
INSTALLER_PID=""
STEAM_PID=""
DBUS_SESSION_BUS_PID="${DBUS_SESSION_BUS_PID:-}"

STATE="boot"
INSTALL_RETRY_AT=0
STEAM_RETRY_AT=0
LAST_HEALTH=0

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '[%s] %s\n' "$(ts)" "$*"; }

cgroup_memory() {
    local current="unknown" limit="unknown"
    if [ -r /sys/fs/cgroup/memory.current ]; then
        current="$(cat /sys/fs/cgroup/memory.current 2>/dev/null || echo unknown)"
    fi
    if [ -r /sys/fs/cgroup/memory.max ]; then
        limit="$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo unknown)"
    fi
    log "CGROUP_MEMORY current=${current} limit=${limit}"
}

diagnostics() {
    log "========== DIAGNOSTICS =========="
    log "STATE=$STATE"
    log "Architecture: $(uname -m)"
    log "User: $(id)"
    log "Wine: $(wine --version 2>/dev/null || true)"
    cgroup_memory

    log "--- /proc memory ---"
    grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo || true

    log "--- filesystem ---"
    df -h /data /dev/shm 2>/dev/null || true

    log "--- listening ports ---"
    ss -lnt 2>/dev/null | grep -E ':(6080|5900)\b' || true

    log "--- top RSS ---"
    ps -eo pid,ppid,user,rss,%mem,stat,comm,args --sort=-rss | head -35 || true

    log "--- Steam files ---"
    find "$WINEPREFIX/drive_c" -maxdepth 6 -type f \
      \( -iname 'steam.exe' -o -iname 'steamwebhelper.exe' -o -iname 'SteamSetup.exe' \) \
      -print 2>/dev/null || true

    for f in /tmp/wineboot.log /tmp/steam-installer.log /tmp/steam.log \
             /tmp/xvfb.log /tmp/openbox.log /tmp/x11vnc.log /tmp/novnc.log; do
        log "--- $f ---"
        tail -120 "$f" 2>/dev/null || true
    done
    log "======== END DIAGNOSTICS ========"
}

cleanup() {
    set +e
    wineserver -k >/dev/null 2>&1 || true
    for p in "${NOVNC_PID:-}" "${VNC_PID:-}" "${OPENBOX_PID:-}" \
             "${XVFB_PID:-}" "${DBUS_SESSION_BUS_PID:-}"; do
        [ -n "$p" ] && kill "$p" >/dev/null 2>&1 || true
    done
}
trap cleanup TERM INT EXIT

hold_for_debug() {
    diagnostics
    log "Container remains alive for VNC/log inspection."
    while true; do sleep 3600; done
}

log "===================================="
log "=== TASKBARHERO NORTHFLANK V17 ==="
log "===================================="
log "Runtime architecture: $(uname -m)"
log "Runtime user: $(id)"
log "Wine: $(wine --version)"
log "Persistent prefix: $WINEPREFIX"
cgroup_memory

case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
        log "FATAL: x86_64 Northflank node required."
        hold_for_debug
        ;;
esac

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

if ! mkdir -p "$WINEPREFIX" 2>/tmp/data-error.log; then
    log "FATAL: /data is not writable."
    cat /tmp/data-error.log || true
    hold_for_debug
fi

# One D-Bus session for the entire container lifetime.
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
        hold_for_debug
    fi
    log "Xvfb: OK"
}

start_openbox() {
    openbox-session >/tmp/openbox.log 2>&1 &
    OPENBOX_PID=$!
    sleep 0.5

    if ! kill -0 "$OPENBOX_PID" 2>/dev/null; then
        log "FATAL: Openbox failed."
        hold_for_debug
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
    : > /tmp/novnc.log

    # Canonical websockify syntax. With no source host specified it binds the
    # listen socket on all interfaces, which is what Northflank's HTTP proxy needs.
    websockify \
        --web /usr/share/novnc \
        6080 \
        127.0.0.1:5900 \
        >/tmp/novnc.log 2>&1 &
    NOVNC_PID=$!
}

novnc_port_open() {
    ss -lnt 2>/dev/null | grep -qE '(^|[[:space:]])(\*|0\.0\.0\.0|\[::\]):6080([[:space:]]|$)'
}

novnc_http_ok() {
    # Ignore any HTTP(S)_PROXY injected by the hosting environment.
    curl --noproxy '*' -fsS --max-time 2 \
        http://127.0.0.1:6080/vnc.html >/dev/null 2>&1
}

verify_novnc() {
    local ok=0
    for _ in $(seq 1 40); do
        if kill -0 "$NOVNC_PID" 2>/dev/null && novnc_port_open && novnc_http_ok; then
            ok=1
            break
        fi
        sleep 0.25
    done

    if [ "$ok" -eq 1 ]; then
        log "noVNC listener: OK"
        log "noVNC local HTTP: OK"
        return 0
    fi

    log "noVNC verification failed."
    tail -120 /tmp/novnc.log || true
    return 1
}

log "Starting graphical stack..."
start_x
start_openbox
start_vnc
sleep 0.5

if ! kill -0 "$VNC_PID" 2>/dev/null; then
    log "FATAL: x11vnc failed."
    hold_for_debug
fi
log "VNC: OK"

start_novnc
if ! verify_novnc; then
    log "FATAL: noVNC cannot bind/serve 6080."
    hold_for_debug
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

    [ -n "$found" ] && [ -s "$found" ] && {
        printf '%s\n' "$found"
        return 0
    }

    return 1
}

steam_running() {
    pgrep -u "$(id -u)" -f 'steam\.exe|steamwebhelper\.exe' >/dev/null 2>&1
}

installer_running() {
    pgrep -u "$(id -u)" -f 'SteamSetup\.exe' >/dev/null 2>&1
}

start_wineboot() {
    STATE="wineboot"
    log "FIRST RUN: initializing Wine prefix in background..."
    : > /tmp/wineboot.log

    # Do not disable winemenubuilder here. V14's override caused an avoidable
    # wineboot error. Only optional Gecko/Mono handlers are suppressed.
    WINEDLLOVERRIDES="mscoree,mshtml=" \
        wineboot -u >>/tmp/wineboot.log 2>&1 &
    WINEBOOT_PID=$!

    log "Wineboot PID: $WINEBOOT_PID"
}

start_installer() {
    STATE="installer"
    log "Wine prefix initialization is complete."
    log "Launching official SteamSetup.exe visibly in VNC..."
    : > /tmp/steam-installer.log

    # WineHQ 26.04 is a new-WoW64 build. Explicitly request new WoW64 for the
    # Windows Steam installer while keeping the prefix itself 64-bit.
    WINEARCH=wow64 \
        wine /opt/steam-bootstrap/SteamSetup.exe \
        >>/tmp/steam-installer.log 2>&1 &
    INSTALLER_PID=$!

    log "Steam installer PID: $INSTALLER_PID"
}

start_steam() {
    local steam_exe
    steam_exe="$(find_steam || true)"
    [ -n "$steam_exe" ] && [ -s "$steam_exe" ] || return 1

    STATE="steam"
    log "Steam executable: $steam_exe"

    if [ "${FARM_MODE:-0}" = "1" ]; then
        log "Starting farm mode + TaskbarHero AppID 3678970..."
        WINEARCH=wow64 \
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
        WINEARCH=wow64 \
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

# Determine initial state.
STEAM_EXE="$(find_steam || true)"

if [ -n "$STEAM_EXE" ]; then
    start_steam || true
elif [ -f "$WINEPREFIX/system.reg" ] && [ -d "$WINEPREFIX/drive_c/windows" ]; then
    # Prefix already exists from a prior V17 start; do not initialize it again.
    STATE="prefix-ready"
    start_installer
else
    start_wineboot
fi

while true; do
    sleep 2
    NOW="$(date +%s)"

    # Keep X alive.
    if ! kill -0 "$XVFB_PID" 2>/dev/null; then
        log "FATAL: Xvfb exited."
        hold_for_debug
    fi

    # Recover VNC.
    if ! kill -0 "$VNC_PID" 2>/dev/null; then
        log "x11vnc died. Restarting..."
        tail -80 /tmp/x11vnc.log || true
        start_vnc
        sleep 1
    fi

    # Recover noVNC only on actual process/listener failure.
    # A temporary HTTP request failure must NOT cause a restart loop.
    if ! kill -0 "$NOVNC_PID" 2>/dev/null || ! novnc_port_open; then
        log "noVNC process/listener is down. Restarting websockify..."
        tail -120 /tmp/novnc.log || true
        kill "$NOVNC_PID" >/dev/null 2>&1 || true
        start_novnc
        if ! verify_novnc; then
            log "FATAL: noVNC failed after restart."
            hold_for_debug
        fi
    fi

    # State: Wine prefix initialization.
    if [ "$STATE" = "wineboot" ]; then
        if ! kill -0 "$WINEBOOT_PID" 2>/dev/null; then
            wait "$WINEBOOT_PID" 2>/dev/null || WINEBOOT_RC=$?
            WINEBOOT_RC="${WINEBOOT_RC:-0}"

            log "Wineboot exited with code $WINEBOOT_RC"

            if [ "$WINEBOOT_RC" -ne 0 ] || \
               [ ! -f "$WINEPREFIX/system.reg" ] || \
               [ ! -d "$WINEPREFIX/drive_c/windows" ]; then
                log "FATAL: Wine prefix initialization failed."
                hold_for_debug
            fi

            log "Wine prefix: OK"
            # Important: do NOT wineserver -w. Wine explorer/services may remain
            # alive by design and would make wineserver -w wait indefinitely.
            sleep 2
            start_installer
        fi
    fi

    STEAM_EXE="$(find_steam || true)"

    if [ -n "$STEAM_EXE" ]; then
        if ! installer_running && ! steam_running && [ "$NOW" -ge "$STEAM_RETRY_AT" ]; then
            log "Steam installed but not running. Starting/restarting..."
            tail -100 /tmp/steam.log 2>/dev/null || true
            start_steam || true
            STEAM_RETRY_AT=$((NOW + 30))
        fi
    elif [ "$STATE" = "installer" ]; then
        if ! installer_running && [ "$NOW" -ge "$INSTALL_RETRY_AT" ]; then
            log "Steam installer is no longer running and steam.exe is absent."
            tail -160 /tmp/steam-installer.log 2>/dev/null || true

            # Do not hammer Wine with retry attempts.
            INSTALL_RETRY_AT=$((NOW + 60))
            log "Installer will retry in 60 seconds unless Steam appears."
        fi

        if ! installer_running && [ "$NOW" -ge "$INSTALL_RETRY_AT" ]; then
            start_installer
        fi
    fi

    # Useful health output every minute.
    if [ "$NOW" -ge "$LAST_HEALTH" ]; then
        log "HEALTH state=$STATE"
        cgroup_memory

        log "Ports:"
        ss -lnt 2>/dev/null | grep -E ':(6080|5900)\b' || true

        log "Top RSS:"
        ps -eo pid,rss,comm --sort=-rss | head -10 || true

        # Local HTTP probe is informational only and never triggers a restart.
        if novnc_http_ok; then
            log "HEALTH noVNC_http=OK"
        else
            log "HEALTH noVNC_http=FAIL (informational; process/listener retained)"
        fi

        LAST_HEALTH=$((NOW + 60))
    fi
done
