# Taskbar Hero / Northflank v13 - fail-safe runtime installer

This repository is FLAT. Every file must be in the repository root.

## What changed

The Docker build no longer tries to install Steam.

Build-time work is limited to things that are deterministic:
- install WineHQ Wine 11
- download official SteamSetup.exe
- validate it is a Windows PE32 executable
- create a clean 64-bit Wine prefix

At runtime:
1. Xvfb starts.
2. Openbox starts.
3. x11vnc starts.
4. noVNC starts.
5. Only then does SteamSetup.exe run.
6. Silent installation is attempted twice.
7. The script searches the entire Wine C: drive for Steam.exe instead of
   assuming a single installation path.
8. Installer exit codes are not trusted as the sole success signal.
9. If silent installation still fails, the normal Steam installer is opened
   visibly in noVNC.
10. noVNC remains alive instead of crashing the service.

## Northflank
- Port: 6080
- Protocol: HTTP
- Recommended persistent volume: /data

Default VNC password:
cambia12

## Logs
/data/logs/steam-installer.log
/data/logs/steam-installer-visible.log
/data/logs/steam.log
/data/logs/watchdog.log
