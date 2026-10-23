# Captures du premier accueil — piste V

**Aucune capture avant/après produite dans cette session.** La consigne directe du 23 octobre interdit
de lancer une app Mac ou un simulateur, y compris le simulateur dédié de V. Elle prime sur la demande
de captures du brief. Aucun rendu n'a été inspecté et aucune fidélité pixel par pixel n'est annoncée.
Ce dossier contient donc un index de préparation, pas des preuves visuelles.

Les routes suivantes sont préparées, mais n'ont pas été lancées :

| Argument après `-uiPreview -uiPreviewScreen` | Contenu |
|---|---|
| `first-run-server` | Nouveau serveur, checklist et début de #général |
| `first-run-channel` | Début d'un salon, avec action Modifier |
| `first-run-dm` | Début d'un MP avec nom Mood connu |
| `first-run-friends` | Amis vides, action Ajouter un ami |
| `first-run-notifications` | Notifications vides existantes |
| `first-run-search` | Recherche existante sans résultat |
| `first-run-server-long` | Nom de serveur long |
| `first-run-dm-long` | Nom d'affichage long |
| `first-run-large-text` | Checklist en Dynamic Type accessibility3 |

Ces routes s'appuient sur le présentateur mobile existant (`MobileUIPreviewSheet`), sans modification de
la racine de l'app. Les aperçus SwiftUI « First server » et « First server desktop » se trouvent dans
`FirstRunPreview.swift`. Leur présence ne prouve pas un lancement ni une inspection du rendu.

Lors d'une future validation autorisée : utiliser exclusivement **Mood V iPhone**, une identité d'app
isolée et ses propres données, jamais iPhone 18 Pro, Mood Mobile Review ni l'app de démo installée.
Prévoir une référence avant changements, puis comparer chaque état à taille native. Vérifier les étapes
cochées, le vrai focus de saisie, les droits insuffisants, les noms inconnus, les textes longs, VoiceOver,
Dynamic Type et Reduce Motion. Éteindre ensuite uniquement ce simulateur dédié.

Pour le bureau, appliquer le protocole de `docs/UI-DESKTOP-PIXEL-PERFECT.md` après autorisation : captures
PNG natives, référence Discord, même densité, mesures des traits et des glyphes. Les builds actuels ne
constituent pas une validation visuelle.
