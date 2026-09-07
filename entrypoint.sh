#!/bin/bash
set -e
chown -R steamuser:steamuser /data
exec su - steamuser -c "/start.sh"
