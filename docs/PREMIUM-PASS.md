# Passe premium — Mood X

Travail local dans `mood-codex-X`, branche `codex/premium-pass`, le 23 octobre 2026.

**Une conversation ne doit jamais s’arrêter.** La passe rend visible ce qui attend, protège les messages pendant la panne et offre la reprise là où elle est nécessaire. La capsule de saisie avec micro, les listes iPhone et le rendu desktop existants sont conservés hors de ces états.

## Ce qui change

- Hors ligne : explication, nombre de messages en attente et statut sous chaque message. Les textes, photos et vocaux restent dans la file existante. Le retour du réseau, une synchronisation réussie ou le réessai relancent les envois avec leur transaction d’origine.
- Serveur injoignable : lire les conversations déjà chargées et écrire restent possibles. L’app explique que les nouvelles réceptions attendent aussi. Les listes sans cache sont distinguées des listes réellement vides.
- Reprise : les messages acceptés passent à l’état envoyé avec une transition de 100 ms, sans animation si Reduce Motion est actif. Une confirmation sobre indique le nombre réellement repris pendant quatre secondes. Le compteur ne double pas si la réception précède la réponse HTTP.
- Envoi refusé : même présentation et mêmes actions **Renvoyer / Supprimer** dans les salons, MP et fils. Les fichiers refusés survivent au relancement ; un réessai réutilise la transaction et les fichiers déjà transférés. Les messages d’un compte ne passent pas dans la file d’un autre.
- Suppression : le message disparaît localement, **Annuler** reste disponible cinq secondes, puis la suppression réelle commence. Si elle échoue, le message revient avec Réessayer. Une ancienne minuterie ne peut pas supprimer un message rétabli. Si l’app est arrêtée avant l’échéance, cette suppression différée n’est pas exécutée ; aucune promesse de tâche en arrière-plan n’est ajoutée.
- Session expirée : le cache et la file sont conservés. Les envois s’arrêtent ; la reconnexion existante permet de reprendre. Une déconnexion explicitement confirmée continue d’effacer les données locales comme auparavant.
- Créer un serveur ou un salon : les ressources déjà créées sont mémorisées par compte. Un échec de visibilité ou de rattachement reprend le même serveur/salon après réessai ou relancement, au lieu de créer un doublon. Les informations de reprise sont effacées à la déconnexion.
- Quitter un serveur : conséquence détaillée, attente explicite, fermeture après réussite. Une sortie partielle est expliquée et peut être reprise.
- Permissions et médias : Réglages pour micro/notifications ; autre fichier pour une photo indisponible ou trop lourde. La préparation est visible, un échec ne vide pas la saisie. Le micro refusé n’élargit plus sa capsule.
- Formulaires et erreurs : composant partagé, erreurs persistantes, attente et résultat distincts, textes courts en français. Les confirmations de compte distinguent une demande envoyée d’un changement réellement enregistré.

L’inventaire par surface et les corrections figurent dans [PREMIUM-AUDIT.md](PREMIUM-AUDIT.md).


## Passe 2 — habillage des états

L’idée reste **une conversation ne doit jamais s’arrêter**. Les six planches U (`U-00` à `U-05`) ont été ouvertes pour reprendre le même langage : surfaces sombres, hiérarchie courte, actions violettes en capsule. Aucun nouveau style de navigation ni effet décoratif.

- La panne occupe une fine capsule de verre sous l’en-tête. Elle donne le nombre de messages qui attendent ; un appui ouvre les détails et Réessayer. Sur desktop, la barre fine reste dans la colonne de conversation, au-dessus du fil.
- Le sous-titre de l’en-tête reflète la connexion de Mood pendant la panne. Le point vert et le nombre de membres en ligne réapparaissent après reprise.
- Les messages en attente sont grisés avec une horloge et « partira tout seul ». Un refus colore le texte en rouge doux et propose **Renvoyer · Supprimer** à cet endroit, sans carte.
- **Message supprimé · Annuler** apparaît en capsule au-dessus de la saisie, avec une barre de temps de cinq secondes. Une première capture montrait le dernier message derrière la capsule : la place est désormais réservée et le message reste lisible.
- L’envoi fait passer le message du gris au rendu normal, avec une petite coche temporaire pendant deux secondes. Elle s’affiche lors du passage réel de l’état local en attente à envoyé, puis disparaît ; aucun effet répétitif. La transition de couleur existante respecte Reduce Motion.
- Les autorisations et erreurs de formulaire utilisent les mêmes boutons Mood, avec appui et désactivation visibles. Les listes vides et chargements conservent les composants natifs U/V.

Les règles d’annulation, persistance, transaction et isolation de compte restent conservées. Deux tests de logique supplémentaires vérifient les textes de file et les bornes de la barre des cinq secondes. Les tests d’interface couvrent aussi les détails réseau, la reprise avec coche puis disparition, et le passage des détails de session expirée à la connexion, sans saisir d’identifiant.

## Vérifications

| Vérification | Résultat |
|---|---|
| Build iPhone / iOS Simulator arm64 | `** BUILD SUCCEEDED **` |
| Build Mac Catalyst sans signature | `** BUILD SUCCEEDED **` ; aucune app Mac lancée |
| Ensemble de `moodTests` | **223 tests, 33 suites, aucun échec** |
| Tests d’interface ciblés | **6 tests, aucun échec**, sur **Mood X iPhone** uniquement |
| Captures iPhone | Passe visuelle : 13 avant + 13 après + 10 captures d’interaction + 4 contrôles complémentaires ; inspection et corrections avant archivage |

Les neuf tests de la première passe couvrent : séparation réseau/service/session, interruption pendant l’envoi, compteur global et par conversation, reprise ordonnée sans doublon, double réessai, suppression locale d’un message en attente, expiration sans perte, fichiers refusés après relance et isolation par compte, échéance de cinq secondes et annulation, refus puis réessai de suppression, photo trop lourde sans envoi partiel du texte, vocal conservé hors ligne, absence de contenu technique brut dans les erreurs, et reprise d’une création partielle de serveur/salon après relancement sans créer de doublon.

Les six tests d’interface appuient réellement sur Annuler et constatent le retour du message, sur Renvoyer puis Supprimer dans un échec d’envoi, et sur Choisir un fichier pour ouvrir le vrai sélecteur. Ils vérifient aussi les détails de la capsule, la fermeture des détails avant la connexion et la disparition de la coche après l’envoi. Leurs captures avant/après sont conservées avec les autres PNG.

La feuille de connexion de l’aperçu utilise un client synthétique sans persistance dont toutes les requêtes sont interceptées localement, même si une configuration de développement existe. Aucun champ de connexion n’est rempli.

Les pannes réseau et les réponses de service sont injectées avec un transport HTTP intercepté sur un domaine `.invalid`. Les captures utilisent des données sans compte. Aucun compte Mood réel, inscription réelle ou panne du service de production n’a été utilisé pour ces contrôles. Les refus système micro/notifications sont représentés par des fixtures ; l’ouverture effective des Réglages et un enregistrement audio sur un appareil réel ne sont pas annoncés comme testés. PhotosPicker utilise le choix système de fichiers, sans demander d’accès global à la photothèque : une photo inaccessible propose une autre sélection.

Le rendu et les parcours Mac ont été revus dans le code et compilés. Leur validation visuelle en exécution reste hors périmètre, puisque le lancement d’apps Mac est interdit. VoiceOver et toutes les tailles Dynamic Type ne sont pas annoncés comme testés.

Journaux de la relecture finale : `build/premium-logs/visual-ios-final.log`, `visual-catalyst-final.log` et `visual-release-tests.log`. Résultat complet : `build/premium-logs/visual-release.xcresult` (**223 tests unitaires, 33 suites ; six tests d’interface**). Le transport des tests et celui de l’aperçu restent locaux ; ce résultat ne constitue pas un parcours réel contre le service Mood.

## Captures et reproduction

Voir [l’index des captures](screenshots/premium/README.md). Les nouveaux écrans se lancent par exemple avec :

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl launch --terminate-running-process C0052827-E1BA-4ADC-AB64-5778DF4BAA63 \
  Mood.mood -uiPreview -uiPreviewScreen premium-offline
```

Simulateur créé pour cette piste : **Mood X iPhone**, iPhone 17, iOS 27.0, `C0052827-E1BA-4ADC-AB64-5778DF4BAA63`. Il est éteint à la fin du travail. Aucun autre simulateur ni appareil réel n’a été utilisé.

Commandes de vérification :

```sh
xcodebuild -project mood.xcodeproj -scheme mood \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/Premium \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  SUPABASE_URL='' SUPABASE_ANON_KEY='' build

xcodebuild -project mood.xcodeproj -scheme mood \
  -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build/PremiumCatalyst \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  SUPABASE_URL='' SUPABASE_ANON_KEY='' build

xcodebuild -project mood.xcodeproj -scheme mood \
  -destination 'platform=iOS Simulator,id=C0052827-E1BA-4ADC-AB64-5778DF4BAA63' \
  -derivedDataPath build/Premium CODE_SIGNING_ALLOWED=NO \
  SUPABASE_URL='' SUPABASE_ANON_KEY='' -parallel-testing-enabled NO \
  test -only-testing:moodTests -only-testing:moodUITests/PremiumRecoveryUITests
```

Les paramètres de service sont vidés uniquement pour les builds de contrôle. Les fichiers de configuration privés ne sont ni modifiés, ni affichés, ni ajoutés à git. Journaux et résultats XCTest restent sous `build/premium-logs/`, ignoré par git.

## Grille de direction

Appréciation de cette passe, pas une mesure auprès de vrais utilisateurs :

| Critère | Avant | Après | Pourquoi |
|---|---:|---:|---|
| Point de vue | 3/5 | 4/5 | La promesse apparaît précisément pendant la panne et la reprise |
| Cohérence | 3/5 | 4/5 | Même langage pour attendre, échouer, reprendre et annuler sur iPhone et Mac |
| Exécution | 2/5 | 4/5 | Annulation réelle, file durable, perte à l’expiration corrigée, preuves unitaires et interactions iPhone |
| Total | **8/15** | **12/15** | Le 15/15 demanderait des parcours réels autorisés, une revue Mac et une revue d’accessibilité complète |

Pour la seule relecture visuelle : **point de vue 4/5 → 4/5 ; cohérence 3/5 → 4/5 ; exécution 3/5 → 4/5**, soit **10/15 → 12/15**. La première passe avait la bonne logique ; les captures montraient encore des états visuellement disjoints. La note finale reste 12/15 avec les limites de validation ci-dessus.

Tout reste local. Aucun push, PR, changement serveur/Supabase, nouvelle cryptographie, lancement d’app Mac, remplacement de la démo installée ni installation sur appareil réel.
