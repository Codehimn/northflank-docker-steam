# Steam for Linux is x86_64 and still requires i386 execution.
# Force an amd64 image even if Northflank's BuildKit worker itself is ARM.
FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/steamuser \
    DISPLAY=:0 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Ubuntu's Steam metapackages pull the matching host libraries.
# Explicit core i386 packages are kept here because Steam's bootstrap is 32-bit.
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        dbus-x11 \
        procps \
        xdg-user-dirs \
        xdg-utils \
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

# IMPORTANT:
# BuildKit can be running through cross-architecture emulation and may be unable
# to EXECUTE an i386 ELF even though the final x86 runtime can. Therefore these
# build checks verify presence/packaging only; they deliberately do not execute
# /lib/ld-linux.so.2.
RUN test -x /usr/games/steam && \
    test -e /lib/ld-linux.so.2 && \
    test -e /lib/i386-linux-gnu/libc.so.6 && \
    dpkg-query -W -f='${Status}\n' libc6:i386 | grep -q 'install ok installed' && \
    dpkg-query -W -f='${Status}\n' steam-libs-i386:i386 | grep -q 'install ok installed'

# steamdeps is for interactive desktop privilege escalation via apt/pkexec.
# All system dependencies are baked in at build time and runtime is non-root.
RUN if [ -e /usr/bin/steamdeps ]; then ln -sf /bin/true /usr/bin/steamdeps; fi

# Xvfb needs this before we drop root.
RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

RUN useradd --uid 1000 --create-home --shell /bin/bash steamuser && \
    mkdir -p /data/Steam /data/.steam /home/steamuser/.local/share && \
    chown -R steamuser:steamuser /data /home/steamuser

COPY start.sh /usr/local/bin/start.sh
RUN chmod 0755 /usr/local/bin/start.sh

USER steamuser
WORKDIR /home/steamuser

EXPOSE 6080

CMD ["/usr/local/bin/start.sh"]
