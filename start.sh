#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY=:99
export HOME=/home/steamuser
export PATH="/usr/games:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LIBGL_ALWAYS_SOFTWARE=1

VNC_PASSWORD="${VNC_PASSWORD:-cambiar123}"
VNC_PASSFILE="$HOME/.vnc/passwd"

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

cleanup() {
  log "Stopping child processes..."
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$HOME/.vnc"

if [[ ! -f "$VNC_PASSFILE" ]]; then
  log "Creating VNC password..."
  x11vnc -storepasswd "$VNC_PASSWORD" "$VNC_PASSFILE" >/dev/null
  chmod 600 "$VNC_PASSFILE"
fi

log "Starting Xvfb..."
Xvfb :99 \
  -screen 0 1024x768x16 \
  -ac \
  -nolisten tcp \
  -noreset \
  >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!

for i in $(seq 1 30); do
  if xdpyinfo -display :99 >/dev/null 2>&1; then
    log "Xvfb ready."
    break
  fi
  if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    log "ERROR: Xvfb exited."
    cat /tmp/xvfb.log || true
    exit 1
  fi
  if [[ "$i" == "30" ]]; then
    log "ERROR: Xvfb did not become ready."
    cat /tmp/xvfb.log || true
    exit 1
  fi
  sleep 0.5
done

log "Starting D-Bus session + Openbox..."
dbus-launch openbox >/tmp/openbox.log 2>&1 &

log "Starting x11vnc..."
x11vnc \
  -display :99 \
  -rfbport 5900 \
  -rfbauth "$VNC_PASSFILE" \
  -forever \
  -shared \
  -noxdamage \
  -localhost \
  >/tmp/x11vnc.log 2>&1 &
X11VNC_PID=$!

for i in $(seq 1 30); do
  if (echo >/dev/tcp/127.0.0.1/5900) >/dev/null 2>&1; then
    log "x11vnc ready."
    break
  fi
  if ! kill -0 "$X11VNC_PID" 2>/dev/null; then
    log "ERROR: x11vnc exited."
    cat /tmp/x11vnc.log || true
    exit 1
  fi
  if [[ "$i" == "30" ]]; then
    log "ERROR: port 5900 did not open."
    cat /tmp/x11vnc.log || true
    exit 1
  fi
  sleep 0.5
done

log "Starting noVNC on HTTP :6080..."
websockify \
  --web=/usr/share/novnc/ \
  6080 127.0.0.1:5900 \
  >/tmp/novnc.log 2>&1 &
NOVNC_PID=$!

sleep 2
if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
  log "ERROR: noVNC failed."
  cat /tmp/novnc.log || true
  exit 1
fi

log "noVNC READY: /vnc.html"
log "VNC PASSWORD: $VNC_PASSWORD"

STEAM_BIN="/usr/games/steam"
if [[ ! -x "$STEAM_BIN" ]]; then
  log "ERROR: Steam launcher not found at $STEAM_BIN"
  dpkg -l | grep -E 'steam|libgl' || true
  exit 1
fi

log "Starting Steam from $STEAM_BIN"
log "First launch can download/update the rest of the Steam client."

"$STEAM_BIN" -no-cef-sandbox >/tmp/steam.log 2>&1 &
STEAM_PID=$!

sleep 10

if kill -0 "$STEAM_PID" 2>/dev/null; then
  log "Steam process is running. Open noVNC and log in."
else
  log "WARNING: Steam exited early. Last Steam log lines:"
  tail -n 100 /tmp/steam.log || true
  log "noVNC remains available for inspection."
fi

wait "$NOVNC_PID"
