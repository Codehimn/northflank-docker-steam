# Taskbar Hero / Northflank v14

This version does not assume SteamSetup.exe is the first thing Wine should run.

Runtime sequence:

1. Start noVNC.
2. Run a tiny 64-bit Windows EXE compiled in the Docker build.
3. Run a tiny 32-bit Windows EXE compiled in the Docker build.
4. If PE32 fails, stop attempting Steam and keep noVNC alive.
5. If PE32 works, try to extract Steam.exe directly from SteamSetup.exe with 7-Zip.
6. If extraction works, bypass the Windows installer completely.
7. If extraction fails, run SteamSetup.exe with detailed Wine loader/SEH logs.

Important log lines:
- PE64 TEST: OK/FAILED
- PE32 TEST: OK/FAILED

Logs:
- /data/logs/pe64-test.log
- /data/logs/pe32-test.log
- /data/logs/steam-extract.log
- /data/logs/steam-installer.log
- /data/logs/steam.log

Northflank:
- 6080 HTTP
- persistent volume recommended at /data
- VNC password: cambia12
