# Taskbar Hero / Northflank - Steam Windows + Wine 11 WoW64

IMPORTANT:
This repository is intentionally FLAT. Do not create a `scripts/` directory.
All files must be kept in the repository root exactly as they appear in this ZIP.

Required root files:

- Dockerfile
- entrypoint.sh
- start.sh
- steam-watchdog.sh
- install-taskbarhero.sh
- launch-taskbarhero.sh
- README.md
- NORTHFLANK.md
- .dockerignore

Northflank:
- Expose container port 6080
- Protocol: HTTP
- Recommended persistent volume mount: /data

Default VNC password:
cambia12

This version uses Windows Steam through Wine 11 new WoW64 and does not use
Steam for Linux or Linux i386 packages.
