FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99
ENV TZ=UTC

RUN dpkg --add-architecture i386 && \
    apt update && \
    apt install -y --no-install-recommends \
    xvfb \
    openbox \
    x11vnc \
    novnc \
    websockify \
    wine64 \
    wine32 \
    wget \
    curl \
    unzip \
    procps \
    ca-certificates \
    supervisor \
    && apt clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir -p /root/.vnc /opt/taskbarhero/logs

WORKDIR /opt/taskbarhero

COPY start.sh /opt/taskbarhero/start.sh
RUN chmod +x /opt/taskbarhero/start.sh

EXPOSE 6080

CMD ["/opt/taskbarhero/start.sh"]
