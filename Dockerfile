FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/steamuser
ENV DISPLAY=:0

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates curl wget \
    xvfb openbox x11vnc novnc websockify \
    steam-installer \
    libgl1 libgl1:i386 libglvnd0:i386 \
    libgtk2.0-0:i386 libnss3:i386 && \
    rm -rf /var/lib/apt/lists/*

# Preparar X11 para ejecución sin root
RUN mkdir -p /tmp/.X11-unix && \
    chmod 1777 /tmp/.X11-unix

RUN useradd -m -s /bin/bash steamuser && \
    mkdir -p /data/Steam && \
    mkdir -p /home/steamuser/.steam && \
    mkdir -p /home/steamuser/.local/share && \
    chown -R steamuser:steamuser /data /home/steamuser

COPY start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh

USER steamuser
WORKDIR /home/steamuser

EXPOSE 6080 5900

CMD ["/usr/local/bin/start.sh"]
