# Brief G — Messagerie : envoi, médias, réception (Claude)

Branche `claude/messaging`. Lis `AGENTS.md` et `docs/BACKEND-PLAN.md`. Le serveur cible est
Continuwuity (pas matrix.org) : il exige les **médias authentifiés**.

## À faire
1. **Médias authentifiés (bloquant)** : aujourd'hui `resolveMediaURL` construit
   `/_matrix/media/v3/download|thumbnail` sans authentification et `AsyncImage` ne peut pas envoyer
   d'en-tête → les images ne s'afficheront pas sur notre serveur.
   - `MatrixClient` : `/_matrix/client/v1/media/download/{server}/{id}` et `/thumbnail/…` avec
     `Authorization: Bearer` (repli v3 si le serveur ne connaît pas v1) ;
   - `MediaLoader` (actor) : téléchargement authentifié + cache mémoire (`NSCache`) et disque
     (`Caches/Mood/media/`, taille max 500 Mo, LRU) ;
   - `AuthenticatedImage` (vue) remplace `AsyncImage` pour avatars, icônes de serveur, pièces jointes,
     aperçus ; fichiers : téléchargement authentifié vers un fichier temporaire puis partage/ouverture.
   - upload : `POST /_matrix/media/v3/upload` (toujours valable), avec progression, annulation,
     limite **25 Mo** (message clair au-delà), images redimensionnées (≤ 2560 px, JPEG 0,85, HEIC
     converti), `info` (w, h, size, mimetype) et miniature pour les images.
2. **Envoi** : `formatted_body` HTML (`format: org.matrix.custom.html`) à partir du markdown (gras,
   italique, barré, code, blocs de code, citations, liens) ; `m.mentions` (`user_ids`) quand un
   @nom correspond à un membre ; limite **4 000 caractères** avec compteur dans la barre de saisie au-delà
   de 3 500 (Discord affiche aussi un compteur) ; respect de `retry_after_ms` sur 429.
3. **File d'attente** : `MessageOutbox` passe d'`UserDefaults` à un fichier JSON dans Application
   Support (comme `SyncCache`), migration de l'ancien stockage, ordre garanti par salon, pièces jointes
   en attente aussi (fichier copié localement, envoyé au retour du réseau).
4. **Réception** : filtre de sync (timeline 30, `lazy_load_members`, sans `presence` des autres
   serveurs), `unread_thread_notifications` ; vérifier pagination et comblement de trous contre
   Continuwuity ; les redactions et éditions arrivent aussi pour les messages du cache.
5. Tests Swift Testing : markdown → HTML, détection des mentions, limite de longueur, sérialisation de
   l'outbox et migration, choix v1/v3 des URL média, calcul de redimensionnement.

## Contraintes
Modifications de `MatrixStore` / `MatrixClient` ajoutées en fin de classe sous
`// MARK: - Messaging pipeline` quand c'est du neuf ; une autre piste ajoute `login(accessToken:…)`
dans la section Auth et une autre les notifications. Vérification = commande `swiftc -typecheck` des
autres briefs (pas de xcodebuild sur le MacBook, **n'ouvre aucune app sur le MacBook**). Rien sur GitHub.
