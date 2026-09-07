#!/usr/bin/env bash
set -Eeuo pipefail

# Northflank persistent volumes can arrive owned by root.
mkdir -p /data
chown steamuser:steamuser /data

exec gosu steamuser "$@"
