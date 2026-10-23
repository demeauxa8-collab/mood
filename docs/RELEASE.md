# Mood — livrer une version

## Mac : le .dmg
`scripts/make-dmg.sh` (sur le Studio) → `build/Release-dmg/Mood.dmg` : version **Release** de l'app Mac
(Mac Catalyst), signée **ad hoc** (pas de compte Apple Developer), avec un raccourci « Applications ».

Installer : ouvrir le .dmg, glisser **Mood** dans **Applications**.
**Premier lancement sur un autre Mac** : l'app n'est pas notarisée, macOS la bloque. Clic droit sur Mood →
**Ouvrir** → **Ouvrir**. Si macOS dit « endommagée » : Réglages Système › Confidentialité et sécurité →
« Ouvrir quand même », ou dans un Terminal : `xattr -dr com.apple.quarantine /Applications/Mood.app`.
Pour supprimer ces étapes : compte Apple Developer (99 €/an) → signature Developer ID + notarisation.

Le serveur Mood doit tourner (Mac Studio allumé) : l'app s'y connecte par Internet.

## iPhone
- Son iPhone : `scripts/install-iphone.sh` (Xcode ouvert sur le projet, destination « iPhone de ADM »),
  à refaire tous les 7 jours (compte Apple gratuit).
- Un autre iPhone : le brancher au Studio, Mode développeur activé, l'ajouter comme destination dans Xcode,
  puis « Faire confiance » au développeur dans Réglages › Général › VPN et gestion de l'appareil.
- Pour distribuer à d'autres sans câble : compte Apple Developer → TestFlight.

## Icône
`python3 scripts/make-app-icon.py mood/Resources/Assets.xcassets/AppIcon.appiconset` regénère l'icône
(deux « o » entrelacés, violet `#6e56cf` / bleu `#2997ff`) : version iPhone pleine et plaque macOS.
