# Steam for Linux is x86_64 and still requires i386 execution.
FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/steamuser \
    DISPLAY=:0 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        dbus-x11 \
        procps \
        xdg-user-dirs \
        xdg-utils \
        fonts-dejavu-core \
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

# Build checks verify package/file presence only.
# Do NOT execute the 32-bit loader here because cross-architecture BuildKit
# workers can reject i386 ELF even when the final x86_64 runtime supports it.
RUN test -x /usr/games/steam && \
    test -e /lib/ld-linux.so.2 && \
    test -e /lib/i386-linux-gnu/libc.so.6 && \
    dpkg-query -W -f='${Status}\n' libc6:i386 | grep -q 'install ok installed' && \
    dpkg-query -W -f='${Status}\n' steam-libs-i386:i386 | grep -q 'install ok installed'

# Prevent Steam from opening apt/pkexec dependency dialogs at runtime.
# Every host dependency is installed during build and runtime is non-root.
RUN if [ -e /usr/bin/steamdeps ]; then ln -sf /bin/true /usr/bin/steamdeps; fi

# Xvfb needs this directory before dropping root.
RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# IMPORTANT: do not force UID 1000.
# Ubuntu 24.04 images can already reserve UID 1000, which caused v8 to fail.
RUN useradd --create-home --shell /bin/bash steamuser && \
    mkdir -p /data/Steam /data/.steam /home/steamuser/.local/share && \
    chown -R steamuser:steamuser /data /home/steamuser && \
    id steamuser

COPY start.sh /usr/local/bin/start.sh
RUN chmod 0755 /usr/local/bin/start.sh

USER steamuser
WORKDIR /home/steamuser

EXPOSE 6080

CMD ["/usr/local/bin/start.sh"]
