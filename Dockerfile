FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99
ENV PATH="/usr/games:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      wget \
      procps \
      file \
      xterm \
      x11-utils \
      xvfb \
      openbox \
      x11vnc \
      novnc \
      websockify \
      dbus-x11 \
      fonts-dejavu-core \
      udev \
      wine64 \
      wine32 \
      steam-installer \
      libc6:i386 \
      libgl1-mesa-dri:amd64 \
      libgl1-mesa-dri:i386 \
      libgl1:amd64 \
      libgl1:i386 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN useradd -m -s /bin/bash steamuser && \
    mkdir -p /home/steamuser/.vnc /home/steamuser/.local/share/Steam /opt/taskbarhero && \
    chown -R steamuser:steamuser /home/steamuser /opt/taskbarhero

WORKDIR /opt/taskbarhero
COPY --chown=steamuser:steamuser start.sh /opt/taskbarhero/start.sh
RUN chmod +x /opt/taskbarhero/start.sh

USER steamuser

EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -fsS http://127.0.0.1:6080/vnc.html >/dev/null || exit 1

CMD ["/opt/taskbarhero/start.sh"]
