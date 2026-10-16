#!/bin/bash
set -eu
umask 077
ROOT="${MOOD_SERVER_ROOT:-$HOME/mood-server}"
exec /usr/bin/env python3 "$ROOT/scripts/monitor.py"
