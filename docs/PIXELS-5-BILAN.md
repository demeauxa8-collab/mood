# Mood Pixels 5 — bilan local, 8 octobre 2026

La copie desktop a été recompilée, installée et parcourue avec Computer Use.
Le 1:1 global n’est pas terminé. Aucun commit, push, CI, PR ou envoi GitHub.

## Ce qui a changé

| Zone | Correction et vérification |
| --- | --- |
| Navigation rapide | Un composant commun pour Cmd-K et la recherche latérale ; index des serveurs, salons et MP réellement chargés ; filtres @, #, ! et *. Flèches, Entrée et Échap vérifiés. Tab ne change pas la sélection et ne casse plus Entrée. |
| Amis | Ajouter dans la page, pas une fenêtre séparée ; recherche conservée dans En attente et appliquée aux invitations. Onglet En ligne absent sans présence en ligne : logique testée, pas de compte réel utilisé pour ce cas. |
| Paramètres | Fenêtre centrée de 1400 pt, marges verticales 72 pt, sidebar 253 pt, en-tête 49 pt et trait physique 1 px. Recherche des catégories et Échap testés. Compte présente les données Mood/Matrix ; aucun faux e-mail ou téléphone. Le bouton Profil n’annonce pas une modification de l’identifiant utilisateur. |
| MP | Profil latéral 312 pt + trait 1 px, masquable ; en-tête 16 Medium, introduction alignée à gauche, saisie 16 et placeholder « à @… ». La date de compte n’est pas inventée si la source ne la fournit pas. |
| Salons et membres | Salon actif visible même après lecture ; noms salons/membres 16 Medium, catégories et en-têtes rapprochés du référentiel ; texte des messages 16. Pas de validation pixel exhaustive de cette page. |

La structure suit le guide SwiftUI : composants communs, état local du
sélecteur, cibles identifiées et extraction du contenu de conversation.
Les branches de calibration restent réservées au desktop Catalyst.

## Mesures natives

PNG lossless avec profil ICC converti vers sRGB, écran 1×. Les fenêtres ont
des largeurs différentes : les éléments centrés sont comparés avec leur
translation géométrique connue, pas un décalage choisi pour améliorer l’erreur.
Les quatre textes ci-dessous sont à leur position attendue (meilleur dx/dy 0).

| Texte | Erreur RGB moyenne sur 255 | Pixels d’encre exactement identiques |
| --- | ---: | ---: |
| Compte (en-tête paramètres) | 0,6103 | 131 / 343 |
| Infos du compte | 0,4988 | 541 / 1118 |
| Rechercher (paramètres) | 0,9002 | 107 / 424 |
| Où désires-tu aller ? (texte statique) | 0,9381 | 458 / 1152 |

Pour le dernier texte, 27 pixels du curseur bleu UIKit clignotant sont
explicitement exclus. Le JSON conserve la mesure brute et la mesure excluant
le curseur ; ce n’est ni une retouche de capture ni une validation du curseur.
Les douze zones améliorées de Pixels 4 restent inchangées, entre 0,46 et 1,10.
Tous reste à 5,8212 et En attente à 2,6345. Une faible moyenne ne signifie PAS
que chaque pixel est identique.

Les bandes de séparateurs contrôlées sur Amis et les nouveaux fonds/traits
des paramètres et du profil MP ont leur couleur sRGB exacte. La bande d’un
pixel croise parfois un autre trait : le voisin identique à cette intersection
ne correspond pas à une ligne de deux pixels. Les contrôles ne couvrent pas
tous les contours arrondis de l’application.

## Build, préservation et preuves

29 tests dans 4 suites passent. Le paquet réellement installé est
`/Users/Adm/Applications/Mood Pixels.app`, identifiant `Mood.mood.pixelLab`,
minimum macOS 14.0, signature vérifiée. Lancement natif contrôlé en `-uiPreview`.
Le SHA-256 de `mood.debug.dylib` dans le build et dans l’app installée est
`38a9b8fab29e5d8e2735853b4011ead300cf9df7d72a0556c6c0fe54dc2efb07`.
Les captures `*-delivery.png`, `new-ux-measures-final.json`,
`friends-rules-final.json`, `online-roi-final.txt`, `clean-proof-final.json`
et `scope-proof-final.txt` contrôlent cette livraison. La mesure brute du
placeholder de recherche vaut 3,6113 avec le curseur présent ; le texte
statique reste à 0,9381 après son exclusion explicitement décrite ci-dessus.
Les contrôles de transport, appels, invitations réelles et compte réel ne sont
pas réalisés : aucun message, appel, achat ou changement de compte Discord.

La base `/Users/Adm/mood-build` garde ses 24 sources/réglages identiques.
`/Users/Adm/Applications/Mood.app` garde son binaire original
`6a04619a5f253d5fe3c031af2b9bfd944e85bbf875248cc9855b7c042b9a26d1`.
MatrixClient, MatrixStore, FileAttenteMessages, KeychainHelper, Modeles et
moodApp sont inchangés. Aucun travail ni build mobile/web.

Les versions Pixels précédentes et les sources avant/après sont conservées
dans `/Users/Adm/Documents/Codex/2026-10-07/le-probl-me-de-mood-l/work/pixel-pass5-iw053Q`.
Ce dossier contient les captures privées Discord (ne pas diffuser), les PNG
Mood, les logs de tests, les scripts de mesures et les preuves de préservation.
La capture finale publique locale est dans `outputs/mood-pixels-5-mp.png`.

Le champ Catalyst traite les commandes sur le premier répondant : la priorité
des commandes sur le traitement de texte/focus est décrite par
[Apple](https://developer.apple.com/documentation/UIKit/UIKeyCommand/wantsPriorityOverSystemBehavior).
Ce comportement a été vérifié dans l’app, pas déduit de la compilation.

## À terminer, dans l’ordre

1. Contours et couverture des glyphes Tous / En attente, puis curseur et saisie éditée.
2. Menus contextuels, épinglés (encore ancien panneau Mood), recherche de messages, profil complet et redimensionnement des colonnes.
3. Lien d’aide et son parcours Maj-Tab : Discord lui donne le focus, Mood garde actuellement le champ actif. Ne pas annoncer une UX clavier intégralement identique.
4. Autres pages, états de survol/erreur/désactivation et densités Retina, avec une référence native comparable pour chaque état.
5. Séparer fidélité visuelle et services Discord absents de Matrix (Nitro, Boutique, etc.). Toute extension backend ou publication nécessite une autorisation distincte.
