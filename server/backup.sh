#!/bin/bash
set -eu
umask 077
ROOT="${MOOD_SERVER_ROOT:-$HOME/mood-server}"
DEST="${MOOD_BACKUP_ROOT:-$HOME/Backups/mood-server}"
DOMAIN="gui/$(id -u)"
PLIST="$HOME/Library/LaunchAgents/app.mood.server.plist"
# Fail before interrupting service if recovery verification is unavailable.
[ -r "${MOOD_BACKUP_IDENTITY:-$ROOT/backup-identity.age-key}" ] || { echo 'FAIL backup identity unavailable' >&2; exit 1; }
[ -r "$ROOT/scripts/backup-recipient.txt" ] || { echo 'FAIL backup recipient unavailable' >&2; exit 1; }
[ -x /opt/homebrew/bin/age ]
mkdir "$ROOT/maintenance.lock" || exit 1
stopped=0
cleanup() {
    if [ "$stopped" -eq 1 ]; then /bin/launchctl bootstrap "$DOMAIN" "$PLIST"; fi
    rmdir "$ROOT/maintenance.lock"
}
trap cleanup EXIT
# Unload KeepAlive before taking a cold, consistent RocksDB + media copy.
/bin/launchctl bootout "$DOMAIN/app.mood.server"
stopped=1
for attempt in {1..60}; do
    if ! /usr/sbin/lsof -t "$ROOT/data/LOCK" >/dev/null 2>&1 && ! /usr/bin/curl -fsS --max-time 1 http://127.0.0.1:6167/_matrix/client/versions >/dev/null 2>&1; then break; fi
    sleep 1
done
if /usr/sbin/lsof -t "$ROOT/data/LOCK" >/dev/null 2>&1 || /usr/bin/curl -fsS --max-time 1 http://127.0.0.1:6167/_matrix/client/versions >/dev/null 2>&1; then exit 1; fi
mkdir -p "$DEST"
tmp=$(mktemp -d "$DEST/.snapshot.XXXXXX")
/usr/bin/ditto "$ROOT/data" "$tmp/data"
/usr/bin/ditto "$ROOT/continuwuity.toml" "$tmp/continuwuity.toml"
# Secrets belong in an independently protected recovery set, never in logs.
/usr/bin/ditto "$ROOT/registration_token" "$tmp/registration_token"
/usr/bin/ditto "$ROOT/.env" "$tmp/.env"
python3 "$ROOT/scripts/snapshot.py" create "$tmp"
python3 "$ROOT/scripts/snapshot.py" verify "$tmp"
# Resume immediately after the cold copy; encryption does not need downtime.
/bin/launchctl bootstrap "$DOMAIN" "$PLIST"
stopped=0
python3 "$ROOT/scripts/encrypted-backup.py" encrypt "$tmp" "$DEST/$(date +%F).tar.age"
python3 "$ROOT/scripts/encrypted-backup.py" prune "$DEST"
date +%s > "$ROOT/backup.success.tmp"
mv "$ROOT/backup.success.tmp" "$ROOT/backup.success"
printf '%s backup encrypted and verified\n' "$(date -u +%FT%TZ)"
