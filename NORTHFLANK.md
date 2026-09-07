# Northflank setup v13

Repository root must contain:
- Dockerfile
- entrypoint.sh
- start.sh
- install-steam.sh
- steam-watchdog.sh
- install-taskbarhero.sh
- launch-taskbarhero.sh
- README.md
- NORTHFLANK.md
- .dockerignore

Northflank:
- expose 6080 as HTTP
- mount persistent storage at /data if available
- default VNC password: cambia12

The build intentionally does NOT install Steam anymore.
Steam installation occurs only after noVNC is already running.
