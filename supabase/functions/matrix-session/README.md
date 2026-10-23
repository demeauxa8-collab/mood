# Edge Function `matrix-session`

Transforme une session Mood (Supabase Auth) en session Matrix sur le serveur Mood
(Continuwuity, `mood.local`). Au premier appel, elle crée le compte Matrix avec le jeton
d'inscription ; ensuite, elle ouvre simplement une session sur l'appareil demandé. L'app ne voit
jamais de mot de passe Matrix.

Contrat : `docs/BACKEND-PLAN.md` §2 (la piste F code l'app contre lui).

## Contrat en bref

```
POST {SUPABASE_URL}/functions/v1/matrix-session
Authorization: Bearer <access_token Supabase>     apikey: <clé publique>
{ "device_id": "MOODMAC1A2B3C4D", "device_name": "Mood · Mac" }

200 { "homeserver", "user_id", "access_token", "device_id", "created" }
401 { "error": "not_authenticated" }
503 { "error": "homeserver_unreachable" }
500 { "error": "provisioning_failed", "detail": "…" }
```

Hors contrat, réservés à un client bogué : `400 {"error":"invalid_request","detail":…}` (corps
illisible, `device_id` absent ou hors `[A-Za-z0-9._-]{1,64}`) et `405 {"error":"method_not_allowed"}`.
`device_name` est facultatif (défaut « Mood », coupé à 100 caractères).

## Fichiers

| Fichier | Rôle | Déployé |
|---|---|---|
| `index.ts` | point d'entrée (`Deno.serve`) | oui |
| `handler.ts` | le parcours : auth, login / inscription, profil, réponses | oui |
| `lib.ts` | fonctions pures : localpart, mot de passe, corps Matrix, mapping d'erreurs | oui |
| `lib_test.ts`, `handler_test.ts`, `testing.ts` | tests Deno, hors ligne | non |

Aucune dépendance : seulement `fetch`, `crypto.subtle`, `AbortController`.

## Variables d'environnement

| Variable | Fournie par | Usage |
|---|---|---|
| `SUPABASE_URL` | Supabase (auto) | appels Auth et PostgREST |
| `SUPABASE_PUBLISHABLE_KEYS` ou `SUPABASE_ANON_KEY` | Supabase (auto) | `apikey` pour `GET /auth/v1/user` |
| `SUPABASE_SECRET_KEYS` ou `SUPABASE_SERVICE_ROLE_KEY` | Supabase (auto) | lecture / écriture de `public.profiles` |
| `MATRIX_HOMESERVER_URL` | **secret à créer** | URL publique du serveur, renvoyée telle quelle à l'app : `https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443` |
| `MATRIX_REGISTRATION_TOKEN` | **secret à créer** | même valeur que `~/mood-server/registration_token` sur le Studio |
| `MATRIX_PASSWORD_PEPPER` | **secret à créer** | 32 caractères minimum, celui de `~/mood-server/.env` |

- Les nouvelles clés `sb_…` (dictionnaires JSON, clé `default`) sont préférées aux anciennes
  clés JWT, que Supabase retire fin 2026. Les clés `sb_` partent dans `apikey` seulement.
- Les valeurs sont nettoyées des espaces et retours à la ligne en trop (copier-coller).
- Le pepper est utilisé comme texte UTF-8 brut, il n'est pas décodé du base64.
- Si une variable manque : `500 provisioning_failed`, `detail: "missing_config: NOM, …"` (les
  noms seulement, jamais les valeurs).

**Coller les trois secrets** (Augustin) : Dashboard → Edge Functions → Secrets, ou depuis le
Studio, sans afficher les valeurs :

```bash
supabase secrets set --project-ref jxpgyblzymshyzbkgmat --env-file ~/mood-server/.env
```

(`~/mood-server/.env` doit contenir exactement ces trois variables, voir la fiche D : vérifier
avec `cut -d= -f1 ~/mood-server/.env`, qui n'affiche que les noms.) Pas besoin de redéployer
après un changement de secret.

**Ne change jamais `MATRIX_PASSWORD_PEPPER` une fois le premier compte créé** : tous les mots
de passe Matrix en dérivent. Après un changement, chaque compte existant répond
`matrix_credentials_rejected` tant que son mot de passe n'est pas réinitialisé côté serveur
(procédure dans `docs/OPS.md`, piste D).

## Déploiement

`verify_jwt` doit être **désactivé** (`supabase/config.toml` le fait pour la CLI). La fonction
vérifie elle-même chaque jeton auprès de Supabase Auth (`GET /auth/v1/user`), ce qui est plus
strict que le contrôle de la passerelle (une session révoquée est refusée). Avec la passerelle
activée, un jeton expiré recevrait le 401 de la passerelle au lieu de
`{"error":"not_authenticated"}`, et le contrôle ne comprend pas les nouvelles clés.

- **MCP Supabase** (session principale) : `deploy_edge_function` avec `name: "matrix-session"`,
  `entrypoint_path: "index.ts"`, `verify_jwt: false` et les fichiers `index.ts`, `handler.ts`,
  `lib.ts` (contenu tel quel, mêmes noms).
- **CLI** :
  `supabase functions deploy matrix-session --project-ref jxpgyblzymshyzbkgmat --no-verify-jwt`

## Tests

Hors ligne (46 tests, aucune connexion réseau) :

```bash
deno test supabase/functions/matrix-session/      # Studio : /opt/homebrew/bin/deno
```

`lib_test.ts` couvre les fonctions pures, avec deux vecteurs HMAC fixes (RFC 4231 cas 2, et un
vecteur Mood calculé indépendamment avec `openssl`). `handler_test.ts` joue tout le parcours
contre un faux Supabase + faux Continuwuity : inscription UIAA, reconnexion sur le même
appareil, deux premiers appels simultanés, `M_USER_IN_USE`, jeton d'inscription refusé, pepper
différent, serveur coupé, Funnel 502, délai de 8 s, secrets absents, et vérifie qu'aucun secret
n'apparaît dans les journaux.

En réel, une fois la fonction déployée, les secrets collés et le serveur D en ligne :

```bash
scripts/test-matrix-session.sh <access_token_supabase>        # ou : … - < jeton.txt
REPEAT=1 scripts/test-matrix-session.sh - < jeton.txt         # + 2e appel : created=false, même appareil
```

Le script affiche le statut et le corps (jeton Matrix masqué), puis vérifie la session avec
`/_matrix/client/v3/account/whoami`. Le jeton Supabase n'est jamais affiché ni passé en argument
à `curl`. Obtenir un jeton pour un compte de test **déjà créé** (fourni par Augustin) :

```bash
curl -s "https://jxpgyblzymshyzbkgmat.supabase.co/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"…","password":"…"}' | sed -E 's/.*"access_token":"([^"]+)".*/\1/' > jeton.txt
```

Attendu : 1er appel `200`, `created: true`, `user_id` `@m<12 hex>:mood.local` ; 2e appel `200`,
`created: false`, même `user_id` et même `device_id` ; `profiles.matrix_user_id` et
`matrix_homeserver` remplis.

## Comportement

1. **Auth** : `Authorization: Bearer` absent → 401 sans aucun appel. Sinon `GET /auth/v1/user` ;
   400/401/403/404 → 401. Supabase Auth injoignable → **500**, pas 401 (l'app ne doit pas
   déconnecter l'utilisateur pour une panne Supabase).
2. **Identifiants** : id Supabase en minuscules (attention, `UUID.uuidString` en Swift est en
   majuscules) ; localpart `m` + 12 premiers hex ; mot de passe
   `base64url(HMAC-SHA256(pepper, id))`, sans `=` (43 caractères).
3. **Matrix** : `POST /login` (`m.login.password`, `m.id.user`, `device_id`,
   `initial_device_display_name`). `M_FORBIDDEN` → `POST /register` : 1er tour sans `auth`
   (401 + `session`), 2e tour avec `m.login.registration_token` (`m.login.dummy` aussi géré).
   `M_USER_IN_USE` → nouveau `/login`. Le même `device_id` réutilise le même appareil Matrix :
   Continuwuity remplace son jeton, il n'y a pas de multiplication des sessions.
4. **Appels simultanés** (Mac et iPhone au premier lancement) : les deux calculent le même mot
   de passe ; l'un inscrit, l'autre tombe sur `M_USER_IN_USE` et se connecte. Testé.
5. **Nom d'affichage** (compte neuf seulement, ou profil jamais relié) : `profiles.display_name`,
   sinon la partie avant `@` de l'e-mail, sinon les noms Discord de l'Auth ; 64 caractères max.
   Il remplace le nom par défaut de Continuwuity (`localpart` + suffixe).
6. **Profil** : `matrix_user_id` / `matrix_homeserver` écrits par upsert (clé secrète) seulement
   s'ils diffèrent. Un échec d'écriture (ou du nom d'affichage) n'empêche pas la session : il
   est journalisé et l'appel suivant réessaie. Un ancien lien Matrix manuel est remplacé
   (journal `replaced_other_link: true`).
7. **Délais** : 8 s par requête, 25 s pour l'appel entier. Délai dépassé, connexion refusée ou
   réponse 502/503/504 du Funnel → `503 homeserver_unreachable`.
8. **Journaux** (Dashboard → Edge Functions → matrix-session → Logs) : une ligne JSON par appel
   (`outcome`, `path`, `created`, `user` = localpart, `ms`, et `stage` / `reason` / `detail` en
   cas d'échec). Jamais de jeton, mot de passe, pepper, corps de requête ou texte libre renvoyé
   par le serveur Matrix.

## Valeurs de `detail` (500)

| `detail` | Cause | Que faire |
|---|---|---|
| `missing_config: …` | secret absent ou pepper < 32 caractères | coller les secrets |
| `supabase_auth_unreachable (…)` / `supabase_auth_failed (HTTP n)` | Supabase Auth en panne | réessayer |
| `matrix_register_failed: registration_token_rejected: M_FORBIDDEN` | le jeton Supabase ≠ `~/mood-server/registration_token` | recoller le bon jeton |
| `matrix_register_failed: M_FORBIDDEN (HTTP 403)` | inscriptions fermées sur le serveur | `allow_registration = true` (fiche D) |
| `matrix_register_failed: uiaa_unsupported_flows: …` | le serveur exige une autre étape (captcha, e-mail) | revoir la config du serveur |
| `matrix_credentials_rejected` | le compte existe mais refuse le mot de passe dérivé : pepper changé, ou collision de localpart | réinitialiser le mot de passe côté serveur |
| `matrix_login_failed: M_USER_DEACTIVATED (HTTP 403)` | compte Matrix désactivé | admin du serveur |
| `matrix_user_id_mismatch` | le serveur a renvoyé un autre utilisateur | vérifier `MATRIX_HOMESERVER_URL` |
| `matrix_login_failed: no_errcode (HTTP 404)` | l'URL ne mène pas à un serveur Matrix | vérifier `MATRIX_HOMESERVER_URL` / le Funnel |
| `internal_error` | bogue de la fonction | lire les journaux |

## Limites connues

- **Premier compte = admin** : Continuwuity donne les droits d'admin au premier compte inscrit.
  Le compte de test `@moodtest1` de la piste D doit être créé **avant** tout compte Mood.
- **Collision de localpart** : 48 bits (12 hex). Probabilité négligeable pour le MVP ; en cas de
  collision le second utilisateur reçoit `matrix_credentials_rejected` (aucun accès au compte
  de l'autre, les mots de passe diffèrent).
- **`profiles.matrix_user_id` modifiable par l'utilisateur** (politique RLS « update own
  profile », utilisée par l'ancien écran « Relie ton compte Matrix »). Quelqu'un peut y écrire
  l'identifiant Matrix d'un autre ; la contrainte `unique` fait alors échouer l'écriture du vrai
  propriétaire (journalisé, non bloquant). À fermer quand le lien manuel disparaît, par une
  migration qui retire `update` sur la table à `authenticated` puis le rend colonne par colonne
  (`display_name`, `avatar_url`, champs Discord) — un `revoke` sur deux colonnes seules ne suffit
  pas tant que le droit existe sur toute la table.
- **Double appel pour le même appareil** : le second `/login` remplace le jeton du premier.
  L'app doit garder la dernière réponse (ou ne pas lancer deux appels en parallèle).
