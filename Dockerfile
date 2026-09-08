# Native Steam for Linux cannot run on Northflank nodes that reject i386 ELF.
# Wine 11 new-WoW64 runs 32-bit Windows components inside a 64-bit Unix process,
# so it does not require Linux IA32 execution support.
FROM --platform=linux/amd64 ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/steamuser \
    DISPLAY=:0 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Minimal X11/noVNC stack + software OpenGL dependencies.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        gnupg \
        xauth \
        dbus-x11 \
        procps \
        psmisc \
        xvfb \
        openbox \
        x11vnc \
        novnc \
        websockify \
        fonts-liberation \
        libgl1 \
        libgl1-mesa-dri \
        libegl1 \
        libglx-mesa0 \
        libx11-6 \
        libxext6 \
        libxrender1 \
        libxrandr2 \
        libxi6 \
        libxcursor1 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libfontconfig1 && \
    rm -rf /var/lib/apt/lists/*

# WineHQ stable on Ubuntu 26.04 uses the completed "new WoW64" architecture.
# No Linux i386 architecture is enabled or installed.
RUN install -d -m 0755 /etc/apt/keyrings && \
    wget -qO- https://dl.winehq.org/wine-builds/winehq.key \
        | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.gpg && \
    wget -qO /etc/apt/sources.list.d/winehq.sources \
        https://dl.winehq.org/wine-builds/ubuntu/dists/resolute/winehq-resolute.sources && \
    sed -i \
        's#/etc/apt/keyrings/winehq-archive.key#/etc/apt/keyrings/winehq-archive.gpg#' \
        /etc/apt/sources.list.d/winehq.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable && \
    rm -rf /var/lib/apt/lists/* && \
    wine --version

RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

RUN useradd --create-home --shell /bin/bash steamuser && \
    mkdir -p /data /opt/steam-bootstrap /opt/wineprefix-template && \
    chown -R steamuser:steamuser \
        /data /opt/steam-bootstrap /opt/wineprefix-template /home/steamuser

# Download the official Windows Steam installer at build time.
RUN wget -qO /opt/steam-bootstrap/SteamSetup.exe \
        https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe && \
    test -s /opt/steam-bootstrap/SteamSetup.exe && \
    chown steamuser:steamuser /opt/steam-bootstrap/SteamSetup.exe

# Build a ready-to-use 64-bit Wine prefix and install Steam silently.
# Wine 11's new WoW64 can run Steam's 32-bit Windows bootstrap without Linux i386.
USER steamuser
RUN export WINEPREFIX=/opt/wineprefix-template && \
    export WINEARCH=wow64 && \
    export WINEDLLOVERRIDES="mscoree,mshtml=" && \
    xvfb-run -a wineboot -u >/tmp/wineboot-build.log 2>&1 && \
    xvfb-run -a wine /opt/steam-bootstrap/SteamSetup.exe /S \
        >/tmp/steam-install-build.log 2>&1 && \
    wineserver -k || true

USER root
COPY start.sh /usr/local/bin/start.sh
RUN chmod 0755 /usr/local/bin/start.sh && \
    chown -R steamuser:steamuser /opt/wineprefix-template

USER steamuser
WORKDIR /home/steamuser

EXPOSE 6080

CMD ["/usr/local/bin/start.sh"]
