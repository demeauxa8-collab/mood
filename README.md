<div align="center">

# m∞d

**Messagerie privacy-first bâtie sur Matrix — pensée pour ne jamais s'arrêter.**

`SwiftUI` · `iOS / iPadOS / Mac Catalyst` · `Protocole Matrix` · Projet AX Studio

</div>

---

## En une phrase

Mood est un client de messagerie natif Apple, écrit en SwiftUI, qui parle le protocole
[Matrix](https://matrix.org) via un client HTTP écrit à la main. L'objectif long terme est une
messagerie **« indestructible »** : une conversation qui survit à la panne réseau, à la censure
et aux zones blanches.

> **Lis ceci avant tout le reste :** ce README décrit le projet. Les trois documents ci-dessous
> séparent volontairement **ce qui est rêvé** de **ce qui est codé**. Ne les confonds pas.

| Document | Ce qu'il contient |
|---|---|
| [`docs/VISION.md`](docs/VISION.md) | Le **pourquoi** et la cible produit. Rien là-dedans n'est une promesse de code existant. |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Le **comment** réel : la stack telle qu'elle est écrite aujourd'hui, fichier par fichier. |
| [`docs/HANDOFF.md`](docs/HANDOFF.md) | L'**état des lieux** : ce qui marche, ce qui manque, les pièges, par où reprendre. |

---

## État du projet en un coup d'œil

| | |
|---|---|
| **Stade** | MVP chat 1-to-1, en développement actif |
| **Ce qui marche** | Login / register / SSO Matrix, sync temps réel, envoi-réception, DMs, réactions, éditions, suppressions, typing, présence, upload média, file d'attente hors-ligne |
| **Ce qui manque** | E2EE (Olm/Megolm), serveur Synapse dédié, couches mesh / satellite / LoRa, tests, CI |
| **Chiffrement** | ❌ **Pas d'E2EE.** Les salons chiffrés sont détectés et affichés comme illisibles, pas déchiffrés |
| **Plateformes** | iPhone, iPad, Mac (Catalyst) — cible de déploiement iOS 26.2 |
| **Distribution** | Aucune. Pas d'Apple Developer Program → ni TestFlight, ni App Store |
| **Volume de code** | ~14 300 lignes de Swift sur 20 fichiers |

---

## Démarrage rapide

### Pré-requis

- macOS avec **Xcode 26** installé
- Un compte sur un homeserver Matrix (par défaut le client pointe sur `matrix.org`)
- **Aucune dépendance externe** : pas de SPM, pas de CocoaPods, pas de Package.resolved.
  Tout est écrit à la main sur `Foundation` / `URLSession`. Rien à installer.

### Ouvrir et lancer

```bash
git clone https://github.com/demeauxa8-collab/mood.git
cd mood
open mood.xcodeproj
```

Puis `Cmd+R` sur la cible **mood**.

### Compiler en ligne de commande

Le chemin qui fonctionne aujourd'hui, sans compte développeur Apple :

```bash
xcodebuild -project mood.xcodeproj -scheme mood \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build
```

L'app compilée atterrit dans `build/DerivedData/Build/Products/Debug-maccatalyst/mood.app`.

> ⚠️ **Deux blocages d'environnement connus** — détaillés dans
> [`docs/HANDOFF.md`](docs/HANDOFF.md#3-environnement-de-build--ce-qui-bloque) :
> les **simulateurs iOS sont indisponibles** (CoreSimulator obsolète, la mise à jour demande les
> droits admin), et le build signé échoue faute de **development team**. D'où les flags
> `CODE_SIGNING_ALLOWED=NO` et la destination Mac Catalyst ci-dessus.

---

## Carte du code

Tous les fichiers Swift sont **à plat** dans `mood/`. Les noms sont en français, le contenu
(types, fonctions) en anglais.

```
mood/
├── moodApp.swift          @main, RootView, splash animé, delegates Mac
│
│  ── Réseau & état ──────────────────────────────────────────
├── MatrixClient.swift     Client HTTP Matrix écrit à la main (~50 endpoints)
├── MatrixStore.swift      @Observable @MainActor — le cœur : sync, rooms, messages, outbox
├── FileAttenteMessages.swift  File d'attente hors-ligne persistée + détection réseau
├── KeychainHelper.swift   Persistance du token d'accès
├── Modeles.swift          Modèles UI + données de démo
│
│  ── Interface ──────────────────────────────────────────────
├── VuePrincipale.swift    Layout racine (barre serveurs + liste + chat)
├── ZoneChat.swift         Fil de messages, threads, liste des membres
├── BarreSaisie.swift      Champ de saisie
├── ListeChannels.swift    Colonne des salons + panneau utilisateur
├── BarreServeurs.swift    Barre d'icônes serveurs
├── VueMPs.swift           Messages privés
├── NouveauMP.swift        Création de MP / recherche d'utilisateur
├── VuesAuth.swift         Login, register, SSO
├── ParametresCompte.swift Réglages
├── PopupProfil.swift      Carte de profil
├── VueAppels.swift        Interface d'appel (coquille visuelle, pas de WebRTC)
│
│  ── Design system ──────────────────────────────────────────
├── Theme.swift            Palette (3 thèmes × 6 accents)
├── AdaptiveLayout.swift   Métriques adaptatives + mise à l'échelle Mac Catalyst
└── LogoMood.swift         Logo animé
```

Le détail de chaque brique est dans [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Conventions

- **Langue** : prose et noms de fichiers en français ; types, fonctions et commits en anglais.
- **État** : macro `@Observable` (Swift 5.9+), jamais `ObservableObject`. `MatrixStore` est
  injecté via `.environment(...)`.
- **Couleurs** : tout passe par `MoodTheme.*`. Pas de `.red` / `.white` brut dans les vues.
- **Dimensions** : sur Mac Catalyst, utiliser `LayoutMetrics.*` et `Font.mood(...)`, jamais des
  constantes en dur — un facteur ×1.28 compense le downscale de Catalyst.

---

## Licence

Aucune licence n'a encore été choisie. En l'absence de fichier `LICENSE`, tous droits réservés
par défaut.
