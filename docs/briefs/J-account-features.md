# Brief J — Fonctions « compte » de Discord : réelles, en direct, visibles (Codex)

Branche `codex/account-features`, dossier `~/mood-codex-J` (worktree de `~/mood-codex-merge`, partant de
`codex/pixel-merge`). **Ne commite pas dans `~/mood-codex-merge` et ne change pas sa branche.**
Lis `AGENTS.md`, `docs/BACKEND.md`, `docs/HANDOFF.md`, `docs/UI-DESKTOP-PIXEL-PERFECT.md`.

## Contexte
Le backend est en ligne : compte Mood (Supabase) → fonction `matrix-session` → serveur Matrix Continuwuity
`mood.local` (Studio, `https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443`). Un vrai compte s'est
connecté aujourd'hui. Premier bug trouvé en vrai : changer son nom partait bien au serveur mais l'interface
gardait l'ancien nom (corrigé dans `4a30507` : `updateDisplayName` / `updateAvatar` rafraîchissent
`currentUser` et renvoient un `Bool`). **Ta mission : traquer et corriger tous les bugs de ce genre** sur les
fonctions de base de Discord liées au compte, sur Mac (Catalyst) **et** iPhone.

Un brief parallèle (I, `docs/briefs/I-feature-check.md`) vérifie en direct ce que le serveur accepte ;
son résultat arrivera dans `docs/FEATURE-CHECK.md` sur `codex/feature-check`. Si tu as besoin de savoir si
Continuwuity supporte un appel, teste-le toi-même sans compte (`/versions`, `/capabilities` répondent sans
jeton) ou lis `~/mood-server/src`.

## Liste à passer (chaque ligne : marche / corrigé / masqué, avec preuve)
1. **Nom d'affichage** : modifié dans Paramètres › Profil → visible tout de suite partout (panneau
   utilisateur en bas à gauche, popout de profil, liste des membres, mes messages après la sync suivante).
2. **Avatar** : choisir une image → envoyée et affichée tout de suite. ⚠️ L'**affichage** des images (vues
   `AsyncImage` → `AuthenticatedImage`) est la piste G : ne touche pas au rendu des images, seulement au flux
   « choisir → envoyer → rafraîchir l'état ».
3. **Statut** : en ligne / inactif / ne pas déranger / invisible + statut personnalisé → présence Matrix
   (`setMyStatus`) ; garde le choix après relance ; les autres le voient (présence reçue par la sync) ;
   « Ne pas déranger » coupe les bannières de notification (`Core/Notifications/NotificationPolicy.swift`).
4. **À propos de moi / bio, bannière, pronoms** : s'ils sont affichés, ils doivent être enregistrés. Si
   Continuwuity accepte les champs de profil (MSC4133, `GET/PUT /_matrix/client/v3/profile/{id}/{clé}` ou
   préfixe instable `uk.tcpip.msc4133`), branche-les ; sinon **masque** les champs (règle AGENTS : pas de
   bouton sans effet).
5. **Compte Mood** (Paramètres › Mon compte) : e-mail affiché, **changer le mot de passe** (Supabase
   `PUT /auth/v1/user` `{password}` ; gère la réauthentification si Supabase l'exige), **changer l'e-mail**
   (`{email}` → e-mail de confirmation, message clair), **déconnexion** (Supabase + `POST /logout` Matrix +
   cache local vidé, retour à l'écran de connexion), **supprimer le compte** : seulement s'il existe un vrai
   chemin serveur, sinon masqué.
6. **Amis** : ajouter quelqu'un **par son nom** (`/user_directory/search` ; les identifiants `@m<hex>` sont
   illisibles, ne les montre pas comme « nom d'utilisateur » à taper), demandes en attente
   (accepter / refuser), retirer un ami, bloquer / débloquer (`m.ignored_user_list`, les messages d'un bloqué
   sont masqués), onglets En ligne / Tous / En attente / Bloqués avec la vraie présence.
7. **MP** : ouvrir un MP depuis un profil ou la liste d'amis (réutilise un MP existant au lieu d'en recréer
   un), MP de groupe (plusieurs invités, nom du groupe), quitter un MP de groupe.
8. **Popout de profil** (clic sur un nom ou un avatar) : vraies données (nom, avatar, statut, rôles dans le
   serveur courant), bouton « Envoyer un message » qui ouvre le MP.
9. **Tout bouton de ces écrans** fait quelque chose de réel, sinon il est masqué. Pas de « Bientôt
   disponible », pas de faux succès. Un échec réseau affiche un message clair (pas silencieux).
10. **État** : après chaque action, l'interface reflète le résultat **sans relance** (mise à jour optimiste
    annulée en cas d'erreur, ou mise à jour après succès).

## Contraintes
- **Ne touche pas aux zones de la piste G (en cours)** : fonctions média / upload / envoi de messages de
  `MatrixClient`, `MessageOutbox`, `MediaLoader`, `AuthenticatedImage`, la barre de saisie et le pipeline
  d'envoi, le rendu des images. Tes ajouts dans `MatrixStore` / `MatrixClient` vont **en fin de classe**
  sous `// MARK: - Account features`.
- Respecte les règles d'`AGENTS.md` (couleurs `MoodTheme`, tailles `LayoutMetrics`, animations Discord) et
  le rendu calibré Mood Pixels du Mac (ne casse pas les mesures existantes).
- **Aucun compte réel** : ne crée aucun compte Supabase, ne tape aucun mot de passe. Les tests en direct
  avec un vrai compte seront faits par Augustin. Toi : tests Swift Testing de la logique (mapping statut →
  présence, filtrage des bloqués, choix « réutiliser le MP existant », validation e-mail / mot de passe…),
  builds, et captures en mode démo (`-uiPreview`).
- **N'utilise pas le simulateur « iPhone 18 Pro »** (Augustin s'en sert pour son test) : crée le tien,
  `xcrun simctl create "Mood J iPhone" "iPhone 18 Pro"`. Ne ferme pas et ne relance pas l'app Mac
  « Mood Merge » déjà ouverte (Augustin s'en sert) ; pour tes captures Mac, ne lance pas d'app.
- `Config.xcconfig` est ignoré par git : copie-le depuis `~/mood-codex-merge/Config.xcconfig` dans ton dossier.
- Rien sur GitHub. Aucun secret dans git, les journaux ou les captures. N'ouvre rien sur le MacBook.

## Vérification
Builds Mac Catalyst + iPhone (commandes d'`AGENTS.md`, `derivedDataPath build/DerivedData` dans ton
dossier) jusqu'à `** BUILD SUCCEEDED **`, `moodTests` verts (`-destination 'platform=iOS
Simulator,name=Mood J iPhone'`). Captures des écrans touchés dans `docs/screenshots/account-features/`
(regarde-les avant de dire que c'est fait). Rapport `docs/ACCOUNT-FEATURES.md` (français) : le tableau des
10 points avec état et preuve, ce qu'Augustin doit tester en vrai, et les limites. Commits petits, en
anglais, dernière ligne `Co-Authored-By: Codex <noreply@openai.com>`.
