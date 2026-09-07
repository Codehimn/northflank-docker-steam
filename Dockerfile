FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99

RUN dpkg --add-architecture i386 && \
    apt update && \
    apt install -y --no-install-recommends \
    xvfb \
    openbox \
    x11vnc \
    novnc \
    websockify \
    wget \
    curl \
    ca-certificates \
    unzip \
    software-properties-common \
    libgl1 \
    libxcomposite1 \
    libxrandr2 \
    libxi6 \
    libxcursor1 \
    libxinerama1 \
    libnss3 \
    && apt clean && rm -rf /var/lib/apt/lists/*

# Install WineHQ stable
RUN wget -qO- https://dl.winehq.org/wine-builds/winehq.key | apt-key add - && \
    echo "deb https://dl.winehq.org/wine-builds/ubuntu/ jammy main" > /etc/apt/sources.list.d/winehq.list && \
    apt update && \
    apt install -y --install-recommends winehq-stable && \
    apt clean && rm -rf /var/lib/apt/lists/*

# Steam installer dependencies
RUN mkdir -p /root/.vnc /root/.steam /opt/taskbarhero

WORKDIR /opt/taskbarhero

COPY start.sh /opt/taskbarhero/start.sh
COPY launch-steam.sh /opt/taskbarhero/launch-steam.sh

RUN chmod +x /opt/taskbarhero/*.sh

EXPOSE 6080

CMD ["/opt/taskbarhero/start.sh"]
