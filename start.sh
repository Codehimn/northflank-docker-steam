#!/bin/bash
set -e

# Virtual display
Xvfb :99 -screen 0 1024x768x16 &
sleep 2

# Minimal window manager
openbox &

# Start noVNC on port 6080
websockify --web=/usr/share/novnc/ 6080 localhost:5900 &

echo "Container ready."
echo "Use noVNC to complete Steam login/captcha if needed."

# Placeholder:
# Put Taskbar Hero files in /opt/taskbarhero/game
# Then replace the line below with:
# wine /opt/taskbarhero/game/TBH.exe

tail -f /dev/null
