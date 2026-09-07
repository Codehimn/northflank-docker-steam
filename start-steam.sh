#!/bin/bash

export DISPLAY=:99

if command -v steam >/dev/null 2>&1; then
    steam &
else
    echo "Steam command not found"
fi
