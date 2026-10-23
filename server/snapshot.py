#!/usr/bin/env python3
"""Hash snapshots without printing contents; retain seven completed daily sets."""
import hashlib
import json
import re
import sys
from pathlib import Path


def hashes(root):
    result = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError('Snapshot links forbidden')
        if path.is_file() and path != root / 'manifest.json':
            with path.open('rb') as stream:
                digest = hashlib.sha256()
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
                result[str(path.relative_to(root))] = digest.hexdigest()
    return result



mode, directory = sys.argv[1:]
root = Path(directory)
if mode == 'create':
    (root / 'manifest.json').write_text(json.dumps(hashes(root), sort_keys=True))
elif mode == 'verify':
    if hashes(root) != json.loads((root / 'manifest.json').read_text()):
        raise SystemExit('Snapshot verification failed')
elif mode == 'prune':
    import shutil
    snapshots = sorted(p for p in root.iterdir() if p.is_dir() and re.fullmatch(r'\d{4}-\d{2}-\d{2}', p.name))
    for old in snapshots[:-7]:
        shutil.rmtree(old)
else:
    raise SystemExit('Unknown operation')
