FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/steamuser \
    DISPLAY=:0

# Use Ubuntu's own Steam packaging instead of mixing Valve's repository with
# Ubuntu packages. This package pulls the matching 64/32-bit Steam dependency
# metapackages, which is much less fragile in a minimal container.
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        dbus-x11 \
        file \
        procps \
        xdg-user-dirs \
        xdg-utils \
        bubblewrap \
        xvfb \
        openbox \
        x11vnc \
        novnc \
        websockify \
        steam-installer \
        steam-libs:amd64 \
        steam-libs:i386 \
        steam-libs-i386:i386 \
        libc6:i386 \
        libc6-i386 \
        libgcc-s1:i386 \
        libstdc++6:i386 \
        libgl1:amd64 \
        libgl1:i386 \
        libgl1-mesa-dri:amd64 \
        libgl1-mesa-dri:i386 \
        libegl1:amd64 \
        libegl1:i386 \
        libgbm1:amd64 \
        libgbm1:i386 \
        libdrm2:amd64 \
        libdrm2:i386 \
        libvulkan1:amd64 \
        libvulkan1:i386 \
        mesa-vulkan-drivers:amd64 \
        mesa-vulkan-drivers:i386 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Build-time sanity checks. Fail the image build immediately if the exact
# 32-bit loader/libc that Steam needs are missing or cannot execute.
RUN test -x /usr/games/steam && \
    test -e /lib/ld-linux.so.2 && \
    test -e /lib/i386-linux-gnu/libc.so.6 && \
    dpkg-query -W -f='${Status}\n' libc6:i386 | grep -q 'install ok installed' && \
    /lib/ld-linux.so.2 --help >/dev/null

# On a desktop steamdeps may call apt/pkexec. Runtime here is deliberately
# non-root and every host dependency is baked into the image, so make the
# helper a successful no-op to prevent interactive privilege dialogs.
RUN if [ -e /usr/bin/steamdeps ]; then ln -sf /bin/true /usr/bin/steamdeps; fi

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
