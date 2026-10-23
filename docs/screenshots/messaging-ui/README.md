# Captures K

Captures iPhone natives, mode démo uniquement, ouvertes pour contrôle visuel. Aucun compte réel ni secret. Le simulateur utilisé est **Mood K iPhone**, UUID `383EDCD4-EEA5-4263-9482-6A135645D9F5`.

Pour reproduire, installer le build iPhone dans ce simulateur, puis lancer `Mood.mood` avec `-uiPreview` et les arguments ci-dessous. Terminer uniquement l’app de ce simulateur entre deux lancements. Aucun lancement de Mood Mac.

| Fichier | Arguments complémentaires |
|---|---|
| chat.png | `-uiPreviewScreen chat` |
| mentions.png | `-uiPreviewScreen chat -messagingPreview mentions` |
| reply.png | `-uiPreviewScreen chat -messagingPreview reply` |
| attachment.png | `-uiPreviewScreen chat -messagingPreview attachment` |
| edit.png | `-uiPreviewScreen chat -messagingPreview edit` |
| pins.png | `-uiPreviewScreen chat -messagingPreview pins` |
| settings.png | `-uiPreviewScreen server -messagingPreview settings` |
| invite.png | `-uiPreviewScreen server -messagingPreview invite` |
| create-channel.png | `-uiPreviewScreen server -messagingPreview create-channel` |
| create-server.png | `-uiPreviewScreen create-server -messagingPreview create-server` |
| join-server.png | `-uiPreviewScreen join-server -messagingPreview join-server` |

Capture : `xcrun simctl io 383EDCD4-EEA5-4263-9482-6A135645D9F5 screenshot <fichier.png>`.
Attendre le rendu complet après le lancement ; un premier cliché peut précéder la stabilisation du simulateur sans fenêtre. Les fixtures d’édition, de mentions et de pièce jointe montrent des états de présentation, pas des succès réseau. Les noms/messages proviennent des données de démonstration du projet.

Les images ne prouvent pas le fonctionnement à deux comptes, l’accessibilité complète ni le rendu Mac. Voir `../../MESSAGING-SERVERS.md` pour les vérifications et limites.
