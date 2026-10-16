#!/usr/bin/env python3
"""Exercise Matrix using curl; credentials stay in memory and protected local files."""
import json
import secrets
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import quote

ROOT = Path.home() / 'mood-server'
BASE = sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:6167'


def request(method, path, data=None, token=None):
    config = 'silent\nshow-error\nmax-time = 30\n'
    config += 'url = "' + BASE + path + '"\nrequest = "' + method + '"\n'
    if token:
        config += 'header = "Authorization: Bearer ' + token + '"\n'
    if data is not None:
        body = json.dumps(data)
        config += 'header = "Content-Type: application/json"\ndata = ' + json.dumps(body) + '\n'
    result = subprocess.run(['curl', '--config', '-'], input=config, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError('HTTP transport failed')
    try:
        return json.loads(result.stdout)
    except ValueError:
        raise RuntimeError('Invalid JSON response') from None


def expect(value, key):
    if key not in value:
        raise RuntimeError('Matrix operation failed: ' + str(value.get('errcode', 'unexpected_response')))
    return value[key]


def run():
    versions = request('GET', '/_matrix/client/versions')
    expect(versions, 'versions')
    print('PASS versions')
    credentials = ROOT / 'test-account.json'
    if credentials.exists():
        password = json.loads(credentials.read_text())['password']
    else:
        password = secrets.token_urlsafe(40)
        body = {'username': 'moodtest1', 'password': password, 'device_id': 'MOOD_SERVER_TEST'}
        challenge = request('POST', '/_matrix/client/v3/register', body)
        session = expect(challenge, 'session')
        stages = {stage for flow in challenge.get('flows', []) for stage in flow['stages']}
        if 'm.login.registration_token' not in stages:
            raise RuntimeError('Registration is not gated by token')
        invalid = request('POST', '/_matrix/client/v3/register', {**body, 'auth': {
            'type': 'm.login.registration_token', 'session': session, 'token': 'invalid-test-token'}})
        if 'access_token' in invalid:
            raise RuntimeError('Invalid registration token accepted')
        auth = {'type': 'm.login.registration_token', 'session': session,
                'token': (ROOT / 'registration_token').read_text().strip()}
        registered = request('POST', '/_matrix/client/v3/register', {**body, 'auth': auth})
        if 'access_token' not in registered and 'm.login.dummy' in stages:
            registered = request('POST', '/_matrix/client/v3/register', {**body, 'auth': {
                'type': 'm.login.dummy', 'session': registered.get('session', session)}})
        if expect(registered, 'user_id') != '@moodtest1:mood.local':
            raise RuntimeError('Unexpected test identity')
        credentials.touch(mode=0o600)
        credentials.write_text(json.dumps({'password': password}))
        print('PASS token registration and invalid-token rejection')
    login = request('POST', '/_matrix/client/v3/login', {
        'type': 'm.login.password', 'identifier': {'type': 'm.id.user', 'user': 'moodtest1'},
        'password': password, 'device_id': 'MOOD_SERVER_TEST', 'initial_device_display_name': 'Mood server test'})
    token = expect(login, 'access_token')
    print('PASS password login')
    baseline = request('GET', '/_matrix/client/v3/sync?timeout=0', token=token)
    since = expect(baseline, 'next_batch')
    room = request('POST', '/_matrix/client/v3/createRoom', {'name': 'Mood server verification',
        'preset': 'private_chat'}, token)
    room_id = expect(room, 'room_id')
    marker = 'Mood server verification ' + secrets.token_hex(8)
    sent = request('PUT', '/_matrix/client/v3/rooms/' + quote(room_id, safe='') +
        '/send/m.room.message/' + secrets.token_hex(8), {'msgtype': 'm.text', 'body': marker}, token)
    event_id = expect(sent, 'event_id')
    found = False
    for _ in range(8):
        synced = request('GET', '/_matrix/client/v3/sync?timeout=1000&since=' + quote(since, safe=''), token=token)
        events = synced.get('rooms', {}).get('join', {}).get(room_id, {}).get('timeline', {}).get('events', [])
        if any(e.get('event_id') == event_id and e.get('content', {}).get('body') == marker for e in events):
            found = True
            break
        since = expect(synced, 'next_batch')
    if not found:
        raise RuntimeError('Sent message absent from sync')
    print('PASS create room, send message, read via sync')
    (ROOT / 'test-proof.json').write_text(json.dumps({'room_id': room_id, 'event_id': event_id, 'marker': marker}))
    request('POST', '/_matrix/client/v3/logout', {}, token)


if __name__ == '__main__':
    try:
        run()
    except Exception as error:
        # Never print server responses or exception payloads containing credentials.
        print('FAIL verification (' + type(error).__name__ + ')', file=sys.stderr)
        sys.exit(1)
