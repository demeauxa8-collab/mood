#!/usr/bin/env python3
"""Stream tar through age, verify privately, publish atomically, then remove plaintext."""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

AGE = '/opt/homebrew/bin/age'
SCRIPTS = Path(__file__).resolve().parent

def verify(directory):
    subprocess.run([sys.executable, str(SCRIPTS / 'snapshot.py'), 'verify', str(directory)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def extract(archive, destination, identity):
    # Authenticate the complete age stream before processing its tar members.
    with tempfile.TemporaryFile(dir=destination) as clear:
        subprocess.run([AGE, '-d', '-i', str(identity), str(archive)], stdout=clear,
                       stderr=subprocess.DEVNULL, check=True)
        clear.seek(0)
        with tarfile.open(fileobj=clear, mode='r:') as tar:
            members = tar.getmembers()
            for member in members:
                path = Path(member.name)
                if path.is_absolute() or '..' in path.parts or not (member.isdir() or member.isfile()):
                    raise ValueError('Unsafe archive member')
            tar.extractall(destination, members=members)
    verify(destination)

def encrypt(source, target, recipient, identity):
    verify(source)
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.TemporaryDirectory(prefix='.encrypt-', dir=target.parent) as work:
        pending = Path(work) / 'archive.age'
        with pending.open('xb') as output:
            age = subprocess.Popen([AGE, '-R', str(recipient)], stdin=subprocess.PIPE,
                                   stdout=output, stderr=subprocess.DEVNULL)
            try:
                with tarfile.open(fileobj=age.stdin, mode='w|', dereference=False) as tar:
                    for item in sorted(source.iterdir()):
                        tar.add(item, arcname=item.name)
                age.stdin.close()
                if age.wait() != 0:
                    raise RuntimeError('Encryption failed')
            finally:
                if age.poll() is None:
                    age.kill()
                    age.wait()
            output.flush()
            os.fsync(output.fileno())
        checked = Path(work) / 'checked'
        checked.mkdir(mode=0o700)
        extract(pending, checked, identity)
        if (source / 'manifest.json').read_bytes() != (checked / 'manifest.json').read_bytes():
            raise ValueError('Manifest mismatch')
        os.replace(pending, target)
        # Persist the published name before deleting the only plaintext snapshot.
        fd = os.open(target.parent, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
        shutil.rmtree(source)

def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['encrypt', 'extract', 'prune'])
    parser.add_argument('source', type=Path)
    parser.add_argument('target', nargs='?', type=Path)
    parser.add_argument('--identity', type=Path, default=Path(os.environ.get('MOOD_BACKUP_IDENTITY', str(Path.home() / 'mood-server/backup-identity.age-key'))))
    parser.add_argument('--recipient', type=Path, default=SCRIPTS / 'backup-recipient.txt')
    args = parser.parse_args()
    try:
        if args.mode == 'encrypt':
            encrypt(args.source, args.target, args.recipient, args.identity)
        elif args.mode == 'extract':
            args.target.mkdir(mode=0o700, parents=True, exist_ok=False)
            extract(args.source, args.target, args.identity)
        else:
            archives = sorted(p for p in args.source.iterdir() if p.is_file() and re.fullmatch(r'\d{4}-\d{2}-\d{2}\.tar\.age', p.name))
            for old in archives[:-7]:
                old.unlink()
        print('PASS encrypted backup ' + args.mode)
    except Exception as error:
        print('FAIL encrypted backup (' + type(error).__name__ + ')', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
