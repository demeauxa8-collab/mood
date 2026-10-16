# Serveur Mood — installation et preuves (piste D)

Déploiement natif sur le Studio, réalisé depuis `~/mood-codex-D`, branche `codex/server`.
Aucun envoi GitHub. Aucune modification des applications et services exclus par le brief.

## Version et compilation

Release stable : **Continuwuity 26.9.1**, publiée le 28 septembre 2026.
Tag `v26.9.1`, commit `046074bbc2c8d1af6dd86f93e1c512fbd8b78da8`.
Source : [release officielle](https://forgejo.ellis.link/continuwuation/continuwuity/releases/tag/v26.9.1).
Le miroir GitHub était en retard ; la version a été choisie via l'API du dépôt officiel.

```bash
git clone --depth 1 --branch v26.9.1 https://forgejo.ellis.link/continuwuation/continuwuity.git ~/mood-server/src
cd ~/mood-server/src
cargo build --release --locked
```

Compilation avec Rust Homebrew 1.96.0, architecture arm64 Apple ; journal hors dépôt
`~/mood-server/build.log`. Le fichier amont rust-toolchain demande 1.98.1, mais le Cargo
Homebrew ne passe pas par rustup : la compilation réellement utilisée est notée ici.
Binaire amont `conduwuit`, installé sous le nom `~/mood-server/bin/continuwuity`.

## Configuration et confidentialité

Gabarit : `server/continuwuity.example.toml`. Identité `mood.local`, écoute seulement
127.0.0.1:6167, fédération désactivée, inscription par jeton, requêtes limitées à 25 Mio,
présence locale, saisie et accusés de lecture activés. Prévisualisations limitées à une
liste explicite, 256 Ko, 15 secondes ; interdiction amont des IP privées conservée.
Aucun administrateur déclaré, pas d'attribution de droits via le salon admin.

**Adaptation de la 26.9.1 :** le mode premier démarrage affiche normalement un jeton
sur stderr et donne les droits admin au premier compte. `force_disable_first_run_mode = true`
désactive ce comportement : le jeton de fichier est utilisé dès le premier compte.
Cette option amont est prévue pour les tests Complement ; son utilisation ici répond
aux exigences de confidentialité et d'absence d'administrateur automatique du brief.
Elle doit être revalidée lors de chaque mise à jour.

Les secrets sont générés par `openssl rand -base64 48`, capturés en mémoire, puis écrits
uniquement dans `~/mood-server/registration_token` et `~/mood-server/.env`, permissions 600.
Le dossier racine est privé (700). Aucun secret réel dans les gabarits, commits ou preuves.
Le compte `moodtest1` est uniquement local à ce serveur ; son mot de passe de test reste
dans `~/mood-server/test-account.json` privé. Aucun compte auprès d'un fournisseur externe.

## Services

Gabarits LaunchAgents dans `server/`, installation par `server/install.sh` :

- `app.mood.server` : RunAtLoad + KeepAlive ; logs `~/Library/Logs/MoodServer`.
- `app.mood.backup` : sauvegarde froide quotidienne à 04 h 15, sept archives age vérifiées retenues.
- `app.mood.healthcheck` : toutes les cinq minutes, alertes réseau/disque/journaux/sauvegarde, sans relance du serveur.
- `app.mood.featurecheck` : chaque jour à 05 h 15, contrôle local avec résumé seul.

Les agents fonctionnent après ouverture de session Adm. Le Studio doit rester allumé.
Le script de sauvegarde est la seule interruption programmée du serveur Mood.

## Vérifications

Résultats d'exécution ajoutés après déploiement ci-dessous. Les scripts ne montrent
que des verdicts et ne journalisent pas les réponses contenant des jetons.

Contrôles déjà exécutés : syntaxe des scripts shell/Python, validation des trois plist,
rejet d'un snapshot altéré, conservation de sept snapshots parmi neuf jeux synthétiques.

### Résultats réels — 14 octobre 2026, 13:05–13:10 UTC

| Contrôle | Résultat |
|---|---|
| Compilation `cargo build --release --locked` | `Finished release profile [optimized] target(s) in 9m 14s` |
| Binaire installé `--version` / `file` | `continuwuity 26.9.1 (046074b)` ; Mach-O arm64 |
| `curl http://127.0.0.1:6167/_matrix/client/versions` | HTTP 200, versions jusqu'à v1.18 |
| `python3 server/verify.py` | Inscription de `@moodtest1:mood.local` par UIAA, mauvais jeton refusé, connexion et message relu dans `/sync` : PASS |
| `python3 server/verify.py https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443` | Versions, connexion, salon, envoi et `/sync` : PASS |
| URL HTTPS 8443, TLS vérifié | HTTP 200 ; vérification TLS 0 |
| Funnel via son entrée Internet publique | HTTP 200 ; IP distante 176.58.90.46 ; vérification TLS 0 |
| `funnel status` après publication et après tests | 443 → 127.0.0.1:8000 et 8443 → 127.0.0.1:6167 coexistent |
| Interruption du processus Mood par SIGKILL | KeepAlive relance un nouveau processus ; versions répondent : PASS |
| `launchctl kickstart -k gui/502/app.mood.server` | Nouveau processus, versions répondent : PASS |
| Surveillance, serveur figé par SIGSTOP | Premier échec sans redémarrage ; deuxième échec avec redémarrage et compteur effacé : PASS |
| `~/mood-server/scripts/backup.sh` | `2026-10-14T13:06:23Z backup verified` ; snapshot `~/Backups/mood-server/2026-10-14` |
| `python3 server/restore-test.py ~/Backups/mood-server/2026-10-14` | Manifeste vérifié, base copiée, serveur isolé sur 6168, connexion et message original retrouvés : PASS |
| Fin du test de restauration | Processus isolé arrêté ; seul 127.0.0.1:6167 reste à l'écoute |
| Confidentialité | Secrets et mot de passe test absents des fichiers suivis et des journaux serveur ; fichiers privés à 600 : PASS |
| LaunchAgents en fin de mission | Serveur chargé/running ; sauvegarde et santé chargés/en attente de leur échéance |

Le DNS local Tailscale résout le nom vers l'adresse tailnet du Studio. Pour prouver
l'accès par l'entrée **Internet** de Funnel, une deuxième requête utilise l'adresse
résolue par DNS public (`dig @1.1.1.1`), avec certificat et nom HTTPS conservés :

```bash
curl --resolve mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443:176.58.90.46 \
  --fail --silent --show-error --max-time 30 \
  https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443/_matrix/client/versions
```

Cette IP est une observation datée, pas une adresse à inscrire dans l'app ; le nom
HTTPS reste l'adresse stable. Le test inscription/connexion utilise `curl --config -`
avec corps et en-têtes sur stdin : aucun mot de passe ni jeton dans les arguments de
processus ou les sorties. La réponse UIAA et les jetons de session restent en mémoire.

Les données de test restent dans la base (compte local `moodtest1` et salons de vérification).
Son mot de passe privé et la référence du message restent hors dépôt. Le snapshot et
la copie restaurée sont conservés pour examen. Le test de restauration nécessite ces
fichiers de preuve locaux ; les comptes Mood de production utilisent le pepper du snapshot.

## Hors piste D / à faire par l'intégration

Les trois secrets doivent être saisis dans l'interface privée des Edge Functions Supabase
par le propriétaire ; ils n'ont pas été envoyés à un fournisseur. La piste E puis F doit
valider le provisionnement et le parcours Mood complet. Les builds SwiftUI Mac/iPhone
et les tests de la journée relèvent des pistes app et de l'intégration ; aucun écran app
n'a été modifié ni déclaré validé ici. La permanence s'applique après connexion à la
session Adm ; un Studio éteint ne peut servir aucun utilisateur.

## Durcissement P — 15 octobre 2026

Scripts déployés depuis `~/mood-codex-P` par `server/install.sh`, sans recharger le serveur
existant. Dépendance locale supplémentaire : Homebrew `age` 1.3.2. Identité générée une seule
fois sous `~/mood-server/backup-identity.age-key` (600), destinataire public suivi dans le dépôt.
Deux anciennes sauvegardes converties ; sauvegarde à froid réelle puis restauration depuis
`.tar.age` réussies. Indisponibilité mesurée : environ 7,5 s en local et public pour le test prévu. Un test de précondition a ensuite provoqué
une seconde coupure involontaire ; cause, correction et état final dans SERVER-HARDENING.
Les preuves historiques en clair du 14 octobre ci-dessus sont remplacées par les archives age ;
les copies de restauration en clair ont été supprimées après le test P.

Rotation sans redémarrage (seuil 10 Mio, sept archives), alertes locales et contrôle quotidien
installés. Les réglages proposés ne sont pas appliqués ; voir
`server/continuwuity.proposed.toml.diff`. Aucune clé native de durée de rétention médias ou
limite globale de débit trouvée dans la source 26.9.1 : ces fonctions restent à concevoir,
sans inventer de paramètres. État, limites et consignes de clé hors Studio :
`docs/SERVER-HARDENING.md` et `docs/OPS.md`.
