# Brief N2 — Messagerie complète : médias et barre de saisie (Codex)

Branche `codex/messaging-media`, dossier `~/mood-codex-N2` (worktree de `~/mood-codex-merge`, partant de
`codex/pixel-merge`). **Ne commite pas dans `~/mood-codex-merge` et ne change pas sa branche.**
Lis `AGENTS.md`, `docs/BACKEND.md`, `docs/FEATURE-CHECK.md`, `docs/MESSAGING-SERVERS.md`, et le code de
la piste G (`MediaLoader`, `AuthenticatedImage`, `MediaPreparation`, `MessageOutbox`). Un brief parallèle
**N1** (`~/mood-codex-N1`) fait la conversation (fils, transfert, recherche…) : n'y touche pas.

## But
Que l'envoi et l'affichage des médias et la barre de saisie fassent ce que fait Discord, sur Mac **et**
iPhone, en vrai sur notre serveur. Chaque point : marche / corrigé / ajouté / masqué, avec preuve.

1. **Plusieurs pièces jointes** dans un même envoi (jusqu'à 10, comme Discord) : sélection multiple,
   glisser-déposer de plusieurs fichiers, aperçus retirables un par un, un message par fichier côté Matrix
   (+ le texte), file d'attente hors-ligne conservée (G).
2. **Photos et vidéos sur iPhone** : `PhotosPicker` (photothèque) + appareil photo si dispo ; vidéos
   envoyées en `m.video` avec durée, taille, miniature.
3. **Lecture dans le chat** : vidéo (`m.video`) lisible dans le message (AVPlayer, plein écran),
   audio (`m.audio`) avec barre de lecture, **GIF animés** qui s'animent (`AuthenticatedImage` ne doit pas
   figer la première image), téléchargement authentifié (G).
4. **Messages vocaux** sur iPhone (et Mac si simple) : appui long sur le micro → enregistrement, glisser
   pour annuler, envoi en `m.audio` avec `org.matrix.msc3245.voice` + forme d'onde
   (`org.matrix.msc1767.audio`), lecture avec la forme d'onde. Permission micro demandée au premier usage.
5. **Aperçus de liens** (embeds) : `GET /_matrix/client/v1/media/preview_url?url=…` (Bearer) → carte titre,
   description, image ; cache ; jamais bloquant. ⚠️ Le serveur n'autorise aujourd'hui que github.com,
   youtube.com, wikipedia (`url_preview_domain_explicit_allowlist` dans `~/mood-server/continuwuity.toml`) :
   **ne modifie pas la config du serveur** ; écris dans ton rapport la modification proposée (et ses
   risques) pour qu'Augustin décide.
6. **Sélecteur d'emoji complet** (barre de saisie et réactions) : catégories, recherche par nom français,
   récents, tons de peau si simple ; réactions rapides = récents.
7. **Brouillons par salon** : le texte non envoyé (et la réponse en cours) reste quand on change de salon
   et revient, comme Discord ; survit à une relance.
8. **Barre de saisie** : vérifie Entrée / Maj+Entrée (commit `1fdc77a` : Entrée envoie via
   `MessageReturnKey`, garde-le), collage d'image, `@` mentions (suggestions sans identifiant technique),
   compteur 4 000, état désactivé clair.

## Zones
- À toi : `Features/Chat/MessageComposer.swift`, `AttachmentDraftPreview.swift`, vues de médias (nouveaux
  fichiers), `MediaLoader`, `AuthenticatedImage`, `MediaPreparation`, l'outbox pour les pièces jointes,
  `MatrixStore` / `MatrixClient` en **fin de classe** sous `// MARK: - Media & composer (N2)`.
- **Pas à toi (N1)** : liste des messages et menus de message (`ChatArea.swift` sauf le rendu des pièces
  jointes dans une bulle si nécessaire — documente-le), fils, recherche, transfert.

## Leçons du test réel du 14/10 (à respecter)
- Sur **Mac Catalyst** : un champ multi-lignes avale Entrée, le trousseau refuse les builds non signés,
  les fichiers d'app ne sont pas isolés (Application Support partagé), une modale posée sur une colonne
  étroite est coupée (utilise `modalOverlay`, affiché au niveau de la fenêtre).
- Toute action met l'interface à jour sans relance et affiche une erreur claire si elle échoue.
- Pas de jargon : jamais d'identifiant `@m…:mood.local`, jamais « Matrix ».

## Vérification en direct (côté serveur)
Comptes Matrix jetables autorisés comme `server/feature-check.py` (jeton d'inscription lu **dans le
processus seulement**, rien affiché ni journalisé, comptes `n2check-*` **désactivés à la fin**) pour
vérifier en vrai : envoi multiple, `m.video`/`m.audio`/voix, `preview_url` (domaine autorisé et refusé),
téléchargement authentifié d'un GIF. Ajoute-les dans `server/media-check.py`. Ne touche à aucun autre compte.

## Contraintes
- **Aucun compte Mood (Supabase)**, aucun mot de passe tapé dans une app, aucun secret affiché.
- **Ne lance aucune app Mac** (Mood Merge tourne et partage ses fichiers de session). Simulateur : le
  tien, `xcrun simctl create "Mood N2 iPhone" "iPhone 18 Pro"` ; pas « iPhone 18 Pro ».
- Ne modifie pas la config du serveur ni de Supabase. `Config.xcconfig` : copie-le depuis
  `~/mood-codex-merge/Config.xcconfig`. Rien sur GitHub.

## Livrables
Builds Mac Catalyst + iPhone `** BUILD SUCCEEDED **`, `moodTests` verts sur « Mood N2 iPhone », tests Swift
Testing de la logique (pièces jointes multiples, brouillons, forme d'onde, aperçus, emoji), captures démo
dans `docs/screenshots/media/` (regarde-les), rapport `docs/MEDIA-COMPOSER.md` (français) : tableau des
8 points + ce qu'Augustin doit tester + la proposition d'aperçus de liens. Commits petits, en anglais,
dernière ligne `Co-Authored-By: Codex <noreply@openai.com>`.
