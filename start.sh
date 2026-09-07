#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/home/steamuser}"
export WINEPREFIX="${WINEPREFIX:-/data/wineprefix}"
export WINEDEBUG="${WINEDEBUG:--all}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
export MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-llvmpipe}"
export MALLOC_ARENA_MAX="${MALLOC_ARENA_MAX:-2}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"

LOG_DIR=/data/logs
mkdir -p "$LOG_DIR" "$HOME/.vnc"

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

VNC_PASSWORD="${VNC_PASSWORD:-cambia12}"
if (( ${#VNC_PASSWORD} > 8 )); then
  log "VNC_PASSWORD > 8 chars; using first 8."
  VNC_PASSWORD="${VNC_PASSWORD:0:8}"
fi
(( ${#VNC_PASSWORD} >= 4 )) || die "VNC_PASSWORD must be at least 4 chars."

VNC_PASSFILE="$HOME/.vnc/passwd"
rm -f "$VNC_PASSFILE"
x11vnc -storepasswd "$VNC_PASSWORD" "$VNC_PASSFILE" >/dev/null
chmod 600 "$VNC_PASSFILE"

log "Wine version: $(wine --version)"
log "Kernel: $(uname -m) $(uname -r)"
log "Persistent prefix: $WINEPREFIX"

if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
  log "Copying clean Wine prefix template to persistent storage..."
  mkdir -p "$WINEPREFIX"
  cp -a /opt/prefix-template/. "$WINEPREFIX/"
fi

chmod -R u+rwX "$WINEPREFIX" 2>/dev/null || true

log "Starting Xvfb..."
Xvfb "$DISPLAY" \
  -screen 0 1024x768x16 \
  -ac \
  -nolisten tcp \
  -noreset \
  >"$LOG_DIR/xvfb.log" 2>&1 &
XVFB_PID=$!

for i in $(seq 1 40); do
  if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    log "Xvfb ready."
    break
  fi
  kill -0 "$XVFB_PID" 2>/dev/null || {
    tail -n 80 "$LOG_DIR/xvfb.log" || true
    die "Xvfb exited."
  }
  [[ "$i" != "40" ]] || die "Xvfb did not become ready."
  sleep 0.5
done

log "Starting D-Bus + Openbox..."
dbus-launch openbox >"$LOG_DIR/openbox.log" 2>&1 &

log "Starting x11vnc..."
x11vnc \
  -display "$DISPLAY" \
  -rfbport 5900 \
  -rfbauth "$VNC_PASSFILE" \
  -forever \
  -shared \
  -noxdamage \
  -localhost \
  >"$LOG_DIR/x11vnc.log" 2>&1 &
X11VNC_PID=$!

for i in $(seq 1 40); do
  if (echo >/dev/tcp/127.0.0.1/5900) >/dev/null 2>&1; then
    log "x11vnc ready."
    break
  fi
  kill -0 "$X11VNC_PID" 2>/dev/null || {
    tail -n 80 "$LOG_DIR/x11vnc.log" || true
    die "x11vnc exited."
  }
  [[ "$i" != "40" ]] || die "VNC port 5900 did not open."
  sleep 0.5
done

log "Starting noVNC on HTTP :6080..."
websockify --web=/opt/novnc 6080 127.0.0.1:5900 >"$LOG_DIR/novnc.log" 2>&1 &
NOVNC_PID=$!

sleep 2
kill -0 "$NOVNC_PID" 2>/dev/null || {
  cat "$LOG_DIR/novnc.log" || true
  die "noVNC failed."
}

log "noVNC READY"
log "VNC password: $VNC_PASSWORD"
log "From this point onward, installer failures will NOT kill noVNC."

# Refresh the prebuilt prefix, but don't make harmless update warnings fatal.
log "Refreshing Wine prefix..."
wineboot -u >"$LOG_DIR/wineboot.log" 2>&1 || {
  log "WARNING: wineboot returned non-zero; continuing with existing prefix."
  tail -n 60 "$LOG_DIR/wineboot.log" || true
}

# Install Steam only after the visible desktop/noVNC is ready.
log "Ensuring Steam for Windows is installed..."
if /opt/taskbarhero/install-steam.sh; then
  log "Steam installation check: OK."
  log "Starting Steam watchdog..."
  /opt/taskbarhero/steam-watchdog.sh >>"$LOG_DIR/watchdog.log" 2>&1 &
else
  log "WARNING: Steam silent installation did not complete automatically."
  log "A visible Steam installer has been launched in noVNC as fallback."
  log "The container will stay alive so installation can be completed visually."
fi

wait "$NOVNC_PID"
