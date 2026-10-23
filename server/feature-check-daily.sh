#!/bin/bash
set -eu
umask 077
ROOT="${MOOD_SERVER_ROOT:-$HOME/mood-server}"
[ ! -d "$ROOT/maintenance.lock" ] || exit 0
# Only aggregate verdicts reach launchd logs; no response or traceback is emitted.
if python3 "$ROOT/scripts/feature-check.py" --local --summary-only 2>/dev/null; then
    exit 0
else
    printf 'FAIL feature-check (see aggregate results; no raw responses logged)\n'
    exit 1
fi
