FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99

RUN dpkg --add-architecture i386 && \
    apt update && \
    apt install -y --no-install-recommends \
    wine64 \
    wine32 \
    xvfb \
    openbox \
    x11vnc \
    novnc \
    websockify \
    wget \
    curl \
    ca-certificates \
    unzip \
    xterm \
    procps \
    && apt clean \
    && rm -rf /var/lib/apt/lists/* /tmp/*

RUN mkdir -p /root/.vnc /opt/taskbarhero

WORKDIR /opt/taskbarhero

COPY start.sh .
COPY install-steam.sh .
COPY start-steam.sh .

RUN chmod +x *.sh

EXPOSE 6080

CMD ["/opt/taskbarhero/start.sh"]
