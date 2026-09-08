# TaskbarHero / Northflank
# Native Steam Linux cannot run on the observed Northflank node because Linux
# i386 ELF execution is blocked. Wine 11 new-WoW64 avoids that requirement.
FROM --platform=linux/amd64 ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/steamuser \
    DISPLAY=:0 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Minimal graphical/VNC stack and 64-bit Unix libraries for Wine.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        gnupg \
        file \
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

# WineHQ stable for Ubuntu 26.04.
# Wine 11 completed the new WoW64 architecture, so no Linux i386 multiarch is
# enabled in this image.
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

# Download SteamSetup.exe at BUILD time. Nothing is downloaded by our startup
# script before the Steam client itself starts.
RUN wget -qO /opt/steam-bootstrap/SteamSetup.exe \
        https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe && \
    test -s /opt/steam-bootstrap/SteamSetup.exe && \
    file /opt/steam-bootstrap/SteamSetup.exe | grep -qi 'PE32' && \
    chown steamuser:steamuser /opt/steam-bootstrap/SteamSetup.exe

USER steamuser

# Prepare the Wine prefix at build time, but deliberately DO NOT install Steam
# silently here. That was the fragile part of v10/v11. We also prove during the
# build that Wine can execute a 32-bit Windows program through new WoW64.
RUN export WINEPREFIX=/opt/wineprefix-template && \
    export WINEARCH=win64 && \
    export WINEDEBUG=-all && \
    xvfb-run -a wineboot -u >/tmp/wineboot-build.log 2>&1 && \
    wineserver -w && \
    export WINEARCH=wow64 && \
    xvfb-run -a wine 'C:\windows\syswow64\cmd.exe' /c exit \
        >/tmp/wow64-test.log 2>&1 && \
    wineserver -k && \
    test -f /opt/wineprefix-template/system.reg

USER root
COPY start.sh /usr/local/bin/start.sh
RUN chmod 0755 /usr/local/bin/start.sh && \
    chown -R steamuser:steamuser /opt/wineprefix-template /opt/steam-bootstrap

USER steamuser
WORKDIR /home/steamuser

EXPOSE 6080

CMD ["/usr/local/bin/start.sh"]
