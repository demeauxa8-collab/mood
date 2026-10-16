# Pixels 7 — capsules desktop, 9 octobre 2026

## Résultat et périmètre

Passe UI terminée à la demande de l’utilisateur. Dernier ordre : petites
finitions rapides, aucune attaque des parcours/animations UX. L’essai de
menu flottant et de fondu 100 ms a été retiré du build final. Les enregistrements
restent privés et ne valident pas une sensation ou un timing identiques.
L’intégration à Mood normal n’est PAS faite ni autorisée par cette clôture.

Mac Catalyst uniquement, copie `/Users/Adm/mood-desktop-pixel-lab`, paquet
`/Users/Adm/Applications/Mood Pixels.app`, identifiant `Mood.mood.pixelLab`.
Aucun commit, push, envoi GitHub, changement de backend ou d’identité de compte.
Mood normal et ses 24 fichiers de référence sont inchangés. Les applications
précédentes sont conservées ; aucun build n’a été supprimé.

La bio n’est plus affichée dans la capsule utilisateur desktop. Le statut court
reste visible. La bio dans le modèle et les autres vues n’a pas été effacée.
La photo Discord de l’utilisateur est visible dans cet aperçu. Elle vient d’une
extraction native de la photo affichée à 72 × 72 dans son profil, sans icône
de survol ni badge. Ce n’est pas le fichier original haute résolution.
Fichier privé : `~/Library/Application Support/Mood Pixels/ReferenceAvatar.png`.
Chargement uniquement sous Catalyst calibré avec `-uiPreview` ; pas de photo
embarquée dans le projet, de modification du profil Discord ou d’upload Matrix.

## Pourquoi et comment les contours ont changé

Le bon rayon et la bonne couleur ne suffisent pas : les couvertures partielles
des pixels de coin diffèrent entre les moteurs de rendu. `DesktopCornerCoverage`
intègre des tranches de cercle et génère une petite tuile alpha symétrique,
indépendante des couleurs, mots, personnes et captures. Cache limité à 24 entrées
et 1 Mio. Seul le centre de la tuile s’étire ; les coins gardent leur grille
physique. L’intérieur est décalé d’un seul pixel physique, pas d’un point fixe.
Cette utilisation des portions non étirées suit le mécanisme
[capInsets de SwiftUI](https://developer.apple.com/documentation/swiftui/image/resizable%28capinsets%3Aresizingmode%3A%29/).

Les rayons mesurés restent 8 pt (saisie, utilisateur, bouton profil) et 9 pt
(carte profil). La colonne profil de Pixels 6 est de 320 pt, carte de 306 pt
avec marges de 7 pt. Ne pas rétablir le vieux filet vertical supplémentaire.

Discord possède deux états de saisie mesurés : fond #222327, bord inactif
#27282c, bord actif #323338. `FocusState` suit le vrai champ ; pas de changement
visuel mobile ni de règle Échap inventée. Le bouton profil utilise désormais
le fond #323338 et le bord #37383d. Les textes de la capsule connaissent leur
fond #202024 pour la composition des pixels de bord des glyphes.

## Vérification native et limites

Références Discord natives : conversation Alban, 1920 × 963 ; Mood : Clara,
1600 × 1032. Échelle physique 1× dans les deux cas, sans redimensionnement des
PNG. Profils ICC convertis en sRGB avant mesures. Origines définies par la
géométrie connue, pas de décalage recherché pour minimiser l’erreur.
Chaque coin est une région fixe 12 × 12. Pour les deux coins hauts du profil,
seule la bande extérieure est mesurée : la bannière personnelle n’est pas
comparable. Les pixels de bord sont sélectionnés uniquement dans la référence,
en excluant ses aplats connus, pour éviter de diluer l’erreur dans le fond.

Moyenne des quatre coins, erreur RGB sur 255, pixels de transition seulement :

| Capsule | Avant | Après | Écart maximal après |
| --- | ---: | ---: | ---: |
| Saisie active | 1,5842 | 0,8989 | 3 |
| Utilisateur | 0,7812 | 0,6667 | 3 |
| Carte profil | 0,9991 | 0,6671 | 2 |
| Bouton profil | 1,2500 | 0,5625 | 2 |

Les seize coins sont améliorés. Saisie inactive : erreur de transition
0,6842–0,7059, maximum 2. Les aplats droits du contour correspondent aux couleurs
mesurées. La délimitation haute y=33 reste #262628, sans seconde bande y=32.
Le rail x=72 et les séparateurs y=82 restent d’un pixel uniforme, sans pixel
adjacent de la même couleur dans les zones contrôlées.

33 tests passent : géométrie, masques symétriques et caches, densités 1/2/3,
entrées invalides, polices, séparateurs et tests existants. Les densités 2/3
sont testées mathématiquement, PAS validées visuellement sur un écran Retina.
Paquet installé : minimum macOS 14.0, bibliothèque identique au build testé.
Le SHA-256 du paquet de clôture est conservé dans `package-close.sha256`
avec les preuves privées ci-dessous ; les anciennes apps sont retenues.

Computer Use : saisie locale de « Test », effacement complet par retours arrière,
aucun envoi. Navigation rapide prend le focus ; après fermeture, le contour
de saisie retourne effectivement à #27282c. Photo et disparition de la bio
vérifiées dans le paquet réellement installé.

Preuves privées, journaux, PNG avant/après, mesures et backups :
`/Users/Adm/Documents/Codex/2026-10-07/le-probl-me-de-mood-l/work/pixel-pills7-064zPq`.
Ne pas publier ces captures privées. Les mesures viennent des PNG, pas d’une
affirmation de pipetage manuel de chaque pixel avec Digital Colour Meter.

## Priorité suivante

Le blanc plein relevé sur les libellés contrôlés est #fbfbfb, pas #ffffff.
Dernière finition : « Voir le profil complet », gg sans Medium 16 pt au lieu
de 14 pt, avec la ligne de texte remontée d’un point mesuré. Sa boîte d’encre
est maintenant identique à la référence : x=62…206, y=13…28 dans le bouton.
Les 212 pixels de blanc plein de la référence sont tous exactement #fbfbfb
aux mêmes positions dans Mood. Sur 775 pixels de texte sélectionnés uniquement
dans la référence, l’erreur moyenne passe de 107,9424 à 0,7656 sur 255 ; maximum
3. La couleur seule était déjà correcte, pas la taille et la ligne du glyphe.
Ces mesures n’affirment PAS que toutes les lettres de l’app sont identiques.

Les 2–3 niveaux RGB résiduels sur les contours de courbe, les états de survol
et le contour de l’avatar/statut restent documentés. Le fichier de photo extrait
n’est pas une preuve d’identité des pixels de l’avatar à 32 pt. Ne pas modifier
les seize améliorations et les séparateurs nets sans nouvelle comparaison.
Ni cette passe ni les tests ne valident toute l’application en 1:1. Ne pas
poursuivre l’UX sans nouvelle demande. Ne pas fusionner la copie à l’aveugle :
photo de référence locale privée et polices de comparaison ne sont pas des
ressources de production à publier ; conserver les chemins natifs de l’app.
