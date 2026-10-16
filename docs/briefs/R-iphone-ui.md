# Brief R — Harmoniser toutes les interfaces iPhone (Codex)

Branche `codex/iphone-ui`, dossier `~/mood-codex-R` (worktree de `~/mood-codex-merge`, partant de
`codex/pixel-merge`). **Ne commite pas dans `~/mood-codex-merge` et ne change pas sa branche.**
Lis `AGENTS.md`, `docs/HANDOFF.md`, `docs/MODE-EMPLOI.md`.

## Le problème (retours d'Augustin sur son vrai iPhone)
Plusieurs écrans iPhone sont « dégueulasses » : ce sont des **cartes d'ordinateur posées dans une feuille
iPhone** (fond flou derrière, double coins arrondis, bande grise, bouton terne, textes coupés), et chaque
écran a son propre style. Il veut **une interface iPhone harmonisée**, façon Discord iOS + Liquid Glass sur
les contrôles flottants, « plus rond, plus Discord et plus Apple ».

## Le modèle à suivre (déjà validé)
- `Features/Mobile/MobileCustomStatusSheet.swift` : feuille native = `NavigationStack` + `List`
  `.insetGrouped`, `.scrollContentBackground(.hidden)`, fond `MoodTheme.mobileSurface`, lignes
  `MoodTheme.inputBg`, barre : **croix à gauche** / action à droite (verre Liquid Glass natif), titre court
  en ligne ; présentation `.presentationDetents` adaptés + `.presentationDragIndicator(.visible)` +
  `.presentationBackground(MoodTheme.mobileSurface)`.
- `Features/Mobile/MobileUserProfileSheet.swift` : bannière pleine largeur, grand avatar, **un seul bouton
  principal** (capsule `brandAccent`, 50 pt), une carte arrondie 16 pt pour les détails.
- La barre de saisie iPhone : capsule `mobileGlassCapsule` (« + », champ, emoji, flèche/micro).
- Les cartes du profil (`MobileProfileView` : lignes dans `inputBg`, rayon 16).

Règles communes : marges latérales 16 pt ; rayon 16 pour les cartes, capsule pour les boutons ; police
`Font.mood` (titre de barre 17 semibold, corps 16, secondaire 14–15, légende 12–13 en majuscules pour les
en-têtes de section) ; bouton principal = capsule `brandAccent` texte blanc ; secondaire = capsule
`inputBg` ; destructif = texte rouge `mentionBadge` ; **aucune carte de bureau** (`popupBg` + `clipShape` +
`popoverElevation` + taille fixe) dans une feuille iPhone ; jamais de texte coupé (raccourcis le titre ou
passe à la ligne) ; zones tactiles ≥ 44 pt ; pas de jargon (`@m…:mood.local`, « Matrix »).

## À faire
1. **Inventaire** de tout ce qui s'affiche sur iPhone : chaque `.sheet`, `.fullScreenCover`, `.popover`,
   `.confirmationDialog`, `.alert`, chaque écran de `Features/Mobile/` et chaque vue partagée utilisée en
   mise en page compacte (paramètres du serveur, inviter, créer/modifier un salon, créer/rejoindre un
   serveur, nouveau MP, ajouter un ami, membres, explorer, épingles, fils, recherche, emoji, pièces jointes,
   Paramètres du compte, notifications, statut…). Tableau dans `docs/IPHONE-UI.md` : écran, défaut, correctif.
2. **Corrige chaque écran** selon le modèle : branche compacte native (garde la version bureau intacte,
   `layoutMode == .regular`), présentation cohérente, états vide / chargement / erreur / texte long.
3. **Captures** : ajoute un cas `-uiPreviewScreen <nom>` pour chaque écran si besoin, capture-le sur ton
   simulateur, **regarde chaque capture**, et mets avant/après dans `docs/screenshots/iphone-ui/`.

## Zones et limites
À toi : `Features/Mobile/`, les branches **compactes** des vues partagées (Servers, DirectMessages,
Settings, Profile, Chat sauf la liste des messages). **Ne casse pas le rendu bureau calibré** (Mood Pixels,
`calibrated`, `DesktopPixelRule`) : toute modification de vue partagée passe par `layoutMode`. Pas de
changement de logique dans `MatrixStore` / `MatrixClient` (pistes O2, S, N1 en parallèle) ; si un écran a
besoin d'une donnée, demande-la via une propriété existante ou documente le manque.

## Contraintes
- Aucun compte Mood réel, aucun secret. **Ne lance aucune app Mac.** Simulateur : le tien,
  `xcrun simctl create "Mood R iPhone" "iPhone 18 Pro"` ; pas « iPhone 18 Pro ».
- `mood/Vendor/` et `Config.xcconfig` sont copiés dans ton dossier. Rien sur GitHub.

## Livrables
Builds Mac Catalyst + iPhone `** BUILD SUCCEEDED **`, `moodTests` verts sur « Mood R iPhone », captures
avant/après de **chaque** écran, `docs/IPHONE-UI.md` (français). Commits petits et fréquents (un écran ou
deux par commit), en anglais, dernière ligne `Co-Authored-By: Codex <noreply@openai.com>`.

## Retours de revue Claude — 15/10 au soir (à traiter en premier à la reprise)
0. **Commence par `git merge codex/pixel-merge`** (tes 18 premiers commits y sont déjà fusionnés, plus N1 et des
   correctifs Claude : fil de discussion iPhone natif, flèche retour dans les feuilles à étapes via
   `MobileSheet(onBack:)`, heures « Aujourd'hui à », titres de catégories). Garde ces correctifs.
1. **Réglages du serveur sur iPhone** (`ServerSettings.swift`, écrans `server-overview`, `server-roles`,
   `server-members`, `server-invites`, `server-bans`) : ce sont encore les panneaux de bureau posés dans une carte.
   Titre en double (barre de navigation + gros titre dans la carte) → garder seulement le titre de la barre ;
   contenu en `List` `.mobileGroupedList()` comme `MobileCustomStatusSheet` / `MobileUserProfileSheet`.
2. `server-roles` : l'en-tête de colonne **« MEMBRES » est coupé en « MEMBRE / S »** (cadre de 52 pt,
   `ServerSettings.swift` ~l. 565) → plus de texte coupé ; une `List` native avec le nombre en valeur à droite.
3. `server-overview` : barre blanche parasite à gauche de l'icône (indicateur du rail serveur) → à retirer sur iPhone.
4. `attachment-draft` : bande de bureau isolée → si cet écran sert encore sur iPhone, l'aligner sur les puces de
   pièces jointes de `MediaComposer`, sinon le retirer du parcours iPhone.
5. Recapture les écrans touchés (simulateur dédié, pas l'iPhone 18 Pro), commits fréquents, rapport.
