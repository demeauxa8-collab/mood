#!/usr/bin/env python3
"""Boot a snapshot copy on an isolated port and verify the saved message."""
import json
import os
import shutil
import subprocess
import sys
import time
import tempfile
import argparse
import atexit
from pathlib import Path

ROOT = Path.home() / 'mood-server'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('snapshot', type=Path)
parser.add_argument('--identity', type=Path, default=ROOT / 'backup-identity.age-key')
args = parser.parse_args()
SNAPSHOT = args.snapshot
TARGET = ROOT / 'restore-test'
if TARGET.exists():
    raise SystemExit('Restore test directory already exists; preserve or remove it intentionally')
os.umask(0o077)
if SNAPSHOT.suffix == '.age':
    import importlib.util
    spec = importlib.util.spec_from_file_location('encrypted_backup', Path(__file__).with_name('encrypted-backup.py'))
    encrypted = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(encrypted)
    temporary = tempfile.TemporaryDirectory(prefix='.restore-', dir=ROOT)
    atexit.register(temporary.cleanup)
    encrypted.extract(SNAPSHOT, Path(temporary.name), args.identity)
    SNAPSHOT = Path(temporary.name)
subprocess.run([sys.executable, str(ROOT / 'scripts/snapshot.py'), 'verify', str(SNAPSHOT)], check=True)
TARGET.mkdir(mode=0o700)
shutil.copytree(SNAPSHOT / 'data', TARGET / 'data')
config = (SNAPSHOT / 'continuwuity.toml').read_text()
config = config.replace(str(ROOT / 'data'), str(TARGET / 'data')).replace('port = 6167', 'port = 6168')
(TARGET / 'continuwuity.toml').write_text(config)
# Import helpers without exercising registration on the restored server.
sys.path.insert(0, str(ROOT / 'scripts'))
import verify
verify.BASE = 'http://127.0.0.1:6168'
request = verify.request
process = None
try:
    with (TARGET / 'server.log').open('w') as log:
        process = subprocess.Popen([str(ROOT / 'bin/continuwuity'), '-c', str(TARGET / 'continuwuity.toml')],
                                   stdout=log, stderr=log)
        for attempt in range(60):
            if process.poll() is not None:
                raise RuntimeError('Isolated server stopped')
            try:
                if 'versions' in request('GET', '/_matrix/client/versions'):
                    break
            except RuntimeError:
                pass
            time.sleep(1)
        else:
            raise RuntimeError('Restore startup timeout')
        password = json.loads((ROOT / 'test-account.json').read_text())['password']
        login = request('POST', '/_matrix/client/v3/login', {
            'type': 'm.login.password', 'identifier': {'type': 'm.id.user', 'user': 'moodtest1'},
            'password': password, 'device_id': 'MOOD_RESTORE_TEST'})
        token = verify.expect(login, 'access_token')
        proof = json.loads((ROOT / 'test-proof.json').read_text())
        from urllib.parse import quote
        event = request('GET', '/_matrix/client/v3/rooms/' + quote(proof['room_id'], safe='') +
                        '/event/' + quote(proof['event_id'], safe=''), token=token)
        if event.get('content', {}).get('body') != proof['marker']:
            raise RuntimeError('Restored message mismatch')
        request('POST', '/_matrix/client/v3/logout', {}, token)
        print('PASS snapshot hashes, isolated startup, restored login and original message')
except Exception as error:
    print('FAIL restore (' + type(error).__name__ + ')', file=sys.stderr)
    sys.exit(1)
finally:
    if process and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
