# Northflank setup

1. Delete the old repository contents.
2. Extract THIS ZIP.
3. Upload every extracted file directly to the repository root.
4. Verify that `launch-taskbarhero.sh` is visible beside `Dockerfile`.
5. Do not upload the ZIP itself as the repository content.
6. Build from the root Dockerfile.
7. Expose port 6080 as HTTP.
8. Recommended: mount persistent storage at `/data`.
9. Deploy.
10. Open the generated public URL.

Default VNC password:
cambia12

If you use GitHub, the repository should visually look like:

Dockerfile
entrypoint.sh
start.sh
steam-watchdog.sh
install-taskbarhero.sh
launch-taskbarhero.sh
README.md
NORTHFLANK.md
.dockerignore

There should be NO `scripts/` directory.
