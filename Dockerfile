FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive

RUN echo "deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates curl wget steam-installer \
    xvfb openbox x11vnc novnc websockify dbus-x11 xterm \
    libgl1 libgl1:i386 libxss1:i386 libasound2:i386 libxtst6:i386 \
    procps psmisc && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash steamuser && mkdir -p /data && chown -R steamuser:steamuser /data

COPY entrypoint.sh /entrypoint.sh
COPY start.sh /start.sh
COPY install-taskbarhero.sh /install-taskbarhero.sh

RUN chmod +x /entrypoint.sh /start.sh /install-taskbarhero.sh

ENV DISPLAY=:99
ENV HOME=/home/steamuser
ENV USER=steamuser
ENV VNC_PASSWORD=cambiar123

EXPOSE 6080
ENTRYPOINT ["/entrypoint.sh"]
