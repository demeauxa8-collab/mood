# Durcissement serveur Mood — piste P

Exécuté le 15 octobre 2026 dans `~/mood-codex-P`, branche `codex/server-hardening`.
Aucun envoi GitHub, aucune modification Supabase. Les services exclus, les applications,
les comptes utilisateurs existants et la configuration Funnel sont restés inchangés.

## Réalisé et installé

- `age` 1.3.2 installé. Identité privée créée une seule fois, permissions 600, jamais affichée
  ni incluse dans une sauvegarde. Seul le destinataire public est suivi par git.
- `backup.sh` conserve la copie froide et le manifeste ; le service reprend avant le
  chiffrement. Tar diffusé dans age, déchiffrement privé et comparaison au manifeste,
  publication atomique puis suppression du clair. Sept dernières dates conservées.
  Sur erreur, le snapshot clair reste privé pour récupération ; le marqueur de succès ne bouge pas.
- Deux anciennes sauvegardes converties et vérifiées : `2026-10-14.tar.age` et
  `2026-10-15.tar.age`. Le second fichier a ensuite été remplacé par la sauvegarde froide du test.
  Aucun dossier quotidien en clair ne reste dans `~/Backups/mood-server`.
- `restore-test.py` accepte une archive age et une identité externe ; restauration isolée
  uniquement sur 6168. Les anciennes et nouvelles copies de test en clair ont été supprimées
  après succès et arrêt du processus isolé.
- Surveillance toutes les cinq minutes : disque < 10 Gio, sauvegarde > 36 h ou absente,
  versions locales et publiques HTTPS 8443, taille des journaux. Alertes privées horodatées,
  demande de notification macOS locale. La santé ne redémarre plus automatiquement Mood.
- Rotation copytruncate à 10 Mio, sept archives par journal, sans redémarrage.
- Quatrième agent `app.mood.featurecheck`, quotidien 05 h 15 : contrôle local et compteurs
  seuls, aucune réponse ni trace détaillée dans les journaux.
- Propositions non appliquées dans `server/continuwuity.proposed.toml.diff` : noms et
  aperçus de liens, avec raison/risque. La source 26.9.1 ne contient pas d'option native
  de durée de rétention des médias ou de débit global : aucune fausse clé ajoutée.

## Preuves d'exécution

| Contrôle | Résultat |
|---|---|
| Syntaxe shell, compilation Python, quatre plist | PASS |
| Chiffrement/déchiffrement synthétique et suppression du clair | PASS |
| Archive tronquée et manifeste altéré | Refusés ; clair conservé en cas d'échec de vérification |
| Conservation sept archives parmi dix dates synthétiques | PASS |
| Rotation répétée avec descripteur ouvert, sept fichiers | PASS ; écriture continue dans le journal d'origine |
| Alertes simulées disque, âge sauvegarde, réseau local/public | Quatre lignes attendues, dans un dossier temporaire isolé |
| Notification macOS du test simulé | `osascript` accepte la demande ; affichage visuel non vérifié |
| Installation `server/install.sh` | Quatre agents chargés ; aucun rechargement du serveur |
| Sauvegarde froide prévue, 17:48 UTC | PASS ; sauvegarde chiffrée et vérifiée à 17:48:46Z |
| Retour versions local / public | 7,46 s / 7,59 s après première indisponibilité ; HTTP 200 final |
| Durée totale de ce test | 8,68 s, donc retour en moins d'une minute |
| Restauration réelle depuis `2026-10-15.tar.age` | PASS manifeste, démarrage isolé, connexion et message original |
| Santé installée, puis lancée par LaunchAgent | PASS ; aucune indisponibilité ni alerte réelle lors du contrôle |
| Contrôle fonctionnel installé, `--local --summary-only` | PASS=137, FAIL=2, INFO=24 ; sortie non nulle conservée |
| Deux FAIL connus | Recherche d'utilisateurs sans salon commun ; endpoint `/notifications` absent |
| Funnel consulté en lecture seule | 443 → 8000 et 8443 → 6167 toujours présents |

Le contrôle fonctionnel crée ses propres comptes jetables et les désactive ; il laisse
éventuellement leurs médias/salons de test dans la base, comme le banc existant. Les FAIL
connus restent visibles, sans les transformer en succès. Aucun test UI SwiftUI n'est concerné.

## Ce qu'Augustin doit encore faire

**Mettre la clé privée hors du Studio**, en suivant `docs/OPS.md` : copie protégée dans un
gestionnaire de mots de passe ou sur USB, test avec la copie externe, puis retrait local.
La clé privée est encore sur le Studio (600). **En l'état, le chiffrement des sauvegardes
ne protège donc pas contre le vol du Studio.** FileVault est aussi à activer par Augustin.

Attention : vérifier automatiquement un déchiffrement nécessite la clé. Après retrait,
configurer `MOOD_BACKUP_IDENTITY` vers un support externe accessible au moment de la sauvegarde,
ou organiser sa présence uniquement lors des vérifications. Sans clé disponible, le script
refuse avant arrêt du serveur et la sauvegarde vieillit (alerte après 36 h). Une clé USB volée
avec le Studio n'offre pas de protection contre ce vol. La sauvegarde sur le même disque
ne protège pas d'une panne de disque : conserver aussi les archives ailleurs, séparées de la clé.

La rotation est vérifiée toutes les cinq minutes, pas à chaque écriture ; elle peut dépasser
le seuil entre contrôles et perdre quelques lignes simultanées à la troncature. Les notifications
peuvent être masquées par les autorisations macOS ; `alerts.log` reste la référence.
Les réglages de serveur attendent une fenêtre de maintenance décidée par Augustin.

## Incident de validation — contrainte de coupure unique dépassée

Après le test prévu, un test de précondition avec un dossier temporaire et une identité
absente a provoqué **une seconde interruption non autorisée** vers 17:51 UTC. En Bash,
`set -e` ne quitte pas sur le premier échec d'une liste `test && test` ; le script a donc
continué jusqu'au `bootout` réel. La copie a échoué car le dossier de test n'avait pas de
données, et le trap a rechargé le serveur. Le dossier temporaire de sauvegarde était vide.
Aucune base active ni archive existante n'a été remplacée lors de cet incident.

Correction : chaque précondition utilise maintenant un refus explicite `|| exit 1`.
Le test de régression remplace toutes les commandes launchctl par un stub interdit ;
il prouve qu'une clé ou un destinataire absent refuse avant verrou et commande de service.
Aucun nouveau test de coupure n'a été effectué. Le serveur local répond HTTP 200 et
l'accès public 8443 également ; la surveillance repasse PASS à 17:52:22 UTC.
Deux alertes de disponibilité ont été consignées pendant l'incident. La durée exacte
de cette seconde interruption n'a pas été mesurée. Cette contrainte du brief n'a donc
pas été respectée, malgré la restauration réussie et la correction vérifiée.
