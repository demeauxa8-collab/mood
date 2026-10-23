#!/bin/bash
set -eu
umask 077
ROOT="$HOME/mood-server"
SOURCE=$(cd "$(dirname "$0")" && pwd)
[ -x "$ROOT/bin/continuwuity" ] || { echo 'Compile and install the binary first.' >&2; exit 1; }
[ -f "$ROOT/.env" ] && [ -f "$ROOT/registration_token" ] || exit 1
mkdir -p "$ROOT/scripts" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/MoodServer"
chmod 700 "$ROOT" "$HOME/Library/Logs/MoodServer"
chmod 600 "$ROOT/.env" "$ROOT/registration_token"
for script in backup.sh healthcheck.sh snapshot.py verify.py restore-test.py encrypted-backup.py monitor.py feature-check.py feature-check-daily.sh backup-recipient.txt; do cp "$SOURCE/$script" "$ROOT/scripts/$script"; done
# Do not replace an existing live configuration.
[ -f "$ROOT/continuwuity.toml" ] || cp "$SOURCE/continuwuity.example.toml" "$ROOT/continuwuity.toml"
chmod 700 "$ROOT/scripts/backup.sh" "$ROOT/scripts/healthcheck.sh" "$ROOT/scripts/feature-check-daily.sh"
for name in server backup healthcheck featurecheck; do
    cp "$SOURCE/app.mood.$name.plist" "$HOME/Library/LaunchAgents/"
    /usr/bin/plutil -lint "$HOME/Library/LaunchAgents/app.mood.$name.plist"
    if ! /bin/launchctl print "gui/$(id -u)/app.mood.$name" >/dev/null 2>&1; then
        /bin/launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/app.mood.$name.plist"
    fi
done
