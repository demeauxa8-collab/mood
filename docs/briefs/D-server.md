# Brief D — Serveur Matrix Mood sur le Mac Studio (Codex)

Branche `codex/server`, dossier `~/mood-codex-D`. Lis `docs/BACKEND-PLAN.md` (§1 décisions, §7 règles).
Les fichiers du dépôt vont dans `server/` (gabarits, scripts, plist) — **aucun secret dedans**.
Les données et secrets réels vivent hors du dépôt dans `~/mood-server/`.

## À faire
1. **Compiler Continuwuity** (dernière release stable) en natif : `cargo build --release` dans
   `~/mood-server/src`, binaire copié dans `~/mood-server/bin/continuwuity`. Note la version exacte.
2. **Config** `~/mood-server/continuwuity.toml` (gabarit commité : `server/continuwuity.example.toml`) :
   `server_name = "mood.local"`, `database_path = "/Users/Adm/mood-server/data"`,
   `address = ["127.0.0.1"]`, `port = 6167`, `allow_federation = false`,
   `allow_registration = true`, `registration_token_file = "/Users/Adm/mood-server/registration_token"`,
   `max_request_size = 26214400` (25 Mo), `allow_local_presence = true`,
   `allow_incoming_presence = false`, `allow_outgoing_presence = false`,
   `allow_local_typing = true`, `allow_local_read_receipts = true`,
   prévisualisations d'URL activées avec limites raisonnables, `admins_list` vide pour l'instant.
3. **Secrets** (générés sur le Studio, `openssl rand -base64 48`, fichiers `chmod 600`) :
   `~/mood-server/registration_token`, et `~/mood-server/.env` avec `MATRIX_REGISTRATION_TOKEN`,
   `MATRIX_PASSWORD_PEPPER`, `MATRIX_HOMESERVER_URL=https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443`.
   Ne les affiche jamais dans le journal, ne les commite jamais.
4. **Service permanent** `~/Library/LaunchAgents/app.mood.server.plist` (gabarit dans `server/`) :
   `RunAtLoad`, `KeepAlive`, journaux dans `~/Library/Logs/MoodServer/`.
5. **Publication** : `tailscale funnel --bg --https=8443 http://127.0.0.1:6167`
   (CLI : `/Applications/Tailscale.app/Contents/MacOS/Tailscale`). **Ne modifie pas** la règle
   existante `/ → http://127.0.0.1:8000` sur 443 (API ClipFactory). Vérifie avec `funnel status`
   que les deux coexistent.
6. **Sauvegarde** `server/backup.sh` + plist quotidien : copie cohérente de `data/` vers
   `~/Backups/mood-server/AAAA-MM-JJ/`, 7 jours gardés. **Fais une restauration de test** sur une copie.
7. **Santé** `server/healthcheck.sh` + plist toutes les 5 min : `GET /_matrix/client/versions` en
   local ; si échec 2 fois, `launchctl kickstart -k gui/$UID/app.mood.server`, trace dans les journaux.
8. **Preuves** (dans `docs/SERVER-SETUP.md`) :
   - `curl https://…ts.net:8443/_matrix/client/versions` OK ;
   - inscription d'un compte de test `@moodtest1:mood.local` par jeton avec `curl` (flux UIAA
     `m.login.registration_token`), connexion, envoi d'un message dans un salon, lecture par `/sync` ;
   - redémarrage forcé du service → revient seul ; sauvegarde + restauration testées.
9. `docs/OPS.md` : démarrer/arrêter/mettre à jour, voir les journaux, rotation du jeton et du pepper,
   restauration, que faire si le Studio est éteint, comment changer de `server_name` plus tard.

## Interdits
Pas de Docker, pas de modification du Funnel 443, du serveur Minecraft, de Redis/Ollama ni de
ClipFactory. Rien sur GitHub. Aucun secret dans les fichiers suivis, les captures ou le résumé final.
