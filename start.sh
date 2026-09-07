#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY=:99
export HOME=/home/steamuser
export PATH="/usr/games:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LIBGL_ALWAYS_SOFTWARE=1

VNC_PASSWORD="${VNC_PASSWORD:-cambiar123}"
VNC_PASSFILE="$HOME/.vnc/passwd"
STEAM_BIN="/usr/games/steam"

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

cleanup() {
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
Xvfb :99 -screen 0 1024x768x16 -ac -nolisten tcp -noreset >/tmp/xvfb.log 2>&1 &
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
  sleep 0.5
done

log "Starting D-Bus + Openbox..."
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
  sleep 0.5
done

log "Starting noVNC :6080..."
websockify --web=/usr/share/novnc/ 6080 127.0.0.1:5900 >/tmp/novnc.log 2>&1 &
NOVNC_PID=$!
sleep 2

log "noVNC READY: /vnc.html"
log "VNC PASSWORD: $VNC_PASSWORD"

# ---- CRITICAL PLATFORM TEST ----
log "=== PLATFORM CHECK ==="
log "Kernel architecture: $(uname -m)"
log "Kernel: $(uname -r)"

if [[ -e /lib/ld-linux.so.2 ]]; then
  log "32-bit loader: $(file -b /lib/ld-linux.so.2)"
else
  log "ERROR: /lib/ld-linux.so.2 is missing."
fi

if /lib/ld-linux.so.2 --help >/tmp/ia32-test.log 2>&1; then
  log "IA32 TEST: OK. Kernel can execute 32-bit x86 ELF binaries."
else
  RC=$?
  log "IA32 TEST: FAILED (exit $RC)."
  log "This runtime cannot execute the 32-bit Linux component required by Steam."
  log "32-bit test output:"
  tail -n 20 /tmp/ia32-test.log || true
  log "Steam Linux cannot bootstrap correctly in this runtime unless 32-bit execution is enabled."
  log "noVNC will remain available."
  wait "$NOVNC_PID"
  exit 0
fi

if [[ ! -x "$STEAM_BIN" ]]; then
  log "ERROR: Steam launcher missing: $STEAM_BIN"
  wait "$NOVNC_PID"
  exit 0
fi

# Remove only incomplete bootstrap files from previous failed launches.
STEAM_ROOT="$HOME/.steam/debian-installation"
mkdir -p "$STEAM_ROOT"

log "Cleaning incomplete Steam bootstrap fragments..."
find "$STEAM_ROOT" -type f \( -name '*.part' -o -name 'steam-runtime.tar.xz.part*' \) -delete 2>/dev/null || true

# If the previously downloaded bootstrap executable is not a valid x86 ELF, remove it.
BOOTSTRAP="$STEAM_ROOT/ubuntu12_32/steam"
if [[ -e "$BOOTSTRAP" ]]; then
  DESC="$(file -b "$BOOTSTRAP" || true)"
  log "Existing Steam bootstrap: $DESC"
  if [[ "$DESC" != *"ELF 32-bit"* ]]; then
    log "Invalid/corrupt bootstrap detected. Removing ubuntu12_32 for a clean retry."
    rm -rf "$STEAM_ROOT/ubuntu12_32"
  fi
fi

run_steam() {
  local attempt="$1"
  log "Starting Steam attempt $attempt..."
  rm -f /tmp/steam.log
  "$STEAM_BIN" -no-cef-sandbox >/tmp/steam.log 2>&1 &
  STEAM_PID=$!
  sleep 12

  if kill -0 "$STEAM_PID" 2>/dev/null; then
    log "Steam is running. Open noVNC and log in."
    return 0
  fi

  log "Steam exited during attempt $attempt."
  tail -n 100 /tmp/steam.log || true
  return 1
}

if ! run_steam 1; then
  log "Preparing one clean retry..."
  find "$STEAM_ROOT" -type f \( -name '*.part' -o -name 'steam-runtime.tar.xz.part*' \) -delete 2>/dev/null || true

  if [[ -e "$BOOTSTRAP" ]]; then
    log "Bootstrap after failure: $(file -b "$BOOTSTRAP" || true)"
  fi

  sleep 3

  if ! run_steam 2; then
    log "Steam still failed after clean retry."
    log "The last /tmp/steam.log above is the useful diagnostic."
    log "noVNC remains available."
  fi
fi

wait "$NOVNC_PID"
