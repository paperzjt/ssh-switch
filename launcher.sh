#!/bin/sh
RESOURCES="$(cd "$(dirname "$0")/../Resources" && pwd)"
exec /usr/bin/python3 "$RESOURCES/app.py"
