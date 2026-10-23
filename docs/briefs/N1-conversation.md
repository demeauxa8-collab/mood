# Brief N1 — Messagerie complète : la conversation (Codex)

Branche `codex/messaging-conversation`, dossier `~/mood-codex-N1` (worktree de `~/mood-codex-merge`,
partant de `codex/pixel-merge`). **Ne commite pas dans `~/mood-codex-merge` et ne change pas sa branche.**
Lis `AGENTS.md`, `docs/BACKEND.md`, `docs/FEATURE-CHECK.md`, `docs/MESSAGING-SERVERS.md`,
`docs/FINISH-BASICS.md`. Un brief parallèle **N2** (`~/mood-codex-N2`) fait les médias et la barre de
saisie : n'y touche pas (voir « Zones »).

## But
Que la conversation de Mood fasse tout ce que fait Discord, sur Mac **et** iPhone, en vrai sur notre
serveur Continuwuity (`mood.local`). Chaque point : marche / corrigé / ajouté / masqué, avec preuve.

1. **Fils de discussion** (threads, `m.thread`) : « Créer un fil » depuis un message, panneau du fil
   (desktop : à droite comme Discord ; iPhone : écran poussé), répondre dans le fil, compteur de réponses
   et dernier message sous le message racine, liste des fils du salon, non-lus des fils (la sync demande
   déjà `unread_thread_notifications`). ⚠️ `/relations` répond 404 `M_UNRECOGNIZED` sur ce serveur :
   teste `GET /_matrix/client/v1/rooms/{id}/threads` et, sinon, construis les fils depuis la sync et
   `/messages`. Les fils avaient été masqués par la piste K : réactive-les seulement s'ils marchent vraiment.
2. **Transférer** un message vers un autre salon ou MP (sélecteur avec recherche), comme Discord.
3. **Marquer comme non lu** : `m.marked_unread` (account data de salon, MSC2867 stable ou
   `com.famedly.marked_unread`) + pastille ; retiré à la lecture.
4. **Copier le lien du message** (`mood://message/<roomId>/<eventId>` ou matrix.to) et l'ouvrir
   (`onOpenURL` existant) → saute au message (`/context` existe sur le serveur).
5. **Recherche** : `POST /_matrix/client/v3/search` marche sur ce serveur. Recherche dans le salon et dans le
   serveur (desktop : champ en haut à droite comme Discord ; iPhone : écran de recherche), résultats
   cliquables qui sautent au message, filtres simples (de : @nom, dans : #salon) si possible.
6. **Messages système** lisibles : arrivées/départs, changements de nom, d'icône, de sujet, épingles
   (« X a épinglé un message »), comme les lignes grises de Discord, sans jargon Matrix.
7. **Séparateurs de date**, groupement des messages, « (modifié) », heure au survol (desktop) : vérifie
   et corrige.

## Zones
- À toi : `Features/Chat/ChatArea.swift` (liste des messages, menus de message, panneaux), vues de fil /
  recherche / transfert (nouveaux fichiers), `MatrixStore` / `MatrixClient` en **fin de classe** sous
  `// MARK: - Conversation (N1)`.
- **Pas à toi (N2)** : `MessageComposer.swift` (barre de saisie), pièces jointes, médias, emoji, aperçus de
  liens, `MediaLoader`, `AuthenticatedImage`. Si tu as besoin d'un point d'accroche dans la barre de saisie
  (ex. répondre dans un fil), ajoute un paramètre minimal et documente-le.

## Leçons du test réel du 14/10 (à respecter)
- Ce qui compile n'est pas ce qui marche : sur **Mac Catalyst** un champ multi-lignes avale Entrée, le
  trousseau refuse les builds non signés, une modale posée sur une colonne étroite est coupée (utilise
  `modalOverlay`, désormais affiché au niveau de la fenêtre via `WindowModalHost`).
- Toute action doit mettre l'interface à jour sans relance, et afficher une erreur claire si elle échoue.
- Pas de jargon : jamais d'identifiant `@m…:mood.local` affiché, jamais « Matrix ».

## Vérification en direct (côté serveur)
Tu peux créer des **comptes Matrix jetables sur notre serveur** comme `server/feature-check.py` (jeton
d'inscription lu dans `~/mood-server/registration_token` **dans le processus seulement**, mots de passe
générés en mémoire, rien affiché ni journalisé, comptes `n1check-*` **désactivés à la fin**) pour vérifier
fils, recherche, `m.marked_unread`, `/context` en vrai. Ajoute ces contrôles à `server/feature-check.py`
ou dans `server/conversation-check.py`. Ne touche à aucun autre compte.

## Contraintes
- **Aucun compte Mood (Supabase)**, aucun mot de passe tapé dans une app, aucun secret affiché.
- **Ne lance aucune app Mac** (l'app « Mood Merge » d'Augustin tourne et partage ses fichiers de session :
  une 2e instance se connecterait avec son compte). Simulateur : le tien,
  `xcrun simctl create "Mood N1 iPhone" "iPhone 18 Pro"` ; pas « iPhone 18 Pro ».
- `Config.xcconfig` (ignoré par git) : copie-le depuis `~/mood-codex-merge/Config.xcconfig`. Rien sur GitHub.

## Livrables
Builds Mac Catalyst + iPhone `** BUILD SUCCEEDED **`, `moodTests` verts sur « Mood N1 iPhone », tests Swift
Testing de la logique (fils, transfert, non-lu, liens de message, recherche), captures démo
(`-uiPreview`) dans `docs/screenshots/conversation/` (regarde-les), rapport `docs/CONVERSATION.md`
(français) : tableau des 7 points + ce qu'Augustin doit tester. Commits petits, en anglais, dernière ligne
`Co-Authored-By: Codex <noreply@openai.com>`.
