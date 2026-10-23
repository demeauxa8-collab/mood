# Captures — passe premium X

## Passe visuelle 2

Les séries `visual-before/` et `visual-after/` comparent les états dans **Mood X iPhone**, sans compte. Les PNG sont des captures natives ; les planches de comparaison ne les remplacent pas. Le simulateur dédié est éteint après vérification.

| État / route `premium-…` | Avant | Après |
|---|---|---|
| Hors ligne (`offline`) | [Avant](visual-before/offline.png) | [Après](visual-after/offline.png) |
| Mood injoignable (`unreachable`) | [Avant](visual-before/unreachable.png) | [Après](visual-after/unreachable.png) |
| Envoi refusé (`failed`) | [Avant](visual-before/failed.png) | [Après](visual-after/failed.png) |
| Annulation (`undo`) | [Avant](visual-before/undo.png) | [Après](visual-after/undo.png) |
| Reprise (`recovered`) | [Avant](visual-before/recovered.png) | [Après](visual-after/recovered.png) |
| Micro refusé (`permission`) | [Avant](visual-before/permission.png) | [Après](visual-after/permission.png) |
| Photo inaccessible (`photos`) | [Avant](visual-before/photos.png) | [Après](visual-after/photos.png) |
| Notifications refusées (`notifications`) | [Avant](visual-before/notifications.png) | [Après](visual-after/notifications.png) |
| Photo trop lourde (`large-photo`) | [Avant](visual-before/large-photo.png) | [Après](visual-after/large-photo.png) |
| Session expirée (`session`) | [Avant](visual-before/session.png) | [Après](visual-after/session.png) |
| Connexion lente (`loading`) | [Avant](visual-before/loading.png) | [Après](visual-after/loading.png) |
| Salon vide (`empty`) | [Avant](visual-before/empty.png) | [Après](visual-after/empty.png) |
| Conversation neutre (`before`) | [Avant](visual-before/before.png) | [Après](visual-after/before.png) |

La file de l’aperçu hors ligne/injoignable contient maintenant **deux** messages pour vérifier le compteur et les regroupements ; la première série en contenait un. La route `premium-recovered` commence hors ligne puis change réellement les états synthétiques après deux secondes ; les coches « Envoyé » restent deux secondes. Les confirmations sont capturées au moment de la reprise par XCTest.

Les six planches U ont été ouvertes pour la comparaison de langage visuel. Les premières captures blanches et les essais où la capsule d’annulation couvrait un message ont été corrigés puis remplacés dans la série finale.

Interactions finales : [détails réseau](visual-after/offline-details.png), [connexion Mood après expiration](visual-after/session-login.png), [après Renvoyer](visual-after/failed-after-retry.png), [après Supprimer](visual-after/failed-after-discard.png), [avant Annuler](visual-after/undo-before-tap.png), [après Annuler](visual-after/undo-after-tap.png), [sélecteur de pièces jointes](visual-after/large-photo-file-picker.png), [coches de reprise](visual-after/recovered-message-checkmarks.png), [après disparition des coches](visual-after/recovered-settled.png), [capsule testée](visual-after/offline-capsule.png).

Contrôles complémentaires, comparés aux captures de première passe : [amis vides](visual-after/first-run-friends.png), [notifications vides](visual-after/first-run-notifications.png), [erreur de formulaire](visual-after/create-channel-error.png), [chargement de formulaire](visual-after/create-channel-loading.png).

## Première passe conservée pour historique


PNG capturés dans **Mood X iPhone**, ouverts et inspectés individuellement. Les images ne sont pas retouchées. La première série (démarrage blanc / confirmation système de lien) a été remplacée après inspection. Le bandeau qui masquait l’en-tête a été corrigé puis recapturé.

`before-chat.png` est la capture du code de départ, avant modifications. `before-fixture.png` montre la conversation synthétique neutre ; ce n’est pas une reconstitution des anciens états manquants. Les autres images montrent les nouveaux états. La barre, le micro et l’en-tête restent présents.

| Route `-uiPreview -uiPreviewScreen` | Capture |
|---|---|
| `premium-before` | [Conversation neutre](before-fixture.png) |
| `premium-offline` | [Hors ligne et file](after-offline.png) |
| `premium-unreachable` | [Service injoignable](after-unreachable.png) |
| `premium-failed` | [Envoi refusé](after-failed.png) |
| `premium-recovered` | [Reprise](after-recovered.png) |
| `premium-undo` | [Annulation disponible](after-undo.png) |
| `premium-permission` / `premium-microphone` | [Micro refusé](after-permission.png) |
| `premium-photos` | [Photo inaccessible](after-photos.png) |
| `premium-notifications` | [Notifications refusées](after-notifications.png) |
| `premium-large-photo` | [Photo trop lourde](after-large-photo.png) |
| `premium-session` | [Session expirée](after-session.png) |
| `premium-loading` | [Connexion lente](after-loading.png) |
| `premium-empty` | [Salon vide connu](after-empty.png) |
| `first-run-friends` | [Amis vides](first-run-friends.png) |
| `first-run-notifications` | [Notifications vides](first-run-notifications.png) |
| `create-channel-error` | [Erreur de formulaire](create-channel-error.png) |
| `create-channel-loading` | [Attente de formulaire](create-channel-loading.png) |

Captures des interactions XCTest : [avant Annuler](undo-before-tap.png), [après Annuler](undo-after-tap.png), [après Réessayer](failed-after-retry.png), [après Supprimer](failed-after-discard.png), [sélecteur réellement ouvert](large-photo-file-picker.png).

Les états sont des fixtures isolées, sans session réelle ni restauration de secrets. La reprise HTTP et l’annulation des requêtes sont vérifiées séparément par les tests unitaires avec transport intercepté. Le scénario de panne reste injecté pendant l’aperçu ; il ne coupe pas le réseau du Mac. Le simulateur de cette piste est éteint à la fin.
