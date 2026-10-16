#!/usr/bin/env python3
"""Replays the app's DM flow on the live Mood homeserver with two throwaway accounts.

A creates a DM like MatrixClient.createRoom(isDirect:inviteUserIds:preset:), sends a message,
B syncs with the app's exact filter, sees the invite, joins and must receive the message.
Secrets (registration token, passwords, access tokens) stay in memory; only statuses print.
"""
import json
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE = sys.argv[1] if len(sys.argv) > 1 else 'https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443'
V3 = '/_matrix/client/v3'
APP_FILTER = '{"room":{"timeline":{"limit":30,"unread_thread_notifications":true},"state":{"lazy_load_members":true}},"presence":{"types":["m.presence"]}}'
TOKEN = (Path.home() / 'mood-server/registration_token').read_text().strip()


def call(method, path, body=None, token=None):
    headers = {'Content-Type': 'application/json'} if body is not None else {}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(urllib.request.Request(BASE + path, data, headers, method=method), timeout=40) as r:
            return r.status, json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, {'raw': raw[:200].decode('utf8', 'replace')}


def register(localpart):
    password = secrets.token_urlsafe(24)
    body = {'username': localpart, 'password': password, 'inhibit_login': False}
    status, res = call('POST', V3 + '/register', body)
    session = res.get('session')
    body['auth'] = {'type': 'm.login.registration_token', 'token': TOKEN, 'session': session}
    status, res = call('POST', V3 + '/register', body)
    assert status == 200, ('register', status, res.get('errcode'))
    return {'user_id': res['user_id'], 'token': res['access_token'], 'password': password}


def sync(actor, since=None):
    query = {'timeout': '0', 'filter': APP_FILTER}
    if since:
        query['since'] = since
    return call('GET', V3 + '/sync?' + urllib.parse.urlencode(query), token=actor['token'])


def say(label, ok, detail=''):
    print(('PASS' if ok else 'FAIL'), '-', label, ('- ' + detail) if detail else '')


def main():
    stamp = time.strftime('%H%M%S')
    a = register(f'dmcheck-a-{stamp}')
    b = register(f'dmcheck-b-{stamp}')
    try:
        status, first_b = sync(b)
        say('B initial sync with app filter', status == 200, f'HTTP {status} {first_b.get("errcode", "")}')
        since_b = first_b.get('next_batch')

        status, res = call('POST', V3 + '/createRoom',
                           {'is_direct': True, 'invite': [b['user_id']], 'preset': 'trusted_private_chat'}, a['token'])
        room = res.get('room_id')
        say('A creates DM (app body)', status == 200, f'HTTP {status} {res.get("errcode", "")}')

        status, res = call('PUT', V3 + f'/rooms/{urllib.parse.quote(room)}/send/m.room.message/t{stamp}',
                           {'msgtype': 'm.text', 'body': 'salut depuis A'}, a['token'])
        say('A sends a message', status == 200, f'HTTP {status} {res.get("errcode", "")}')

        status, inc = sync(b, since_b)
        invite = inc.get('rooms', {}).get('invite', {}).get(room)
        say('B incremental sync sees the invite', status == 200 and invite is not None, f'HTTP {status}')
        if invite:
            mine = [e for e in invite.get('invite_state', {}).get('events', [])
                    if e.get('type') == 'm.room.member' and e.get('state_key') == b['user_id']]
            say('invite carries is_direct for B', bool(mine and mine[0].get('content', {}).get('is_direct')),
                json.dumps(mine[0].get('content', {})) if mine else 'no member event')
            names = [e.get('type') for e in invite.get('invite_state', {}).get('events', [])]
            print('INFO - invite_state types:', names)
        since_b = inc.get('next_batch', since_b)

        status, res = call('POST', V3 + f'/join/{urllib.parse.quote(room)}', {}, b['token'])
        say('B joins', status == 200, f'HTTP {status} {res.get("errcode", "")}')

        status, inc = sync(b, since_b)
        joined = inc.get('rooms', {}).get('join', {}).get(room, {})
        bodies = [e.get('content', {}).get('body') for e in joined.get('timeline', {}).get('events', [])
                  if e.get('type') == 'm.room.message']
        timeline = joined.get('timeline', {})
        if 'salut depuis A' in bodies:
            say('B receives A\'s message after joining', True, f'HTTP {status}')
        else:
            # Continuwuity sends a limited timeline holding only the join: the app back-fills it from
            # prev_batch (MatrixStore fillGap). Check that this back-fill finds the message.
            prev = timeline.get('prev_batch')
            query = urllib.parse.urlencode({'dir': 'b', 'limit': '30', 'from': prev or ''})
            status2, page = call('GET', V3 + f'/rooms/{urllib.parse.quote(room)}/messages?{query}', token=b['token'])
            found = any(e.get('content', {}).get('body') == 'salut depuis A' for e in page.get('chunk', []))
            print('INFO - join came as limited=%s with %s; app back-fills from prev_batch' % (timeline.get('limited'), [e.get('type') for e in timeline.get('events', [])]))
            say('B gets A\'s message by back-filling like the app', status2 == 200 and found, f'HTTP {status2}')
        since_b = inc.get('next_batch', since_b)

        status, res = call('PUT', V3 + f'/rooms/{urllib.parse.quote(room)}/send/m.room.message/u{stamp}',
                           {'msgtype': 'm.text', 'body': 'deuxième'}, a['token'])
        status, inc = sync(b, since_b)
        joined = inc.get('rooms', {}).get('join', {}).get(room, {})
        bodies = [e.get('content', {}).get('body') for e in joined.get('timeline', {}).get('events', [])]
        say('B receives a later message live', 'deuxième' in bodies, f'HTTP {status}')

        status, full = sync(b)
        joined = full.get('rooms', {}).get('join', {}).get(room, {})
        bodies = [e.get('content', {}).get('body') for e in joined.get('timeline', {}).get('events', [])]
        say('B fresh initial sync shows both messages', {'salut depuis A', 'deuxième'} <= set(bodies), f'HTTP {status}')
    finally:
        for actor in (a, b):
            auth = {'type': 'm.login.password', 'identifier': {'type': 'm.id.user', 'user': actor['user_id']},
                    'password': actor['password']}
            status, res = call('POST', V3 + '/account/deactivate', {}, actor['token'])
            status, res = call('POST', V3 + '/account/deactivate', {'auth': dict(auth, session=res.get('session'))}, actor['token'])
            print('INFO - deactivated', actor['user_id'].split(':')[0], f'HTTP {status}')


if __name__ == '__main__':
    main()
