FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/steamuser
ENV DISPLAY=:0
ENV DATA=/data

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg \
    xvfb openbox x11vnc novnc websockify \
    python3 \
    libgl1 libgl1:i386 libglvnd0:i386 \
    libgtk2.0-0:i386 libnss3:i386 \
    steam-installer && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash steamuser && \
    mkdir -p /data /home/steamuser/.steam /home/steamuser/.local/share/Steam && \
    chown -R steamuser:steamuser /data /home/steamuser

COPY start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh

USER steamuser
WORKDIR /home/steamuser

EXPOSE 6080 5900

CMD ["/usr/local/bin/start.sh"]
