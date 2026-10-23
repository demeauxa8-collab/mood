# E2EE — phase 1, fondation

## Périmètre

Travail local dans `~/mood-codex-O1`, branche `codex/e2ee-foundation`.
Aucune intégration dans MatrixStore, MatrixClient, outbox ou UI. Mood n'est donc pas encore un
client chiffrant ses conversations. Aucun badge E2EE ajouté. Aucun envoi GitHub, aucune app Mac
lancée, aucune configuration serveur, aucun Rust Homebrew et aucune donnée Supabase modifiés.
`Config.xcconfig` copié depuis le worktree de fusion, sans afficher son contenu.

## Résultats vérifiés le 15 octobre 2026

| Vérification | Résultat |
|---|---|
| Framework arm64 iPhone / simulateur / Mac Catalyst | Trois slices présentes dans Info.plist ; archives officielles liées |
| Reconstruction avec le script final | Réussie ; manifeste SHA-256 identique et Swift régénéré sans différence git |
| Taille du xcframework | 315 290 098 octets (environ 301 Mio), donc ignoré par git |
| Build Mood Mac Catalyst | `** BUILD SUCCEEDED **`, exécutable Mach-O arm64 inspecté sans lancement |
| Build Mood iPhone physique (generic/platform=iOS) | `** BUILD SUCCEEDED **` ; compilation, pas essai sur téléphone physique |
| moodTests sur Mood O1 iPhone (iPhone 17, iOS 27) | `** TEST SUCCEEDED **`, 142 réussis, 0 échec, 0 ignoré, aucun avertissement runtime |
| Alice/Bob en MemoryStore officiel | Clés générées, upload/query/claim simulés, partage Olm de clé Megolm, « bonjour » déchiffré |
| Tiers exclu | Déchiffrement refusé sans sa clé de salon |
| Stockage SQLite chiffré | Identité conservée après réouverture ; mauvaise passphrase refusée |
| Pont Swift | Refus d'envoi avant partage et refus d'acquitter une réponse d'erreur |
| Preuve locale sur Continuwuity en service | Upload clés, keys/query, keys/claim, to-device chiffré : PASS |
| Message réellement stocké | GET de l'événement envoyé : m.room.encrypted ; déchiffrement de ce contenu par Bob : PASS |
| Nettoyage des comptes o1check-* | Les deux comptes désactivés avec succès ; sorties sans secrets |
| Avertissements du pont et tests crypto dans les builds finaux | Aucun ; isolation @MainActor alignée avec les bindings |

Preuves locales (non commitées) : `build/O1/mac-build.log`, `iphone-build.log`,
`tests-verified.log`, `live-check.log`, `crypto-build.log`, `rebuild-check.log`.
Résultat final des tests :
`build/O1/Simulator/Logs/Test/Test-mood-2026.10.15_20-08-44-+0200.xcresult`.
Xcode utilise son clone de test « Clone 1 of Mood O1 iPhone » ; le résumé xcresult confirme
l'UUID du simulateur dédié, le modèle iPhone 17 et les 142 tests. Le simulateur iPhone 18 Pro
n'a jamais été utilisé par ces commandes. Un essai intermédiaire sans clonage (`-parallel-testing-enabled NO`)
n'a pas démarré correctement ; la collecte de diagnostics signalait simctl introuvable dans son
sous-processus. Le passage standard a ensuite réussi sur le code final. Aucun réglage global Xcode
ni service CoreSimulator partagé n'a été modifié pour contourner cet incident.

Ces preuves valident la fondation, pas l'intégration des conversations dans Mood. Rien ne chiffre
encore les envois ordinaires de l'app : cette activation relève exclusivement de la phase 2.

## Source et construction

Source officielle : https://github.com/matrix-org/matrix-rust-sdk/tree/matrix-sdk-crypto-ffi-0.17.0
Dernier tag stable dédié à la crate, vérifié avec `git ls-remote --tags` le 15 octobre 2026 :
`matrix-sdk-crypto-ffi-0.17.0`, commit `cf099deb272f2ef44a0b8b8f7afd96004c3a822a`.
Tag non signé (`git verify-tag` : no signature found) ; commit exact contrôlé avant compilation.
Aucune primitive cryptographique écrite dans Mood. Un patch de binding expose le constructeur
MemoryStore officiel pour les tests ; il ne change aucun algorithme.
Le numéro Cargo interne de la crate FFI reste 0.1.0 ; la version de distribution est celle du tag.
vodozemac 0.10.0 et UniFFI 0.31.0, dépendances du Cargo.lock officiel.

`./scripts/build-crypto.sh` suit les étapes du script Apple officiel
`bindings/apple/build_crypto_xcframework.sh` : compilation statique, génération UniFFI depuis
la bibliothèque, regroupement des en-têtes/modulemap, création du xcframework.
Adaptation : trois slices arm64, iPhone, simulateur et Catalyst (pas de x86_64 ni macOS natif).
Rust 1.93.0, minimum demandé par ce commit. Installation isolée dans `~/mood-toolchains`,
`--no-modify-path`, PATH limité au processus du script, Xcode sélectionné par DEVELOPER_DIR.
Une première installation 1.88.0 a été lancée avant lecture du MSRV ; elle n'est pas utilisée.
Cargo emploie `--locked`. Le script refuse un commit inattendu, tout fichier non suivi ou toute modification autre que
le patch de binding versionné, comparé intégralement à git diff.
Les binaires dépassent 50 Mo et restent hors git ; Swift généré et licence sont suivis.
Empreintes des fichiers dans `mood/Vendor/MatrixSDKCrypto/SHA256SUMS`.
Un autre SDK Apple, chemin absolu ou environnement peut changer les octets : ne pas confondre
épinglage des sources et garantie universelle de compilation bit à bit.

## Liaison Xcode

`project.pbxproj` : ajout d'une PBXFileReference explicite vers
`mood/Vendor/MatrixSDKCrypto/MatrixSDKCrypto.xcframework`, d'une PBXBuildFile dans la phase
Frameworks de la seule cible mood, et d'une référence visible dans le groupe principal.
Une exception du groupe synchronisé exclut ce même framework et les documents/manifestes
Vendor de l'inclusion automatique, pour éviter une seconde liaison ou leur copie en ressources.
Les fichiers Swift générés restent compilés via le groupe synchronisé. UniFFI produit trois
fichiers Swift et trois modules C qui partagent leurs types de buffers. Pour la règle Swift
`MemberImportVisibility` activée dans Mood, le script ajoute à chaque fichier Swift les trois
imports FFI explicites. Ce post-traitement ne modifie aucune logique générée, et évite de changer
les réglages Swift globaux du projet.
La bibliothèque est **statique** : son code est intégré à l'exécutable au lien ; aucune phase
Embed Frameworks / copie d'un framework dynamique n'est nécessaire ni souhaitable.

## Pont Swift et stockage

`CryptoEngine` est une classe @MainActor qui sérialise l'accès à OlmMachine et n'effectue aucun
appel réseau. Elle suit l'isolation du Swift généré dans cette cible MainActor. Les appels FFI sont
synchrones : avant intégration à l'UI en phase 2, isoler les bindings compilés dans un module dédié
non isolé et déplacer le travail bloquant sur un actor/exécuteur approprié, sans désactiver les
vérifications de concurrence du projet.
Il expose identité publique, requêtes sortantes, sync, acquittement, suivi des utilisateurs,
claim des sessions manquantes, partage Megolm, chiffrement et déchiffrement.
Le chiffrement refuse un salon dont le partage n'a pas été confirmé ; un nouveau passage de sync
invalide la confirmation locale. La phase 2 doit traiter toutes les requêtes de partage avant
confirmation. Les réponses HTTP ne doivent être acquittées qu'après succès et validation du schéma.
Le wrapper ne journalise aucune clé, passphrase, requête ou erreur du SDK.

Stockage : `Application Support/Mood/crypto/<userId encodé base64url>/<deviceId encodé>/`.
Le sous-dossier appareil évite de réutiliser accidentellement les sessions d'un autre appareil.
Passphrase aléatoire de 32 octets via Security/SecRandomCopyBytes, conservée par KeychainHelper.
Sur une app signée et avec accès au trousseau, elle va au trousseau ; sinon le helper existant
se replie sur `Application Support/Mood/credentials.json`, dossier 700, fichier 600.
Ce repli **ne protège pas contre la lecture du disque de la session macOS**. Ne pas annoncer
la protection équivalente au trousseau. Une clé manquante avec un stockage existant provoque un
échec, jamais une nouvelle clé silencieuse. Ne pas effacer ce secret au logout sans stratégie
cohérente de destruction/récupération du stockage. La gestion actuelle de logout/deleteAll devra
être revue en phase 2 avant toute intégration.

## Binding pour tests en mémoire

L'API Swift amont de ce tag ne propose que SQLite. Le patch versionné
`mood/Vendor/MatrixSDKCrypto/memory-store.patch` ajoute le constructeur UniFFI `new_in_memory` :
il appelle uniquement `matrix_sdk_crypto::OlmMachine::new`, donc le MemoryStore officiel.
Les tests Swift Alice/Bob/tiers utilisent ce constructeur, sans stockage disque ni trousseau.
Les chemins applicatifs et le test en direct utilisent le constructeur SQLite chiffré officiel.
Le patch est la seule divergence de source ; le script en contrôle l'intégralité avant compilation.

## Plan détaillé de phase 2

1. **Session et durée de vie.** Dans `MatrixStore.login(accessToken:userId:homeserver:deviceId:)`,
   `login(username:password:homeserver:)`, SSO et restauration, ouvrir l'engine après whoami et avant
   `startSyncLoop()`. Fixer un deviceId stable pour toute la durée du stockage. Annuler les tâches
   crypto et réseau à la déconnexion ; associer chaque opération à `syncGeneration`. Ne jamais
   partager une machine entre deux comptes/appareils. Bloquer l'envoi si le stockage est inaccessible.
2. **Contrats réseau.** Étendre MatrixClient avec POST `/keys/upload`, `/keys/query`, `/keys/claim`,
   PUT `/sendToDevice/{eventType}/{txnId}`, signature/backup aux phases concernées ; conserver les
   identifiants de requêtes SDK pour les reprises, ne pas générer un nouveau txnId à chaque retry.
   `Request.toDevice.body` contient la map utilisateurs/appareils : l'envelopper dans `messages`.
   N'appeler `markRequestAsSent` qu'après un vrai succès HTTP et réponse Matrix valide. Échecs 429
   avec retry_after_ms ; erreurs réseau sans acquittement. Ne jamais journaliser les bodies.
3. **Sync.** Étendre `MatrixSyncResponse` (MatrixClient.swift) pour `to_device`, `device_lists`,
   `device_one_time_keys_count`, `device_unused_fallback_key_types`. Dans `startSyncLoop`, avant
   `processSyncResponse`, appeler receiveSyncChanges, traiter les requêtes sortantes puis les
   événements de salon. Sauver le token next_batch uniquement après traitement crypto durable.
   Auditer `syncFilterJSON` (lazy_load_members) et récupérer les membres complets avant partage,
   ne pas déduire les destinataires des seuls auteurs déjà chargés.
4. **État des salons.** `processStateEvent` traite déjà `m.room.encryption` : mémoriser l'algorithme,
   traiter membership/history_visibility et changements d'appareils, invalider/renouveler les sessions
   via le SDK. Un salon annoncé chiffré ne repasse jamais automatiquement à l'envoi clair.
5. **Ordre d'envoi.** Dans le drain d'outbox de MatrixStore (appels client.sendRoomMessage / sendMessage),
   avant tout envoi : upload des clés → suivi/query des membres/appareils → claim des OTK manquantes
   → partage Megolm to-device et acquittements → chiffrement du contenu complet → PUT
   `/rooms/{roomId}/send/m.room.encrypted/{txnId}`. Sérialiser le claim et le partage par salon.
   Ajouter à MatrixClient une variante d'envoi avec eventType explicite. Chiffrer également edits,
   réponses, threads et mentions dans le contenu ; conserver seulement les métadonnées standard
   requises hors chiffrement. Persister le ciphertext et txnId avant retry pour éviter les doublons.
6. **Réception.** `processTimelineEvent` accepte déjà m.room.encrypted mais l'affiche en remplacement :
   déchiffrer avant le parsing commun des messages et avant notifications, mentions et recherche.
   Même pipeline pour pagination/contexte/réponses ; conserver l'événement chiffré pour réessai
   lorsqu'une clé arrive dans sync. Distinguer clé absente, événement invalide et confiance insuffisante.
   Ne jamais traiter un déchiffrement réussi comme une preuve que l'appareil est vérifié.
7. **Pièces jointes.** Dans `uploadAttachment(of:)` / chemins d'upload autour de MatrixStore.swift
   2945 et 2963 et `sendAttachment`, chiffrer fichier ET miniature avant upload via l'API officielle
   de chiffrement média du SDK. Ce tag FFI ne propose pas de binding média : prévoir un pont vers
   `matrix_sdk_crypto::file_encryption::{AttachmentEncryptor, AttachmentDecryptor}` et
   `MediaEncryptionInfo`, déjà présents dans le SDK ; aucune AES maison. Mettre les descripteurs
   `file`/`thumbnail_file` (clé, IV, hash) dans le contenu Megolm ; jamais dans Supabase ni les logs.
   Télécharger via endpoint média authentifié, vérifier le hash puis déchiffrer localement. Les chemins
   actuels d'outbox gardent du texte et des médias clairs : coordonner avec Q pour protection locale,
   purge et fichiers temporaires. Ne pas prétendre que la base crypto chiffre aussi SyncCache/outbox.
8. **Création et migration.** Ajouter m.room.encryption dans initial_state pour createDM,
   createGroupDM, createRoom privé et createMessagingChannel privé. Les espaces/publics restent
   un choix explicite. Pour les salons privés existants, afficher l'effet irréversible, vérifier les
   membres et appareils puis envoyer l'état m.room.encryption ; l'historique ancien reste clair sur
   le serveur, aucun ré-envoi ni suppression automatique. Jamais de migration silencieuse prétendant
   rechiffrer rétrospectivement l'historique.
9. **UI et confidentialité.** Afficher « chiffré » seulement selon l'état effectif du salon et le chemin
   d'envoi actif. Afficher séparément « appareil non vérifié » tant que phase 3 absente. Masquer les
   aperçus de liens serveur en salons chiffrés, éviter leur requête HTTP même lors de la saisie.
   Ne pas proposer une récupération de clés inexistante. Prévenir de la perte d'historique en cas
   de perte des clés. Notifications sans contenu tant qu'une politique locale sûre n'est pas validée.
10. **Validation avant activation.** Tests à deux comptes et plusieurs appareils : texte, réponses,
    modifications, fichier/miniature, offline/reprise, redémarrage, rotation, changement de membres,
    session expirée, clés tardives, replay d'événements et refus d'envoi clair sur salon chiffré.
    Puis phase 3 : vérification SAS/QR, cross-signing, backup chiffré et récupération sur nouvel appareil.

## Commandes de vérification

Après `./scripts/build-crypto.sh` :

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project mood.xcodeproj -scheme mood \
  -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build/O1/Mac \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
xcodebuild -project mood.xcodeproj -scheme mood \
  -destination 'generic/platform=iOS' -derivedDataPath build/O1/iPhone \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project mood.xcodeproj -scheme mood \
  -destination 'platform=iOS Simulator,id=46B497A7-55BA-4C98-ADFF-227B7A206BC3' \
  -derivedDataPath build/O1/Simulator CODE_SIGNING_ALLOWED=NO test -only-testing:moodTests
./server/e2ee-check.sh
```

Le simulateur identifié ici se nomme « Mood O1 iPhone » (modèle iPhone 17), créé pour cette mission.
Sur un autre Mac, le recréer puis remplacer l'UUID. Aucune commande ne lance une application Mac.
Le test en direct utilise seulement l'API locale du serveur en service, pas sa configuration.
Le jeton d'inscription est lu directement en mémoire depuis son fichier privé ; aucun secret
n'est passé en argument, écrit dans les scripts ou affiché. Les mots de passe et access_tokens
restent dans le processus et les comptes sont désactivés même après un échec ordinaire du test.
Les corps d'erreur sont volontairement supprimés des sorties. Les salons/médias ne sont pas
supprimés physiquement de la base : une preuve jetable laisse un salon contenant du ciphertext.

Les tests de conversation utilisent explicitement la politique `untrusted` pour ces appareils
jetables sans cross-signing : ils prouvent le chiffrement, **pas** la vérification d'identité.
Le pont de déchiffrement choisit par défaut `crossSignedOrLegacy` ; la politique produit et les
états d'avertissement doivent être décidés en phase 2/3, sans confondre ces deux garanties.
