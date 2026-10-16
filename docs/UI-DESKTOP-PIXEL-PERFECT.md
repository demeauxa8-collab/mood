# UI desktop — priorité n°1 : fidélité pixel par pixel

Décision utilisateur du 7 octobre 2026. Cette consigne prime sur les anciens
conseils de mise à l’échelle et d’auto-commit. Desktop uniquement.

## Décision et état validé

L’utilisateur a validé visuellement les nouveaux séparateurs de la page Amis
dans **Mood Pixels** : un seul trait net change réellement la qualité de l’UI.
Cette méthode devient la priorité n°1 des prochains travaux UI desktop et doit
être étendue progressivement à toutes les pages, une page à la fois.

Cette validation porte sur les séparateurs observés, pas sur toute l’application.
Les glyphes, icônes, autres états et autres densités d’écran restent à comparer.
Ne jamais transformer « les séparateurs sont validés » en « toute l’UI est parfaite ».

## Pourquoi

Une couleur correcte dans le code ne garantit pas les bons pixels à l’écran.
Un trait peut être étalé sur plusieurs lignes de pixels par la mise à l’échelle,
une position fractionnaire, un contour doublé ou une composition de plusieurs
couches. Il paraît alors flou, plus épais ou entouré d’une autre couleur.

Dans l’ancienne configuration desktop, Catalyst utilisait l’idiome iPad réduit
à environ 77 %, avec une compensation de dimensions de 1.298. Ces transformations
ne garantissaient pas un dessin 1:1 : des franges apparaissaient autour des traits
et des lettres. Changer seulement les couleurs ne réglait pas cette cause.

Le laboratoire utilise désormais l’idiome Mac et une échelle de layout de 1.
Cette correction de la chaîne de rendu permet de vérifier les pixels réellement
produits, plutôt que de juger seulement des constantes SwiftUI.

Références Apple :
[Mac Catalyst](https://developer.apple.com/design/human-interface-guidelines/mac-catalyst),
[choix de l’idiome](https://developer.apple.com/documentation/uikit/choosing-a-user-interface-idiom-for-your-mac-app).

## Où travailler — ne jamais mélanger les versions

- Version normale clean : `/Users/Adm/Applications/Mood.app`.
- Sources de cette base : `/Users/Adm/mood-build`, export de `df964e6`.
- Copie de travail : `/Users/Adm/mood-desktop-pixel-lab`.
- Application expérimentale : `/Users/Adm/Applications/Mood Pixels.app`,
  identité `Mood.mood.pixelLab`.
- Dépôt Git lié au GitHub : `/Users/Adm/mood`. Ce checkout n’est pas à confondre
  avec les sources de l’app clean ni avec la copie expérimentale.

Ne pas remplacer l’app normale ou modifier sa base pour faire des essais.
Conserver le paquet expérimental validé avant tout nouveau remplacement.
Le code peut avancer sans que la dernière compilation soit le rendu validé :
identifier explicitement le paquet lancé, sa provenance et sa capture.

Cette documentation est préparée **localement** dans le dépôt Git et dans le
laboratoire. Aucun commit, push, PR, déclenchement CI, commentaire ou envoi GitHub
n’est autorisé sans nouvelle autorisation explicite. Ne publier ni les captures
personnelles ni les ressources extraites de Discord.

## Comment produire un séparateur net

Dans le laboratoire, les réglages Catalyst de la cible app sont :

```text
TARGETED_DEVICE_FAMILY[sdk=macosx*] = 6
LayoutMetrics.scale = 1.0
```

La condition `sdk=macosx*` est indispensable : ne pas modifier les cibles mobiles.
Ne pas réintroduire la compensation 1.298 ni un scaleEffect pour imiter le rendu.

Le composant partagé `DesktopPixelRule` dans `mood/DesktopPixelRule.swift`
(également utilisé par `DesktopFriendsRule`) dessine une bande rectangulaire remplie,
avec `FillStyle(antialiased: false)`, sans ombre ni contour superposé.
Sur l’écran de référence mesuré à 1×, sa dimension transversale est de 1 point,
soit exactement **1 pixel physique**. Sa couleur est un aplat sRGB mesuré.

Pour chaque nouveau séparateur :

1. Identifier le trait équivalent dans le vrai Discord natif.
2. Mesurer sa couleur et son épaisseur physique, pas seulement sa valeur en points.
3. Dessiner une seule bande opaque, horizontale ou verticale.
4. Aligner ses deux bords sur la grille physique ; contrôler aussi les positions
   des parents, qui peuvent introduire une demi-position malgré une largeur entière.
5. Éviter le cumul bord de panneau + Divider + overlay : un seul élément doit
   posséder la séparation. Vérifier qu’elle n’a pas disparu entre deux colonnes.
6. Ne pas redimensionner ou filtrer une capture pour juger le résultat.

**Attention aux écrans Retina :** 1 point n’est pas toujours 1 pixel.
Pour une cible d’un pixel physique, l’épaisseur logique doit être
`1 / displayScale`, avec les bords alignés à cette grille. Si Discord dessine deux
pixels sur cet écran, reproduire les deux pixels mesurés plutôt que supposer
qu’un pixel logique est la référence. Refaire les mesures après déplacement de
fenêtre vers un écran de densité différente. Le composant adapte désormais
l’épaisseur à `displayScale` ; les tests couvrent 1×, 2× et 3×, mais la validation
par captures ne prouve pas encore l’exactitude à toutes les densités.

## Comment mesurer et accepter le résultat

Ouvrir Mood Pixels et le vrai Discord sur le même écran, dans le même thème,
avec zoom et géométrie comparables.

Utiliser **Digital Colour Meter / la pipette**, affichage sRGB et ouverture
minimale. Relever le cœur du trait, ses voisins et le fond.
Compléter par des captures natives **PNG sans perte**, à résolution réelle,
en tenant compte du profil ICC lors de la conversion en sRGB.

Une capture JPEG, même renommée .png, est inutilisable pour une preuve pixel.
Si la pipette ne suit pas le pointeur automatisé, le signaler : une lecture
des pixels du PNG est une mesure complémentaire, pas un relevé manuel prétendu.

Preuve locale conservée pour la page Amis, le 7 octobre 2026 :
`discord-amis-native.png` et `mood-pixels-ggsans.png`, dans les sorties de cette
conversation. Les mêmes coordonnées sont relatives à chaque fenêtre capturée.
Après conversion ICC vers sRGB, les échantillons correspondent exactement :

| Coupe contrôlée | Discord | Mood Pixels |
|---|---|---|
| Sous l’en-tête, x=600, y=82 | RGB 44,44,49 — #2c2c31 | RGB 44,44,49 — #2c2c31 |
| Voisins y=81 et y=83 | RGB 26,26,30 — #1a1a1e | RGB 26,26,30 — #1a1a1e |
| Bord de la barre serveurs, x=72, y=600 | RGB 38,38,40 — #262628 | RGB 38,38,40 — #262628 |
| Voisins x=71 et x=73 | RGB 18,18,20 — #121214 | RGB 18,18,20 — #121214 |

Ces coupes prouvent un trait unique aux endroits mesurés, pas tous les pixels
de toute sa longueur. Pour chaque extension, vérifier également plusieurs
coupes, la longueur complète hors intersections, les extrémités et les coins.
Dans les zones comparables, accepter seulement les mêmes épaisseurs, positions
et valeurs sRGB ; consigner les écarts, pas seulement une impression de ressemblance.

## Textes et icônes : même exigence, sans faux raccourci

Pour les lettres, vérifier la famille réelle, le fichier et la graisse de police,
la taille, l’interlettrage, la ligne de base et la position fractionnaire.
Même police ne signifie pas automatiquement même rasterisation entre moteurs.

Les courbes et les lettres ont normalement des pixels d’anticrénelage :
ne pas supprimer ces nuances pour les rendre artificiellement « uniformes ».
L’objectif est de reproduire les pixels de Discord, y compris ses pixels de bord,
sans franges parasites ni fonte de substitution.

Le laboratoire contient des références gg sans et des masques d’icônes pour une
comparaison privée. Ne pas les distribuer sans droits appropriés. Les masques
mesurés à 1× ne prouvent pas leur exactitude en Retina, au survol ou dans d’autres états.

## Extension locale « Pixels 2 » — 7 octobre 2026

La règle commune remplace 41 séparateurs rectangulaires de l’interface :
salons, MP, paramètres, invitations, profils et fenêtres secondaires. Les
séparateurs des menus système restent natifs. Ce déploiement de code ne signifie
pas que chacune de ces pages a été comparée à Discord pixel par pixel.

Les largeurs desktop mesurées sont : barre serveurs 72, liste MP/salons 285,
panneau utilisateur 341, membres 264, activité Amis 419 points, à échelle 1.
L’en-tête principal se termine à y=82 (33 + 49). Les offsets fractionnaires
des traits ont été retirés uniquement pour Catalyst.

Les captures finales Amis et salon contrôlent chaque pixel des segments suivants :

| Segment, coordonnées relatives Mood 1600×1032 | Pixels contrôlés | sRGB uniforme |
|---|---:|---|
| Barre serveurs, x=72, y=84…949 | 866 | #262628 |
| Sous l’en-tête latéral, y=82, x=81…348 | 268 | #262628 |
| Sous l’en-tête principal, y=82, x=358…1597 | 1240 | #2c2c31 |
| Liste MP, y=303, x=81…348 | 268 | #262628 |
| Activité Amis, x=1180, y=84…1019 | 936 | #2c2c31 |
| Membres du salon, x=1335, y=84…1019 | 936 | #2c2c31 |

Tous les pixels de ces segments ont la couleur attendue. Aucun trait voisin
de même couleur, sauf le pixel d’intersection de la ligne verticale avec
l’en-tête. Les extrémités arrondies et autres états ne sont pas certifiés.

La police réelle gg sans est utilisée par `Font.mood` sur Catalyst, ainsi
que par les libellés CoreText calibrés. Quatre graisses sont testées sans
substitution. Certains textes définis directement en police système restent
à reprendre. 14 nouveaux masques d’icônes mesurés complètent les références
du pilote : en-tête salon, saisie, invitation, barre de titre.

Les glyphes restent différents du rendu Discord. Un essai optionnel
`-pixelTextMasks` améliore trois libellés mais dégrade « En ligne » : il est
conservé pour recherche, désactivé dans le paquet lancé par défaut. Aucun
masque de capture de mot ne remplace un texte dynamique. Ne pas annoncer
une équivalence complète des moteurs de rasterisation.

Build Catalyst local réussi, signature du paquet installé vérifiée,
16 tests automatisés réussis. Vérifications manuelles en mode démo :
recherche Clara (1 résultat puis 5 après effacement), Tous (6), demandes,
retour Amis, menu ouvert/fermé sans action, MP Clara, panneau membres masqué
puis restauré, paramètres ouverts puis fermés sans modification.
Ces contrôles ne prouvent pas l’envoi réseau ou le fonctionnement du backend.

La méthode de composants SwiftUI a servi à centraliser les traits plutôt
qu’à dupliquer leurs réglages. Les sources de transport et d’authentification
contrôlées sont inchangées. La version clean et ses 24 fichiers Swift/projet
contrôlés sont inchangés. Tous les anciens paquets d’essai ont été conservés.
Aucune suppression de données, aucun commit, push ou envoi GitHub.

## Avancée « Pixels 3 » — 8 octobre 2026

Le nouveau rendu est installé uniquement dans Mood Pixels et actif sans
options spéciales. Les archives de la passe précédente et de chaque essai
restent dans le dossier local `work/pixel-pass3-Nc69jl` de cette conversation.
L’app normale et les 24 fichiers Swift/projet de sa base `df964e6` ont été
recontrôlés : aucun changement. Les six fichiers transport/authentification/
modèles/app contrôlés sont également inchangés. Aucun envoi GitHub.

### Recette de glyphes dynamiques

`CalibratedDesktopText` délègue à `DesktopGlyphRasterizer`, un composant commun
qui utilise la chaîne réelle, sa police et sa graisse ; pas une capture de mot.

1. Garder la largeur typographique réelle, sans arrondir chaque libellé au point
   entier, pour éviter le cumul de décalages entre les onglets.
2. Dessiner chaque glyphe avec `CTFontDrawGlyphs`, à position physique au quart
   de pixel. Stabiliser uniquement le bruit de phase de layout sur 1/64 pixel ;
   ne pas déplacer l’origine réelle du composant.
3. Dessiner le masque noir sur blanc avec lissage CG, puis inverser sa
   précompensation (`1 - black²`, arrondi entier) et convertir en couverture
   monochrome. Le lissage des courbes est conservé.
4. Composer en sRGB avec la couleur de texte et le fond opaque connu de l’état
   (sélection, survol ou fond normal). Sans fond opaque connu, conserver l’alpha.
   Respecter l’opacité du texte ; ne jamais transformer les emoji couleur en
   masques monochromes. La voie native reste disponible en repli.
5. Livrer à la résolution de `displayScale`, sans interpolation. Cache borné à
   200 images et 8 Mio ; clef comprenant texte, fonte, taille, bornes, densité,
   phase et couleurs. Garder le texte comme label d’accessibilité.

L’inversion du masque s’appuie sur le code primaire du
[rasteriseur macOS de Skia](https://skia.googlesource.com/skia/+/refs/heads/main/src/ports/SkScalerContext_mac_ct.cpp).
La phase au quart de pixel et la stabilisation 1/64 sont des choix validés par
nos comparaisons locales, pas une preuve des paramètres exacts du Discord
installé. La composition retenue est une approximation mesurée ; ne pas
annoncer une équivalence parfaite de tout Skia et CoreText.

La méthode SwiftUI a servi à garder un seul composant et un cache borné,
avec repli natif, au lieu de corrections propres à chaque mot.

### Mesures natives à 1×, thème sombre

PNG natifs lossless, profil ICC converti en sRGB. Discord est la référence
fraîche du 8 octobre ; Mood est le paquet effectivement installé. Erreur =
moyenne de la différence absolue des trois canaux, sur l’union des pixels
d’encre (écart au fond > 12), et non sur une grande zone essentiellement vide.

| Libellé mesuré | Avant | Pixels 3 |
|---|---:|---:|
| Amis, navigation latérale | 20,1190 | 1,0123 |
| Amis, en-tête | 18,0308 | 0,6850 |
| Recherche ou lance une conversation | 23,4216 | 0,8596 |
| En ligne, onglet | 21,8516 | 1,1369 |
| En ligne, titre du panneau activité | 60,0700 | 0,4602 |

Unités : niveaux RGB sur 255, pas pourcentages. Les cinq résultats Pixels 3
ont leur meilleur alignement à **dx=0, dy=0**, sans déplacer la capture.
Le panneau à droite est comparé selon son ancrage au bord droit, les fenêtres
ayant des largeurs différentes. Le tableau utilise les positions non corrigées.
Avec une correction dy=1, l’ancien titre d’activité donnait encore 30,1106 ;
sa ligne de base a été corrigée dans le layout de Pixels 3.
Les rectangles sont fixes et aucun redimensionnement d’image n’est effectué.

**Le 1:1 complet n’est pas acquis.** De nombreux pixels de bord restent
différents malgré leur faible écart moyen. Les textes multilignes, les champs
éditables, les textes définis directement en police système, les autres
libellés, états et densités ne sont pas certifiés par ces cinq mesures.

Les bandes contrôlées restent uniformes sur un pixel : barre serveurs,
sous-en-têtes, ligne MP et bord du panneau activité/membres. Aucune bande
voisine de même couleur, hors intersection avec l’en-tête. Le contrôle couvre
866, 268, 1240, 268 et 830 pixels selon le segment, pas les coins arrondis.

Build local réussi, signature vérifiée, paquet installé identique au build.
22 tests passent (dont six nouveaux tests de glyphes : phase, couverture,
bornes invalides, densité/cache, opacité/fond, troncature/emoji). Navigation
locale contrôlée : Clara (1 résultat, puis 5 après effacement), Tous (6),
demandes et retour Amis, menu ouvert/fermé sans action, MP Clara, membres
masqués/restaurés, paramètres ouverts/fermés sans modification.
Ce sont des contrôles en démo, pas une validation réseau du backend.

Paramètres de diagnostic, à utiliser seulement pour comparaison :

- `-pixelNativeText` : ancien dessin CTLine natif, nouveau moteur désactivé.
- `-pixelTextMasks` : premier essai conservé, nouveau moteur désactivé.
- `-pixelGlyphCanvas` : livraison Canvas au lieu d’Image.
- `-pixelGlyphTransparent` : composition alpha au lieu du fond opaque connu.

Les anciens arguments `-pixelGlyphQuarter`, `-pixelGlyphImage` et
`-pixelGlyphOpaque` ne sont plus nécessaires : c’est maintenant le défaut
desktop. La branche non-Catalyst ne les utilise pas.

## Pixels 4 — correction colorimétrique des contours de lettres (8 octobre)

### Pourquoi et comment

La même police et les mêmes positions ne suffisent pas : les pixels de bord
des caractères gris étaient encore trop clairs. La lecture du
[code macOS de Skia](https://skia.googlesource.com/skia/+/refs/heads/main/src/ports/SkTypeface_mac_ct.cpp)
montre une correction de luminance de l’encre dans le chemin de lissage
CoreGraphics. Le [calcul des tables de couverture](https://chromium.googlesource.com/skia/+/d2b9e48baf1697760afc1dc8ea3ad40110b8cacc/src/core/SkMaskGamma.cpp)
sert de référence pour une correction commune, et non pour redessiner chaque mot.

Dans le laboratoire, la luminance de l’encre est calculée par les coefficients
54/183/19, divisés par 256. Elle est réduite de moitié avant canonicalisation
sur trois bits. Huit tables de 256 valeurs corrigent ensuite la couverture.
Le modèle mesuré utilise gamma 1,75, contraste nul et une table neutre pour
le groupe le plus clair (224–255). Cette exception commune préserve les textes
blancs déjà mesurés. La composition opaque sRGB sur fond connu utilise une
division entière par 255 sans ajouter un arrondi de bord.

Ce sont des **paramètres empiriques du laboratoire**, pas une identification
des paramètres internes du Discord installé, ni une équivalence de tous les
rendus de Skia. Pas de réglage par mot ni de capture collée à la place du texte.
Le cache et le repli natif restent communs, conformément au guide SwiftUI.

La palette desktop distingue maintenant le gris des onglets inactifs
(`#abacb2`), celui du titre MP (`#81828a`) et l’indication de recherche
(`#8f9097`). « Messages privés » passe en gg sans Medium 14 ; la section
« En ligne » en Medium 14, `#efeff1`. Deux décalages entiers d’un pixel ont été
corrigés sans modifier les séparateurs. L’indication de recherche utilise le
moteur commun uniquement à vide ; le vrai champ demeure éditable et conserve
son libellé d’accessibilité « Rechercher ».

L’essai de composition RGB 16 bits et l’essai de mélange dans le profil natif
de l’écran ont dégradé les mesures : ils n’ont pas été retenus. Leurs scripts,
captures, source d’essai et paquets précédents sont conservés dans le dossier
de travail `pixel-pass4-gFUNDf`, sans suppression des versions antérieures.

### Contrôle du paquet livré

Comparaison de la même référence Discord native et du paquet Mood Pixels
installé, PNG lossless, ICC converti en sRGB, sans redimensionnement. Même
métrique d’union de pixels d’encre (>12 du fond) que Pixels 3. Rectangles fixes.

| Libellé | Pixels 3 | Pixels 4 |
|---|---:|---:|
| Amis, navigation latérale | 1,0123 | 0,7281 |
| Amis, en-tête | 0,6850 | 0,6315 |
| Recherche ou lance une conversation | 0,8596 | 0,6692 |
| En ligne, onglet | 1,1369 | 0,8287 |
| En ligne, panneau activité | 0,4602 | 0,4608 |
| Demandes de message | 5,4447 | 0,8255 |
| Nitro | 4,7170 | 0,8365 |
| Boutique | 5,2013 | 0,7772 |
| Quêtes | 5,8974 | 0,8042 |
| Tous, onglet inactif | 13,9102 | 5,8212 |
| En attente, onglet inactif | 11,3640 | 2,6345 |
| Messages privés | 65,7173 | 0,6533 |
| Rechercher, indication à vide | 58,7772 | 1,0939 |
| En ligne, préfixe du titre de section | 97,9120 | 0,7728 |

Niveaux RGB sur 255, pas pourcentages. Les quatorze meilleurs alignements
sont dx=0, dy=0 ; les chiffres sont ceux des positions non corrigées.
Le panneau activité est ancré à droite. Le titre de section est mesuré avant
le compteur, qui diffère entre comptes. Le titre du panneau activité est
pratiquement inchangé : 0,4602 → 0,4608 n’est pas une amélioration.

**Pas de 1:1 exact annoncé.** Les bords des deux onglets gris restent
prioritaires. Les pixels de bord non identiques subsistent même sous un niveau
RGB moyen ; les contenus variables, saisies, autres pages et densités ne sont
pas certifiés par ces mesures. La pipette Digital Colour Meter a été vérifiée
en sRGB, mais sa lecture ne suit pas les clics automatisés ici : les valeurs
de cette passe proviennent des PNG, pas d’un relevé manuel de chaque pixel.

Les cinq segments Amis et quatre segments serveur contrôlés restent uniformes,
sur un seul pixel physique. Seule l’intersection en-tête / panneau compte
un pixel voisin de même couleur ; pas de double bande. 25 tests passent,
dont trois nouveaux contrôles des tables de couleur et de la composition.
Recherche Clara : un résultat puis cinq après effacement ; Tous : six ;
En attente : état vide ; retour En ligne et libellé accessible vérifiés en démo.

Paquet Catalyst `Mood.mood.pixelLab`, minimum macOS 14.0, signature vérifiée,
lancement réel contrôlé. Binaire livré identique au build local : SHA-256
`36991bdca7cd200bc6e96770e39eb98edd152a0e327b824cedd9f640e14ccbfe`.
Les 24 sources / réglages de la base clean et le binaire de Mood normal
restent identiques ; les fichiers backend contrôlés sont inchangés.
Aucun commit, push, CI, PR ou publication GitHub. Documentation locale seulement.

## Ordre de travail prioritaire

1. Conserver le rendu des séparateurs validé sur Amis ; ne pas le dégrader.
2. Étendre les séparateurs à une autre page desktop dans la copie seulement :
   barre serveurs, liste des MP/salons, en-tête, contenu, panneaux latéraux.
3. Contrôler les contours de champs et boutons avec la même méthode.
4. Finaliser les contours d’icônes et les glyphes par comparaison mesurée.
5. Répéter page par page et état par état, puis vérifier les autres densités d’écran.

Pour chaque étape : capture avant/après, mesures, build local du bon paquet,
lancement réel et contrôle des interactions. Distinguer compilation réussie,
tests fonctionnels et validation visuelle. Aucun travail mobile, web ou backend
n’entre dans cette priorité.

Une intégration dans la version normale, une diffusion des ressources ou une
publication GitHub exige une décision distincte de l’utilisateur.

## Pixels 5 — parcours UI/UX natif du 8 octobre

Voir [le bilan de livraison et les limites](PIXELS-5-BILAN.md).
La recette reste inchangée : capture native PNG, conversion ICC vers sRGB,
grille physique, mesure avant/après et essais dans le paquet livré. Computer
Use sert aux interactions, pas à mesurer une image JPEG compressée.

Les nouvelles corrections concernent la navigation commune, Ajouter intégré,
la recherche des invitations, les paramètres centrés, le profil latéral des
MP et les polices des salons/membres/messages. La base clean et le backend
restent inchangés. 29 tests passent, complétés par des contrôles UI natifs.

Trois textes des paramètres donnent, sans recalage du ROI : Compte 0,6103,
Infos du compte 0,4988, Rechercher 0,9002 RGB moyen sur 255. Les traductions
géométriques connues des fenêtres centrées sont documentées dans le script.
Le sélecteur donne 0,9381 sur son texte statique, après exclusion explicite
de 27 pixels du curseur UIKit bleu clignotant ; conserver aussi l’erreur brute.
Cette exclusion ne valide PAS le curseur, ni l’identité de l’écran complet.
Tous et En attente gardent les écarts Pixels 4 (5,8212 et 2,6345).

Ne pas confondre ces contrôles avec un 1:1 global. Les panneaux épinglés,
menus contextuels, profils complets, parcours du lien d’aide, redimensionnement
des colonnes, saisie éditée et nombreuses pages restent à reprendre. Les
services Discord absents de Matrix ne doivent pas être simulés comme actifs.
