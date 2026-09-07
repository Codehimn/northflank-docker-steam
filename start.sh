#!/bin/bash
set -e

export DISPLAY=:99

echo "Starting TaskbarHero environment"

if [ ! -f /root/.vnc/passwd ]; then
    x11vnc -storepasswd cambiar123 /root/.vnc/passwd
fi

Xvfb :99 -screen 0 1280x720x16 -ac -nolisten tcp -noreset &
sleep 3

openbox &
sleep 2

x11vnc \
-display :99 \
-rfbport 5900 \
-rfbauth /root/.vnc/passwd \
-forever \
-shared \
-noxdamage \
-bg

sleep 2

websockify --web=/usr/share/novnc/ 6080 localhost:5900 &

sleep 5

# Launch Steam automatically
/opt/taskbarhero/launch-steam.sh &

tail -f /dev/null
