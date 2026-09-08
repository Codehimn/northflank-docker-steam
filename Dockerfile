# TaskbarHero on Northflank - V16 FINAL
# Native Steam Linux is intentionally not used because the observed Northflank
# x86_64 runtime rejects Linux i386 ELF execution. This image uses Windows Steam
# with Wine 11 new-WoW64 and keeps runtime non-root.
FROM --platform=linux/amd64 ubuntu:26.04

LABEL taskbarhero.version="v16-final-20260908"

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/steamuser \
    DISPLAY=:0 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        curl \
        gnupg \
        file \
        procps \
        psmisc \
        iproute2 \
        tini \
        xauth \
        x11-utils \
        dbus-x11 \
        xvfb \
        openbox \
        x11vnc \
        novnc \
        websockify \
        fonts-dejavu-core \
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
    rm -rf /var/lib/apt/lists/*

# Prepare X socket directory before dropping root.
RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# Do not force UID 1000; previous Northflank builds showed it can be occupied.
RUN useradd --create-home --shell /bin/bash steamuser && \
    mkdir -p /data /opt/steam-bootstrap && \
    chown -R steamuser:steamuser /data /opt/steam-bootstrap /home/steamuser

# Official Windows Steam installer baked into the image.
RUN wget -qO /opt/steam-bootstrap/SteamSetup.exe \
        https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe && \
    test -s /opt/steam-bootstrap/SteamSetup.exe && \
    file /opt/steam-bootstrap/SteamSetup.exe | grep -qi 'PE32' && \
    chown steamuser:steamuser /opt/steam-bootstrap/SteamSetup.exe

# Build-time dependency verification.
RUN command -v wine >/dev/null && \
    command -v wineserver >/dev/null && \
    command -v Xvfb >/dev/null && \
    command -v xdpyinfo >/dev/null && \
    command -v openbox-session >/dev/null && \
    command -v x11vnc >/dev/null && \
    command -v websockify >/dev/null && \
    command -v curl >/dev/null && \
    command -v ss >/dev/null && \
    test -f /usr/share/novnc/vnc.html && \
    wine --version

COPY start.sh /usr/local/bin/start.sh
RUN chmod 0755 /usr/local/bin/start.sh

USER steamuser
WORKDIR /home/steamuser

EXPOSE 6080

# Northflank wraps the container entrypoint, so register tini as subreaper.
ENTRYPOINT ["/usr/bin/tini", "-s", "--"]
CMD ["/usr/local/bin/start.sh"]
