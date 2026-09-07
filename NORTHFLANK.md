# Northflank checklist

1. Put all files from this ZIP at the root of a fresh repository.
2. Create a Northflank build/service from the Dockerfile.
3. Expose container port `6080` as `HTTP`.
4. Set `VNC_PASSWORD` to an 8-character password if you do not want the default.
5. Recommended: attach persistent storage mounted at `/data`.
6. Deploy.
7. Open the public URL. It redirects to noVNC.
8. Enter the VNC password.
9. Steam for Windows should self-update and then show its login UI.
10. Log in normally and complete Steam Guard/captcha if requested.

Default VNC password: `cambia12`

Useful environment variables:

- `LOW_MEMORY=1`
- `STEAM_START_SILENT=0`
- `VNC_PASSWORD=cambia12`

After login, you may change `STEAM_START_SILENT=1`.

If Steam does not appear, inspect:

`/data/logs/steam.log`

and:

`/data/logs/watchdog.log`
