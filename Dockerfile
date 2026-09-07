# syntax=docker/dockerfile:1

FROM debian:forky-slim AS pebuilder

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      gcc-mingw-w64-i686 \
      gcc-mingw-w64-x86-64 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN printf '%s\n' \
    '#include <stdio.h>' \
    'int main(void){puts("PE32_OK"); return 0;}' \
    > pe32.c && \
    i686-w64-mingw32-gcc -Os -s pe32.c -o pe32-test.exe && \
    printf '%s\n' \
    '#include <stdio.h>' \
    'int main(void){puts("PE64_OK"); return 0;}' \
    > pe64.c && \
    x86_64-w64-mingw32-gcc -Os -s pe64.c -o pe64-test.exe

FROM debian:forky-slim

ENV DEBIAN_FRONTEND=noninteractive

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
      7zip \
    && rm -rf /var/lib/apt/lists/*

# WineHQ Testing/Forky packages use the new WoW64 implementation.
# No Linux i386 architecture is enabled.
RUN mkdir -pm755 /etc/apt/keyrings && \
    wget -qO- https://dl.winehq.org/wine-builds/winehq.key \
      | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key && \
    wget -qO /etc/apt/sources.list.d/winehq-forky.sources \
      https://dl.winehq.org/wine-builds/debian/dists/forky/winehq-forky.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable && \
    rm -rf /var/lib/apt/lists/*

RUN wine --version | tee /tmp/wine-version.txt && \
    grep -Eq 'wine-11\.' /tmp/wine-version.txt

RUN useradd --uid 1000 --create-home --shell /bin/bash steamuser && \
    mkdir -p /opt/installers /opt/prefix-template /opt/taskbarhero /opt/novnc /opt/tests /data && \
    chown -R steamuser:steamuser /opt/prefix-template /opt/taskbarhero /opt/tests /data

COPY --from=pebuilder /build/pe32-test.exe /opt/tests/pe32-test.exe
COPY --from=pebuilder /build/pe64-test.exe /opt/tests/pe64-test.exe

# Official Steam Windows bootstrapper.
RUN curl -fL \
      --retry 5 \
      --retry-all-errors \
      --connect-timeout 20 \
      https://media.steampowered.com/client/installer/SteamSetup.exe \
      -o /opt/installers/SteamSetup.exe && \
    test -s /opt/installers/SteamSetup.exe && \
    file /opt/installers/SteamSetup.exe | tee /tmp/steamsetup-file.txt && \
    grep -qi 'PE32' /tmp/steamsetup-file.txt

# Build only a clean 64-bit Wine prefix. Do not install Steam during image build.
RUN gosu steamuser env \
      HOME=/home/steamuser \
      WINEPREFIX=/opt/prefix-template \
      WINEDEBUG=-all \
      WINEDLLOVERRIDES="mscoree,mshtml=" \
      xvfb-run -a wineboot -u && \
    gosu steamuser env \
      HOME=/home/steamuser \
      WINEPREFIX=/opt/prefix-template \
      WINEDEBUG=-all \
      wineserver -w && \
    test -f /opt/prefix-template/system.reg

RUN cp -a /usr/share/novnc/. /opt/novnc/ && \
    printf '%s\n' \
      '<!doctype html><meta charset="utf-8">' \
      '<meta http-equiv="refresh" content="0;url=/vnc.html?autoconnect=1&resize=scale">' \
      '<title>Taskbar Hero</title>' \
      '<a href="/vnc.html?autoconnect=1&resize=scale">Open noVNC</a>' \
      > /opt/novnc/index.html

COPY entrypoint.sh /opt/taskbarhero/entrypoint.sh
COPY start.sh /opt/taskbarhero/start.sh
COPY prepare-steam.sh /opt/taskbarhero/prepare-steam.sh
COPY steam-watchdog.sh /opt/taskbarhero/steam-watchdog.sh
COPY install-taskbarhero.sh /opt/taskbarhero/install-taskbarhero.sh
COPY launch-taskbarhero.sh /opt/taskbarhero/launch-taskbarhero.sh

RUN chmod +x /opt/taskbarhero/*.sh && \
    chown -R steamuser:steamuser /opt/taskbarhero

ENV DISPLAY=:99 \
    HOME=/home/steamuser \
    WINEPREFIX=/data/wineprefix \
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
