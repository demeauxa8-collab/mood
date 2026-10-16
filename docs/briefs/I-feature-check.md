# Brief I — Contrôle en direct de toutes les fonctions côté serveur (Codex)

Branche `codex/feature-check`, dossier `~/mood-featcheck` (worktree de `~/mood-codex-merge`).
**Ne commite pas dans `~/mood-codex-merge` et ne change pas sa branche** : la session principale y fusionne.
Lis `AGENTS.md`, `docs/BACKEND.md`, `docs/SERVER-SETUP.md`, `docs/OPS.md`, `server/verify.py`.

## But
Prouver, contre le **vrai serveur Mood**, que chaque appel Matrix dont l'app a besoin pour les fonctions de
base de Discord (compte + messages + serveurs) marche vraiment. Livrables : `server/feature-check.py`
(Python, bibliothèque standard seulement) et `docs/FEATURE-CHECK.md` (en français, tableau de résultats).
Ce n'est **pas** du code d'app : ne modifie pas `mood/`.

## Serveur
Continuwuity 26.9.1, `server_name = mood.local`, local `http://127.0.0.1:6167`, public
`https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443` (par défaut : l'URL publique, c'est le chemin
de l'app ; option `--local`). Inscription uniquement par jeton (UIAA `m.login.registration_token`), jeton dans
`~/mood-server/registration_token` (600). Fédération coupée. Requêtes max 25 Mio.

## Règles strictes (sécurité)
- **N'affiche, ne journalise, ne commite jamais un secret** : jeton d'inscription, mots de passe, jetons
  d'accès. Ne lis pas `MATRIX_PASSWORD_PEPPER` (inutile). Le jeton d'inscription est lu **dans le processus
  Python** uniquement (jamais `cat`, jamais en argument de commande, jamais `set -x`). Mots de passe de test :
  `secrets.token_urlsafe` en mémoire. Masque tout champ `access_token` avant affichage. Avant de finir,
  vérifie (dans Python, sans l'afficher) que le jeton n'apparaît ni dans tes sorties ni dans tes fichiers.
- Ne touche pas : config/données/binaire de `~/mood-server` (lecture du fichier jeton seulement), les
  LaunchAgents, Tailscale Funnel (le 443 est l'API ClipFactory sur 127.0.0.1:8000 : **jamais**), Minecraft,
  Redis, Ollama, `~/mood-desktop-pixel-lab`, `~/mood-build`, `~/mood-src`, `~/Documents/mood`, les apps de
  `~/Applications`, les apps lancées. Ne redémarre pas le serveur Matrix.
- **Rien sur GitHub** (ni push ni PR). Commits locaux seulement.
- Comptes de test : exactement **trois** comptes jetables par exécution, `featcheck-a-<AAAAMMJJHHMM>`,
  `featcheck-b-<…>`, `featcheck-c-<…>` ; **désactive-les tous à la fin** (`POST /account/deactivate`, UIAA
  `m.login.password`) même en cas d'échec (`try/finally`). Ne touche à aucun autre compte (`@moodtest1`,
  `@m…` = vrais comptes ou autres preuves).

## Ce qu'il faut vérifier
D'abord, lis `mood/Core/Matrix/MatrixClient.swift` (et `MatrixStore.swift` si besoin) et liste **tous les
endpoints appelés par l'app** : le contrôle doit tous les couvrir. Ajoute ceux qu'une autre piste (G) est en
train de brancher : médias authentifiés `GET /_matrix/client/v1/media/download/{server}/{id}` et
`/thumbnail/{server}/{id}?width=&height=&method=scale` avec Bearer, ce que répond le
`/_matrix/media/v3/download` **non authentifié** (à noter), `POST /_matrix/media/v3/upload`, et un envoi de
plus de 25 Mio refusé (statut + errcode ; génère les octets en mémoire, pas de gros fichier dans le dépôt).

Une ligne PASS / FAIL / INFO par contrôle, avec code HTTP et errcode, regroupées comme Discord :

- **Compte** : inscription par jeton, connexion, `whoami`, `/capabilities` (`m.change_password`,
  `m.set_displayname`, `m.set_avatar_url`, champs de profil), nom d'affichage écrit/lu (et B voit le nouveau
  nom de A via `/profile` **et** dans l'événement membre du salon après `/sync`), avatar (upload + `avatar_url`
  + téléchargement authentifié), **champs de profil personnalisés** (MSC4133 : `PUT/GET
  /_matrix/client/v3/profile/{userId}/{clé}` stable ou préfixe instable `uk.tcpip.msc4133` — dis si le serveur
  peut stocker un « À propos de moi »), présence/statut (`online`, `unavailable`, `offline` + `status_msg`)
  et B le voit, appareils (liste + renommer), règles push : `GET`, sourdine `PUT
  /pushrules/global/room/{roomId}` `{"actions":[]}` puis `DELETE`, blocage (`m.ignored_user_list`) et ses
  effets, déconnexion.
- **Trouver quelqu'un / amis** : **C cherche A par son nom d'affichage dans `/user_directory/search` sans
  partager aucun salon avec A** (c'est ainsi qu'on « ajoute un ami » ; les identifiants `@m<hex>` sont
  illisibles). Note précisément ce que le serveur renvoie et, si C ne trouve pas A, quel réglage de
  Continuwuity le permettrait (cherche dans `~/mood-server/src` la doc/clé de config du répertoire
  d'utilisateurs — **sans modifier la config**, propose seulement). Puis reproduis le parcours ami/MP de
  l'app tel qu'il est codé (`m.direct`, invitations…) : A crée un MP avec B (`is_direct`), B voit
  l'invitation dans `/sync`, rejoint, `m.direct` à jour des deux côtés.
- **Messages** : `m.text` avec `format: org.matrix.custom.html`, `formatted_body`, `m.mentions.user_ids` ; B le
  reçoit ; modification (`m.replace` + `m.new_content`) vue par B ; réponse (`m.in_reply_to`) ; réaction
  (`m.annotation`) puis retrait par redaction ; suppression d'un message ; épingle (`m.room.pinned_events`) ;
  saisie (`PUT /typing`) vue par B ; accusés `m.read` et `m.read.private` + marqueur `m.fully_read` ;
  `/messages` en arrière ; `/context`, `/relations`, `/search` serveur si l'app les utilise (dis si
  Continuwuity sait faire `/search`) ; message image (`m.image` + `info` w/h/size/mimetype + miniature) et
  fichier (`m.file`) ; même `txnId` envoyé deux fois → même `event_id` ; en-têtes de limite de débit, s'il y en a.
- **Serveurs / salons** : créer un espace (`creation_content.type = m.space`), un salon enfant lié par
  `m.space.child` / `m.space.parent`, `GET /_matrix/client/v1/rooms/{espace}/hierarchy`, inviter B dans
  l'espace et le salon, B rejoint, renommer le salon (`m.room.name`) et son sujet, niveaux de pouvoir (A
  promeut/rétrograde B), expulser, bannir/débannir, quitter, alias de salon créer/résoudre si l'app s'en sert
  (liens d'invitation).

`python3 server/feature-check.py [--local]` : une ligne par contrôle (`PASS|FAIL|INFO groupe — nom — HTTP
errcode`), un résumé, code de sortie 0 seulement si tous les contrôles requis passent. Délais d'attente
partout. `INFO` = fonction que l'app n'utilise pas, ou constat utile. Lance-le sur le Studio et corrige ton
script jusqu'à ce que les échecs restants soient de vrais problèmes du serveur ou du contrat de l'app.

## `docs/FEATURE-CHECK.md` (français)
Comment le lancer, la date, le tableau des résultats par fonction, et pour chaque FAIL ou résultat
surprenant : une explication courte et **ce que l'app doit faire** (ex. « Continuwuity ne fait pas
`/search` → recherche locale », « C ne trouve pas A → il faut … »). Termine par la liste des endpoints de
l'app que le serveur refuse, s'il y en a.

## Fin
Commits sur `codex/feature-check` (messages en anglais, dernière ligne
`Co-Authored-By: Codex <noreply@openai.com>`). Résumé final court : compteurs, FAIL/INFO avec causes,
hash du commit, confirmation que les 3 comptes sont désactivés et qu'aucun secret n'apparaît nulle part.
