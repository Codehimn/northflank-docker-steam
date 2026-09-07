#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/home/steamuser}"
export WINEPREFIX="${WINEPREFIX:-/data/wineprefix}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
export MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-llvmpipe}"
export MALLOC_ARENA_MAX="${MALLOC_ARENA_MAX:-2}"

LOG_DIR=/data/logs
mkdir -p "$LOG_DIR" "$HOME/.vnc"

log(){ printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die(){ log "ERROR: $*"; exit 1; }
cleanup(){ jobs -pr | xargs -r kill 2>/dev/null || true; }
trap cleanup EXIT INT TERM

VNC_PASSWORD="${VNC_PASSWORD:-cambia12}"
if (( ${#VNC_PASSWORD} > 8 )); then
  log "VNC_PASSWORD > 8 chars; using first 8."
  VNC_PASSWORD="${VNC_PASSWORD:0:8}"
fi
(( ${#VNC_PASSWORD} >= 4 )) || die "VNC_PASSWORD must be at least 4 chars."

rm -f "$HOME/.vnc/passwd"
x11vnc -storepasswd "$VNC_PASSWORD" "$HOME/.vnc/passwd" >/dev/null
chmod 600 "$HOME/.vnc/passwd"

log "Wine: $(wine --version)"
log "Kernel: $(uname -m) $(uname -r)"

if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
  log "Creating persistent Wine prefix..."
  mkdir -p "$WINEPREFIX"
  cp -a /opt/prefix-template/. "$WINEPREFIX/"
fi

log "Starting Xvfb..."
Xvfb "$DISPLAY" -screen 0 1024x768x16 -ac -nolisten tcp -noreset >"$LOG_DIR/xvfb.log" 2>&1 &
XVFB_PID=$!

for i in $(seq 1 40); do
  if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    log "Xvfb ready."
    break
  fi
  kill -0 "$XVFB_PID" 2>/dev/null || die "Xvfb exited."
  [[ "$i" != "40" ]] || die "Xvfb timeout."
  sleep .5
done

log "Starting Openbox..."
dbus-launch openbox >"$LOG_DIR/openbox.log" 2>&1 &

log "Starting x11vnc..."
x11vnc \
  -display "$DISPLAY" \
  -rfbport 5900 \
  -rfbauth "$HOME/.vnc/passwd" \
  -forever -shared -noxdamage -localhost \
  >"$LOG_DIR/x11vnc.log" 2>&1 &
X11VNC_PID=$!

for i in $(seq 1 40); do
  if (echo >/dev/tcp/127.0.0.1/5900) >/dev/null 2>&1; then
    log "x11vnc ready."
    break
  fi
  kill -0 "$X11VNC_PID" 2>/dev/null || die "x11vnc exited."
  [[ "$i" != "40" ]] || die "x11vnc timeout."
  sleep .5
done

log "Starting noVNC :6080..."
websockify --web=/opt/novnc 6080 127.0.0.1:5900 >"$LOG_DIR/novnc.log" 2>&1 &
NOVNC_PID=$!
sleep 2
kill -0 "$NOVNC_PID" 2>/dev/null || die "noVNC failed."

log "noVNC READY"
log "VNC password: $VNC_PASSWORD"

# Never let Steam preparation kill the VNC service.
if /opt/taskbarhero/prepare-steam.sh; then
  log "Steam preparation succeeded. Starting watchdog..."
  /opt/taskbarhero/steam-watchdog.sh >>"$LOG_DIR/watchdog.log" 2>&1 &
else
  log "Steam preparation did not complete."
  log "noVNC remains alive. See /data/logs/ for the exact blocker."
fi

wait "$NOVNC_PID"
