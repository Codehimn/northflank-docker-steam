FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/steamuser \
    DISPLAY=:0

# Steam requires both amd64 and i386 userspace libraries.
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
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
        libvulkan1:amd64 \
        libvulkan1:i386 \
        mesa-vulkan-drivers:amd64 \
        mesa-vulkan-drivers:i386 && \
    rm -rf /var/lib/apt/lists/*

# Install Valve's current official launcher package directly.
# Important: we DO NOT create steam-stable.list ourselves.
# The package owns that conffile, avoiding dpkg's interactive conffile prompt.
RUN curl -fsSL \
        https://repo.steampowered.com/steam/archive/stable/steam_latest.deb \
        -o /tmp/steam.deb && \
    apt-get update && \
    apt-get install -y \
        -o Dpkg::Options::="--force-confnew" \
        /tmp/steam.deb && \
    rm -f /tmp/steam.deb && \
    rm -rf /var/lib/apt/lists/* && \
    test -x /usr/bin/steam

# In a normal desktop steamdeps may invoke apt/pkexec.
# All system packages are baked into this image and runtime is deliberately
# non-root. Flathub uses the same pattern: make steamdeps a successful no-op.
RUN ln -sf /bin/true /usr/bin/steamdeps

# Xvfb cannot create this directory after USER steamuser.
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
