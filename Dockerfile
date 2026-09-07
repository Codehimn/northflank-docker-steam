FROM debian:forky-slim

ENV DEBIAN_FRONTEND=noninteractive

# Base tools + minimal X11/noVNC stack.
# IMPORTANT: do NOT enable i386. Northflank's kernel in your test cannot execute
# Linux IA32 ELF binaries, so this image intentionally uses Wine's NEW WoW64.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      wget \
      gnupg \
      file \
      procps \
      psmisc \
      xauth \
      xvfb \
      x11-utils \
      openbox \
      x11vnc \
      novnc \
      websockify \
      dbus-x11 \
      fonts-dejavu-core \
      fonts-liberation \
      libgl1 \
      libgl1-mesa-dri \
      mesa-utils \
      gosu \
      tini \
    && rm -rf /var/lib/apt/lists/*

# WineHQ official repository for Debian Testing/Forky.
# WineHQ's Forky packages use the new WoW64 architecture and do NOT need i386.
RUN mkdir -pm755 /etc/apt/keyrings && \
    wget -qO- https://dl.winehq.org/wine-builds/winehq.key \
      | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key && \
    wget -qO /etc/apt/sources.list.d/winehq-forky.sources \
      https://dl.winehq.org/wine-builds/debian/dists/forky/winehq-forky.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable && \
    rm -rf /var/lib/apt/lists/*

# Fail the build if an old Wine accidentally gets pulled in.
RUN wine --version | tee /tmp/wine-version.txt && \
    grep -Eq 'wine-11\.' /tmp/wine-version.txt

# Normal runtime user. Fixed UID helps persistent volumes.
RUN useradd --uid 1000 --create-home --shell /bin/bash steamuser && \
    mkdir -p /opt/installers /opt/prefix-template /opt/taskbarhero /opt/novnc /data && \
    chown -R steamuser:steamuser /opt/prefix-template /opt/taskbarhero /data

# Official Windows Steam installer.
RUN curl -fL \
      --retry 5 \
      --retry-all-errors \
      --connect-timeout 20 \
      https://media.steampowered.com/client/installer/SteamSetup.exe \
      -o /opt/installers/SteamSetup.exe && \
    test -s /opt/installers/SteamSetup.exe && \
    file /opt/installers/SteamSetup.exe | tee /tmp/steamsetup-file.txt && \
    grep -qi 'PE32' /tmp/steamsetup-file.txt

# Build a ready-to-copy Wine prefix and prove that 32-bit WINDOWS PE code runs
# through Wine 11 new WoW64 without Linux IA32 support.
RUN gosu steamuser env \
      HOME=/home/steamuser \
      WINEPREFIX=/opt/prefix-template \
      WINEARCH=wow64 \
      WINEDEBUG=-all \
      WINEDLLOVERRIDES="mscoree,mshtml=" \
      xvfb-run -a wineboot -u && \
    gosu steamuser env \
      HOME=/home/steamuser \
      WINEPREFIX=/opt/prefix-template \
      WINEARCH=wow64 \
      WINEDEBUG=-all \
      xvfb-run -a wine 'C:\windows\syswow64\cmd.exe' /c echo WOW64_OK \
      | tee /tmp/wow64-test.txt && \
    grep -q 'WOW64_OK' /tmp/wow64-test.txt

# Install the Windows Steam bootstrapper into the template at BUILD time.
# Runtime therefore starts from an already-installed Steam client and only needs
# Steam's normal self-update + your login.
RUN gosu steamuser env \
      HOME=/home/steamuser \
      WINEPREFIX=/opt/prefix-template \
      WINEARCH=wow64 \
      WINEDEBUG=-all \
      WINEDLLOVERRIDES="mscoree,mshtml=" \
      xvfb-run -a wine /opt/installers/SteamSetup.exe /S && \
    gosu steamuser env \
      HOME=/home/steamuser \
      WINEPREFIX=/opt/prefix-template \
      WINEARCH=wow64 \
      WINEDEBUG=-all \
      wineserver -w && \
    test -f "/opt/prefix-template/drive_c/Program Files (x86)/Steam/Steam.exe"

# noVNC web root with a friendly default redirect.
RUN cp -a /usr/share/novnc/. /opt/novnc/ && \
    printf '%s\n' \
      '<!doctype html><meta charset="utf-8">' \
      '<meta http-equiv="refresh" content="0;url=/vnc.html?autoconnect=1&resize=scale">' \
      '<title>Taskbar Hero</title>' \
      '<a href="/vnc.html?autoconnect=1&resize=scale">Open noVNC</a>' \
      > /opt/novnc/index.html

COPY entrypoint.sh /opt/taskbarhero/entrypoint.sh
COPY start.sh /opt/taskbarhero/start.sh
COPY scripts/steam-watchdog.sh /opt/taskbarhero/steam-watchdog.sh
COPY scripts/install-taskbarhero.sh /opt/taskbarhero/install-taskbarhero.sh
COPY scripts/launch-taskbarhero.sh /opt/taskbarhero/launch-taskbarhero.sh

RUN chmod +x /opt/taskbarhero/*.sh && \
    chown -R steamuser:steamuser /opt/taskbarhero

ENV DISPLAY=:99 \
    HOME=/home/steamuser \
    WINEPREFIX=/data/wineprefix \
    WINEARCH=wow64 \
    WINEDEBUG=-all \
    LIBGL_ALWAYS_SOFTWARE=1 \
    GALLIUM_DRIVER=llvmpipe \
    MESA_LOADER_DRIVER_OVERRIDE=llvmpipe \
    MALLOC_ARENA_MAX=2 \
    VNC_PASSWORD=cambia12 \
    LOW_MEMORY=1 \
    STEAM_START_SILENT=0

EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
  CMD curl -fsS http://127.0.0.1:6080/ >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini","--","/opt/taskbarhero/entrypoint.sh"]
CMD ["/opt/taskbarhero/start.sh"]
