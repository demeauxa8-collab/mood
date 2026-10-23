#!/usr/bin/env python3
"""Bounded Mood log rotation and local operational alerts; never restart services."""
import datetime
import os
import shutil
import subprocess
import time
from pathlib import Path

os.umask(0o077)
ROOT = Path(os.environ.get('MOOD_SERVER_ROOT', str(Path.home() / 'mood-server')))
LOGS = Path.home() / 'Library/Logs/MoodServer'
LIMIT = 10 * 1024 * 1024
PUBLIC = 'https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443/_matrix/client/versions'

def probe(url):
    return subprocess.run(['/usr/bin/curl', '-fsS', '--max-time', '15', url],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

def rotate(path):
    # Copy/truncate preserves the inode held open by launchd and the running server.
    for index in range(7, 1, -1):
        previous = Path(str(path) + '.' + str(index - 1))
        if previous.exists():
            os.replace(previous, Path(str(path) + '.' + str(index)))
    with path.open('r+b') as live, Path(str(path) + '.1').open('wb') as archive:
        shutil.copyfileobj(live, archive)
        archive.flush()
        os.fsync(archive.fileno())
        live.seek(0)
        live.truncate()

def main():
    LOGS.mkdir(mode=0o700, parents=True, exist_ok=True)
    (LOGS / 'alerts.log').touch(mode=0o600, exist_ok=True)
    alerts = []
    if shutil.disk_usage(ROOT).free < 10 * 1024**3:
        alerts.append('Disque : moins de 10 Gio disponibles')
    for path in sorted(LOGS.glob('*.log')):
        if path.is_file() and path.stat().st_size >= LIMIT:
            alerts.append('Journal Mood volumineux : rotation effectuée')
            rotate(path)
    marker = ROOT / 'backup.success'
    try:
        archives = list((Path.home() / 'Backups/mood-server').glob('????-??-??.tar.age'))
        recent = bool(archives) and time.time() - float(marker.read_text()) <= 36 * 3600
    except (OSError, ValueError):
        recent = False
    if not recent:
        alerts.append('Sauvegarde chiffrée absente ou âgée de plus de 36 heures')
    if not (ROOT / 'maintenance.lock').exists():
        if not probe('http://127.0.0.1:6167/_matrix/client/versions'):
            alerts.append('Serveur Mood local indisponible')
        if not probe(PUBLIC):
            alerts.append('Adresse publique Mood 8443 indisponible')
    stamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
    for alert in alerts:
        with (LOGS / 'alerts.log').open('a') as log:
            log.write(stamp + ' ' + alert + '\n')
    if alerts:
        try:
            result = subprocess.run(['/usr/bin/osascript', '-e',
                'display notification "Consultez alerts.log dans les journaux MoodServer." with title "Alerte Mood"'],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
            print('notification ' + ('requested' if result.returncode == 0 else 'unavailable'))
        except (OSError, subprocess.TimeoutExpired):
            print('notification unavailable')
    print(stamp + (' health FAIL alerts=' + str(len(alerts)) if alerts else ' health PASS'))

if __name__ == '__main__':
    main()
