# Plan backend — Mood (mis à jour le 14 octobre 2026)

**But :** un utilisateur crée **un seul compte (Mood)**, par e-mail ou par Discord, et discute tout de
suite : envoi, réception, médias, notifications. Il ne voit jamais le mot « Matrix ». Coût : **0 €**.

Lis d'abord `AGENTS.md`, `docs/HANDOFF.md`, puis ta fiche dans `docs/briefs/` (D à H).
Base de code commune : branche `codex/pixel-merge` (stable + Mood Pixels + comptes + iPhone).

---

## 1. Architecture

```
 App Mood (Mac / iPhone)
   │ ① connexion Mood (e-mail / Discord) ─────────────────► Supabase Auth            (fait)
   │ ② POST /functions/v1/matrix-session + jeton Supabase ─► Edge Function            (piste E)
   │       crée le compte Matrix au 1er appel (jeton d'inscription),
   │       puis ouvre une session Matrix par appareil
   │ ③ /sync, envoi, médias, salons ◄────────────────────► Continuwuity « mood.local » (piste D)
   │                                                     Mac Studio, 127.0.0.1:6167
   │                                                     publié par Tailscale Funnel :8443
   │ ④ notifications locales, sourdine (règles push)                                  (piste H)
```

| Décision | Valeur | Pourquoi |
|---|---|---|
| Serveur Matrix | **Continuwuity**, compilé en natif (Rust) sur le Studio | Un binaire, base RocksDB, peu de RAM ; Docker n'est pas démarré sur le Studio |
| `server_name` | **`mood.local`** (définitif pour ce serveur) | Réseau fermé, sans fédération. Un vrai domaine plus tard = nouveau serveur + migration |
| Adresse publique | **`https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443`** | Tailscale déjà connecté ; le port **443 est déjà pris par l'API ClipFactory (127.0.0.1:8000) : ne pas y toucher** |
| Fédération | **désactivée** (`allow_federation = false`) | Moins de surface, pas besoin de DNS |
| Inscription | **uniquement par jeton** (`m.login.registration_token`) | Personne ne crée de compte en direct sur le serveur |
| Mot de passe Matrix | **dérivé** : `base64url(HMAC-SHA256(MATRIX_PASSWORD_PEPPER, supabase_user_id))` | Rien à stocker, la fonction le recalcule à chaque connexion ; l'app ne le connaît jamais |
| Nom Matrix | `@m<12 premiers hex de l'id Supabase>:mood.local` | Stable, unique, sans donnée personnelle |
| Secrets | `MATRIX_REGISTRATION_TOKEN`, `MATRIX_PASSWORD_PEPPER`, `MATRIX_HOMESERVER_URL` | Seulement dans `~/mood-server/.env` (Studio) et les secrets des Edge Functions Supabase. **Jamais** dans git, le chat ou une capture. Augustin les colle dans Supabase |

## 2. Contrat d'API `matrix-session` (pistes E et F s'y tiennent)

```
POST {SUPABASE_URL}/functions/v1/matrix-session
Headers: Authorization: Bearer <access_token Supabase>, apikey: <clé publique>
Body:    { "device_id": "MOODMAC1A2B3C4D", "device_name": "Mood · Mac" }   // device_id stable par appareil

200 → { "homeserver": "https://…ts.net:8443", "user_id": "@m1a2b3c4d5e6f:mood.local",
        "access_token": "…", "device_id": "MOODMAC1A2B3C4D", "created": true|false }
401 → { "error": "not_authenticated" }        // jeton Supabase absent / expiré
503 → { "error": "homeserver_unreachable" }   // Studio éteint, Funnel coupé
500 → { "error": "provisioning_failed", "detail": "…" }
```
- Premier appel : inscription (avec le jeton), nom d'affichage = `profiles.display_name` ou partie
  avant @ de l'e-mail, puis `profiles.matrix_user_id` / `matrix_homeserver` remplis.
- Appels suivants : simple `/login` (mot de passe dérivé) avec le `device_id` reçu → même appareil
  Matrix réutilisé, pas de multiplication des sessions.

---

## 3. Pistes (en parallèle, une branche chacune)

| Piste | Qui | Branche | Fiche |
|---|---|---|---|
| **D — Serveur Matrix + exploitation** | Codex (Studio, `~/mood-codex-D`) | `codex/server` | `docs/briefs/D-server.md` |
| **E — Edge Function `matrix-session`** | Claude (Opus) | `claude/edge-matrix-session` | `docs/briefs/E-edge-function.md` |
| **F — App : connexion Matrix automatique** | Codex (Studio, `~/mood-codex-F`) | `codex/app-provisioning` | `docs/briefs/F-app-provisioning.md` |
| **G — Messagerie : envoi, médias, réception** | Claude (Opus) | `claude/messaging` | `docs/briefs/G-messaging.md` |
| **H — Notifications, sourdine, paramètres** | Claude (Sonnet) | `claude/notifications` | `docs/briefs/H-notifications.md` |

Intégration : Claude fusionne chaque piste dans `codex/pixel-merge` quand elle est verte
(build Mac + iPhone + tests), puis teste le parcours complet (§4).

## 4. Test de bout en bout (critère final de la journée)

1. Créer un compte Mood par e-mail → confirmer → **arriver sur Amis sans étape Matrix**.
2. Deuxième compte (deuxième appareil ou simulateur) → s'ajouter en ami → **MP dans les deux sens**.
3. Créer un serveur, un salon, inviter l'autre compte → messages, réponse, modification, réaction,
   suppression, épingle, image, fichier → **tout visible des deux côtés**.
4. Couper le réseau, envoyer 3 messages, rétablir → **partent dans l'ordre**.
5. Relancer l'app → **historique présent tout de suite** (cache) ; nouvelle connexion Mood sans
   question Matrix.
6. Couper le serveur (`launchctl kickstart -k`) → **il revient seul**, l'app se resynchronise.
7. Notification locale reçue pour un MP quand Mood est en arrière-plan ; un salon en sourdine n'en
   envoie pas.

## 5. Plus tard (hors de cette étape)
Connexion Matrix par jeton Supabase (JWT/OIDC), chiffrement de bout en bout (vodozemac),
fédération + vrai domaine, notifications push app fermée (APNs + Sygnal, compte Apple Developer),
signature de l'app (sinon le trousseau Mac est inutilisable), découpage de `MatrixStore`
(~2 300 lignes) en services.

## 6. Risques
| Risque | Parade |
|---|---|
| Studio éteint / box coupée | L'outbox garde les messages ; contrôle de santé + redémarrage auto ; à terme serveur cloud |
| Débit limité de Funnel | Suffisant pour démarrer ; limite d'envoi 25 Mo |
| Fuite du jeton d'inscription ou du « pepper » | Seulement dans `.env` (Studio, `chmod 600`) et secrets Supabase ; procédure de rotation dans `docs/OPS.md` |
| `server_name` définitif | `mood.local` assumé pour le MVP ; migration documentée le jour du vrai domaine |
| E-mails Supabase limités | SMTP gratuit (Resend) avant d'inviter des testeurs |

## 7. Règles pour tous les agents
- **Rien sur GitHub** sans le oui d'Augustin. Jamais de secret dans git, le chat, un log ou une capture.
- Ne pas toucher : serveur Minecraft, API ClipFactory (`127.0.0.1:8000`, Funnel 443), Redis, Ollama,
  `~/mood-desktop-pixel-lab`, `~/mood-build`, `~/Documents/mood`, les apps de `~/Applications`.
- Chaque piste se termine par une preuve (commande, capture, test) consignée dans `docs/`.
