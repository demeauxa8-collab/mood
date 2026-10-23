# Premier accueil Mood — piste V

Travail local du 23 octobre 2026 dans `/Users/Adm/mood-codex-V`, branche `codex/first-run-ux`, base
`a0256f7`. Ce rapport distingue le code réalisé des vérifications qui nécessitent un lancement.

## Audit de départ

| État | Ce qui existait | Travail V |
|---|---|---|
| Nouveau serveur | Checklist desktop : invitation, icône, premier message inactif ; aucune mémorisation | Quatre étapes actives, icône serveur, progression locale et présentation partagée iPhone/Mac |
| Début de salon | Entête desktop, avec bouton Modifier montré sans vérifier les droits | Rond #, textes conservés, droits réels du salon et ajout sur iPhone |
| Début de MP | Grand avatar desktop, texte présent seulement dans une variante ; entête montré même avant d'avoir atteint le début | Présentation commune, nom Mood seulement s'il est connu, blocage existant avec confirmation et indication hors ligne |
| Amis vides | « Aucun résultat » dans Tous même sans amis ; indication générique dans En ligne | Symbole infini Mood, texte explicite et action Ajouter un ami ; distinction vide/recherche/hors ligne |
| Amis sur iPhone | Recherche native dans Nouveau message, ouverte par Ajouter des amis | État amis vides dans cette feuille, bouton qui donne le focus au nom d'utilisateur |
| Notifications vides | « Rien de nouveau » sur iPhone ; « Tu es à jour ! » dans l'inbox desktop | Conservés, déjà courts et honnêtes |
| Recherche vide | « Aucun résultat », avec suggestion de changer les mots-clés | Conservée ; une fixture d'aperçu est ajoutée |

La liste des MP vides, propriété de U, n'est pas modifiée. Les racines `MoodApp`, `ContentView` (partie
navigation avant `FriendsPlaceholderView`) et `MobileRootView`, ainsi que `MobileDMListView`, restent
inchangées. Dans `ContentView.swift`, seules deux branches d'état vide de `FriendsPlaceholderView`
ont été complétées. Dans `DirectMessages.swift`, les changements sont limités à `DMChatArea`.

## Comportement ajouté

Les états de début n'apparaissent qu'après confirmation du début réel de l'historique par une pagination
terminée. Un indicateur « plus d'historique : non » sans curseur connu ne suffit pas. Le chargement
initial réutilise la méthode existante de conversation ; si l'historique est encore inconnu et vide,
l'app présente le chargement ou une action pour charger les messages. Aucune conversation vide n'est
affirmée pendant une erreur réseau.

La checklist apparaît au début du premier salon texte d'un serveur vide que la personne peut gérer.
Une checklist déjà commencée reste accessible après le premier message, jusqu'aux quatre étapes faites.
Elle ne se déclenche pas sur un salon déjà rempli dont aucune checklist n'a été commencée localement.

| Étape | Action | Preuve locale de réalisation |
|---|---|---|
| Inviter tes amis | Ouvre l'invitation existante | Invitation directe réussie, code/lien réellement copié ou autre membre présent ; ouvrir la feuille seul ne coche rien |
| Choisir une icône | Ouvre les réglages existants | Icône réellement présente dans le modèle serveur |
| Envoyer ton premier message | Donne le focus à la vraie barre de saisie | Message personnel accepté, hors message système ; ni un brouillon ni un message en attente/en erreur ne coche l'étape |
| Ouvrir Mood sur ton autre appareil | Feuille d'instructions | Confirmation explicite « J'ai ouvert Mood… » ; le texte explique que Mood ne peut pas le vérifier ici |

La copie d'une invitation atteste sa préparation au partage, pas sa réception par un ami. La feuille
de l'autre appareil explique comment ouvrir l'app avec le même compte et à qui demander l'installation :
aucun lien App Store ou téléchargement inexistant n'est inventé.

La progression utilise `UserDefaults`, avec version du format, compte et identifiant canonique du serveur.
Un autre compte ou serveur n'hérite pas des étapes. Les aperçus restent en mémoire et n'écrivent pas cette
progression. Ce sont des préférences locales ; elles ne sont pas synchronisées entre appareils.

Le bouton Modifier dépend des niveaux réellement requis pour le nom **et** le sujet du salon. Le MP utilise
le blocage existant, avec confirmation, uniquement pour un interlocuteur individuel qui n'est pas déjà
bloqué ; aucun bouton de blocage d'une personne n'est ajouté aux MP de groupe. Aucun nouveau système
d'amis n'est inventé. Le nom d'utilisateur public n'est affiché
que lorsqu'il est disponible : aucun identifiant technique n'est transformé en faux nom Mood. Le store
actuel ne fournit pas systématiquement le nom Mood des interlocuteurs ; cette ligne reste alors masquée.

La ligne hors ligne utilise l'envoi différé existant. Elle reste masquée si la saisie de la conversation
est désactivée. Aucun badge ou texte de chiffrement de bout en bout n'est ajouté.

## Accessibilité et rendu

Les nouveaux textes suivent Dynamic Type via `ScaledMetric` et `Font.mood`, restent multilignes et sont
dans des surfaces défilantes. Les boutons ont une hauteur minimale de 44 pt, les étapes annoncent
« Terminé » / « À faire », les titres sont marqués comme entêtes et les symboles décoratifs sont masqués
à VoiceOver. Aucune nouvelle animation n'est ajoutée, y compris avec Reduce Motion.

Les séparateurs desktop continuent d'utiliser `DesktopPixelRule`. Les couleurs restent dans MoodTheme.
Les feuilles iPhone réutilisent les présentations natives existantes. Ces choix de code ne constituent
pas une preuve de lisibilité effective avec VoiceOver, de bon placement du clavier ni de fidélité 1:1.

## Validation

Vérification reproductible sans lancement : `bash scripts/verify-first-run.sh`. Les builds sont
séquentiels, limités à `-jobs 4`, en arm64 (le framework crypto local du simulateur est arm64).
Les sorties restent dans `build/first-run/`, hors git. Aucune app n'est installée par ces scripts.

Vérification finale réussie sur le code `3b4d117`, à 17 h 41 (Europe/Paris), sans lancement :

| Vérification | Résultat | Journal local |
|---|---|---|
| Mac Catalyst arm64, sans signature | `** BUILD SUCCEEDED **` | `mac-build.log` |
| iPhone physique arm64, destination générique, sans signature ni installation | `** BUILD SUCCEEDED **` | `iphone-build.log` |
| App et bundles de tests iOS Simulator arm64 | `** TEST BUILD SUCCEEDED **` | `test-build.log` |
| Même fichier `moodTests/FirstRunTests.swift`, exécuté dans un module Foundation/Observation autonome | **13 tests réussis, 0 échec** | `logic-tests.log` |
| Comparaison des zones réservées à U et des configurations à `a0256f7` | Inchangées ; `git diff --check` réussi | Contrôle statique local |

Le module de tests autonome utilise uniquement les bibliothèques système ; il n'ajoute aucune dépendance
au projet Mood et ne charge pas l'app. La suite complète `moodTests` a été **compilée mais pas exécutée**.
Les builds et tests de logique ne prouvent pas le fonctionnement réseau, le focus réel, le rendu ni les
annonces VoiceOver. Aucun compte ni service distant n'a été utilisé pour les tester.

Les tests nouveaux couvrent : isolation compte/serveur, persistance après relance, format invalide,
idempotence, étapes non cochées à l'ouverture, quatre étapes obligatoires, aperçu en mémoire, vrai début
d'historique, curseur absent, droits du nom et du sujet, message personnel effectivement accepté, amis
vides/recherche/hors ligne et absence de nom technique affiché.

## Captures et décisions pour Augustin

**Captures avant/après non réalisées et rendu non inspecté.** La consigne directe de cette session
interdit de lancer une app Mac ou un simulateur, y compris celui de V ; elle prime sur le brief.
Les routes de contrôle sont prêtes dans [l'index des captures](screenshots/first-run/README.md).
Il reste donc à valider visuellement ces états et à exécuter toute la suite `moodTests` sur un simulateur
dédié lorsque les lancements seront autorisés. Aucun simulateur V n'a été créé ou démarré ici ; aucun
simulateur d'Augustin n'a été utilisé ni arrêté.

Aucun compte Mood réel, secret affiché ou commité, changement de configuration serveur/Supabase,
nouvelle cryptographie, lancement d'app Mac, remplacement de démo installée ou action GitHub.
Les commits restent locaux sur la branche de V. Le travail de U dans son worktree n'a pas été modifié.
