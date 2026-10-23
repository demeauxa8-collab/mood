# Brief L — Finitions des bases : nom d'utilisateur, MP reçus, mentions, Discord (Codex)

Branche `codex/finish-basics`, dossier `~/mood-codex-L` (worktree de `~/mood-codex-merge`, partant de
`codex/pixel-merge` **après** la fusion des pistes J et K — c'est fait). **Ne commite pas dans `~/mood-codex-merge` et ne
change pas sa branche.** Lis `AGENTS.md`, `docs/BACKEND.md`, `docs/FEATURE-CHECK.md`,
`docs/ACCOUNT-FEATURES.md`, `docs/MESSAGING-SERVERS.md`.

## Contexte
Le contrôle en direct du serveur (`docs/FEATURE-CHECK.md`, 137 PASS) a trouvé des trous côté app. Et
Continuwuity **cache dans sa recherche tout utilisateur qui ne partage aucun salon** : on a donc ajouté des
**noms d'utilisateur Mood uniques façon Discord** (`profiles.username`, rempli à l'inscription, RPC
`find_user_by_username` en correspondance exacte, `MoodUsername` pour le format, `MatrixStore.searchUsers`
met le résultat exact en premier — commit `d3f3288`). Il manque l'interface.

## À faire
1. **Nom d'utilisateur visible et modifiable** :
   - `AccountStore.setUsername(_:)` → `PATCH profiles` `{username}` (le droit est donné par colonne) ;
     validation `MoodUsername` avant l'envoi ; nom déjà pris (Postgres `23505`, HTTP 409) →
     « Ce nom d'utilisateur est déjà pris » ; format refusé → règle affichée (2 à 32 caractères : lettres
     minuscules, chiffres, `_` et `.`).
   - Paramètres › Mon compte : ligne « Nom d'utilisateur » + Modifier, comme Discord.
   - Popout de profil et profil complet : le nom d'utilisateur sous le nom d'affichage (le sien et celui
     des autres quand on le connaît : pour les autres, ajoute une RPC seulement si c'est nécessaire et
     sans permettre de lister les comptes ; sinon n'affiche que le sien).
   - « Ajouter un ami » : champ « Nom d'utilisateur », texte d'aide « Tu peux ajouter des amis avec leur
     nom d'utilisateur Mood », message clair si personne ne l'a ; plus aucun exemple `@x:matrix.org`.
2. **Invitations sur iPhone et MP déjà rejoints** : accepter un MP écrit déjà `m.direct` (commits
   `22a5d21` + piste J) et l'historique d'un salon rejoint sans message est récupéré (`5705eb6`).
   Reste : (a) les invitations reçues (MP « Veut discuter avec toi » et serveurs) doivent être visibles et
   acceptables **sur iPhone** aussi, avec un badge sur l'onglet Amis / Accueil quand il y en a ;
   (b) au démarrage, répare les MP déjà rejoints sans `m.direct` (salon à 2 membres créé avec
   `is_direct`, ou dont l'événement d'invitation me concernant avait `is_direct`) pour qu'ils
   réapparaissent dans les MP.
3. **Boîte de réception des mentions** : `/notifications` n'existe pas sur Continuwuity (404
   `M_UNRECOGNIZED`). Alimente l'onglet Mentions depuis les messages déjà reçus (sync + cache : `m.mentions`
   qui me contient, `@room`, ou mon nom) ; garde la route serveur seulement si elle répond. Si ce n'est pas
   possible proprement : masque l'onglet.
4. **Discord dans les Paramètres** : la section Discord (synchroniser, délier, importer mes serveurs,
   utiliser mon profil Discord) n'apparaît que si `accountStore.discordEnabled` est vrai (déjà chargé par
   l'écran de connexion via `auth/v1/settings` ; recharge-le si besoin).
5. Balaye les textes restants qui citent `matrix.org` ou « Matrix » dans le parcours normal (le champ
   homeserver de la connexion avancée peut rester).

## Contraintes
- Ajouts dans `MatrixStore` / `MatrixClient` en fin de classe sous `// MARK: - Finish basics`.
- `AGENTS.md` (couleurs, tailles, animations Discord), rendu calibré Mood Pixels du Mac intact.
- **Aucun compte réel**, aucun mot de passe tapé, aucun secret. Tests Swift Testing de la logique (erreur
  « déjà pris », détection d'un MP à ranger, filtre des mentions), builds, captures en mode démo.
- Simulateur : le tien, `xcrun simctl create "Mood L iPhone" "iPhone 18 Pro"` (pas « iPhone 18 Pro »,
  Augustin s'en sert). Ne ferme pas et ne relance pas l'app Mac ouverte ; ne lance pas d'app Mac.
- `Config.xcconfig` (ignoré par git) : copie-le depuis `~/mood-codex-merge/Config.xcconfig`.
- Rien sur GitHub.

## Vérification
Builds Mac Catalyst + iPhone jusqu'à `** BUILD SUCCEEDED **`, `moodTests` verts sur « Mood L iPhone »,
captures dans `docs/screenshots/finish-basics/` (regarde-les), rapport `docs/FINISH-BASICS.md` (français)
avec un tableau des 5 points (état + preuve) et ce qu'Augustin doit tester en vrai. Commits petits, en
anglais, dernière ligne `Co-Authored-By: Codex <noreply@openai.com>`.
