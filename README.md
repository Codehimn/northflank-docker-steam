# Taskbar Hero / Northflank v12

This repo is intentionally flat. Put every file in the repository root.

What v12 fixes:
- Do NOT create/test the prefix with WINEARCH=wow64.
- Create a normal 64-bit prefix with WINEARCH=win64.
- Debian Forky WineHQ packages already use NEW WoW64.
- Use the actual 32-bit SteamSetup.exe installer as the WoW64 test.
- The Docker build only succeeds if SteamSetup.exe runs and Steam.exe is created.

Northflank:
- Port 6080
- Protocol HTTP
- Persistent volume recommended at /data

Default VNC password:
cambia12

Repo root files:
Dockerfile
entrypoint.sh
start.sh
steam-watchdog.sh
install-taskbarhero.sh
launch-taskbarhero.sh
README.md
NORTHFLANK.md
.dockerignore
