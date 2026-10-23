#!/usr/bin/env python3
"""N2 disposable-account media contracts; never print credentials or response bodies."""
import argparse
import datetime as dt
import importlib.util
import json
from pathlib import Path
import secrets
import signal
import subprocess
import tempfile
import sys

spec = importlib.util.spec_from_file_location('feature_check', Path(__file__).with_name('feature-check.py'))
feature = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feature)
V3, q = feature.V3, feature.q

class MediaCheck(feature.Check):
    def register(self, letter):
        username = 'n2check-' + secrets.token_hex(6) + '-' + letter
        password = secrets.token_urlsafe(40)
        self.secret_values.append(password)
        actor = {'username': username, 'password': password, 'user_id': '@' + username + ':mood.local'}
        available = self.request('GET', V3 + '/register/available?username=' + q(username))
        if available[0] != 200 or available[1].get('available') is not True:
            raise RuntimeError('identity unavailable')
        body = {'username': username, 'password': password, 'device_id': 'N2CHECK'}
        challenge = self.request('POST', V3 + '/register', body)
        session = challenge[1].get('session')
        if not session:
            raise RuntimeError('registration challenge unavailable')
        self.accounts.append(actor)
        result = self.request('POST', V3 + '/register', {**body, 'auth': {'type': 'm.login.registration_token', 'session': session, 'token': self.secret_values[0]}})
        if 'access_token' not in result[1]:
            result = self.request('POST', V3 + '/register', {**body, 'auth': {'type': 'm.login.dummy', 'session': result[1].get('session', session)}})
        actor.update({k: result[1][k] for k in ('access_token', 'device_id') if k in result[1]})
        self.row('Comptes', 'Créer compte jetable ' + letter, result[0] == 200 and result[1].get('user_id') == actor['user_id'])
        if 'access_token' not in actor:
            raise RuntimeError('registration failed')
        return actor

    def run(self):
        a, b = self.register('a'), self.register('b')
        room = self.call('Médias', 'Créer salon isolé', 'POST', V3 + '/createRoom', {'preset': 'private_chat', 'invite': [b['user_id']]}, a).get('room_id')
        if not room:
            raise RuntimeError('room unavailable')
        self.call('Médias', 'Rejoindre salon isolé', 'POST', V3 + '/join/' + q(room), {}, b)
        # A real two-frame GIF. All binary bytes remain inside the process.
        gif = (feature.ROOT / 'mood/Resources/MediaPreview/n2-animation.gif').read_bytes()
        uri = self.call('Médias', 'Uploader GIF animé', 'POST', '/_matrix/media/v3/upload?filename=n2.gif', gif, a, mime='image/gif').get('content_uri')
        if not uri:
            raise RuntimeError('upload failed')
        path = '/_matrix/client/v1/media/download/' + uri[6:]
        self.call('Médias', 'GIF authentifié intégral', 'GET', path, actor=b, predicate=lambda v: v.get('binary') == gif)
        self.call('Médias', 'GIF sans jeton refusé', 'GET', path, codes={401, 403})
        with tempfile.TemporaryDirectory(prefix='mood-n2-fixtures-') as temporary:
            folder = Path(temporary)
            for name, arguments in [
                ('clip.mp4', ['-f', 'lavfi', '-i', 'color=c=blue:s=64x64:r=10', '-t', '1', '-c:v', 'libx264', '-pix_fmt', 'yuv420p']),
                ('tone.m4a', ['-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100', '-t', '1', '-c:a', 'aac'])
            ]:
                subprocess.run(['ffmpeg', '-v', 'error', '-y', *arguments, str(folder / name)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            video_bytes, audio_bytes = (folder / 'clip.mp4').read_bytes(), (folder / 'tone.m4a').read_bytes()
        video_uri = self.call('Médias', 'Uploader vrai MP4', 'POST', '/_matrix/media/v3/upload?filename=clip.mp4', video_bytes, a, mime='video/mp4').get('content_uri')
        audio_uri = self.call('Médias', 'Uploader vrai AAC', 'POST', '/_matrix/media/v3/upload?filename=tone.m4a', audio_bytes, a, mime='audio/mp4').get('content_uri')
        for label, remote, data in [('MP4', video_uri, video_bytes), ('AAC', audio_uri, audio_bytes)]:
            self.call('Médias', 'Télécharger intégralement ' + label, 'GET', '/_matrix/client/v1/media/download/' + remote[6:], actor=b, predicate=lambda v, expected=data: v.get('binary') == expected)
        contents = [{'msgtype': 'm.text', 'body': 'N2 batch'}]
        contents += [{'msgtype': 'm.image', 'body': 'n2.gif', 'url': uri, 'info': {'mimetype': 'image/gif', 'size': len(gif)}} for _ in range(10)]
        # Real MP4/AAC fixtures; event preservation and authenticated bytes are checked independently.
        contents += [
            {'msgtype': 'm.video', 'body': 'clip.mp4', 'url': video_uri, 'info': {'mimetype': 'video/mp4', 'size': len(video_bytes), 'duration': 1000, 'w': 1, 'h': 1, 'thumbnail_url': uri, 'thumbnail_info': {'mimetype': 'image/gif', 'size': len(gif)}}},
            {'msgtype': 'm.audio', 'body': 'tone.m4a', 'url': audio_uri, 'info': {'mimetype': 'audio/mp4', 'size': len(audio_bytes), 'duration': 1000}},
            {'msgtype': 'm.audio', 'body': 'voice.m4a', 'url': audio_uri, 'info': {'mimetype': 'audio/mp4', 'size': len(audio_bytes), 'duration': 1000}, 'org.matrix.msc3245.voice': {}, 'org.matrix.msc1767.audio': {'duration': 1000, 'waveform': [0, 256, 1024, 256, 0]}}
        ]
        for index, content in enumerate(contents):
            event = self.send(a, room, content, txn='n2-' + str(index))
            self.row('Médias', 'Envoyer événement ' + str(index), bool(event))
            if event:
                self.call('Médias', 'Relire événement exact ' + str(index), 'GET', V3 + '/rooms/' + q(room) + '/event/' + q(event), actor=b, predicate=lambda v, c=content: all(v.get('content', {}).get(k) == val for k, val in c.items()))
        for domain, permitted in [('https://github.com', True), ('https://example.com', False)]:
            response = self.request('GET', '/_matrix/client/v1/media/preview_url?url=' + q(domain), actor=a)
            self.row('Aperçus', 'Domaine autorisé' if permitted else 'Domaine refusé', response[0] == 200 if permitted else response[0] in (400, 403))
        for actor in (a, b):
            self.call('Nettoyage', 'Quitter salon jetable', 'POST', V3 + '/rooms/' + q(room) + '/leave', {}, actor)

    def finish(self):
        lines = [f'{v} {g} — {n} — HTTP {s} {e}' for v, g, n, s, e, _ in self.rows]
        counts = {v: sum(r[0] == v for r in self.rows) for v in ('PASS', 'FAIL', 'INFO')}
        result = {'date': dt.datetime.now(dt.timezone.utc).isoformat(), 'target': self.base, 'counts': counts, 'checks': lines,
                  'limits': 'Real one-second MP4/AAC and animated GIF, exact event and downloaded byte checks. No UI/playback claim. Two accounts deactivated in finally.'}
        output = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
        if any(secret and secret in output for secret in self.secret_values):
            print('FAIL Sécurité — sortie bloquée')
            return 1
        target = feature.ROOT / 'docs/screenshots/media/server-validation.json'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(output)
        print('\n'.join(lines))
        print('Résumé : ' + ', '.join(f'{k}={v}' for k, v in counts.items()))
        return int(bool(counts['FAIL']))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local', action='store_true')
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, feature.interrupted)
    try:
        check = MediaCheck(args.local)
    except OSError:
        print('FAIL Jeton indisponible ; aucun compte créé')
        return 1
    try:
        check.run()
    except BaseException as error:
        check.row('Exécution', 'Interruption ' + type(error).__name__, False)
    finally:
        check.cleanup()
    return check.finish()

if __name__ == '__main__':
    sys.exit(main())
