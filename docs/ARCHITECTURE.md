# Architecture — Mood

> Ce document décrit **le code tel qu'il existe**, vérifié dans les sources.
> Pour la cible produit, voir [`VISION.md`](VISION.md) — les deux divergent volontairement.

---

## 1. La stack, sans détour

| Couche | Choix | Remarque |
|---|---|---|
| Interface | **SwiftUI** | `import UIKit` ponctuel (`UIPasteboard`, delegates Mac) |
| État | **`@Observable`** (macro Swift 5.9+) | Jamais `ObservableObject` |
| Concurrence | **async/await**, `@MainActor` | `MatrixStore` est entièrement `@MainActor` |
| Réseau | **`URLSession` brut** | Client Matrix écrit à la main, aucun SDK |
| Protocole | **Matrix client-server API v3** | |
| Persistance | **Keychain** (token) + **`UserDefaults`** (file d'attente, jeton de sync) | Les messages ne survivent pas au redémarrage |
| Plateformes | iOS / iPadOS / **Mac Catalyst** | Cible iOS 26.2, Swift mode 5.0 |
| Dépendances | **Aucune** | Pas de SPM, ni CocoaPods, ni Carthage |

**Point notable :** zéro dépendance externe. Tout le protocole Matrix — encodage des requêtes,
décodage des événements, boucle de synchronisation, gestion d'erreurs — est écrit à la main sur
`Foundation`. C'est ~1 000 lignes de client HTTP et ~1 500 lignes d'orchestration d'état. C'est
un atout (contrôle total, rien à mettre à jour) et un coût (l'E2EE devra être écrit à la main
ou introduire la première dépendance du projet).

---

## 2. Le flux de données

Une seule direction, de l'API vers les vues :

```
   Homeserver Matrix
          │  HTTP long-polling (/sync)
          ▼
   MatrixClient          Codable brut, ~50 endpoints, sans état métier
          │  MatrixSyncResponse
          ▼
   MatrixStore           processSyncResponse → rooms[MatrixRoom]  (modèle interne)
          │              rebuildUIModels()
          ▼
   servers / dmConversations / messagesByRoom      (modèle UI observable)
          │  .environment(matrixStore)
          ▼
   Vues SwiftUI
```

**La règle qui structure tout :** `MatrixClient` ne sait rien du métier ; il traduit HTTP ↔
Swift. `MatrixStore` détient toute la logique. Les vues ne font que lire l'état et appeler des
méthodes du store.

**Conséquence :** `MatrixStore` fait 1 544 lignes et concentre sync, outbox, pagination,
réactions, présence, profils, salons et espaces. C'est le point de tension principal de
l'architecture — voir [`HANDOFF.md`](HANDOFF.md).

---

## 3. `MatrixClient.swift` — la couche HTTP

Une classe sans état métier, qui détient l'URL du homeserver et le token d'accès.

**Structures `Codable`** — ~30 types miroirs de l'API : `MatrixSyncResponse`, `JoinedRoom`,
`RoomTimeline`, `MatrixEvent`, `RoomSummary`, `UnreadNotifications`, etc. Le contenu variable
des événements passe par `AnyCodable`, un conteneur maison qui décode récursivement le JSON
non typé de Matrix.

**Endpoints couverts** — authentification (`login`, `register` avec flow UIAA, SSO, `whoami`,
`logout`), synchronisation (`sync`), messages (`sendMessage`, `editMessage`, `redactEvent`,
`sendReaction`, `roomMessages`), signalement (`sendTyping`, `sendReadReceipt`, `setReadMarker`,
`setPresence`), médias (`uploadMedia`, `sendImage`, `sendFile`, `resolveMediaURL`), salons
(`createRoom`, `joinRoom`, `leaveRoom`, `inviteUser`, `kickUser`, `banUser`, `unbanUser`,
`setRoomName`, `setRoomTopic`, `getRoomState`, `getRoomMembers`), espaces (`addSpaceChild`,
`removeSpaceChild`), profils et découverte (`getProfile`, `setDisplayName`, `setAvatarUrl`,
`searchUsers`, `getPublicRooms`, `getDirectRooms`, `setDirectRooms`).

**Traitement des erreurs** — `MatrixError` expose `errcode` et un raccourci `isUnknownToken`
(`M_UNKNOWN_TOKEN`) ; c'est ce drapeau qui déclenche la déconnexion automatique quand le
serveur invalide la session. Les chemins d'URL passent par `pathEscape` / `buildURL`, ce qui
évite les injections d'identifiants de salon dans l'URL.

---

## 4. `MatrixStore.swift` — le cœur

`@Observable @MainActor class MatrixStore`. Injecté une fois, lu partout.

### 4.1 État exposé aux vues

```swift
var currentUser: MoodUser?
var servers: [MoodServer]
var dmConversations: [DMConversation]
var messagesByRoom: [String: [ChatMessage]]
var typingUsersByRoom: [String: [String]]
var presenceByUser: [String: UserPresenceInfo]
var pendingInvites: [PendingInvite]
var hasMoreHistory: [String: Bool]
var isLoading: Bool
var errorMessage: String?      // lu par le bandeau d'erreur global
```

En interne, la vérité vit dans `rooms: [MatrixRoom]` — une structure privée qui porte membres,
avatars, compteurs de non-lus, chiffrement, type de salon et enfants d'espace.

### 4.2 La boucle de synchronisation

Une `Task` unique, gardée par un compteur `syncGeneration` qui invalide proprement l'ancienne
boucle si une nouvelle démarre (reconnexion, changement de compte).

- Premier `/sync` avec `timeout: 0` pour un état initial immédiat, puis long-polling à 30 s.
- Le `next_batch` est persisté dans `UserDefaults` → reprise après redémarrage sans tout
  retélécharger.
- Erreur réseau → **backoff exponentiel avec gigue**, plafonné à 60 s.
- Erreur `M_UNKNOWN_TOKEN` → déconnexion propre et message « Session expirée ».
- Au premier sync réussi : présence passée à `online` et **vidange de la file d'attente**.

### 4.3 Le mapping Matrix → interface Discord

C'est la traduction la plus structurante du projet :

| Concept Matrix | Concept Mood |
|---|---|
| Espace (`m.space`) | **Serveur** (icône dans la barre de gauche) |
| Salon enfant d'un espace | **Salon** dans la catégorie « SALONS » |
| Salon sans espace parent | Regroupé dans un serveur de repli **« Matrix » 🌐** |
| Salon marqué dans `m.direct` | **Message privé** |

`rebuildUIModels()` recalcule cette projection à chaque sync. Les identifiants d'interface sont
des `UUID` **dérivés de façon déterministe** des identifiants de salon Matrix, via un hachage
SHA-256 (`stableUUID`) : c'est ce qui permet à SwiftUI de conserver l'identité des éléments
entre deux reconstructions. Un cache et une table inverse rendent la conversion `UUID → roomId`
immédiate.

### 4.4 L'envoi de messages : echo local + file d'attente

C'est la brique la plus aboutie du store, et la première pierre concrète de la promesse
« hors-ligne » de la vision.

```
sendMessage()
   │
   ├─ makeLocalEcho()      le message apparaît instantanément, état .sending
   ├─ outbox.enqueue()     persisté dans UserDefaults (survit au redémarrage)
   ▼
processOutbox()            FIFO, séquentiel
   │
   ├─ succès  → confirmEcho(txnId → eventId), retiré de la file
   ├─ échec transitoire → retryDelay(), jusqu'à 3 tentatives
   └─ échec définitif → état .failed, conservé pour retryMessage() manuel
```

Points de conception à connaître :

- Chaque message porte un **`txnId`** — l'identifiant de transaction Matrix, qui garantit
  l'idempotence côté serveur : un renvoi après timeout ne duplique pas le message.
- `NetworkReachability` (`NWPathMonitor`) déclenche `flushOutbox()` **au retour du réseau**.
- Au démarrage, `restoreOutboxEchoes()` réaffiche les messages en attente dans le fil.
- L'écho local est remplacé par l'événement réel quand il revient par `/sync`, réconcilié via
  le `txnId` présent dans `unsigned.transaction_id`.

### 4.5 Historique et pagination

`loadMoreMessages()` remonte le fil via `/messages` avec un jeton par salon. Quand `/sync`
signale une timeline tronquée (`limited: true`), `fillGap()` comble le trou. `insertSorted()` et
`insertHistoricalEvent()` maintiennent l'ordre chronologique sans doublon.

### 4.6 Réactions, éditions, suppressions

Les événements de relation sont suivis à part (`reactionEvents`, `redactedEventIds`) puis
agrégés sur le message cible par `updateMessageReactions()`. Les suppressions masquent le
contenu sans casser les réponses qui le référencent.

---

## 5. `FileAttenteMessages.swift` — persistance hors-ligne

Deux petites classes `@MainActor` :

- **`MessageOutbox`** — file FIFO de `OutgoingMessage` sérialisée en JSON dans `UserDefaults`
  (clé `mood.outbox`), triée par date de création, dédoublonnée par `txnId`.
- **`NetworkReachability`** — `NWPathMonitor` sur une file dédiée, expose `isConnected` et
  déclenche `onReconnect` **uniquement sur la transition** hors-ligne → en ligne.

---

## 6. Design system

### `Theme.swift`

- `AppTheme` : `dark`, `amoled`, `light`.
- `AccentColor` : 6 teintes (violet par défaut, bleu, vert, jaune, rouge, rose).
- `ThemeManager` : `@Observable`, exposé en **singleton** (`MoodTheme.shared`).
- `MoodTheme` : tous les jetons de couleur, résolus selon le thème actif.

Les valeurs sombres reprennent la palette Discord à l'identique — `1e1f22` (barre serveurs),
`2b2d31` (liste des salons), `313338` (zone de chat).

> **Convention stricte :** aucune couleur brute dans les vues. Tout passe par `MoodTheme.*`.
> Seules exceptions tolérées : `.white` avec opacité explicite sur des surfaces translucides, et
> le rouge destructif du panneau vocal.

### `AdaptiveLayout.swift`

- `LayoutMode` : `.compact` (iPhone) / `.regular` (Mac, iPad), propagé par une clé
  d'environnement `\.layoutMode` dérivée de `horizontalSizeClass`.
- `LayoutMetrics` : toutes les dimensions passent par un facteur d'échelle — **×1.28 sur Mac
  Catalyst**, ×1.0 sur iOS — qui compense le downscale appliqué par Catalyst.
- `Font.mood(_:weight:design:)` applique le même facteur à la typographie.

> **Convention stricte :** sur les vues partagées, utiliser `LayoutMetrics.channelListWidth`
> plutôt que `240`, et `Font.mood(14)` plutôt que `.system(size: 14)`. Une constante en dur
> passera inaperçue sur iPhone et cassera la mise en page sur Mac.

---

## 7. Modèles et vues

`Modeles.swift` porte les modèles d'interface — `MoodUser`, `MoodServer`, `ChannelCategory`,
`Channel`, `ChatMessage`, `MessageReaction`, `MessageAttachment`, `MessageSendState`,
`ReplyRef`, `ThreadInfo`, `LinkEmbed`, `SystemMessageType`, `DMConversation`, `ServerRole` —
ainsi qu'un jeu de données de démonstration (`MockData`) hérité de la phase de maquettage.

Côté vues, `VuePrincipale.swift` assemble le layout racine ; `ZoneChat.swift` (1 736 lignes)
porte le fil de messages, le panneau de threads et la liste des membres ; `ListeChannels.swift`
et `BarreServeurs.swift` la navigation ; `VuesAuth.swift` les parcours de connexion.
`VueAppels.swift` est une **coquille visuelle** : l'interface d'appel existe, la téléphonie
(WebRTC) n'est pas branchée.

Quelques emplacements non évidents, utiles pour s'y retrouver :

- `StatusIndicator` est défini dans `ZoneChat.swift`, pas dans `PopupProfil.swift`.
- `RoleBadge` est défini dans `Modeles.swift`.
- `AnimatedSlash` (le trait du micro coupé) est dans `ListeChannels.swift`.
- `ProfileCardSection` est la version compacte ; `ProfileSection` est l'ancienne, avec fond.

---

## 8. Authentification et session

1. L'utilisateur saisit un homeserver — normalisé par `normalizedHomeserverURL` (ajout du
   schéma, nettoyage) — puis ses identifiants.
2. `login` / `register` (avec gestion du flow UIAA `m.login.dummy`) ou SSO par redirection.
3. Le token, l'identifiant utilisateur et le homeserver partent dans le **Keychain**
   (`KeychainHelper`).
4. Au lancement, `restoreSession()` relit le Keychain, valide le token par `whoami()` et
   redémarre la boucle de sync. En cas d'échec, retour à l'écran de connexion.
5. `logout()` révoque côté serveur et purge Keychain, file d'attente et jeton de sync.

---

## 9. Ce que l'architecture ne fait pas

À garder en tête avant de bâtir dessus :

- **Aucun chiffrement de bout en bout.** Les salons chiffrés sont détectés (`isEncrypted`) et
  leur contenu remplacé par un texte indiquant qu'il n'est pas pris en charge. Aucun code Olm ou
  Megolm n'existe.
- **Aucune persistance des messages.** `messagesByRoom` est en mémoire ; tout est retéléchargé
  au lancement. Seuls le token, le jeton de sync et la file d'attente survivent.
- **Aucun ViewModel.** La logique vit dans `MatrixStore` et directement dans les vues.
- **Core Data présent mais inutilisé.** `mood.xcdatamodeld` est un vestige du gabarit Xcode : il
  est compilé, mais aucun code Swift ne le référence.
- **Aucun test.** `moodTests` et `moodUITests` sont les gabarits Xcode par défaut, 91 lignes en
  tout, sans assertion utile.
- **Aucune couche de transport alternative.** Ni mesh, ni satellite, ni LoRa, ni routeur.
