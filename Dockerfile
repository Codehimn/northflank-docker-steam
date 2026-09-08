FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/steamuser \
    DISPLAY=:0

# Base graphical stack + tools required by the official Steam launcher.
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        dbus-x11 \
        xterm \
        xvfb \
        openbox \
        x11vnc \
        novnc \
        websockify \
        libgl1-mesa-dri:amd64 \
        libgl1-mesa-dri:i386 \
        libgl1-mesa-glx:amd64 \
        libgl1-mesa-glx:i386 \
        mesa-vulkan-drivers:amd64 \
        mesa-vulkan-drivers:i386 \
        libvulkan1:amd64 \
        libvulkan1:i386 && \
    curl -fsSL https://repo.steampowered.com/steam/archive/stable/steam.gpg \
        -o /usr/share/keyrings/steam.gpg && \
    printf '%s\n' \
        'deb [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] https://repo.steampowered.com/steam/ stable steam' \
        > /etc/apt/sources.list.d/steam-stable.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        steam-launcher \
        steam-libs-amd64:amd64 \
        steam-libs-i386:i386 && \
    apt-get clean

# steamdeps is useful on a normal desktop because it can request admin access
# to install missing host packages. In this container all host dependencies are
# installed at build time and runtime is intentionally non-root, so disable the
# helper itself to prevent pkexec/apt dialogs inside VNC.
RUN rm -f /usr/bin/steamdeps && \
    test -x /usr/bin/steam

# X11 socket directory must exist before switching to the unprivileged user.
RUN mkdir -p /tmp/.X11-unix && \
    chmod 1777 /tmp/.X11-unix

RUN useradd --create-home --shell /bin/bash steamuser && \
    mkdir -p \
        /data/Steam \
        /data/.steam \
        /home/steamuser/.local/share && \
    chown -R steamuser:steamuser /data /home/steamuser

COPY start.sh /usr/local/bin/start.sh
RUN chmod 0755 /usr/local/bin/start.sh

USER steamuser
WORKDIR /home/steamuser

EXPOSE 6080

CMD ["/usr/local/bin/start.sh"]
