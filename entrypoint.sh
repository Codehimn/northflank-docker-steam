#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /data
chown steamuser:steamuser /data
exec gosu steamuser "$@"
