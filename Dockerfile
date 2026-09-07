FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99

RUN dpkg --add-architecture i386 && \
    apt update && \
    apt install -y \
    xvfb \
    openbox \
    novnc \
    websockify \
    wine64 \
    wine32 \
    wget \
    curl \
    unzip \
    procps \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/taskbarhero

COPY start.sh /opt/taskbarhero/start.sh
RUN chmod +x /opt/taskbarhero/start.sh

EXPOSE 6080

CMD ["/opt/taskbarhero/start.sh"]
