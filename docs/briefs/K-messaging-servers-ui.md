# Brief K — Messages et serveurs façon Discord : tout réel, en direct, visible (Codex)

Branche `codex/messaging-ui`, dossier `~/mood-codex-K` (worktree de `~/mood-codex-merge`, partant de
`codex/pixel-merge` **après** la fusion de la piste G). **Ne commite pas dans `~/mood-codex-merge` et ne
change pas sa branche.** Lis `AGENTS.md`, `docs/BACKEND.md`, `docs/HANDOFF.md`,
`docs/UI-DESKTOP-PIXEL-PERFECT.md`, puis le code de la piste G (médias authentifiés, `MessageFormatting`,
`MessageOutbox`, `MediaLoader`, `AuthenticatedImage`).

## Contexte
Le backend est en ligne (compte Mood → `matrix-session` → Continuwuity `mood.local` sur le Studio). Un vrai
compte s'y est connecté aujourd'hui. Bug typique trouvé en vrai : une action partait bien au serveur mais
l'interface ne se mettait pas à jour. **Ta mission : que chaque fonction de base de Discord autour des
messages et des serveurs marche vraiment et se voie tout de suite**, sur Mac (Catalyst) **et** iPhone, et
corriger tout ce qui ne va pas. Le brief I (`~/mood-featcheck`, `docs/FEATURE-CHECK.md` sur
`codex/feature-check`) teste en direct ce que le serveur accepte : lis ce fichier dès qu'il existe.
Un brief J (`~/mood-codex-J`) traite en parallèle le **compte** (profil, statut, amis, MP, Paramètres) :
n'y touche pas.

## Liste à passer (chaque ligne : marche / corrigé / masqué, avec preuve)
**Messages**
1. Envoyer : Entrée envoie, Maj+Entrée = retour à la ligne, markdown rendu des deux côtés, mentions `@` avec
   **autocomplétion** des membres (à ajouter si absente), emoji, limite 4 000 (piste G).
2. Modifier (menu + **flèche haut** = modifier mon dernier message, comme Discord), supprimer (confirmation),
   répondre (bandeau « En réponse à … », clic sur la citation → saute au message), réactions (sélecteur +
   réaction rapide, compteur, retirer), épingler / désépingler + panneau des épingles (clic → saute au
   message), copier le texte. Tout ce qui ne peut pas marcher (ex. fils de discussion s'ils sont cassés,
   « Marquer comme non lu ») : masqué.
3. Pièces jointes : bouton +, **glisser-déposer**, **coller une image**, aperçu avant envoi, progression et
   annulation (G), image affichée chez les deux, fichier ouvrable (G).
4. « X est en train d'écrire… », accusés de lecture, **non lus** : salon en gras + pastille, ligne
   « Nouveaux messages », badge rouge de mention sur le salon et le serveur, remis à zéro à la lecture.
5. Historique : remonter charge les anciens messages sans saut, retour en bas, « Aller au présent ».
6. Hors-ligne : messages en attente grisés, Réessayer / Supprimer (G), partent dans l'ordre au retour.

**Serveurs** (serveur = espace Matrix, salon = salle rattachée)
7. Créer un serveur (nom + icône facultative) → `#général` créé et visible, je suis propriétaire.
8. **Accès aux salons** : un membre invité **au serveur seul** doit voir et pouvoir lire tous les salons
   non privés, comme Discord. Vérifie la règle d'accès des salons créés (`join_rule` `restricted` avec
   `allow: [{type: m.room_membership, room_id: <espace>}]`, version de salle ≥ 8) et l'arrivée dans les
   salons (rejoindre automatiquement les salons publics du serveur à l'entrée, ou au premier clic, sans
   écran d'erreur). Corrige la création des salons **et** prévois les salons déjà créés (bouton ou
   réparation automatique côté propriétaire).
9. **Invitations façon Discord** : aujourd'hui l'app montre des liens `https://matrix.to/#/#salon:matrix.org`.
   Fais des **codes d'invitation Mood** : un alias court `#<code>:mood.local` (8 caractères lisibles)
   créé à la demande pour le serveur, affiché comme code + lien `mood://invite/<code>` (copier) ;
   « Rejoindre un serveur » accepte le code seul, le lien `mood://invite/…`, un alias ou un lien
   matrix.to ; ouvrir un lien `mood://invite/…` (`onOpenURL`) propose de rejoindre. Plus aucun exemple
   `matrix.org` dans les textes. Inviter directement une personne (recherche par nom) doit aussi marcher.
10. Salons : créer (texte), renommer, sujet, supprimer, **ordre** (`order` de `m.space.child`), salon
    privé (sur invitation). **Catégories** : seulement si tu peux les rendre réelles et partagées entre
    membres (par ex. état de salon dans l'espace) ; sinon masque la création de catégories.
11. Rôles et modération : rôles = niveaux de pouvoir (propriétaire 100, admin, modérateur 50, membre 0),
    changer le rôle d'un membre, expulser, bannir / débannir, liste des bannis, quitter le serveur.
    « Supprimer le serveur » : seulement si tu en fais une vraie fermeture (le propriétaire retire les
    salons, expulse les membres et quitte, avec confirmation forte) ; sinon masqué.
12. Paramètres du serveur : nom, icône, description, visibles par tous les membres après la sync.
13. **Tout bouton de ces écrans** fait quelque chose de réel, sinon il est masqué. Pas de « Bientôt
    disponible », pas de faux succès ; un échec affiche un message clair. Après chaque action,
    l'interface reflète le résultat sans relance.

## Contraintes
- N'empiète pas sur la piste J : Paramètres du compte, profil et popout de profil, statut, amis, liste des
  MP, `AccountStore`. Tes ajouts dans `MatrixStore` / `MatrixClient` vont **en fin de classe** sous
  `// MARK: - Messaging & servers UI`.
- Respecte `AGENTS.md` (couleurs `MoodTheme`, tailles `LayoutMetrics`, animations Discord minimales) et le
  rendu calibré Mood Pixels du Mac : ne casse pas les mesures existantes.
- **Aucun compte réel** : ne crée aucun compte Supabase, ne tape aucun mot de passe. Tests en direct =
  Augustin. Toi : tests Swift Testing de la logique (codes d'invitation, analyse des liens, règle
  `restricted`, ordre des salons, mapping rôles ↔ niveaux, autocomplétion des mentions, « flèche haut »…),
  builds, captures en mode démo (`-uiPreview`). Si tu as besoin de savoir si le serveur accepte un appel,
  `/versions` et `/capabilities` répondent sans jeton, et `docs/FEATURE-CHECK.md` (brief I) a le reste.
- **N'utilise pas le simulateur « iPhone 18 Pro »** (Augustin s'en sert) : crée le tien,
  `xcrun simctl create "Mood K iPhone" "iPhone 18 Pro"`. Ne ferme pas et ne relance pas l'app Mac
  « Mood Merge » déjà ouverte ; ne lance pas d'app Mac.
- `Config.xcconfig` est ignoré par git : copie-le depuis `~/mood-codex-merge/Config.xcconfig`.
- Rien sur GitHub. Aucun secret dans git, les journaux ou les captures. N'ouvre rien sur le MacBook.

## Vérification
Builds Mac Catalyst + iPhone (commandes d'`AGENTS.md`, `derivedDataPath build/DerivedData` dans ton
dossier) jusqu'à `** BUILD SUCCEEDED **`, `moodTests` verts (`-destination 'platform=iOS
Simulator,name=Mood K iPhone'`). Captures des écrans touchés dans `docs/screenshots/messaging-ui/`
(regarde-les avant de dire que c'est fait). Rapport `docs/MESSAGING-SERVERS.md` (français) : tableau des
13 points avec état et preuve, ce qu'Augustin doit tester en vrai (avec 2 comptes), les limites. Commits
petits, en anglais, dernière ligne `Co-Authored-By: Codex <noreply@openai.com>`.
