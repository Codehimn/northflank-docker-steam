#!/bin/bash
set -e

if command -v steam >/dev/null 2>&1; then
    echo "Steam already installed"
    exit 0
fi

apt update

apt install -y --no-install-recommends \
    steam-installer \
    || echo "Steam package unavailable, manual install required"

apt clean
rm -rf /var/lib/apt/lists/*
