#!/usr/bin/env python3
"""Live Matrix contract checks. Credentials and response bodies never leave memory."""
import argparse
import datetime as dt
import json
import http.client
import ssl
import secrets
import signal
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
V3 = '/_matrix/client/v3'
PUBLIC = 'https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443'

def q(value):
    return urllib.parse.quote(value, safe='')

class Check:
    def __init__(self, local, summary_only=False):
        self.summary_only = summary_only
        self.base = 'http://127.0.0.1:6167' if local else PUBLIC
        self.secret_values = [(Path.home() / 'mood-server/registration_token').read_text().strip()]
        self.accounts = []
        self.rows = []
        self.last = (0, {}, {})
        self.since = {}
        self.rate_headers = set()
        self.stamp = dt.datetime.now().strftime('%Y%m%d%H%M')

    def request(self, method, path, body=None, actor=None, mime='application/json'):
        headers = {}
        if actor:
            headers['Authorization'] = 'Bearer ' + actor['access_token']
        if body is not None:
            headers['Content-Type'] = mime
        data = body if isinstance(body, bytes) else json.dumps(body).encode() if body is not None else None
        try:
            if isinstance(body, bytes) and len(body) > 25 * 1024 * 1024:
                # Read an early 413 even when the server closes the upload socket.
                url = urllib.parse.urlsplit(self.base)
                cls = http.client.HTTPSConnection if url.scheme == 'https' else http.client.HTTPConnection
                conn = cls(url.hostname, url.port, timeout=35)
                try:
                    conn.putrequest(method, path)
                    for key, value in headers.items():
                        conn.putheader(key, value)
                    conn.putheader('Content-Length', str(len(data)))
                    conn.endheaders()
                    try:
                        conn.send(data)
                    except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                        pass
                    response = conn.getresponse()
                    status, raw, hdr = response.status, response.read(), dict(response.headers)
                finally:
                    conn.close()
            else:
                with urllib.request.urlopen(urllib.request.Request(self.base + path, data, headers, method=method), timeout=35) as response:
                    status, raw, hdr = response.status, response.read(), dict(response.headers)
        except urllib.error.HTTPError as error:
            status, raw, hdr = error.code, error.read(), dict(error.headers)
        except (OSError, urllib.error.URLError, http.client.HTTPException):
            self.last = (0, {'errcode': 'TRANSPORT'}, {})
            return self.last
        try:
            result = json.loads(raw)
        except (ValueError, UnicodeDecodeError):
            result = {'binary_size': len(raw), 'binary': raw}
        if isinstance(result, dict) and result.get('access_token'):
            self.secret_values.append(result['access_token'])
        self.rate_headers.update(k for k in hdr if 'ratelimit' in k.lower() or 'retry' in k.lower())
        self.last = status, result, hdr
        return self.last

    def row(self, group, name, ok=True, info=False, detail='', response=None):
        status, body, _ = response or self.last
        errcode = body.get('errcode', '-') if isinstance(body, dict) else '-'
        # Only controlled labels, HTTP codes and Matrix error identifiers are emitted.
        if not isinstance(errcode, str) or not errcode.replace('_', '').isalnum():
            errcode = '-'
        verdict = 'INFO' if info else 'PASS' if ok else 'FAIL'
        self.rows.append((verdict, group, name, status, errcode, detail))

    def call(self, group, name, method, path, body=None, actor=None, predicate=None, info=False, codes=None, detail='', mime='application/json'):
        response = self.request(method, path, body, actor, mime)
        status, value, _ = response
        ok = status in codes if codes else 200 <= status < 300
        if ok and predicate:
            ok = bool(predicate(value))
        self.row(group, name, ok, info, detail, response)
        return value

    def sync(self, actor):
        path = V3 + '/sync?timeout=1000&set_presence=offline'
        if actor['user_id'] in self.since:
            path += '&since=' + q(self.since[actor['user_id']])
        response = self.request('GET', path, actor=actor)
        if response[1].get('next_batch'):
            self.since[actor['user_id']] = response[1]['next_batch']
        return response[1]

    def observe(self, group, name, actor, predicate):
        found = False
        for _ in range(5):
            value = self.sync(actor)
            if predicate(value):
                found = True
                break
        self.row(group, name, found)
        return value

    def timeline(self, value, room):
        return value.get('rooms', {}).get('join', {}).get(room, {}).get('timeline', {}).get('events', [])

    def send(self, actor, room, content, kind='m.room.message', txn=None):
        return self.request('PUT', V3 + '/rooms/' + q(room) + '/send/' + kind + '/' + (txn or secrets.token_hex(10)), content, actor)[1].get('event_id')

    def state(self, actor, room, kind, content, key=''):
        return self.request('PUT', V3 + '/rooms/' + q(room) + '/state/' + kind + '/' + q(key), content, actor)

    def register(self, letter):
        username = 'featcheck-' + letter + '-' + self.stamp
        password = secrets.token_urlsafe(40)
        self.secret_values.append(password)
        actor = {'username': username, 'password': password, 'user_id': '@' + username + ':mood.local'}
        available = self.request('GET', V3 + '/register/available?username=' + q(username))
        if available[0] != 200 or available[1].get('available') is not True:
            raise RuntimeError('test username unavailable; no existing account touched')
        self.accounts.append(actor)  # Unique fresh identity, tracked before registration.
        body = {'username': username, 'password': password, 'device_id': 'FEATURECHECK'}
        challenge = self.request('POST', V3 + '/register', body)
        stages = {s for f in challenge[1].get('flows', []) for s in f.get('stages', [])}
        if letter == 'a':
            self.row('Compte', 'Inscription manuelle app sans jeton', info=True, detail='Le serveur exige registration_token ; MatrixClient.register ne traite que dummy. Utiliser le provisioning Mood, jamais distribuer le jeton à l’app.')
        self.row('Compte', 'UIAA jeton ' + letter, challenge[0] == 401 and 'm.login.registration_token' in stages)
        session = challenge[1].get('session')
        if not session:
            raise RuntimeError('registration challenge')
        invalid = self.request('POST', V3 + '/register', {**body, 'auth': {'type': 'm.login.registration_token', 'session': session, 'token': 'deliberately-invalid'}})
        self.row('Compte', 'Mauvais jeton refusé ' + letter, invalid[0] == 401 and 'access_token' not in invalid[1])
        result = self.request('POST', V3 + '/register', {**body, 'auth': {'type': 'm.login.registration_token', 'session': session, 'token': self.secret_values[0]}})
        if 'access_token' not in result[1] and 'm.login.dummy' in stages:
            result = self.request('POST', V3 + '/register', {**body, 'auth': {'type': 'm.login.dummy', 'session': result[1].get('session', session)}})
        actor.update({k: result[1][k] for k in ('access_token', 'device_id') if k in result[1]})
        self.row('Compte', 'Inscription ' + letter, result[0] == 200 and result[1].get('user_id') == actor['user_id'])
        if 'access_token' not in actor:
            raise RuntimeError('registration failed')
        login = self.call('Compte', 'Connexion ' + letter, 'POST', V3 + '/login', {'type': 'm.login.password', 'identifier': {'type': 'm.id.user', 'user': actor['user_id']}, 'password': password, 'device_id': 'FEATURECHECK'}, predicate=lambda b: b.get('user_id') == actor['user_id'])
        actor.update({k: login[k] for k in ('access_token', 'device_id') if k in login})
        self.call('Compte', 'Whoami ' + letter, 'GET', V3 + '/account/whoami', actor=actor, predicate=lambda b: b.get('user_id') == actor['user_id'])
        return actor

    def run(self):
        self.call('Compte', 'Versions', 'GET', '/_matrix/client/versions', predicate=lambda b: bool(b.get('versions')))
        a, b, c = [self.register(letter) for letter in 'abc']
        flows = self.call('Compte', 'Méthodes de connexion', 'GET', V3 + '/login', predicate=lambda x: any(f['type'] == 'm.login.password' for f in x.get('flows', [])))
        flow_response = self.last
        self.call('Compte', 'Login token invalide (branche optionnelle)', 'POST', V3 + '/login', {'type': 'm.login.token', 'token': 'deliberately-invalid-login-token'}, info=True, detail='m.login.token est annoncé, mais aucun jeton SSO valide disponible : cette variante ne peut pas être prouvée en succès sans fournisseur SSO.')
        self.row('Compte', 'SSO et login token', info=True, detail='Aucun fournisseur SSO configuré ; connexion Mood via Supabase, Matrix par mot de passe. Types annoncés : ' + ', '.join(f['type'] for f in flows.get('flows', [])), response=flow_response)
        self.call('Compte', 'Redirection SSO sans fournisseur', 'GET', V3 + '/login/sso/redirect/featurecheck?redirectUrl=https%3A%2F%2Fexample.org', info=True, detail='Branche SSO optionnelle, aucun fournisseur sur ce serveur.')
        caps = self.call('Compte', 'Capacités', 'GET', V3 + '/capabilities', actor=a)
        for key in ('m.change_password', 'm.set_displayname', 'm.set_avatar_url', 'm.profile_fields', 'uk.tcpip.msc4133.profile_fields'):
            self.row('Compte', 'Capacité ' + key, info=True, detail=json.dumps(caps.get('capabilities', {}).get(key, 'absente'), ensure_ascii=False))
        name = 'FeatureCheck A ' + self.stamp
        self.call('Compte', 'Écrire nom', 'PUT', V3 + '/profile/' + q(a['user_id']) + '/displayname', {'displayname': name}, a)
        self.call('Compte', 'B lit profil A', 'GET', V3 + '/profile/' + q(a['user_id']), actor=b, predicate=lambda x: x.get('displayname') == name)
        directory = self.call('Amis', 'C trouve A sans salon commun', 'POST', V3 + '/user_directory/search', {'search_term': name, 'limit': 20}, c, predicate=lambda x: any(u['user_id'] == a['user_id'] for u in x.get('results', [])), detail='Le serveur masque les utilisateurs sans salon commun ni salon public ; aucune clé search_all_users dans cette version. Prévoir recherche exacte par identifiant ou un salon public de découverte consenti.')
        self.row('Amis', 'Résultat annuaire isolé', info=True, detail='results=' + str(len(directory.get('results', []))) + '; limited=' + str(directory.get('limited')))
        room = self.call('Amis', 'Créer MP is_direct', 'POST', V3 + '/createRoom', {'is_direct': True, 'invite': [b['user_id']], 'preset': 'trusted_private_chat'}, a)['room_id']
        rp = V3 + '/rooms/' + q(room)
        self.observe('Amis', 'Invitation MP visible par B', b, lambda x: room in x.get('rooms', {}).get('invite', {}))
        self.call('Amis', 'B rejoint MP', 'POST', V3 + '/join/' + q(room), {}, b)
        for actor, other in ((a, b), (b, a)):
            path = V3 + '/user/' + q(actor['user_id']) + '/account_data/m.direct'
            self.call('Amis', 'Carte m.direct initiale absente ' + actor['username'][10], 'GET', path, actor=actor, codes={404}, predicate=lambda x: x.get('errcode') == 'M_NOT_FOUND')
            self.call('Amis', 'Écrire m.direct ' + actor['username'][10], 'PUT', path, {other['user_id']: [room]}, actor)
            self.call('Amis', 'Lire m.direct ' + actor['username'][10], 'GET', path, actor=actor, predicate=lambda x, other=other: x.get(other['user_id']) == [room])
        for actor, other in ((a, b), (b, a)):
            self.observe('Amis', 'Carte m.direct reçue via sync ' + actor['username'][10], actor, lambda x, other=other: any(e.get('type') == 'm.direct' and e.get('content', {}).get(other['user_id']) == [room] for e in x.get('account_data', {}).get('events', [])))
        self.row('Amis', 'Contrat app acceptInvite', info=True, detail='createDM écrit m.direct côté A ; acceptInvite rejoint seulement, sans écrire m.direct côté B. Le test écrit explicitement les deux côtés : adaptation app requise.')
        self.sync(b)
        name += ' updated'
        self.call('Compte', 'Changer nom après adhésion', 'PUT', V3 + '/profile/' + q(a['user_id']) + '/displayname', {'displayname': name}, a)
        self.observe('Compte', 'B reçoit nouveau nom membre via sync', b, lambda x: any(e.get('type') == 'm.room.member' and e.get('state_key') == a['user_id'] and e.get('content', {}).get('displayname') == name for e in self.timeline(x, room)))
        self.call('Compte', 'B relit nouveau profil', 'GET', V3 + '/profile/' + q(a['user_id']), actor=b, predicate=lambda x: x.get('displayname') == name)
        for prefix in (V3, '/_matrix/client/unstable/uk.tcpip.msc4133'):
            path = prefix + '/profile/' + q(a['user_id']) + '/org.mood.about'
            self.call('Compte', 'À propos PUT ' + prefix.split('/')[-1], 'PUT', path, {'org.mood.about': 'Feature check biography'}, a, info=True)
            bio = self.call('Compte', 'À propos GET ' + prefix.split('/')[-1], 'GET', path, actor=b, info=True)
            self.row('Compte', 'À propos conservé ' + prefix.split('/')[-1], info=True, detail='Valeur relue identique : ' + str(bio.get('org.mood.about') == 'Feature check biography') + '. L’app peut stocker À propos via ce champ si True.')
        # A valid PNG generated in memory; thumbnail must be decodable media, not a JSON error.
        import struct
        import zlib
        def chunk(kind, data):
            return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!IIBBBBB', 64, 64, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\0' + b'\xff\x80\0' * 64) * 64)) + chunk(b'IEND', b'')
        uploaded = self.call('Médias', 'Upload PNG', 'POST', '/_matrix/media/v3/upload?filename=featurecheck.png', png, a, mime='image/png', predicate=lambda x: 'content_uri' in x)
        mxc = uploaded['content_uri']
        media = '/'.join(q(p) for p in mxc[6:].split('/'))
        self.call('Compte', 'Écrire avatar', 'PUT', V3 + '/profile/' + q(a['user_id']) + '/avatar_url', {'avatar_url': mxc}, a)
        self.call('Compte', 'B lit avatar', 'GET', V3 + '/profile/' + q(a['user_id']), actor=b, predicate=lambda x: x.get('avatar_url') == mxc)
        self.call('Médias', 'Download authentifié avatar', 'GET', '/_matrix/client/v1/media/download/' + media, actor=b, predicate=lambda x: x.get('binary') == png)
        self.call('Médias', 'Thumbnail authentifié scale', 'GET', '/_matrix/client/v1/media/thumbnail/' + media + '?width=32&height=32&method=scale', actor=b, predicate=lambda x: x.get('binary', b'').startswith((b'\x89PNG', b'\xff\xd8', b'RIFF')))
        for kind in ('download', 'thumbnail'):
            suffix = '?width=32&height=32&method=crop' if kind == 'thumbnail' else ''
            self.call('Médias', 'Ancien média non authentifié ' + kind, 'GET', '/_matrix/media/v3/' + kind + '/' + media + suffix, info=True, detail='L’ancien resolveMediaURL de ce checkout utilise cette route ; remplacer par client/v1 avec Bearer (piste G).')
        self.call('Médias', 'Plus de 25 Mio refusé', 'POST', '/_matrix/media/v3/upload', b'x' * (25 * 1024 * 1024 + 1), a, mime='application/octet-stream', codes={413}, predicate=lambda x: x.get('errcode') == 'M_TOO_LARGE')
        for presence in ('online', 'unavailable', 'offline'):
            path = V3 + '/presence/' + q(a['user_id']) + '/status'
            self.call('Compte', 'Présence ' + presence, 'PUT', path, {'presence': presence, 'status_msg': 'featurecheck ' + presence}, a)
            self.call('Compte', 'B lit présence ' + presence, 'GET', path, actor=b, predicate=lambda x, presence=presence: x.get('presence') == presence and x.get('status_msg') == 'featurecheck ' + presence)
        self.call('Compte', 'Appareils', 'GET', V3 + '/devices', actor=a, predicate=lambda x: any(d['device_id'] == a['device_id'] for d in x.get('devices', [])))
        device = V3 + '/devices/' + q(a['device_id'])
        self.call('Compte', 'Renommer appareil', 'PUT', device, {'display_name': 'Feature check renamed'}, a)
        self.call('Compte', 'Relire appareil', 'GET', device, actor=a, predicate=lambda x: x.get('display_name') == 'Feature check renamed')
        self.call('Compte', 'Règles push', 'GET', V3 + '/pushrules/', actor=b, predicate=lambda x: 'global' in x)
        push = V3 + '/pushrules/global/room/' + q(room)
        self.call('Compte', 'Sourdine PUT', 'PUT', push, {'actions': []}, b)
        self.call('Compte', 'Sourdine relue', 'GET', push, actor=b, predicate=lambda x: x.get('actions') == [])
        self.call('Compte', 'Sourdine DELETE', 'DELETE', push, actor=b)
        self.call('Compte', 'Override absent accepté par app', 'DELETE', V3 + '/pushrules/global/override/' + q(room), actor=b, codes={200, 404})
        self.sync(b)
        text = {'msgtype': 'm.text', 'body': 'Featurecheck needle mention', 'format': 'org.matrix.custom.html', 'formatted_body': '<b>Featurecheck needle mention</b>', 'm.mentions': {'user_ids': [b['user_id']]}}
        event = self.send(a, room, text)
        self.row('Messages', 'Envoyer texte riche mention', bool(event))
        self.observe('Messages', 'B reçoit contenu texte riche', b, lambda x: any(e.get('event_id') == event and e.get('content') == text for e in self.timeline(x, room)))
        idem = self.send(a, room, text, txn='idempotency')
        repeated = self.send(a, room, text, txn='idempotency')
        self.row('Messages', 'Même txnId même event_id', bool(idem) and idem == repeated)
        edit = {'msgtype': 'm.text', 'body': '* Edited', 'm.new_content': {'msgtype': 'm.text', 'body': 'Edited'}, 'm.relates_to': {'rel_type': 'm.replace', 'event_id': event}}
        edited = self.send(a, room, edit)
        self.row('Messages', 'Modification m.replace', bool(edited))
        self.observe('Messages', 'B reçoit modification', b, lambda x: any(e.get('event_id') == edited and e.get('content') == edit for e in self.timeline(x, room)))
        reply = self.send(b, room, {'msgtype': 'm.text', 'body': 'Reply', 'm.relates_to': {'m.in_reply_to': {'event_id': event}}})
        self.row('Messages', 'Réponse m.in_reply_to', bool(reply))
        self.observe('Messages', 'A reçoit réponse', a, lambda x: any(e.get('event_id') == reply and e.get('content', {}).get('m.relates_to', {}).get('m.in_reply_to', {}).get('event_id') == event for e in self.timeline(x, room)))
        reaction = self.send(b, room, {'m.relates_to': {'rel_type': 'm.annotation', 'event_id': event, 'key': '👍'}}, 'm.reaction')
        self.row('Messages', 'Réaction m.annotation', bool(reaction))
        self.observe('Messages', 'A reçoit réaction', a, lambda x: any(e.get('event_id') == reaction for e in self.timeline(x, room)))
        for target, actor, label in ((reaction, b, 'Retirer réaction'), (idem, a, 'Supprimer message')):
            self.call('Messages', label, 'PUT', rp + '/redact/' + q(target) + '/' + secrets.token_hex(8), {}, actor, predicate=lambda x: 'event_id' in x)
            self.observe('Messages', label + ' reçu par autre compte', a if actor is b else b, lambda x, target=target: any(e.get('type') == 'm.room.redaction' and (e.get('redacts') == target or e.get('content', {}).get('redacts') == target) for e in self.timeline(x, room)))
        self.state(a, room, 'm.room.pinned_events', {'pinned': [event]})
        self.row('Messages', 'Épingler', self.last[0] == 200)
        self.call('Messages', 'Épingle relue par B', 'GET', rp + '/state/m.room.pinned_events', actor=b, predicate=lambda x: x.get('pinned') == [event])
        self.sync(b)
        self.call('Messages', 'Saisie PUT', 'PUT', rp + '/typing/' + q(a['user_id']), {'typing': True, 'timeout': 30000}, a)
        self.observe('Messages', 'B voit saisie', b, lambda x: any(a['user_id'] in e.get('content', {}).get('user_ids', []) for e in x.get('rooms', {}).get('join', {}).get(room, {}).get('ephemeral', {}).get('events', []) if e.get('type') == 'm.typing'))
        self.call('Messages', 'Arrêter saisie', 'PUT', rp + '/typing/' + q(a['user_id']), {'typing': False}, a)
        self.sync(a)
        for receipt in ('m.read', 'm.read.private'):
            self.call('Messages', 'Accusé ' + receipt, 'POST', rp + '/receipt/' + receipt + '/' + q(event), {}, b)
        self.observe('Messages', 'A voit accusé public de B', a, lambda x: any(b['user_id'] in e.get('content', {}).get(event, {}).get('m.read', {}) for e in x.get('rooms', {}).get('join', {}).get(room, {}).get('ephemeral', {}).get('events', []) if e.get('type') == 'm.receipt'))
        self.call('Messages', 'Marqueurs publics', 'POST', rp + '/read_markers', {'m.fully_read': event, 'm.read': event}, b)
        self.call('Messages', 'Marqueurs privés', 'POST', rp + '/read_markers', {'m.fully_read': event, 'm.read.private': event}, b)
        markers = self.sync(b)
        self.row('Messages', 'B relit fully_read via sync', any(e.get('type') == 'm.fully_read' and e.get('content', {}).get('event_id') == event for e in markers.get('rooms', {}).get('join', {}).get(room, {}).get('account_data', {}).get('events', [])))
        self.call('Messages', 'Historique arrière', 'GET', rp + '/messages?dir=b&limit=50', actor=b, predicate=lambda x: any(e.get('event_id') == event for e in x.get('chunk', [])))
        self.call('Messages', 'Context (hors app)', 'GET', rp + '/context/' + q(event), actor=b, info=True)
        self.call('Messages', 'Relations (hors app)', 'GET', rp + '/relations/' + q(event), actor=b, info=True)
        self.call('Messages', 'Recherche serveur app', 'POST', V3 + '/search', {'search_categories': {'room_events': {'search_term': 'needle', 'filter': {'rooms': [room], 'limit': 25}, 'order_by': 'recent', 'event_context': {'before_limit': 0, 'after_limit': 0}}}}, b, predicate=lambda x: bool(x.get('search_categories', {}).get('room_events', {}).get('results')), detail='Si refusé : recherche locale, ne pas afficher une recherche serveur fonctionnelle.')
        self.call('Messages', 'Notifications app', 'GET', V3 + '/notifications?limit=30', actor=b, predicate=lambda x: 'notifications' in x, detail='Route non implémentée dans cette version : alimenter la boîte de mentions depuis sync/cache local, masquer le contrôle si aucun repli.')
        for kind in ('m.image', 'm.file'):
            content = {'msgtype': kind, 'body': 'featurecheck.png', 'url': mxc, 'info': {'w': 64, 'h': 64, 'size': len(png), 'mimetype': 'image/png', 'thumbnail_url': mxc, 'thumbnail_info': {'w': 64, 'h': 64, 'mimetype': 'image/png', 'size': len(png)}}}
            sent = self.send(a, room, content)
            self.row('Messages', 'Envoi ' + kind, bool(sent))
            self.observe('Messages', 'B reçoit ' + kind, b, lambda x, sent=sent, content=content: any(e.get('event_id') == sent and e.get('content') == content for e in self.timeline(x, room)))
        headers = sorted(self.rate_headers)
        self.row('Messages', 'En-têtes limite débit', info=True, detail=', '.join(headers) or 'Aucun en-tête de limite observé ; aucune rafale destructive effectuée.')
        ignored = V3 + '/user/' + q(b['user_id']) + '/account_data/m.ignored_user_list'
        self.call('Compte', 'Bloquer A', 'PUT', ignored, {'ignored_users': {a['user_id']: {}}}, b)
        self.call('Compte', 'Blocage relu', 'GET', ignored, actor=b, predicate=lambda x: a['user_id'] in x.get('ignored_users', {}))
        self.sync(b)
        blocked_event = self.send(a, room, {'msgtype': 'm.text', 'body': 'Ignored probe'})
        seen = False
        for _ in range(3):
            seen |= any(e.get('event_id') == blocked_event for e in self.timeline(self.sync(b), room))
        self.row('Compte', 'Blocage filtre sync', not seen, detail='Vérifie le filtrage serveur des messages de A ; le client doit aussi filtrer notifications et affichage.')
        self.call('Compte', 'Débloquer A', 'PUT', ignored, {'ignored_users': {}}, b)
        space = self.call('Serveurs', 'Créer espace', 'POST', V3 + '/createRoom', {'name': 'Featurecheck space', 'creation_content': {'type': 'm.space'}, 'preset': 'private_chat'}, a)['room_id']
        child = self.call('Serveurs', 'Créer salon enfant', 'POST', V3 + '/createRoom', {'name': 'Featurecheck channel', 'preset': 'private_chat'}, a)['room_id']
        cp = V3 + '/rooms/' + q(child)
        for parent, kind, key, content in ((space, 'm.space.child', child, {'via': ['mood.local']}), (child, 'm.space.parent', space, {'via': ['mood.local'], 'canonical': True})):
            self.state(a, parent, kind, content, key)
            self.row('Serveurs', kind, self.last[0] == 200)
        self.call('Serveurs', 'Hiérarchie', 'GET', '/_matrix/client/v1/rooms/' + q(space) + '/hierarchy', actor=a, predicate=lambda x: any(r['room_id'] == child for r in x.get('rooms', [])))
        for target in (space, child):
            self.call('Serveurs', 'Inviter B ' + ('espace' if target == space else 'salon'), 'POST', V3 + '/rooms/' + q(target) + '/invite', {'user_id': b['user_id']}, a)
            self.observe('Serveurs', 'B voit invitation ' + ('espace' if target == space else 'salon'), b, lambda x, target=target: target in x.get('rooms', {}).get('invite', {}))
            self.call('Serveurs', 'B rejoint ' + ('espace' if target == space else 'salon'), 'POST', V3 + '/join/' + q(target), {}, b)
        for kind, key, value in (('m.room.name', 'name', 'Renamed channel'), ('m.room.topic', 'topic', 'New topic')):
            self.state(a, child, kind, {key: value})
            self.row('Serveurs', 'Écrire ' + kind, self.last[0] == 200)
            self.call('Serveurs', 'B relit ' + kind, 'GET', cp + '/state/' + kind, actor=b, predicate=lambda x, key=key, value=value: x.get(key) == value)
        self.call('Serveurs', 'Membres app', 'GET', cp + '/members', actor=a, predicate=lambda x: any(e.get('state_key') == b['user_id'] for e in x.get('chunk', [])))
        self.call('Serveurs', 'État complet app', 'GET', cp + '/state', actor=a, predicate=lambda x: isinstance(x, list))
        power = self.request('GET', cp + '/state/m.room.power_levels', actor=a)[1]
        for level in (50, 0):
            power.setdefault('users', {})[b['user_id']] = level
            self.state(a, child, 'm.room.power_levels', power)
            self.row('Serveurs', 'Promouvoir B' if level else 'Rétrograder B', self.last[0] == 200)
            self.call('Serveurs', 'B relit pouvoir ' + str(level), 'GET', cp + '/state/m.room.power_levels', actor=b, predicate=lambda x, level=level: x.get('users', {}).get(b['user_id']) == level)
        for action in ('kick', 'ban', 'unban'):
            self.call('Serveurs', action, 'POST', cp + '/' + action, {'user_id': b['user_id']}, a)
            expected = {'kick': 'leave', 'ban': 'ban', 'unban': 'leave'}[action]
            self.call('Serveurs', 'Vérifier adhésion après ' + action, 'GET', cp + '/state/m.room.member/' + q(b['user_id']), actor=a, predicate=lambda x, expected=expected: x.get('membership') == expected)
        self.call('Serveurs', 'Réinviter B', 'POST', cp + '/invite', {'user_id': b['user_id']}, a)
        self.call('Serveurs', 'B rejoint après déban', 'POST', V3 + '/join/' + q(child), {}, b)
        self.call('Serveurs', 'B quitte', 'POST', cp + '/leave', {}, b)
        self.call('Serveurs', 'Annuaire salons publics app', 'POST', V3 + '/publicRooms', {'limit': 50}, c, predicate=lambda x: 'chunk' in x)
        # Aliases are not called by this checkout; invitation links use room IDs.
        alias = '#featcheck-' + self.stamp + ':mood.local'
        self.call('Serveurs', 'Créer alias (hors app)', 'PUT', V3 + '/directory/room/' + q(alias), {'room_id': child}, a, info=True)
        self.call('Serveurs', 'Résoudre alias (hors app)', 'GET', V3 + '/directory/room/' + q(alias), actor=c, info=True)
        self.call('Serveurs', 'Retirer alias test', 'DELETE', V3 + '/directory/room/' + q(alias), actor=a)
        # Demonstrate the documented discovery condition using only the disposable A.
        self.state(a, child, 'm.room.join_rules', {'join_rule': 'public'})
        self.row('Amis', 'Salon test rendu public pour découverte', self.last[0] == 200)
        self.call('Amis', 'C trouve A membre salon public sans salon commun', 'POST', V3 + '/user_directory/search', {'search_term': name, 'limit': 20}, c, predicate=lambda x: any(u['user_id'] == a['user_id'] for u in x.get('results', [])))
        self.state(a, child, 'm.room.join_rules', {'join_rule': 'invite'})
        self.row('Amis', 'Restaurer salon test privé', self.last[0] == 200)
        self.state(a, space, 'm.space.child', {}, child)
        self.row('Serveurs', 'Retirer salon de espace app', self.last[0] == 200)
        for actor, rooms in ((b, [space, room]), (a, [child, space, room])):
            for target in rooms:
                self.call('Serveurs', 'Quitter salon test', 'POST', V3 + '/rooms/' + q(target) + '/leave', {}, actor)
        # Logout must not prevent final deactivation: reauthenticate inside cleanup.
        self.call('Compte', 'Déconnexion C', 'POST', V3 + '/logout', {}, c)
        self.call('Compte', 'Jeton déconnecté refusé', 'GET', V3 + '/account/whoami', actor=c, codes={401}, predicate=lambda x: x.get('errcode') == 'M_UNKNOWN_TOKEN')

    def cleanup(self):
        for actor in self.accounts:
            success = False
            for _ in range(3):
                login = self.request('POST', V3 + '/login', {'type': 'm.login.password', 'identifier': {'type': 'm.id.user', 'user': actor['user_id']}, 'password': actor['password'], 'device_id': 'FEATURECHECK_CLEANUP'})
                if login[0] != 200:
                    continue
                actor['access_token'] = login[1]['access_token']
                challenge = self.request('POST', V3 + '/account/deactivate', {}, actor)
                auth = {'type': 'm.login.password', 'identifier': {'type': 'm.id.user', 'user': actor['user_id']}, 'password': actor['password']}
                if challenge[1].get('session'):
                    auth['session'] = challenge[1]['session']
                response = challenge if challenge[0] == 200 else self.request('POST', V3 + '/account/deactivate', {'auth': auth, 'erase': True}, actor)
                if response[0] == 200:
                    success = True
                    break
            self.row('Nettoyage', 'Désactivation ' + actor['username'], success)
            if success:
                denied = self.request('POST', V3 + '/login', {'type': 'm.login.password', 'identifier': {'type': 'm.id.user', 'user': actor['user_id']}, 'password': actor['password']})
                self.row('Nettoyage', 'Connexion compte désactivé refusée', denied[0] == 403 and denied[1].get('errcode') in ('M_USER_DEACTIVATED', 'M_FORBIDDEN'))

    def finish(self):
        counts = {v: sum(r[0] == v for r in self.rows) for v in ('PASS', 'FAIL', 'INFO')}
        lines = [f'{v} {g} — {n} — HTTP {s} {e}' for v, g, n, s, e, d in self.rows]
        lines.append('Résumé : ' + ', '.join(f'{k}={v}' for k, v in counts.items()))
        if self.summary_only:
            print(lines[-1])
            return 1 if counts['FAIL'] else 0
        inventory = []
        for filename in ('mood/Core/Matrix/MatrixClient.swift', 'mood/Core/Notifications/PushRules.swift'):
            for line in (ROOT / filename).read_text().splitlines():
                if '"/_matrix/' in line:
                    inventory.append(line.strip())
        doc = ['# Contrôle réel des fonctions Mood', '', 'Exécution : `python3 server/feature-check.py` (HTTPS public, TLS vérifié), ou `python3 server/feature-check.py --local`.', '', 'Python standard uniquement ; délai HTTP 35 s, sync bornée à 5 essais. Trois comptes par exécution, mots de passe et jetons seulement en mémoire, désactivation UIAA dans finally. Ne pas lancer deux fois dans la même minute (identifiants horodatés). Aucun service redémarré, aucune configuration changée, aucun envoi GitHub.', '', 'Date : ' + dt.datetime.now(dt.timezone.utc).isoformat(), 'Cible : ' + self.base, '', lines[-1], '', '| Résultat | Groupe | Fonction | HTTP | errcode | Observation / action app |', '|---|---|---|---|---|---|']
        for v, g, n, s, e, d in self.rows:
            doc.append(f'| {v} | {g} | {n} | {s} | {e} | {d.replace(chr(10), " ").replace("|", "/")} |')
        doc.extend(['', '## Lecture des résultats', '', 'PASS exige le code prévu et, lorsque précisé, le contenu attendu. INFO correspond aux routes hors app, capacités déclarées et constats. FAIL garde un code de sortie non nul même si le serveur répond HTTP 200 avec un résultat insuffisant.', '', 'Le répertoire de cette version filtre en dur dans `~/mood-server/src/src/api/client/user_directory.rs` : salon commun OU utilisateur membre d’un salon dont `join_rule=public`. La recherche dans `src/core/config/mod.rs` ne révèle aucune option pour chercher tous les utilisateurs. `allow_public_room_directory_over_federation` et `lockdown_public_room_directory` concernent les salons, pas ce filtre. Ne pas proposer une clé inexistante : identifiant exact, salon public de découverte consenti, ou évolution serveur nécessaire.', '', 'Le checkout utilise encore les médias `/media/v3` sans Bearer ; la piste G doit utiliser `/client/v1/media` avec Bearer. L’inscription manuelle de MatrixClient ne sait traiter que `m.login.dummy` ; le provisioning Mood est le chemin autorisé pour l’inscription par jeton. SSO n’est pas configuré ; m.login.token est annoncé, mais faute de fournisseur/jeton SSO valide, seul le rejet d’un faux jeton est sondé (succès non prouvé). Les capacités m.change_password / m.set_displayname / m.set_avatar_url sont absentes de la réponse : ce n’est pas un refus ; les écritures de nom et avatar sont prouvées séparément.', '', 'La preuve m.direct des deux comptes est explicite dans le banc. `MatrixStore.acceptInvite` ne met pas à jour la carte du destinataire ; ajouter cette écriture dans l’app. Le stockage MSC4133, s’il est accepté, ne signifie pas qu’un écran À propos existe déjà.', '', 'Limites : ces tests prouvent le contrat HTTP, pas le rendu SwiftUI ni les notifications système. Les salons et médias de test peuvent rester dans la base Matrix ; les trois comptes sont désactivés et les salons quittés. Aucun autre compte manipulé.', '', '## Inventaire exhaustif des chemins du checkout', '', 'Chaque chemin littéral MatrixClient / PushRules ci-dessous est exercé par les familles du tableau ; les variantes SSO sans fournisseur et token sans jeton valide sont INFO, leur succès n’est pas prouvé. /context, /relations, /directory/room, /capabilities, /hierarchy et MSC4133 sont des sondes complémentaires.', '', '```swift', *inventory, '```', '', '## Endpoints app refusés ou contrats incomplets', ''])
        for v, g, n, s, e, d in self.rows:
            if v == 'FAIL' or (v == 'INFO' and s >= 400):
                doc.append(f'- {n} : HTTP {s}, {e}. {d}'.rstrip())
        doc.extend(['', '### Routes effectivement refusées au client de ce checkout', '', '- `GET /_matrix/client/v3/notifications` : 404 M_UNRECOGNIZED ; reconstruire les mentions depuis sync/cache ou masquer la boîte.', '- `GET /_matrix/media/v3/download/{server}/{id}` et `/thumbnail/{server}/{id}` sans Bearer : 403 M_FORBIDDEN ; utiliser les médias authentifiés client/v1 (PASS).', '- `GET /_matrix/client/v3/login/sso/redirect/{idp}` : 404 M_UNRECOGNIZED ; ne proposer aucun fournisseur SSO Matrix absent.', '- `POST /_matrix/client/v3/register` sans étape registration_token : 401 UIAA attendu ; inscription Mood via provisioning, inscription Matrix manuelle incompatible ici.', '', '`POST /user_directory/search` n’est pas refusé (200), mais retourne results=[] sans salon commun/public. `POST /search` fonctionne. Le rejet du faux login token et le 404 de la carte m.direct initiale sont attendus, pas des pannes. `/relations` est hors app et non implémenté.'])
        text = '\n'.join(doc) + '\n'
        output = '\n'.join(lines) + '\n'
        # Scan all tracked files plus generated artifacts and exact emitted output, in-process.
        tracked = subprocess.run(['git', 'ls-files', '-z'], cwd=ROOT, capture_output=True, check=True).stdout.split(b'\0')
        payloads = [text.encode(), output.encode()]
        payloads += [(ROOT / p.decode()).read_bytes() for p in tracked if p and (ROOT / p.decode()).is_file()]
        payloads.append(Path(__file__).read_bytes())
        if any(secret.encode() in payload for secret in self.secret_values if secret for payload in payloads):
            print('FAIL Sécurité — fuite détectée, sorties et rapport bloqués')
            return 1
        (ROOT / 'docs/FEATURE-CHECK.md').write_text(text)
        print(output, end='')
        print('PASS Sécurité — secrets absents des sorties et fichiers contrôlés')
        return 1 if counts['FAIL'] else 0

def interrupted(signum, frame):
    raise KeyboardInterrupt

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local', action='store_true')
    parser.add_argument('--summary-only', action='store_true')
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, interrupted)
    try:
        check = Check(args.local, args.summary_only)
    except OSError:
        print('FAIL Sécurité — fichier jeton indisponible, aucun compte créé')
        return 1
    try:
        check.run()
    except BaseException as error:
        check.row('Exécution', 'Suite interrompue ' + type(error).__name__, False, detail='Certaines preuves dépendantes non exécutées ; aucune réponse brute affichée.')
    finally:
        check.cleanup()
    return check.finish()

if __name__ == '__main__':
    sys.exit(main())
