#!/usr/bin/env python3
"""N1 disposable-account checks; credentials stay in memory, cleanup always runs."""
import importlib.util
import secrets
import signal
import sys
import subprocess
from pathlib import Path
spec = importlib.util.spec_from_file_location('feature_check', Path(__file__).with_name('feature-check.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
q, V3 = module.q, module.V3

class ConversationCheck(module.Check):
    def register(self, letter):
        self.stamp = secrets.token_hex(7)
        username = 'n1check-' + letter + '-' + self.stamp
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
        a, b = [self.register(x) for x in 'ab']
        room = self.call('Conversation', 'Créer salon privé jetable', 'POST', V3 + '/createRoom', {'preset':'private_chat', 'invite':[b['user_id']]}, a)['room_id']
        rp = V3 + '/rooms/' + q(room)
        self.call('Conversation', 'Rejoindre', 'POST', V3 + '/join/' + q(room), {}, b)
        root = self.send(a, room, {'msgtype':'m.text','body':'N1 needle root'})
        reply = self.send(b, room, {'msgtype':'m.text','body':'N1 thread reply','m.relates_to':{'rel_type':'m.thread','event_id':root,'is_falling_back':True,'m.in_reply_to':{'event_id':root}}})
        self.row('Conversation', 'Envoyer fil', bool(reply))
        self.call('Conversation', 'Liste threads v1', 'GET', '/_matrix/client/v1/rooms/' + q(room) + '/threads?include=all', actor=a, predicate=lambda x:any(e.get('event_id') == root and e.get('unsigned',{}).get('m.relations',{}).get('m.thread',{}).get('count',0) >= 1 for e in x.get('chunk',[])))
        self.call('Conversation', 'Repli messages contient fil', 'GET', rp + '/messages?dir=b&limit=100', actor=a, predicate=lambda x:any(e.get('event_id') == reply and e.get('content',{}).get('m.relates_to',{}).get('event_id') == root for e in x.get('chunk',[])))
        self.call('Conversation', 'Sync contient fil', 'GET', V3 + '/sync?timeout=0&filter=' + q('{"room":{"timeline":{"limit":100,"unread_thread_notifications":true}}}'), actor=a, predicate=lambda x:any(e.get('event_id') == reply for e in self.timeline(x, room)))
        self.call('Conversation', 'Accusé fil', 'POST', rp + '/receipt/m.read/' + q(reply), {'thread_id':root}, a)
        self.call('Conversation', 'Context retrouve racine', 'GET', rp + '/context/' + q(root), actor=b, predicate=lambda x:x.get('event',{}).get('event_id') == root)
        for kind in ('m.marked_unread','com.famedly.marked_unread'):
            path = V3 + '/user/' + q(a['user_id']) + '/rooms/' + q(room) + '/account_data/' + kind
            for unread in (True,False):
                self.call('Conversation', kind + ' écrire ' + str(unread), 'PUT', path, {'unread':unread}, a)
                self.call('Conversation', kind + ' relire ' + str(unread), 'GET', path, actor=a, predicate=lambda x, unread=unread:x.get('unread') is unread)
        self.call('Conversation', 'Recherche serveur', 'POST', V3 + '/search', {'search_categories':{'room_events':{'search_term':'needle','filter':{'rooms':[room]},'order_by':'recent'}}}, b, predicate=lambda x:any(h.get('result',{}).get('event_id') == root for h in x.get('search_categories',{}).get('room_events',{}).get('results',[])))
        dest = self.call('Conversation', 'Créer destination transfert', 'POST', V3 + '/createRoom', {'preset':'private_chat','invite':[b['user_id']]}, a)['room_id']
        self.call('Conversation','Rejoindre destination','POST',V3+'/join/'+q(dest),{},b)
        forwarded = self.send(a,dest,{'msgtype':'m.text','body':'Transféré · N1\nN1 needle root'})
        self.call('Conversation','Destinataire relit transfert','GET',V3+'/rooms/'+q(dest)+'/context/'+q(forwarded),actor=b,predicate=lambda x:x.get('event',{}).get('content',{}).get('body') == 'Transféré · N1\nN1 needle root')
        for actor in (a,b):
            for target in (room,dest):
                self.call('Nettoyage','Quitter salon jetable','POST',V3+'/rooms/'+q(target)+'/leave',{},actor)

    def finish(self):
        lines = [f'{v} — {name} — HTTP {status} {err}' for v, group, name, status, err, detail in self.rows]
        output = '\n'.join(lines) + '\n'
        tracked = subprocess.run(['git', 'ls-files', '-z'], cwd=module.ROOT, capture_output=True, check=True).stdout.split(b'\0')
        payloads = [output.encode(), Path(__file__).read_bytes()]
        payloads += [(module.ROOT / name.decode()).read_bytes() for name in tracked if name and (module.ROOT / name.decode()).is_file()]
        if any(s and s.encode() in payload for s in self.secret_values for payload in payloads):
            print('FAIL sorties bloquées')
            return 1
        (module.ROOT/'docs/screenshots/conversation/server-check.txt').write_text(output)
        print(output,end='')
        return int(any(x[0]=='FAIL' for x in self.rows))

def main():
    signal.signal(signal.SIGTERM,module.interrupted)
    check = ConversationCheck(local='--local' in sys.argv)
    try:
        check.run()
    except BaseException as error:
        check.row('Exécution','Interruption '+type(error).__name__,False)
    finally:
        check.cleanup()
    return check.finish()
if __name__ == '__main__':
    sys.exit(main())
