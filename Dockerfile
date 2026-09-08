# TASKBARHERO NORTHFLANK V13
# Northflank's observed x86_64 runtime rejects Linux i386 ELF, so this image
# intentionally uses Windows Steam under Wine 11 new-WoW64.
FROM --platform=linux/amd64 ubuntu:26.04

LABEL taskbarhero.build="v13-20260908"

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/steamuser \
    DISPLAY=:0 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN echo "=== TASKBARHERO V13 BUILD ===" && \
    apt-get update && \
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

# WineHQ stable for Ubuntu 26.04. Wine 11 new-WoW64 can run 32-bit Windows
# binaries from a 64-bit prefix without Linux i386 userspace.
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
    mkdir -p /data /opt/steam-bootstrap && \
    chown -R steamuser:steamuser /data /opt/steam-bootstrap /home/steamuser

# Official Steam Windows installer is baked into the image.
RUN wget -qO /opt/steam-bootstrap/SteamSetup.exe \
        https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe && \
    test -s /opt/steam-bootstrap/SteamSetup.exe && \
    file /opt/steam-bootstrap/SteamSetup.exe | grep -qi 'PE32' && \
    chown steamuser:steamuser /opt/steam-bootstrap/SteamSetup.exe

COPY start.sh /usr/local/bin/start.sh
RUN chmod 0755 /usr/local/bin/start.sh

USER steamuser
WORKDIR /home/steamuser

EXPOSE 6080

CMD ["/usr/local/bin/start.sh"]
