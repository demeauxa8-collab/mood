#!/usr/bin/env python3
"""Regression: missing backup prerequisites must never reach service control."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

class BackupPreflightTests(unittest.TestCase):
    def check_missing(self, identity_present):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            sentinel = root / 'service-called'
            stub = root / 'forbidden-service-control'
            stub.write_text('#!/bin/bash\ntouch "' + str(sentinel) + '"\nexit 99\n')
            stub.chmod(0o700)
            script = root / 'backup.sh'
            source = Path(__file__).with_name('backup.sh').read_text()
            script.write_text(source.replace('/bin/launchctl', str(stub)))
            identity = root / 'identity'
            if identity_present:
                identity.touch()
            env = dict(os.environ, MOOD_SERVER_ROOT=work, MOOD_BACKUP_ROOT=work + '/backups',
                       MOOD_BACKUP_IDENTITY=str(identity))
            result = subprocess.run(['bash', str(script)], env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(sentinel.exists())
            self.assertFalse((root / 'maintenance.lock').exists())

    def test_missing_identity(self):
        self.check_missing(False)

    def test_missing_recipient(self):
        self.check_missing(True)

if __name__ == '__main__':
    unittest.main()
