# Backend Mood — l'étape du 14 octobre 2026

**But de l'étape :** une personne crée **un seul compte Mood** (e-mail, ou Discord une fois activé)
et discute tout de suite. Elle ne voit jamais le mot « Matrix ». Coût : **0 €**.

Ce document décrit **ce qui existe vraiment** à la fin de la journée : architecture, configuration,
exploitation, sécurité, preuves, et ce qui reste. Le plan d'origine est `docs/BACKEND-PLAN.md` ; les
détails par piste sont dans `docs/SERVER-SETUP.md`, `docs/OPS.md`, `docs/MATRIX-SESSION-STATUS.md`,
`docs/PROVISIONING-F.md` et `supabase/functions/matrix-session/README.md`.

---

## 1. Vue d'ensemble

```
 App Mood (Mac Catalyst / iPhone)
   │
   │ ① connexion Mood (e-mail + mot de passe)        ──►  Supabase Auth      projet jxpgyblzymshyzbkgmat
   │                                                       (eu-west-3)        table public.profiles
   │ ② POST /functions/v1/matrix-session              ──►  Edge Function      matrix-session (Deno)
   │      Authorization: Bearer <jeton Supabase>             vérifie le jeton, dérive les identifiants,
   │      { device_id, device_name }                         crée le compte Matrix au 1er appel
   │                                       ◄── { homeserver, user_id, access_token, device_id, created }
   │
   │ ③ /sync, envoi, médias, salons, règles push      ──►  Continuwuity 26.9.1   « mood.local »
   │      Authorization: Bearer <jeton Matrix>              Mac Studio, 127.0.0.1:6167
   │                                                        publié par Tailscale Funnel :8443
   │ ④ notifications locales, badge, sourdine (dans l'app)
```

| Brique | Où | État |
|---|---|---|
| Serveur Matrix | Mac Studio, `~/mood-server` | ✅ en ligne, public, redémarre seul, sauvegardé |
| Adresse publique | `https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443` | ✅ (443 reste à l'API ClipFactory) |
| Fonction `matrix-session` | Supabase Edge Functions | ✅ déployée (v1, ACTIVE), secrets en place, **testée avec un vrai compte** |
| Comptes Mood | Supabase Auth (e-mail, confirmation active) | ✅ ; Discord ⏳ (app Discord à créer) |
| App : connexion automatique | `mood/Core/Account/` | ✅ fusionnée, testée par simulation |
| App : notifications, sourdine, paramètres | `mood/Core/Notifications/`, `Features/Settings` | ✅ fusionnée, compile, testée en logique |
| App : messagerie (médias authentifiés, envoi riche, file d'attente) | `mood/Core/Matrix/` | ✅ fusionnée (G) |
| App : fonctions compte, messages, serveurs façon Discord | `Features/`, `Core/` | ✅ fusionnées (J, K, L) — `docs/ACCOUNT-FEATURES.md`, `docs/MESSAGING-SERVERS.md`, `docs/FINISH-BASICS.md` |
| Noms d'utilisateur Mood (trouver / ajouter quelqu'un) | Supabase `profiles.username` + RPC | ✅ |
| Contrôle en direct de toutes les fonctions serveur | `server/feature-check.py` | ✅ 137 PASS — `docs/FEATURE-CHECK.md` |

Code : branche **`codex/pixel-merge`** du clone `~/mood-codex-merge` sur le Studio. **Rien n'est
poussé sur GitHub** (en attente du oui d'Augustin).

---

## 2. Parcours d'un utilisateur

1. **Inscription** : l'app appelle Supabase `signup` avec `email_redirect_to = mood://auth-callback`.
   Message : « Confirme ton e-mail, puis reviens ». Le lien de l'e-mail rouvre Mood
   (`onOpenURL`), qui termine la connexion. Un trigger SQL crée la ligne `public.profiles`.
2. **Connexion Mood** (ou session restaurée au lancement) → écran « Connexion à Mood… ».
3. `AccountStore.connectMood` appelle `SupabaseAuthClient.matrixSession(deviceId:deviceName:)` :
   `POST {SUPABASE_URL}/functions/v1/matrix-session` avec le jeton Supabase.
4. La fonction :
   1. valide le jeton auprès de `GET /auth/v1/user` (elle ne croit **jamais** un id envoyé par l'app) ;
   2. calcule `localpart = "m" + 12 premiers hex de l'id` et
      `mot de passe = base64url(HMAC-SHA256(MATRIX_PASSWORD_PEPPER, id))` (43 caractères, rien stocké) ;
   3. tente `POST /_matrix/client/v3/login` avec le `device_id` de l'app ;
   4. si le compte n'existe pas : `POST /register` en deux temps (UIAA, étape
      `m.login.registration_token` avec le jeton d'inscription), puis pose le nom d'affichage
      (`profiles.display_name`, sinon la partie avant `@` de l'e-mail, sinon le nom Discord) ;
   5. écrit `profiles.matrix_user_id` et `matrix_homeserver` (clé serveur, seulement si ça change) ;
   6. renvoie la session Matrix.
5. L'app appelle `MatrixStore.login(accessToken:userId:homeserver:deviceId:)` : `whoami` pour
   vérifier, sauvegarde, recharge le cache disque, lance la sync et la file d'envoi.
6. **Connexions suivantes** : même chemin, `login` simple, **même appareil Matrix** (pas de
   multiplication des sessions).

`device_id` = `"MOOD"` + 12 caractères hexadécimaux, généré une fois par installation et rangé dans
`UserDefaults` sous `mood.matrix.device_id` (ce n'est pas un secret). Une connexion Matrix manuelle reste possible dans
**Paramètres › Mon compte › Avancé** (« Utiliser un autre compte Matrix ») ; la prochaine connexion
Mood revient au compte géré.

### Erreurs vues par l'utilisateur

| Réponse de la fonction | Cause | Message dans l'app |
|---|---|---|
| `401 not_authenticated` | jeton Supabase absent ou expiré | « Ta session Mood a expiré. Reconnecte-toi. » |
| `503 homeserver_unreachable` | Studio éteint, Funnel coupé, serveur figé (délai 8 s) | « Le serveur Mood est injoignable » + **Réessayer** |
| `500 provisioning_failed` + `detail` | config manquante, jeton d'inscription refusé, etc. | « Impossible de connecter ton compte Mood. Réessaie dans un instant. » + Réessayer (le `detail` n'est jamais affiché) |
| pas de réponse | pas d'Internet | « Impossible de joindre Mood. Vérifie ta connexion et réessaie. » |

Les messages viennent de `Core/Account/MoodProvisioning.swift` et `AccountStore.connectMood`.

Supabase Auth en panne donne un **500**, pas un 401 : l'app ne déconnecte pas l'utilisateur pendant
une panne Supabase.

---

## 3. Contrat d'API `matrix-session`

```
POST https://jxpgyblzymshyzbkgmat.supabase.co/functions/v1/matrix-session
Authorization: Bearer <access_token Supabase>
apikey: <clé publishable>
{ "device_id": "MOOD1A2B3C4D5E6F", "device_name": "Mood · Mac" }

200 { "homeserver": "https://…ts.net:8443", "user_id": "@m1a2b3c4d5e6f:mood.local",
      "access_token": "…", "device_id": "MOOD1A2B3C4D5E6F", "created": true|false }
401 { "error": "not_authenticated" }
503 { "error": "homeserver_unreachable" }
500 { "error": "provisioning_failed", "detail": "…" }
400 { "error": "invalid_request", "detail": "…" }     // seulement un client bogué
405 { "error": "method_not_allowed" }                  // idem
```

Valeurs de `detail` et leur remède : `supabase/functions/matrix-session/README.md`.

---

## 4. Composants et configuration

### 4.1 Serveur Matrix (Mac Studio, utilisateur `Adm`)

| Élément | Valeur |
|---|---|
| Logiciel | **Continuwuity 26.9.1** (tag `v26.9.1`, commit `046074b`), compilé en natif arm64 (Rust Homebrew 1.96.0), sans Docker |
| Binaire | `~/mood-server/bin/continuwuity` (source `~/mood-server/src`) |
| Config | `~/mood-server/continuwuity.toml` — gabarit suivi : `server/continuwuity.example.toml` |
| Données | `~/mood-server/data` (RocksDB + médias) |
| Identité | `server_name = "mood.local"` — **définitif pour cette base** |
| Écoute | `127.0.0.1:6167` seulement |
| Fédération | désactivée |
| Inscription | uniquement par jeton (`registration_token_file`) ; `force_disable_first_run_mode = true` (pas de jeton imprimé au 1er démarrage, **pas d'admin automatique**) ; `admins_list` vide |
| Taille max d'une requête | 25 Mio (`max_request_size = 26214400`) |
| Présence / saisie / accusés | locaux seulement |
| Aperçus d'URL | liste blanche GitHub, YouTube, Wikipédia ; 256 Ko ; 15 s ; IP privées interdites |
| Publication | `tailscale funnel --bg --https=8443 http://127.0.0.1:6167` — coexiste avec `443 → 127.0.0.1:8000` (ClipFactory, **ne jamais toucher**) |

Services (LaunchAgents, gabarits dans `server/`, installés par `server/install.sh`) :

| Service | Rôle |
|---|---|
| `app.mood.server` | le serveur ; `RunAtLoad` + `KeepAlive` (relancé s'il meurt) |
| `app.mood.healthcheck` | toutes les 5 min `GET /_matrix/client/versions` ; 2 échecs de suite → `launchctl kickstart -k` |
| `app.mood.backup` | 04 h 15 chaque jour : sauvegarde **à froid** (courte coupure), manifeste SHA-256, 7 jours gardés dans `~/Backups/mood-server/AAAA-MM-JJ` |

Journaux : `~/Library/Logs/MoodServer/`. Les agents démarrent à l'ouverture de session `Adm` :
**le Studio doit rester allumé et connecté.**

### 4.2 Secrets (noms seulement — jamais les valeurs)

| Nom | Où il vit | Rôle |
|---|---|---|
| `MATRIX_REGISTRATION_TOKEN` | `~/mood-server/.env` + `~/mood-server/registration_token` (600) + secrets Supabase | autorise la création de comptes sur le serveur |
| `MATRIX_PASSWORD_PEPPER` | `~/mood-server/.env` (600) + secrets Supabase | clé de dérivation des mots de passe Matrix ; **ne jamais le changer** après le 1er utilisateur |
| `MATRIX_HOMESERVER_URL` | idem | `https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443` (pas secret) |

Le dossier `~/mood-server` est en 700. Les sauvegardes contiennent les secrets : privées, jamais
partagées. Supabase fournit lui-même `SUPABASE_URL` et les clés API à la fonction (elle préfère les
nouvelles clés `SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_SECRET_KEYS`, repli sur les anciennes,
retirées fin 2026).

**Coller les secrets dans Supabase** (Augustin seulement ; l'assistant n'a pas le droit de manipuler
ces valeurs et Supabase a coupé l'enregistrement de clés par l'assistant) :

1. Dans Claude Code :
   `! ssh -o HostName=192.168.1.10 -o HostKeyAlias=mac-studio-de-charlesmacstudio.local studio 'cat ~/mood-server/.env' | pbcopy`
   (rien ne s'affiche : les 3 lignes sont dans le presse-papiers) ;
2. https://supabase.com/dashboard/project/jxpgyblzymshyzbkgmat/functions/secrets → champ **Name**
   de la 1re ligne → ⌘V (les 3 lignes se répartissent) → **Save** ;
3. `! printf '' | pbcopy`.

Vérification sans rien révéler : un appel avec un faux jeton doit répondre **401** et non
`missing_config`.

### 4.3 Supabase

| Élément | Valeur |
|---|---|
| Projet | `mood`, ref `jxpgyblzymshyzbkgmat`, eu-west-3 |
| Auth | e-mail activé, confirmation obligatoire ; redirection `mood://auth-callback` ; Discord **désactivé** (en attente de l'app Discord) |
| Fonction | `matrix-session`, `verify_jwt = false` (la fonction valide elle-même chaque jeton : la passerelle renverrait sinon son propre 401 au lieu du contrat, et ne comprend que les anciennes clés JWT) |
| Tables | `public.profiles`, `public.discord_guilds_import` — RLS active, politiques « chacun ses lignes » |
| Triggers | `on_auth_user_created_profile` (crée le profil), `on_profile_updated` (`updated_at`) |
| Migrations | `20261007000000_profiles.sql`, **`20261014000000_profiles_server_owned_matrix_link.sql`**, **`20261014010000_profiles_username_lookup.sql`** |
| Noms d'utilisateur | `profiles.username` unique (2–32 : `a-z 0-9 _ .`, pas de `..`), rempli à l'inscription (partie avant `@` de l'e-mail, ou pseudo Discord, + 4 chiffres si pris) ; modifiable par l'utilisateur ; RPC `find_user_by_username(p_username)` : correspondance **exacte** seulement (pas de liste), réservée aux connectés |

**Droits sur `profiles` depuis le 14/10** : un utilisateur connecté peut écrire seulement
`display_name`, `avatar_url`, `discord_id`, `discord_username`, `discord_avatar_url` (+ `id` à
l'insertion). `matrix_user_id`, `matrix_homeserver`, `created_at`, `updated_at` ne s'écrivent plus que
côté serveur (fonction, clé service). Avant, n'importe qui pouvait mettre l'identifiant Matrix d'un
autre dans sa ligne et bloquer le vrai propriétaire (contrainte `unique`). Vérifié par
`information_schema.column_privileges` après application.

### 4.4 App

| Fonction | Fichiers |
|---|---|
| Comptes, session, provisioning | `Core/Account/SupabaseAuthClient.swift`, `AccountStore.swift`, `AccountModels.swift` |
| Session Matrix sans mot de passe | `MatrixStore.login(accessToken:userId:homeserver:deviceId:)` |
| Notifications locales, badge, décisions | `Core/Notifications/NotificationPolicy.swift`, `NotificationService.swift` |
| Sourdine = règles push Matrix | `Core/Notifications/PushRules.swift` ; `PUT/DELETE /pushrules/global/room/{id}` ; lecture au démarrage + `m.push_rules` à chaque sync |
| Paramètres réels | `Features/Settings/AccountSettings.swift` : Notifications (activer, sons, badge, salons muets), Confidentialité (accusés de lecture → sinon `m.read.private` ; « est en train d'écrire »), Appareils (`GET /devices`, déconnexion de l'appareil courant seulement), Chiffrement (panneau honnête : pas encore de E2EE) |

Notifications : seulement pour les **nouveaux** messages après la 1re sync ; jamais pour mes
messages, les bloqués, les salons muets, le salon ouvert au premier plan, les messages de plus de
15 min ; au plus 5 par rafale ; titre = auteur (+ « · #salon ») ; un clic ouvre la conversation.
Désactivées par défaut, autorisation demandée à l'activation. Badge = mentions dans les salons + MP
non lus (hors salons muets).

---

## 5. Exploitation (aide-mémoire)

Tout le détail : `docs/OPS.md`.

```bash
# santé
curl -fsS http://127.0.0.1:6167/_matrix/client/versions                      # sur le Studio
curl -fsS https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443/_matrix/client/versions
/Applications/Tailscale.app/Contents/MacOS/Tailscale funnel status           # 443 ET 8443 présents
# redémarrer
launchctl kickstart -k "gui/$(id -u)/app.mood.server"
# vérifier une sauvegarde / tester une restauration (copie isolée sur 6168)
python3 ~/mood-server/scripts/snapshot.py verify ~/Backups/mood-server/AAAA-MM-JJ
python3 ~/mood-server/scripts/restore-test.py ~/Backups/mood-server/AAAA-MM-JJ
# journaux de la fonction (sans secret) : Supabase › Edge Functions › matrix-session › Logs
```

| Situation | Effet | Que faire |
|---|---|---|
| Studio éteint / box coupée | app : « Le serveur Mood est injoignable » ; les messages restent dans la file d'envoi | rallumer, ouvrir la session `Adm`, vérifier les 3 agents, 6167 et Funnel 8443 |
| Serveur figé | relancé par la santé en ≤ 10 min | rien |
| Rotation du jeton d'inscription | sans effet sur les comptes existants | `docs/OPS.md` › Rotation, puis recoller dans Supabase |
| Changer le pepper | **bloque tous les comptes** (`matrix_credentials_rejected`) | ne pas le faire ; migration coordonnée décrite dans `docs/OPS.md` |
| Vrai nom de domaine | `server_name` ne se change pas sur une base | nouveau serveur + migration (`docs/OPS.md` › Nouveau domaine) |

---

## 6. Sécurité

| Sujet | Mesure |
|---|---|
| Création de comptes Matrix sauvage | inscription fermée sauf jeton ; le jeton ne quitte jamais le Studio et Supabase |
| Usurpation | la fonction valide le jeton Supabase côté serveur ; le mot de passe Matrix est dérivé de l'id vérifié ; l'app ne le connaît jamais |
| Fuite dans les journaux | la fonction n'écrit que résultat, étape, `errcode`, localpart ; testée : 0 jeton / mot de passe / pepper dans les sorties |
| Admin automatique | désactivé (`force_disable_first_run_mode`, `admins_list` vide) |
| Lien Matrix ↔ profil | écrit seulement par la fonction (droits par colonne, migration du 14/10) |
| Collision de localpart (48 bits) | échoue proprement (`matrix_credentials_rejected`), ne donne jamais accès à l'autre compte |
| Chiffrement de bout en bout | **pas encore** : l'app ne montre ni cadenas ni « E2E » |
| Transport | HTTPS de bout en bout (certificat Tailscale) |

| Trouver quelqu'un | la recherche Matrix de Continuwuity **cache tout utilisateur sans salon commun ni salon public** (aucun réglage) ; on passe par le nom d'utilisateur Mood exact (RPC), impossible d'énumérer les comptes |
| Sessions sur les builds non signés | le trousseau refuse (`errSecMissingEntitlement`) : session Mood et jeton Matrix rangés dans `Application Support/Mood/credentials.json` (dossier 700, fichier 600, protection de données sur iPhone). Un build signé utilisera le trousseau et n'écrira jamais ce fichier |
| Codes d'invitation | un code (alias `#xxxxxxxx:mood.local`) rend le serveur **ouvert à quiconque a le code** ; pas encore d'expiration ni de révocation |

Points ouverts (non bloquants aujourd'hui) :
- `discord_id` reste modifiable par l'utilisateur (valeur `unique`) : quelqu'un pourrait réserver
  l'id Discord d'un autre. À corriger quand la liaison Discord sera faite côté serveur.
- Conseiller sécurité Supabase : fonctions `waitlist_join` / `waitlist_stats` (SECURITY DEFINER)
  exécutables par `anon` et table `waitlist` sans politique. **Elles ne viennent pas de Mood** (liste
  d'attente d'un site ?) : laissées telles quelles, à confirmer par Augustin.
- « Leaked password protection » désactivée dans Supabase Auth (réglage du dashboard).
- Le disque du Studio n'est pas chiffré (**FileVault désactivé**) : messages et sauvegardes en clair au
  repos. À activer par Augustin (Réglages Système › Confidentialité et sécurité › FileVault).
- Continuwuity ajoute par défaut un suffixe aux noms des nouveaux comptes (`new_user_displayname_suffix`) ;
  la fonction pose le vrai nom juste après, mais le régler à `""` serait plus propre.
- Deux appels simultanés pour le même appareil : le 2e jeton remplace le 1er (l'app n'appelle
  qu'une fois à la fois).

---

## 7. Preuves (14 octobre 2026)

| Vérification | Résultat |
|---|---|
| Compilation Continuwuity `cargo build --release --locked` | OK en 9 min 14 s ; `continuwuity 26.9.1 (046074b)` arm64 |
| `server/verify.py` local puis via l'adresse publique | inscription UIAA de `@moodtest1`, mauvais jeton refusé, connexion, message relu par `/sync` : PASS |
| Accès par l'entrée Internet de Funnel (IP publique, TLS vérifié) | HTTP 200 |
| `funnel status` | 443 → 8000 et 8443 → 6167 coexistent |
| Processus tué (SIGKILL), `kickstart -k`, serveur figé (SIGSTOP) | revient seul : PASS ×3 |
| Sauvegarde + restauration isolée (port 6168) | manifeste vérifié, message original retrouvé : PASS |
| Tests Deno de la fonction | **46 réussis**, 0 échec ; `deno check` et `deno lint` OK ; 3 mutations volontaires détectées |
| Déploiement Supabase | `matrix-session` ACTIVE v1 ; sans jeton → `401 not_authenticated` |
| **Vraie fonction ↔ vrai Continuwuity** (`scripts/matrix-session-local-e2e.ts`, seul Supabase simulé) | `200 created:true` en 199 ms (inscription par jeton), `whoami` OK, nom `e2e-probe` posé ; 2e appel `created:false` même appareil (54 ms) ; mauvais jeton `401` |
| Fusion D + E + F + H dans `codex/pixel-merge` | aucun conflit |
| Build Mac Catalyst + iPhone 18 Pro (Xcode 27) | `** BUILD SUCCEEDED **` ×2 |
| `moodTests` | `** TEST SUCCEEDED **`, **62 tests** (contrat, erreurs, `device_id`, décisions de notification, badge, règles push, préférences, appareils…) |
| Droits `profiles` après migration | INSERT/UPDATE limités aux colonnes prévues (requête `column_privileges`) |
| Secrets collés par Augustin dans Supabase | la fonction répond `401` (et plus `missing_config`) à un faux jeton |
| **Vrai compte Mood d'Augustin, app Mac sur le Studio** (15:30:56) | journal de la fonction : `matrix_session ok`, `path: register`, `created: true`, 340 ms ; compte `@mb222b6fe1674:mood.local` ; `profiles.matrix_user_id` + `matrix_homeserver` remplis ; arrivée dans l'app sans question Matrix |
| Changement de nom depuis Paramètres › Profil | arrive sur le serveur (`/profile` répond le nouveau nom) ; **bug trouvé** : l'app ne rafraîchissait pas son propre affichage → corrigé (`4a30507`) |

| `server/feature-check.py` (3 comptes jetables désactivés à la fin) | **137 PASS, 2 FAIL, 24 INFO** : FAIL = recherche sans salon commun (→ noms d'utilisateur) et `/notifications` absent (→ mentions locales) |
| Parcours MP de l'app rejoué sur le serveur (2 comptes jetables) | invitation `is_direct` OK, mais après acceptation la sync ne contient que l'arrivée (`limited: true`) → **bug app trouvé et corrigé** (`5705eb6`) |
| Fusion D…L + correctifs | Mac + iPhone `** BUILD SUCCEEDED **`, **131 tests** `** TEST SUCCEEDED **` (`95c9266`) |

### Bugs trouvés en vrai cet après-midi (et corrigés)

| Symptôme vu par Augustin | Cause | Correctif |
|---|---|---|
| Changer son nom « ne se met pas » | l'app envoyait au serveur sans rafraîchir son état | `4a30507` |
| Inscription : le lien de l'e-mail mène à une page qui ne marche pas, rien dans Mood, bouton pressé 12 fois | message de confirmation affiché comme une erreur, bouton actif pendant l'envoi, lien `mood://` ouvert sur un autre appareil | écran « Vérifie ta boîte mail » + connexion automatique (`7e2f5ab`) |
| Le message envoyé de l'iPhone n'arrive pas sur le Mac | MP accepté non rangé dans `m.direct` ; premier message jamais récupéré (`limited`) | `22a5d21`, `5705eb6` (+ J, L) |
| Déconnecté à chaque mise à jour | trousseau refusé sur build non signé | `39b4413` |
| Bouton « Se connecter avec Discord » sans effet | fournisseur désactivé dans Supabase | masqué tant que désactivé (`d3f3288`) |
| Personne ne peut être trouvé | recherche Matrix limitée aux salons communs | noms d'utilisateur Mood (`d3f3288` + migration) |
| Deux MP nommés `md88cc4dfa1b7`, sur les deux comptes | membres chargés à la demande : nom de l'autre absent ; un MP créé de chaque côté | pair lu dans `m.direct`, profil chargé si absent, un seul MP par personne (`b3f4a9d`) |
| Impossible d'envoyer depuis l'app Mac | champ multi-lignes : Mac Catalyst avale Entrée (ajoute une ligne) ; pas de bouton Envoyer sur desktop | Entrée envoie, Maj+Entrée = nouvelle ligne (`1fdc77a`) — **confirmé par Augustin** |

Comptes de test sur **notre** serveur seulement : `@moodtest1:mood.local` (piste D),
`@m0e2e00001014:mood.local` (banc E) ; les comptes `featcheck-*` et `dmcheck-*` sont désactivés.
Comptes Mood réels : `demeauxa8@gmail.com` (`demeauxa8`) et `demeauxa@icloud.com` (`demeauxa`), créés par
Augustin lui-même.

---

## 8. Ce qui n'est pas encore prouvé

| Point | Bloqué par |
|---|---|
| Test complet du plan §4 (2 comptes, MP, serveur/salon, hors-ligne, relance, redémarrage, notifications) | secrets + Augustin qui pilote l'app (l'assistant ne tape pas de mot de passe) + piste G |
| Images et fichiers sur notre serveur | piste G (médias authentifiés : sans elle, Continuwuity refuse les téléchargements non authentifiés) |
| Notifications réelles sur Mac non signé | peut ne pas marcher sans signature ; iPhone : seulement app ouverte (pas d'APNs) |
| `m.read.private`, `GET /devices` contre Continuwuity | test de bout en bout |
| Connexion Discord | création de l'app « Mood » sur discord.com/developers + Client ID/Secret dans Supabase (`docs/ACCOUNTS-SETUP-STATUS.md`) |

## 9. Suite

1. ~~Augustin colle les secrets~~ (fait, 15:28) ; ~~1re vraie connexion~~ (fait, 15:30).
2. Fusion de la piste G, builds, tests ; contrôle automatique de toutes les fonctions côté serveur
   (`server/feature-check.py`, `docs/FEATURE-CHECK.md`) ; revue de l'interface compte + messages.
3. Test de bout en bout §4 du plan, piloté par Augustin sur le Studio (simulateur iPhone + app Mac).
4. Décisions en attente : push GitHub, renommer « Mood Merge » en « Mood », icônes de la barre de
   saisie, app Discord.
5. Plus tard : vrai domaine + fédération, chiffrement (vodozemac), push app fermée (APNs + Sygnal,
   compte Apple Developer), signature de l'app, serveur hors du Studio, SMTP (Resend) avant des
   testeurs, découpage de `MatrixStore`.
