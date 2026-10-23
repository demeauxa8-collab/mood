# Intégration du parcours d’accueil Mood — piste U

Travail local dans `~/mood-codex-U`, branche `codex/onboarding`, le 23 octobre 2026.

## Résultat de la passe 3

- **Photo** : la capture existante `/Users/Adm/mood-logs/uv/U-avatar.png` a été ouverte et examinée. Le cercle suivait directement le sous-titre et le bouton photo remontait de 5 pt, ce qui expliquait le chevauchement. Un espace de 28 pt est ajouté avant le cercle ; `@ScaledMetric(relativeTo: .body)` l'agrandit avec le texte d'accessibilité. Le bouton reste en haut à droite du cercle et le contenu conserve son défilement.
- **Test du nom** : le résultat archivé `build/DDreview/Logs/Test/Test-mood-2026.10.23_18-05-12-+0200.xcresult` confirme l'unique échec : le test attendait « Ce nom d'utilisateur est déjà pris » alors que l'erreur typée ajoutée en passe 2 renvoie « Ce nom d'utilisateur est déjà pris. ». Le contrat réseau n'a pas changé. Le test vérifie désormais le cas `AccountError.usernameTaken` et son texte ponctué ; toute autre erreur fait échouer le test. Sa session synthétique utilise explicitement `persistsSession: false` pour exclure le stockage de session réel.
- **Vérification exécutée** : les 29 tests du harnais de logique réussissent à nouveau (`/tmp/mood-onboarding-unit-pass3.log`). La compilation Mac Catalyst réussit (`** BUILD SUCCEEDED **`, `/tmp/mood-onboarding-catalyst-pass3.log`), sans lancement. L'app iPhone et l'ensemble des tests, dont le test corrigé, compilent pour la destination générique iOS Simulator ARM64 (`** TEST BUILD SUCCEEDED **`, `/tmp/mood-onboarding-ios-pass3.log`), sans appareil choisi ou démarré.
- **Limite conservée** : la consigne directe actuelle interdit tout simulateur, y compris « Mood U iPhone ». La suite hébergée `moodTests` n'est donc pas relancée, et aucune nouvelle capture avatar normale ou grand texte n'est produite. La correction de géométrie reste à vérifier visuellement dans l'app. L'ancienne capture examinée n'est pas une preuve du rendu après correction.

## Résultat de la passe 2

Le blocage client d’inscription est supprimé : la création du compte utilise l’inscription existante par e-mail et mot de passe, sans demander de recherche anonyme du nom. Le nom d’utilisateur est choisi **après** la confirmation et l’ouverture de session, avec la recherche authentifiée déjà livrée et l’attribution par `AccountStore.setUsername`.

Le code compile pour Mac Catalyst et iPhone. **29 tests de logique sont exécutés et réussis sans app ni simulateur.** Les tests des stores avec HTTP intercepté sont compilés, mais ne sont pas exécutés. Aucun parcours avec un vrai compte et aucune revue visuelle en application ne sont annoncés comme validés.

La consigne directe de cette session interdit aussi le simulateur propre à la piste U. Elle prime sur l’autorisation de captures écrite en fin de brief. Aucun simulateur n’a donc été créé, démarré ou utilisé, aucune app Mac n’a été lancée et aucune installation n’a été effectuée. La version de démonstration installée reste intacte. Aucun serveur, réglage Supabase ou code cryptographique n’est modifié ; rien n’est envoyé sur GitHub.

## Parcours et intégration

1. Accueil → e-mail → `.account` : un seul champ de mot de passe, création du compte.
2. `.confirmation` : code de six chiffres, ouverture automatique de la session et effacement du code et du mot de passe. Un callback e-mail emprunte également ce chemin, sans nouvelle inscription.
3. `.displayName` → `.username` : nom affiché facultatif, puis nom d’utilisateur obligatoire, sur son propre écran à un champ.
4. `.trust` → `.server` → `.notifications` → `.friends` → `.avatar` → fin : chemins précédents conservés, y compris Passer et Plus tard.

Les deux sources relues sont intégrées sous `mood/Features/Onboarding/`, dans le groupe synchronisé de la cible commune iOS / Mac Catalyst. Le modèle utilise `@Observable` / `@MainActor`, la vue `@Bindable`. Aucun stub, moteur de rendu, PNG Mobbin ou fichier d’`onboarding-import/` n’est embarqué ou commité.

`RootView` conserve la récupération du mot de passe, les sessions Matrix seules et les routes de démonstration. Après achèvement, il affiche la racine habituelle. Seul le contenu des Messages réellement vides est remplacé sur iPhone et Mac ; les listes peuplées, la pilule utilisateur flottante et les autres écrans existants sont conservés. Aucun onglet de la maquette de rendu n’est ajouté. Le logo reste `MoodInfinitySymbol`.

## Vérification et enregistrement du nom

- Aucune recherche de nom n’est nécessaire à l’inscription ni à la confirmation. Le protocole expose séparément `register(email:password:)`, `confirmCode` et `setUsername`.
- L’écran `.username` vérifie le format localement, puis interroge `AccountStore.isUsernameAvailable`, qui utilise `find_user_by_username` avec la session authentifiée. Une réponse correspondant au profil de l’utilisateur est autorisée ; ce profil est rechargé pour tenir compte d’une liaison récente au service de messages.
- Aucun état positif n’est affiché avant réponse serveur. Une panne laisse la disponibilité inconnue et bloque Continuer. Une nouvelle saisie, une nouvelle vérification ou un changement d’écran invalide le résultat précédent ; une réponse tardive ne peut pas approuver un autre nom.
- Le texte positif est « Nom vérifié. Tu peux continuer. ». La recherche existante filtre les profils sans identifiant de messagerie : elle reste un contrôle préalable, pas une réservation. L’attribution réelle et sa contrainte unique restent la décision finale.
- Un HTTP 409 ou le code SQL `23505` devient une erreur typée, puis « Ce nom d'utilisateur est déjà pris. » sous le champ. Le compte reste connecté, le nom perd son état positif et l’utilisateur peut en choisir un autre. Aucun appel d’inscription supplémentaire n’est effectué.

Aucune API nouvelle, migration SQL ou modification Supabase n’est requise par ce réordonnancement. Le précédent blocage « vérification anonyme absente » ne s’applique plus.

## Reprise et confidentialité

- Achèvement par compte : `mood.onboarding.done.<userId>`, uniquement après `actions.finish()` réussi. Une erreur conserve le brouillon et l’étape ; les brouillons sont supprimés après succès.
- Brouillon invité : `mood.onboarding.progress`. La confirmation le transfère vers `mood.onboarding.progress.<userId>`. Une connexion charge uniquement le brouillon de son compte ; les champs d’un formulaire invité ne sont pas transférés à ce compte.
- Un compte confirmé sans nom choisi reprend à `.username`, même s’il a quitté l’app sur le nom affiché. Le checkpoint `usernameSaved` est enregistré après attribution réussie ; après ce checkpoint, la progression normale est reprise. Un ancien brouillon sans checkpoint revient au choix connecté du nom.
- Si le processus s’arrête entre la sauvegarde de la session OTP et le transfert du brouillon, le lancement suivant récupère le brouillon de confirmation seulement si son e-mail correspond à la session restaurée. Ce compte n’est pas confondu avec une ancienne session exemptée de l’onboarding.
- Au premier lancement après mise à jour, une session ancienne restaurée sans progression est marquée terminée par identifiant stable. Une installation neuve ou un compte au parcours interrompu n’est pas exempté. Tests dédiés présents.
- Les brouillons contiennent seulement les saisies autorisées et le choix emoji : aucun mot de passe, code, jeton, objet PhotosPicker ou octet de photo. La déconnexion et le changement de compte effacent les brouillons concernés ; les clés d’achèvement restent isolées par compte.

## Actions existantes conservées

| Action | Branchement |
|---|---|
| Inscription / confirmation / renvoi | `registerForOnboarding`, `confirmSignup(code:email:)`, renvoi existant ; aucune conservation du mot de passe pour le polling. Erreurs d’inscription et limites de fréquence propagées. |
| Connexion | E-mail et mot de passe, UUID stable, reprise du brouillon du compte ou accès direct si déjà terminé. |
| Mot de passe oublié | `sendRecoveryCode` et écran de récupération par code existant ; ouverture seulement après succès, mot de passe du formulaire effacé. |
| Nom affiché | `MatrixStore.updateDisplayName` après connexion au service de messages. |
| Photo | Entrée limitée à 20 Mo, réduction ImageIO à 512 px et réencodage JPEG sans métadonnées source, puis envoi existant. PhotosPicker sur iPhone/Catalyst. |
| Emoji | Le profil déployé n’a pas de champ persistant `avatarEmoji` : rendu PNG 256 px puis même envoi d’avatar, sans inventer de champ serveur. |
| Ami | Recherche exacte du nom Mood, sans accès aux contacts ; création/réutilisation du DM puis ouverture dans la vraie racine. |
| Invitation / serveur | Résolution des codes/liens existants ; modèles Amis, Jeux, Études et serveur minimal. Un espace partiellement créé est mémorisé par compte pour reprendre sans doublon. |
| Notifications | Seul Autoriser demande la permission système. Passer et Plus tard ne demandent rien ; un refus système permet de continuer. |
| Fin | Vérifie la session et la connexion au service de messages avant l’écriture de la clé d’achèvement. |

L’écran de confiance précise les limites de l’envoi hors ligne et du stockage séparé. Aucun cadenas ni annonce de chiffrement de bout en bout actif n’est ajouté.

## Vérifications réalisées

| Contrôle | Résultat |
|---|---|
| Tests du modèle, adaptateur injectable et cycle de vie | **29 tests exécutés et réussis** en ligne de commande. Sources de production copiées à l’identique dans un paquet temporaire ; seul le type de valeur UI `MoodUser` est remplacé pour ce harnais. Préférences éphémères propres à chaque test. |
| Mac Catalyst | `** BUILD SUCCEEDED **`, compilation sans signature. Aucun lancement. |
| iOS Simulator ARM64 + tests hébergés | `** TEST BUILD SUCCEEDED **` avec destination générique : compilation de l’app et des tests, aucun appareil choisi ou démarré. |
| HTTP simulé des stores | Tests ajoutés et compilés pour l’inscription sans nom, la session après OTP, recherche authentifiée, nom pris/propre nom, panne réseau, collisions 409 et 23505, nouvelle tentative, mauvais code, renvoi limité et erreurs d’inscription existantes. **Non exécutés** : ils nécessitent un hôte d’app. |
| Périmètre git | Diff vérifié ; aucun fichier d’import, secret, serveur ou Supabase ajouté aux commits. Commits locaux uniquement. |

Les 29 tests exécutés couvrent aussi les bornes de validation, l’ordre complet jusqu’au nom connecté, l’absence de réponse serveur positive implicite, la reprise à `.username`, le callback e-mail, la compatibilité des anciens brouillons, les réponses tardives, l’isolation des comptes, les fins réussies/échouées, photo/emoji transmis, récupération, invitation refusée, ami absent et ajout/ouverture, modèles de serveur, notifications ignorées/acceptées, exemption des sessions anciennes et effacement à la déconnexion.

Commandes reproductibles, sans installation ni lancement :

```sh
scripts/test-onboarding-headless.sh

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project mood.xcodeproj -scheme mood \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath build/OnboardingValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  SUPABASE_URL='' SUPABASE_ANON_KEY='' build

xcodebuild -project mood.xcodeproj -scheme mood \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/OnboardingValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  SUPABASE_URL='' SUPABASE_ANON_KEY='' build-for-testing
```

Exécuter les builds successivement car ils partagent la base de compilation. Les paramètres Supabase sont remplacés par des valeurs vides pour ces builds ; aucune configuration privée n’est affichée. Les avertissements de concurrence/dépréciation préexistants hors onboarding ne sont pas traités ici.

Journaux locaux de cette passe : `/tmp/mood-onboarding-unit-pass2.log`, `/tmp/mood-onboarding-catalyst-pass2.log`, `/tmp/mood-onboarding-ios-pass2.log`.

## Revue visuelle restant à faire

La route `-onboardingPreview` reste isolée : préférences séparées, aucune restauration de session, aucun store réel, aucun lien entrant traité et aucune demande système. `-onboardingStep` accepte maintenant aussi `username`. Les options de revue sont décrites dans [screenshots/onboarding/README.md](screenshots/onboarding/README.md).

**Aucune capture nouvelle n’est fournie**, conformément à la consigne actuelle de ne lancer aucune app ni simulateur. Restent non vérifiés en situation réelle :

- iPhone 393 × 852 : chaque étape vide/remplie, clavier, attente, erreurs et hors ligne, nom pris/long, photo/emoji, grands textes, Passer et notifications.
- Mac Catalyst 1280 × 800 puis redimensionné : carte de 480 pt centrée à hauteur naturelle, champs à un écran, erreurs et clavier matériel.
- Accessibilité : VoiceOver, ordre de lecture, navigation clavier, contraste mesuré, grandes tailles de texte et Reduce Motion.
- Accueil vide dans les vraies racines et comparaison des listes peuplées ; inscription et autres actions sur le vrai service avec autorisation d’utiliser un compte approprié.

La réussite des compilations et des tests de logique ne constitue pas une validation visuelle ni un test d’inscription sur le service réel.
