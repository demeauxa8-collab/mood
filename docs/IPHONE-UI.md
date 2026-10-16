# Audit des interfaces iPhone — piste R

Travail local dans `mood-codex-R`, branche `codex/iphone-ui`. Aucun compte réel, aucune intervention serveur ni Supabase, aucun envoi GitHub. Les présentations sont vérifiées sur **Mood R iPhone** uniquement. Les fenêtres bureau calibrées restent dans leurs branches régulières.

## Inventaire

| Écran / présentation | Défaut initial | Correctif prévu / vérification |
|---|---|---|
| Accueil, MP, invitations reçues | Styles mobiles déjà présents ; noms longs et cibles à contrôler | Conserver les cartes mobiles, cibles 44 pt |
| Liste des salons / menu serveur | Nom tronqué, feuilles de bureau pour les actions | Titres multilignes et feuilles natives |
| Conversation / saisie | Capsule validée | Conserver la liste des messages ; harmoniser les feuilles annexes |
| Notifications | Marges 12, titres parfois comprimés | Marges 16, texte adaptable |
| Profil personnel | Modèle validé | Conserver cartes 16 et boutons capsules |
| Statut personnalisé (sheet) | Modèle validé | Conserver liste native ; contrôles tactiles |
| Choix de présence (confirmationDialog) | Natif | Conserver |
| Profil d’un membre (sheet) | Modèle validé, nom limité à une ligne | Nom multilignes, fermeture accessible |
| Choix créer / rejoindre (sheet) | Entête de bureau, grand espace gris | Navigation native, choix en liste |
| Créer un serveur | Formulaire de bureau dans feuille | Formulaire natif et capsule principale |
| Rejoindre un serveur | Formulaire de bureau | Code ou lien, formulaire natif |
| Paramètres serveur | Sélecteur de sections et panneaux bureau | Liste de navigation native |
| Profil serveur | Double titre, indicateur blanc du rail, carte de bureau | List native, un seul titre, icône sans rail, sauvegarde dans la barre |
| Rôles serveur | Tableau large, en-tête MEMBRES coupé | List native ; description multiligne et nombre à droite |
| Membres serveur / modération | Identifiants techniques, menus petits | List native et recherche, noms lisibles, cible 44, actions existantes conservées |
| Invitations serveur | Double titre, bouton et copie de bureau | List native, capsule principale, code et partage système |
| Bannissements | Double titre, identifiants techniques et ligne large | List native, état vide, nom et action sur deux lignes séparées |
| Quitter / réparer accès (alert) | Natif | Conserver confirmations réelles |
| Créer un salon (sheet) | popupBg, coins, ombre de bureau | Navigation et List insetGrouped |
| Modifier un salon (sheet) | Carte de bureau, barre de sauvegarde | Formulaire natif, sauvegarde dans barre |
| Supprimer un salon (alert) | Natif | Conserver |
| Inviter des amis (sheet) | Carte de bureau ; titre trop long | Titre court, recherche, invitation/copie réelles |
| Nouveau MP / ajouter un ami (sheet) | Entête personnalisé, texte trop petit | Navigation native et recherche en liste |
| MP de groupe | Formulaire sans sélection visible | Sélection cochée, capsule de création |
| Membres d’un salon (sheet) | Panneau bureau et profil non ouvrable | Liste native, ouverture du profil |
| Épingles (sheet) | Hauteur fixe 250 et petites cartes | Liste native et état vide |
| Fil (sheet) | Ancienne coquille avec réponses fictives et saisie sans envoi | Fil réel de N1 conservé après fusion ; présentation iPhone native |
| Recherche | Panneau fixe 400, absent du chat mobile | Recherche native branchée au modèle existant |
| Emoji / réactions (sheet ou popover adaptatif) | Hauteur fixe 340, grille <44 | Navigation native, hauteur flexible, grille 44 |
| Pièces jointes | Choix horizontaux comprimés | Liste verticale native ; sélecteurs système conservés |
| Brouillon pièce jointe | Bande de bureau isolée, nom tronqué et petites cibles | Carte 16 commune au composeur, nom multiligne, retrait 44, envoi capsule |
| Photo / fichier / caméra | Présentations système | Conserver ; caméra non disponible dans simulateur |
| Vidéo plein écran (fullScreenCover) | Contrôleur système | Conserver |
| Paramètres (sheet) | Fond différent, fermeture texte à droite | Surface commune, croix à gauche |
| Mon compte | Lignes de bureau et compte technique | Carte mobile, nom Mood uniquement |
| Nom d’utilisateur (sheet) | Fond/champ et grand titre incohérents | Liste native, action dans barre |
| E-mail et mot de passe | Champs arrondis gris, placeholders longs | Libellés séparés, champs lisibles, capsules |
| Profil à modifier | Marges 24, champs de bureau | Cartes 16, actions mobiles |
| Bio / pronoms | Champs système incohérents | Champs mobiles cohérents |
| Apparence | Aperçus de bureau trop larges | Choix en lignes et grille d’accents 44 |
| Notifications réglages | Instructions « clic droit » | Cartes, texte « appui long » |
| Confidentialité | Lignes de bureau | Carte mobile et toggles natifs |
| Appareils | Cartes bureau | Liste mobile ; état déconnecté explicite |
| Déconnexion (confirmationDialog) | Natif | Conserver et confirmer depuis les paramètres |
| Chiffrement | Texte informatif existant | Présentation mobile sans badge de protection |
| Raccourcis clavier | Hors usage iPhone | Masquer dans navigation compacte |
| Import Discord (sheet) | Carte fixe minHeight 480 | Liste native, vide/erreur/chargement |
| Explorer (sheet) | Fermeture à droite, pas d’erreur propre | Croix, surface commune, erreur/réessayer |
| Authentification / récupération | Écrans autonomes, piste comptes | Inventoriés hors retouche de logique ; aucun compte utilisé |
| Rejoindre depuis un lien (alert racine) | Natif | Conserver |
| Switcher, inbox, appels, popovers de bureau | Inaccessibles depuis navigation mobile actuelle | Hors chemin iPhone ; aucun changement bureau |

## Captures

Avant/après dans `docs/screenshots/iphone-ui/{before,after}/`. Entrées reproductibles :
`-uiPreview -uiPreviewScreen <nom>` ; voir `scripts/capture-iphone-ui.sh`.
Les données proviennent uniquement des fixtures existantes, sans restauration de session.

## Reprise du 16 octobre 2026

- Historique et modifications locales relus ; 18 commits UI antérieurs conservés.
- Fusion locale `codex/pixel-merge` jusqu’à `96f79e4` sans conflit ; conversation N1, retour de feuille à étapes et heures conservés.
- Retours de revue traités dans les cinq pages serveur et le brouillon de pièce jointe ; branches compactes distinctes des panneaux réguliers.
- Anciennes captures blanches, bloquées sur le lancement ou sur une confirmation d’ouverture écartées. La nouvelle procédure lance chaque route avec ses arguments, sans lien à confirmer.

## Validation

Vérification terminée le 16 octobre 2026, sur le code de `405d6b2` (les commits suivants portent sur les captures, leur script et ce rapport).

| Vérification | Résultat |
|---|---|
| iPhone, destination `74CF31F5-9565-4142-B844-E27058C8F892` | `** BUILD SUCCEEDED **` |
| Mac Catalyst, sans signature et sans lancement | `** BUILD SUCCEEDED **` |
| Préparation des tests | `** TEST BUILD SUCCEEDED **` |
| `moodTests`, exécution sur Mood R iPhone | **160 tests, 29 suites ; 0 échec, 0 ignoré** ; `** TEST EXECUTE SUCCEEDED **` |
| Inspection visuelle | **51 captures avant + 51 après**, toutes regardées ; aucune capture de lancement ou de confirmation d’ouverture retenue |

[Preuves et empreintes des captures](screenshots/iphone-ui/validation.json). Journaux locaux : `build/iphone-ui/review-iphone-build.log`, `review-mac-build.log`, `review-test-build.log`, `review-tests.log`. Résultat Xcode : `build/iphone-ui/ReviewTests.xcresult` (hors git). Les builds gardent des avertissements existants de concurrence et de dépréciation dans les composants hors piste R.

Aucun lancement de l’app Mac ; le rendu bureau n’a donc pas été inspecté visuellement pendant cette reprise. Aucun compte réel, secret affiché ou commité, changement serveur/Supabase, nouvelle crypto ni publication GitHub. Aucun test de compte, d’envoi ou de modération avec un service réel : les captures valident les présentations avec des données de démonstration.

Pour reproduire les captures : construire l’app iPhone dans `build/DerivedData`, puis `scripts/capture-iphone-ui.sh after`. Le script vise exclusivement le simulateur dédié. `MOOD_CAPTURE_SCREENS="server-roles attachment-draft"` limite la série ; `MOOD_CAPTURE_APP` choisit une copie de référence pour `before`. Les formulaires système photo/fichier, confirmations natives et caméra sont inventoriés ; ils ne constituent pas des pages personnalisées supplémentaires dans les 51 routes.

## Limites des données disponibles

Les pages rôles, membres et bannissements lisent les données déjà exposées par le store. Celui-ci ne fournit pas d’état de chargement distinct pour chaque page ; aucun indicateur fictif n’a été ajouté. Les erreurs des actions serveur utilisent le bandeau existant dans la feuille. Les scénarios chargement/erreur de création et de recherche sont des fixtures visuelles, sans requête réelle. La conversation et les fils de N1 restent conservés ; la liste des messages n’a pas été retouchée par cette reprise.

## Index des captures

Les captures « avant » proviennent de la copie de référence préparée par la passe précédente (base `17b29a4`), avec les entrées de démonstration ajoutées pour accéder aux écrans. Les formulaires de salons et d’invitation ont été remis à cette base avant capture. Pour les cinq sous-pages serveur, le code de référence est celui de `96f79e4`, avant les corrections de revue. Les nouveaux états de démonstration n’impliquent pas qu’ils existaient dans le parcours initial. Les dialogues système et sélecteurs photo/fichier sont inventoriés ci-dessus ; la caméra demande un appareil réel.

| Route de démonstration | Avant | Après |
|---|---|---|

| `home` | [Voir](screenshots/iphone-ui/before/home.png) | [Voir](screenshots/iphone-ui/after/home.png) |
| `server` | [Voir](screenshots/iphone-ui/before/server.png) | [Voir](screenshots/iphone-ui/after/server.png) |
| `chat` | [Voir](screenshots/iphone-ui/before/chat.png) | [Voir](screenshots/iphone-ui/after/chat.png) |
| `notifications` | [Voir](screenshots/iphone-ui/before/notifications.png) | [Voir](screenshots/iphone-ui/after/notifications.png) |
| `profile` | [Voir](screenshots/iphone-ui/before/profile.png) | [Voir](screenshots/iphone-ui/after/profile.png) |
| `custom-status` | [Voir](screenshots/iphone-ui/before/custom-status.png) | [Voir](screenshots/iphone-ui/after/custom-status.png) |
| `profile-popup` | [Voir](screenshots/iphone-ui/before/profile-popup.png) | [Voir](screenshots/iphone-ui/after/profile-popup.png) |
| `create-server` | [Voir](screenshots/iphone-ui/before/create-server.png) | [Voir](screenshots/iphone-ui/after/create-server.png) |
| `create-server-form` | [Voir](screenshots/iphone-ui/before/create-server-form.png) | [Voir](screenshots/iphone-ui/after/create-server-form.png) |
| `join-server` | [Voir](screenshots/iphone-ui/before/join-server.png) | [Voir](screenshots/iphone-ui/after/join-server.png) |
| `new-dm` | [Voir](screenshots/iphone-ui/before/new-dm.png) | [Voir](screenshots/iphone-ui/after/new-dm.png) |
| `group-dm` | [Voir](screenshots/iphone-ui/before/group-dm.png) | [Voir](screenshots/iphone-ui/after/group-dm.png) |
| `server-settings` | [Voir](screenshots/iphone-ui/before/server-settings.png) | [Voir](screenshots/iphone-ui/after/server-settings.png) |
| `server-overview` | [Voir](screenshots/iphone-ui/before/server-overview.png) | [Voir](screenshots/iphone-ui/after/server-overview.png) |
| `server-roles` | [Voir](screenshots/iphone-ui/before/server-roles.png) | [Voir](screenshots/iphone-ui/after/server-roles.png) |
| `server-members` | [Voir](screenshots/iphone-ui/before/server-members.png) | [Voir](screenshots/iphone-ui/after/server-members.png) |
| `server-invites` | [Voir](screenshots/iphone-ui/before/server-invites.png) | [Voir](screenshots/iphone-ui/after/server-invites.png) |
| `server-bans` | [Voir](screenshots/iphone-ui/before/server-bans.png) | [Voir](screenshots/iphone-ui/after/server-bans.png) |
| `create-channel` | [Voir](screenshots/iphone-ui/before/create-channel.png) | [Voir](screenshots/iphone-ui/after/create-channel.png) |
| `edit-channel` | [Voir](screenshots/iphone-ui/before/edit-channel.png) | [Voir](screenshots/iphone-ui/after/edit-channel.png) |
| `invite` | [Voir](screenshots/iphone-ui/before/invite.png) | [Voir](screenshots/iphone-ui/after/invite.png) |
| `members` | [Voir](screenshots/iphone-ui/before/members.png) | [Voir](screenshots/iphone-ui/after/members.png) |
| `members-empty` | [Voir](screenshots/iphone-ui/before/members-empty.png) | [Voir](screenshots/iphone-ui/after/members-empty.png) |
| `pins` | [Voir](screenshots/iphone-ui/before/pins.png) | [Voir](screenshots/iphone-ui/after/pins.png) |
| `pins-empty` | [Voir](screenshots/iphone-ui/before/pins-empty.png) | [Voir](screenshots/iphone-ui/after/pins-empty.png) |
| `thread` | [Voir](screenshots/iphone-ui/before/thread.png) | [Voir](screenshots/iphone-ui/after/thread.png) |
| `search` | [Voir](screenshots/iphone-ui/before/search.png) | [Voir](screenshots/iphone-ui/after/search.png) |
| `emoji` | [Voir](screenshots/iphone-ui/before/emoji.png) | [Voir](screenshots/iphone-ui/after/emoji.png) |
| `attachments` | [Voir](screenshots/iphone-ui/before/attachments.png) | [Voir](screenshots/iphone-ui/after/attachments.png) |
| `attachment-draft` | [Voir](screenshots/iphone-ui/before/attachment-draft.png) | [Voir](screenshots/iphone-ui/after/attachment-draft.png) |
| `settings` | [Voir](screenshots/iphone-ui/before/settings.png) | [Voir](screenshots/iphone-ui/after/settings.png) |
| `account` | [Voir](screenshots/iphone-ui/before/account.png) | [Voir](screenshots/iphone-ui/after/account.png) |
| `profile-settings` | [Voir](screenshots/iphone-ui/before/profile-settings.png) | [Voir](screenshots/iphone-ui/after/profile-settings.png) |
| `account-credentials` | [Voir](screenshots/iphone-ui/before/account-credentials.png) | [Voir](screenshots/iphone-ui/after/account-credentials.png) |
| `username` | [Voir](screenshots/iphone-ui/before/username.png) | [Voir](screenshots/iphone-ui/after/username.png) |
| `appearance` | [Voir](screenshots/iphone-ui/before/appearance.png) | [Voir](screenshots/iphone-ui/after/appearance.png) |
| `privacy` | [Voir](screenshots/iphone-ui/before/privacy.png) | [Voir](screenshots/iphone-ui/after/privacy.png) |
| `devices` | [Voir](screenshots/iphone-ui/before/devices.png) | [Voir](screenshots/iphone-ui/after/devices.png) |
| `notification-settings` | [Voir](screenshots/iphone-ui/before/notification-settings.png) | [Voir](screenshots/iphone-ui/after/notification-settings.png) |
| `encryption` | [Voir](screenshots/iphone-ui/before/encryption.png) | [Voir](screenshots/iphone-ui/after/encryption.png) |
| `explore` | [Voir](screenshots/iphone-ui/before/explore.png) | [Voir](screenshots/iphone-ui/after/explore.png) |
| `discord-import` | [Voir](screenshots/iphone-ui/before/discord-import.png) | [Voir](screenshots/iphone-ui/after/discord-import.png) |
| `profile-long` | [Voir](screenshots/iphone-ui/before/profile-long.png) | [Voir](screenshots/iphone-ui/after/profile-long.png) |
| `video` | [Voir](screenshots/iphone-ui/before/video.png) | [Voir](screenshots/iphone-ui/after/video.png) |
| `audio` | [Voir](screenshots/iphone-ui/before/audio.png) | [Voir](screenshots/iphone-ui/after/audio.png) |
| `create-channel-error` | [Voir](screenshots/iphone-ui/before/create-channel-error.png) | [Voir](screenshots/iphone-ui/after/create-channel-error.png) |
| `create-channel-loading` | [Voir](screenshots/iphone-ui/before/create-channel-loading.png) | [Voir](screenshots/iphone-ui/after/create-channel-loading.png) |
| `search-error` | [Voir](screenshots/iphone-ui/before/search-error.png) | [Voir](screenshots/iphone-ui/after/search-error.png) |
| `search-loading` | [Voir](screenshots/iphone-ui/before/search-loading.png) | [Voir](screenshots/iphone-ui/after/search-loading.png) |
| `search-results` | [Voir](screenshots/iphone-ui/before/search-results.png) | [Voir](screenshots/iphone-ui/after/search-results.png) |
| `new-dm-results` | [Voir](screenshots/iphone-ui/before/new-dm-results.png) | [Voir](screenshots/iphone-ui/after/new-dm-results.png) |
