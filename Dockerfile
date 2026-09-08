# TaskbarHero on Northflank - V15
# Native Steam Linux is intentionally NOT used because the observed Northflank
# x86_64 runtime rejects Linux i386 ELF execution. This image uses Windows Steam
# through Wine 11 new-WoW64 and remains non-root at runtime.
FROM --platform=linux/amd64 ubuntu:26.04

LABEL taskbarhero.version="v15-20260908"

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/steamuser \
    DISPLAY=:0 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        gnupg \
        file \
        procps \
        psmisc \
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

# Official WineHQ stable repository for Ubuntu 26.04.
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

# Xvfb needs this to exist before runtime drops root.
RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# Do not force UID 1000; previous Northflank builds showed it may already exist.
RUN useradd --create-home --shell /bin/bash steamuser && \
    mkdir -p /data /opt/steam-bootstrap && \
    chown -R steamuser:steamuser /data /opt/steam-bootstrap /home/steamuser

# Bake the official Windows Steam installer into the image during build.
RUN wget -qO /opt/steam-bootstrap/SteamSetup.exe \
        https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe && \
    test -s /opt/steam-bootstrap/SteamSetup.exe && \
    file /opt/steam-bootstrap/SteamSetup.exe | grep -qi 'PE32' && \
    chown steamuser:steamuser /opt/steam-bootstrap/SteamSetup.exe

# Fail build early if any command/path required by start.sh is absent.
RUN command -v wine >/dev/null && \
    command -v wineserver >/dev/null && \
    command -v Xvfb >/dev/null && \
    command -v xdpyinfo >/dev/null && \
    command -v openbox-session >/dev/null && \
    command -v x11vnc >/dev/null && \
    command -v websockify >/dev/null && \
    command -v dbus-launch >/dev/null && \
    test -f /usr/share/novnc/vnc.html && \
    wine --version

COPY start.sh /usr/local/bin/start.sh
RUN chmod 0755 /usr/local/bin/start.sh

USER steamuser
WORKDIR /home/steamuser

EXPOSE 6080

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/start.sh"]
