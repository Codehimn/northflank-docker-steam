# Taskbar Hero on Northflank: Steam for Windows + Wine 11 WoW64

This repository intentionally does **not** use Steam for Linux.

Your Northflank runtime was confirmed to be `x86_64`, but it cannot execute
Linux IA32 ELF binaries. Steam for Linux therefore cannot run there.

This image instead uses:

- Debian Forky (amd64 only)
- WineHQ Wine 11 stable
- Wine 11 **new WoW64**
- Windows `SteamSetup.exe`
- Xvfb
- Openbox
- x11vnc
- noVNC
- Mesa/llvmpipe software rendering

Wine 11 new WoW64 runs 32-bit Windows PE applications inside a 64-bit Unix
host process, so it does not depend on Linux IA32 execution.

## What happens automatically

During Docker build:

1. WineHQ official repository is added.
2. Wine 11 stable is installed.
3. The build fails if Wine is not version 11.x.
4. The official Windows Steam installer is downloaded.
5. The build fails if `SteamSetup.exe` is not a Windows PE executable.
6. A fresh `WINEARCH=wow64` prefix is created.
7. A 32-bit Windows `cmd.exe` is executed as a build-time WoW64 test.
8. SteamSetup.exe is silently installed into a template prefix.
9. The build fails if `Steam.exe` is not present afterward.

At container startup:

1. The prebuilt Steam/Wine prefix is copied into `/data/wineprefix` if needed.
2. Xvfb starts.
3. Openbox starts.
4. x11vnc starts.
5. noVNC starts on port 6080.
6. Wine refreshes the prefix.
7. Windows Steam starts automatically.
8. Steam can update itself.
9. You enter noVNC and log in to Steam.

## Northflank settings

Expose:

- Port: `6080`
- Protocol: `HTTP`

Open the generated Northflank URL. `/` redirects automatically to noVNC.

Default VNC password:

`cambia12`

Classic VNC passwords effectively use 8 characters, so the default is exactly
8 characters. You can override it with the environment variable:

`VNC_PASSWORD=abcdefgh`

## Recommended environment variables

For the first login:

- `VNC_PASSWORD=cambia12`
- `LOW_MEMORY=1`
- `STEAM_START_SILENT=0`

After Steam is authenticated, you can try:

- `STEAM_START_SILENT=1`

That asks Steam to start minimized/silent.

## Persistence

For Steam login, installed games, and Steam Cloud metadata to survive container
replacement/redeploy, attach a Northflank persistent volume at:

`/data`

Everything important is under:

`/data/wineprefix`

Logs are under:

`/data/logs`

Important logs:

- `/data/logs/steam.log`
- `/data/logs/watchdog.log`
- `/data/logs/wineboot.log`
- `/data/logs/novnc.log`
- `/data/logs/x11vnc.log`

## Taskbar Hero helpers

After you have logged into Steam, from a Northflank shell:

Install Taskbar Hero:

`/opt/taskbarhero/install-taskbarhero.sh`

Launch Taskbar Hero:

`/opt/taskbarhero/launch-taskbarhero.sh`

The default App ID configured is `3678970`.

## About 512 MB RAM

This architecture removes the Linux-IA32 blocker and is deliberately minimal.
However, the modern Steam UI uses multiple Chromium/CEF helper processes.

`LOW_MEMORY=1` starts Steam with container-friendly CEF/GPU flags and Mesa
software rendering, but **512 MB is still a hard runtime limit**. If the kernel
OOM-kills Steam during its first self-update or login UI, that is a memory
limit rather than a Wine/IA32 compatibility failure.

The image itself does not install a full desktop environment, GNOME, KDE, XFCE,
or Steam for Linux.
