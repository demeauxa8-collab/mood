# Conversation — piste N1

Travail local dans `mood-codex-N1`, branche `codex/messaging-conversation`.
Aucun compte Mood/Supabase utilisé, aucune app Mac lancée, aucune configuration serveur modifiée,
aucune action GitHub. `Config.xcconfig` copié sans affichage depuis le worktree de fusion, toujours ignoré.

## Les sept points

| Point | État et preuve | Limite à connaître |
|---|---|---|
| 1. Fils | Ajoutés : relations `m.thread`, envoi par la file persistante existante, panneau à droite, compteur et dernier texte sous la racine, liste et non-lus. `/threads` v1 répond 200 et fournit le compteur ; `/messages` et sync contiennent les réponses. Chargement par pages de 100, racines anciennes via `/context`, sans `/relations`. Accusé avec `thread_id` accepté. | L’historique est chargé progressivement ; le bouton « plus anciennes » reste présent tant qu’il n’est pas épuisé. Les réponses ne sont pas dupliquées dans le salon. Sur iPhone, le fil est poussé depuis le message ; la liste des fils est accessible depuis le menu d’en-tête, même dans un salon vide. |
| 2. Transfert | Ajouté pour le texte : sélecteur de salons et MP avec recherche, nom de l’auteur original en préfixe, envoi sous mon identité. Fermeture après acceptation HTTP, erreur et nouvel essai sinon. Le compte destinataire jetable relit le texte par `/context`. | Les messages contenant des pièces jointes sont masqués du transfert : médias réservés à N2. Les salons chiffrés sont exclus. La limite de longueur s’applique au texte avec son préfixe. |
| 3. Non lu | Ajouté : écriture `m.marked_unread`, prise en compte de l’ancien format, pastilles par les modèles de salons/MP existants, retrait à la lecture. Le marquage manuel dans la conversation ouverte reste visible jusqu’à sa réouverture. Les deux formats ont été écrits et relus en vrai, à true puis false. | La donnée de compte revient par la sync ; hors ligne, une erreur est affichée et aucune fausse écriture réussie n’est annoncée. |
| 4. Liens | Lien `mood://message/…/…` encodé par composant, validation stricte, chargement du contexte et demande de navigation. Tests de caractères réservés, liens invalides, `/context` réel. | Gestionnaire global raccordé dans `MoodApp.swift`, y compris accueil et MP. Un lien reçu avant la première sync est conservé en mémoire puis résolu ; une conversation inaccessible affiche une erreur. Le parcours authentifié à froid reste à tester par Augustin. |
| 5. Recherche | Recherche serveur existante conservée ; entrée dédiée au salon sur desktop, écran mobile accessible depuis le menu d’en-tête, filtres `de:` / `dans:`, résultats ouvrant leur conversation et message. `/search` réel retrouve la racine attendue. | Recherche mobile disponible même dans un salon vide ; choix salon/serveur et filtres. La recherche reste limitée aux conversations accessibles et non chiffrées. |
| 6. Système | Ajouté depuis les vrais événements : arrivées/départs/exclusions, nom, icône, sujet, épingle/retrait. Noms lisibles ou « Quelqu’un », sans identifiant technique comme nom de secours. Le rendu gris est partagé avec iPhone. Faux bouton « Fais coucou » retiré. | Les événements d’état initiaux servent à construire les salons, pas à inventer un historique. Les changements de nom sont distingués grâce à `prev_content`. |
| 7. Présentation | Groupement limité au même auteur, moins de cinq minutes et même date ; cassure après une ligne système et avant une réponse. Séparateurs desktop conservés, séparateurs ajoutés au composant partagé mobile pour les messages réels. « (modifié) » et heure au survol conservés ; aide avec date complète. | Le rendu Mac ne peut pas être inspecté, car tout lancement Mac est interdit. |

## Périmètre et raccordements

Le brief donne `ChatArea.swift`, de nouvelles vues et les sections `Conversation (N1)` de
`MatrixStore` / `MatrixClient`. Les ajouts réseau et d’état sont placés en fin de classe ; des appels
minimaux dans la sync, la conversion, les modèles non lus, la lecture, les échos et la restauration
raccordent ces ajouts au pipeline existant. Deux champs optionnels de `MatrixUnsigned` décodent
`prev_content` et `m.relations` ; pas de changement du format de cache incompatible.

`MessageComposer.swift`, les pièces jointes, médias, emoji et aperçus de liens ne sont pas modifiés.
Aucun paramètre de composeur ajouté : le fil a son propre champ texte simple, Entrée et bouton Envoyer.

Deux raccordements minimaux complètent les parcours demandés :

- `mood/App/MoodApp.swift` : traitement global de `mood://message`, avant les invitations et callbacks
  existants ; point d’entrée de démonstration strictement sous `-uiPreview -conversationPreview`.
- `mood/Features/Mobile/MobileChatScreen.swift`, hors composeur : menu d’en-tête Recherche/Fils,
  navigation poussée vers le fil avec son vrai salon, ouverture d’une réponse trouvée par recherche,
  et bandeau d’erreur refermable. Une `NavigationStack` locale porte ces destinations.

Ces raccordements servent uniquement N1. Le composeur mobile existant et tous les fichiers réservés
à N2 sont conservés. Les comptes, serveurs, réglages et parcours Supabase ne sont pas modifiés.

## Contrôle serveur

`python3 server/conversation-check.py --local` utilise exclusivement des comptes `n1check-*` créés
par UIAA avec le jeton lu en mémoire. Mots de passe générés en mémoire, jetons jamais affichés.
Les corps HTTP ne sont jamais imprimés. Désactivation UIAA en `finally`, puis tentative de connexion
refusée pour chaque compte. Le rapport ne contient que des libellés contrôlés et codes HTTP.

Preuve : [server-check.txt](screenshots/conversation/server-check.txt). Aucun autre compte manipulé.
Les salons jetables sont quittés et peuvent rester dans la base, sans compte actif associé.
Ce contrôle prouve le transport, pas les interactions SwiftUI authentifiées.

## Vérifications et captures

- Mac Catalyst : `** BUILD SUCCEEDED **`, sans lancement d’app Mac.
- iPhone : `** BUILD SUCCEEDED **` sur **Mood N1 iPhone**, UUID
  `F2EB95FA-2CC0-4CE3-8AEC-3F6518E3B0DA`. Le simulateur personnel n’a pas été manipulé.
- Swift Testing : `** TEST SUCCEEDED **`, **148 tests dans 27 suites, 0 échec**, dont 9 tests N1
  (relations de fil, liens, transfert, groupement, événements système, décodage, non-lu, filtres,
  contrats HTTP authentifiés interceptés vers `.invalid`). Aucun accès à une session réelle.
- Journaux locaux ignorés : `build/conversation/mac-build.log`, `iphone-build.log`, `iphone-tests.log` ;
  résultat structuré : `build/conversation/Tests.xcresult`.
- Contrôle serveur relancé le 15 octobre : **38 PASS, 0 FAIL**, une information sur l’inscription
  manuelle. Les deux désactivations et les deux refus de reconnexion sont présents dans la preuve.
- Captures de démo dans `docs/screenshots/conversation/` : conversation (date, ligne système,
  compteur et dernier texte du fil, message modifié), fil, liste des fils, transfert, recherche.
  Les cinq PNG ont été ouverts et inspectés. Le doublon de date de la fixture a été supprimé.
  La capture recherche montre le véritable écran au repos, sans résultats artificiels.
- Empreintes, commit source et résultats : [validation.json](screenshots/conversation/validation.json).

Les compilations et tests ne prouvent pas les interactions authentifiées SwiftUI. Aucun rendu Mac
n’a été inspecté. Le fil desktop à droite concerne `ChatArea` ; dans les vues réutilisant uniquement
`MessageRow` sans callback de fil (notamment les MP desktop), l’accès de secours est modal.
La pagination couvre l’historique disponible, sans garantir que tous les fils sont déjà chargés.

## À tester par Augustin

1. Sur deux appareils : créer un fil, répondre, fermer/réouvrir, charger plusieurs pages, modifier puis
   supprimer une réponse depuis l’autre appareil. Vérifier compteur, dernier texte, non-lu et absence
   des réponses dans le salon principal. Couper le réseau : conserver le brouillon trop long, voir
   l’envoi en attente et Réessayer après un refus définitif.
2. Transférer un texte vers un salon et un MP, chercher la destination, vérifier chez le destinataire.
   Essayer une destination sans permission et une coupure réseau : le sélecteur doit rester ouvert.
3. Marquer non lu depuis le message ouvert, quitter puis revenir ; vérifier pastilles et disparition
   du marquage sur les deux appareils après sync et relance.
4. Ouvrir un lien vers un ancien message depuis un salon desktop déjà ouvert ; vérifier le contexte et
   le saut. Refaire depuis l’accueil, un MP et à froid après restauration de la session.
5. Rechercher un mot dans le salon puis le serveur ; filtrer auteur et salon, charger une page suivante,
   ouvrir un résultat d’un autre salon et une réponse de fil. Essayer aucun résultat et panne réseau.
6. Faire entrer/sortir une personne, changer nom/icône/sujet, épingler puis retirer l’épingle ; vérifier
   des lignes françaises, sans identifiant technique et sans faux bouton.
7. Recevoir plusieurs messages du même auteur, une réponse, un événement système et des messages
   autour de minuit ; vérifier dates, regroupement, mention « modifié » et heure au survol Mac.
