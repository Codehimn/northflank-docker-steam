FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/steamuser
ENV DISPLAY=:0

# Steam needs i386 libraries
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    gnupg \
    xvfb \
    openbox \
    x11vnc \
    novnc \
    websockify \
    dbus-x11 \
    libgl1 \
    libgl1:i386 \
    libnss3:i386 \
    libgtk2.0-0:i386 \
    libxss1:i386 \
    libxtst6:i386 \
    libxrandr2:i386 \
    libxinerama1:i386 \
    libxcursor1:i386 && \
    rm -rf /var/lib/apt/lists/*

# Install official Steam client during build as root
RUN wget -qO /tmp/steam.deb https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb && \
    dpkg -i /tmp/steam.deb || true && \
    apt-get update && \
    apt-get install -fy -y && \
    rm -f /tmp/steam.deb && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/.X11-unix && \
    chmod 1777 /tmp/.X11-unix

RUN useradd -m -s /bin/bash steamuser && \
    mkdir -p /data/Steam \
             /data/.steam \
             /home/steamuser/.steam \
             /home/steamuser/.local/share && \
    chown -R steamuser:steamuser /data /home/steamuser

COPY start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh

USER steamuser
WORKDIR /home/steamuser

EXPOSE 6080 5900

CMD ["/usr/local/bin/start.sh"]
