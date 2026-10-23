# Exploitation du serveur Mood

Tout appartient à l'utilisateur Adm. Binaire et données : `~/mood-server`.
Identité définitive : `mood.local`. Aucune fédération. Écoute locale : 6167.
Adresse publique : `https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443`.
Les commandes ci-dessous concernent uniquement Mood. Ne jamais réinitialiser Funnel :
443 publie une autre application et doit rester intact.

## Démarrer, arrêter, redémarrer

```bash
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/app.mood.server.plist
launchctl kickstart -k "gui/$(id -u)/app.mood.server"
```

Pour un arrêt volontaire prolongé, arrêter la surveillance et les sauvegardes avant le serveur :

```bash
launchctl bootout "gui/$(id -u)/app.mood.healthcheck"
launchctl bootout "gui/$(id -u)/app.mood.backup"
launchctl bootout "gui/$(id -u)/app.mood.featurecheck"
launchctl bootout "gui/$(id -u)/app.mood.server"
```

Relancer les quatre agents avec `server/install.sh` depuis ce dépôt.
Les LaunchAgents démarrent à l'ouverture de session de Adm, pas avant une connexion utilisateur.

```bash
curl --fail --silent http://127.0.0.1:6167/_matrix/client/versions
/Applications/Tailscale.app/Contents/MacOS/Tailscale funnel status
```

Pour publier ou rétablir uniquement Mood :

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale funnel --bg --https=8443 http://127.0.0.1:6167
```

## Journaux et surveillance

`~/Library/Logs/MoodServer/app.mood.server{,.error}.log` ; fichiers analogues pour
`app.mood.healthcheck` et `app.mood.backup`. Niveau serveur `warn`.
Ne jamais activer un journal HTTP détaillé, afficher `.env`, ni copier des réponses de connexion.
La configuration désactive le mode premier démarrage qui imprime un jeton sur stderr.
`admins_list` reste vide et l'appartenance au salon administrateur ne donne pas de privilèges.
Les prévisualisations sont limitées à GitHub, YouTube et Wikipédia, 256 Ko, délai 15 secondes ;
les plages IP privées restent interdites par les valeurs amont.

La surveillance s'exécute toutes les cinq minutes : versions locales et HTTPS public 8443,
espace libre (alerte sous 10 Gio), journaux et dernière sauvegarde **vérifiée** (alerte
au-delà de 36 h). Elle **ne redémarre jamais le serveur**. Les alertes horodatées sont
écrites dans `~/Library/Logs/MoodServer/alerts.log` (600), avec demande de notification
macOS locale. L'affichage dépend des autorisations Notifications et de la session graphique.
La sauvegarde pose `~/mood-server/maintenance.lock` ; les sondes réseau et le contrôle
fonctionnel la respectent. Ne retirer ce verrou qu'après vérification qu'aucune sauvegarde
n'est en cours. Une copie `.snapshot.*` laissée par un échec reste privée : la vérifier et
la chiffrer avec `encrypted-backup.py encrypt` avant de supprimer le clair.

Rotation automatique au seuil de 10 Mio, contrôlée toutes les cinq minutes : chaque
`*.log` garde sept archives `.1` à `.7`. Copie puis troncature du fichier ouvert : aucun
redémarrage. Ce seuil peut être dépassé entre deux contrôles ; quelques lignes écrites
pendant la copie peuvent être perdues (limite du mécanisme copytruncate).

`app.mood.featurecheck` lance chaque jour à 05 h 15 `feature-check.py --local --summary-only`.
Seuls les compteurs PASS/FAIL/INFO sont journalisés. Le test crée ses propres comptes
jetables puis les désactive ; il ne modifie aucun compte utilisateur existant. Deux FAIL
connus restent présents : recherche sans salon commun et `/notifications` non implémenté.
Une interruption ou une impossibilité de nettoyage doit être examinée, pas déclarée réussie.

## Sauvegardes chiffrées et restauration

`~/mood-server/scripts/backup.sh`, chaque jour à 04 h 15, décharge uniquement Mood,
attend la fermeture de RocksDB, copie données, médias, configuration et secrets dans un
dossier privé et vérifie le manifeste SHA-256. Il recharge immédiatement le serveur,
y compris en cas d'erreur de copie, avant l'archivage chiffré. Il diffuse ensuite le tar
directement dans `age` : aucun tar en clair persistant. Il déchiffre dans un espace temporaire
privé, compare le manifeste, publie atomiquement `~/Backups/mood-server/AAAA-MM-JJ.tar.age`,
puis supprime le snapshot clair. Les sept dernières dates réussies sont conservées.
Le marqueur privé `~/mood-server/backup.success` n'est mis à jour qu'après réussite.
Une archive chiffrée erronée ne remplace pas la précédente sauvegarde vérifiée.

Clé publique : `server/backup-recipient.txt` (suivie par git, non secrète).
Clé privée : `~/mood-server/backup-identity.age-key` (600, jamais incluse dans une sauvegarde).
Sans cette clé privée, les archives sont irrécupérables.

### À faire par Augustin : sortir la clé du Studio

1. Importer le fichier privé directement dans un gestionnaire de mots de passe fiable,
   ou le copier sur une clé USB conservée en lieu sûr ; ne pas le coller dans une conversation,
   un journal ou un dépôt. Garder idéalement deux copies indépendantes protégées.
2. Vérifier la copie externe avec la commande de restauration ci-dessous, en donnant
   son chemin à `--identity`. Ne jamais afficher le contenu de la clé.
3. Après cette preuve, retirer `~/mood-server/backup-identity.age-key` du Studio et vider
   les éventuelles copies temporaires / corbeille. Sur SSD, effacer un fichier ne garantit
   pas l'effacement physique des blocs : activer aussi FileVault dans Réglages Système.

**Tant que la clé privée reste sur le Studio, le chiffrement ne protège pas contre le vol
du Studio.** FileVault reste à activer par Augustin. Les données actives restent sur ce disque.
Les archives sur le même disque ne protègent pas non plus contre une panne physique :
les copier sur un support externe, séparément de la clé.

La vérification automatique par déchiffrement nécessite une identité accessible : après
retrait de la clé locale, fournir une clé USB protégée montée via `MOOD_BACKUP_IDENTITY`
dans `EnvironmentVariables` de **l'agent de sauvegarde uniquement**, puis recharger cet
agent (jamais le serveur). Pour un lancement manuel :

```bash
MOOD_BACKUP_IDENTITY=/Volumes/RECOVERY/backup-identity.age-key ~/mood-server/scripts/backup.sh
```

Si aucune identité n'est accessible, le script refuse **avant toute coupure** ; les sauvegardes
ne se renouvellent plus et une alerte apparaîtra après 36 h. Un support de clé connecté au
Studio et volé avec lui n'offre pas la séparation recherchée. Il faut donc choisir entre
vérification automatique avec clé accessible et vérification manuelle avec clé hors ligne ;
le script fourni privilégie la vérification obligatoire et refuse de simuler son succès.

### Vérifier / tester une archive

```bash
python3 ~/mood-server/scripts/restore-test.py ~/Backups/mood-server/AAAA-MM-JJ.tar.age --identity /Volumes/RECOVERY/backup-identity.age-key
```

Ce test vérifie le manifeste, démarre une copie sur **127.0.0.1:6168**, vérifie la connexion
au compte local de test et le message témoin puis arrête le processus isolé. Il nécessite
`~/mood-server/test-account.json` et `test-proof.json` (preuves locales privées, à conserver
séparément pour rejouer ce test après une perte totale du Studio). Le dossier `restore-test`
reste privé ; le supprimer après vérification qu'aucun processus n'écoute sur 6168, avant
de recommencer. Le test n'ouvre aucun Funnel et ne remplace jamais la base active.

Pour une restauration de production : arrêter d'abord santé, sauvegarde, contrôle quotidien,
puis serveur. Extraire vers un **nouveau** dossier privé avec :

```bash
python3 ~/mood-server/scripts/encrypted-backup.py extract /chemin/AAAA-MM-JJ.tar.age /chemin/prive/nouveau-dossier --identity /Volumes/RECOVERY/backup-identity.age-key
```

Le script refuse les chemins dangereux/liens et vérifie le manifeste avant réussite.
Conserver l'ancien `data`, recopier le `data` vérifié avec `ditto` ; restaurer configuration
et secrets seulement si nécessaire, permissions 600. Ne jamais fusionner deux bases RocksDB.
Réinstaller avec `server/install.sh`, vérifier versions locales et publiques, connexion et sync.
Ne jamais utiliser une commande de restauration sur un service actif.

## Mise à jour

Consulter les releases et notes officielles :
<https://forgejo.ellis.link/continuwuation/continuwuity/releases>.
Faire une sauvegarde, récupérer le tag stable dans `~/mood-server/src`, compiler
`cargo build --release --locked` (voir les adaptations macOS dans SERVER-SETUP),
puis remplacer le binaire seulement une fois compilé. Garder l'ancien binaire pour retour arrière.
Redémarrer et refaire le test local et public. Une migration de base peut imposer de restaurer
le snapshot avec l'ancien binaire : ne pas rétrograder directement une base migrée.

## Rotation des secrets

Ne pas utiliser de commande qui affiche le secret ni de `set -x`.
Générer avec `openssl rand -base64 48` en capturant sa sortie dans un programme local,
jamais vers le terminal. Écrire les fichiers privés avec umask 077 et permissions 600.

Jeton d'inscription : remplacer ensemble `registration_token` et
`MATRIX_REGISTRATION_TOKEN` dans `.env`, charger le même nouveau secret dans Supabase,
puis redémarrer Mood et vérifier le flux UIAA. La rotation ne change pas les comptes existants.
Les anciens snapshots contiennent encore l'ancien secret et doivent rester privés.

Pepper : **ne pas remplacer uniquement la variable**. Cela changerait tous les mots de passe
dérivés. Il faut une migration coordonnée de la fonction de provisionnement et des comptes
existants (ancien pepper temporairement conservé dans un stockage privé, mise à jour du mot
de passe à la prochaine connexion, puis retrait de l'ancien). Aucun automatisme de migration
n'est fourni par la piste D. Ne jamais envoyer le pepper dans un message ou un log.
Les secrets Supabase sont à saisir dans leur interface privée par le propriétaire ; aucun compte
externe ni secret en ligne n'est créé par ce déploiement.

## Studio éteint ou indisponible

Le serveur et Funnel deviennent inaccessibles ; les appareils conservent leur file d'envoi.
Rallumer le Studio, ouvrir la session Adm, vérifier les trois LaunchAgents, le port 6167
et Funnel 8443. Le redémarrage automatique ne répare pas une box ni une coupure électrique.

## Nouveau domaine

Ne jamais changer `server_name` sur cette base. Les identifiants Matrix et les salons
contiennent `mood.local`. Installer un nouveau serveur avec le domaine définitif dans une
base distincte, sauvegarder l'ancien, recréer/provisionner les identités Mood et les salons,
puis migrer les données compatibles et les associations Supabase. Prévoir une transition
avec historique de l'ancien serveur conservé ; la fédération est une décision séparée.
