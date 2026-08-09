# Handoff — Mood

**État arrêté au 9 août 2026.** Ce document s'adresse à quelqu'un — humain ou agent — qui
reprend le projet sans contexte. Il dit où en est le code, ce qui bloque, et par où reprendre.

- Le **pourquoi** du projet : [`VISION.md`](VISION.md)
- Le **comment** du code : [`ARCHITECTURE.md`](ARCHITECTURE.md)

---

## 1. Situation en trois phrases

Mood est un client Matrix natif Apple, écrit en SwiftUI sans aucune dépendance externe. Le MVP
de chat fonctionne : connexion, synchronisation temps réel, envoi-réception, messages privés,
réactions, historique, file d'attente hors-ligne. **Il n'y a pas de chiffrement de bout en bout,
pas de serveur dédié, pas de tests, et aucune des couches de transport alternatives** qui
constituent la promesse produit.

---

## 2. ⚠️ Travail en cours non commité

**C'est le point le plus important de ce document.**

Au moment de la rédaction, le checkout principal
(`/Users/augustindemeaux/Documents/autre/mood`) porte un volume de travail substantiel **jamais
commité** :

```
 10 fichiers modifiés, 2 nouveaux — +1 261 / −370 lignes

 M mood/MatrixStore.swift      +635 / −…    le gros du travail
 M mood/MatrixClient.swift     +363 / −…
 M mood/ZoneChat.swift         +262 / −…
 M mood/VueMPs.swift           +179 / −…
 M mood/VuePrincipale.swift    +102 / −…
 M mood/KeychainHelper.swift, Modeles.swift, BarreSaisie.swift,
   VuesAuth.swift, moodApp.swift
 ?? mood/FileAttenteMessages.swift    ← nouveau, non suivi par git
 ?? mood/NouveauMP.swift              ← nouveau, non suivi par git
```

Ce travail apporte, entre autres : la **file d'attente hors-ligne** avec echo local et reprise
réseau, `whoami()` et une restauration de session robuste, la gestion de `m.direct` pour les
messages privés, la **pagination d'historique** et le comblement de trous de timeline, un
bandeau d'erreur global (`ErrorBanner`), un avertissement de salon chiffré
(`EncryptedRoomNotice`), le renvoi manuel des messages échoués, et la recherche d'utilisateur
pour créer un MP.

**Le dernier commit `385efcb` ne contient rien de tout cela** — l'historique git s'arrête à du
travail d'interface (« Polish user status panel… »). Les deux fichiers non suivis sont
particulièrement exposés : ils ne sont dans aucun commit et aucun stash.

> **Première action recommandée pour qui reprend :** commiter ce travail, ou au minimum le
> sauvegarder. Il compile et il est fonctionnel (vérifié — voir §3).

---

## 3. Environnement de build : ce qui bloque

Deux obstacles, tous deux vérifiés en tentant réellement la compilation.

### Les simulateurs iOS sont indisponibles

```
CoreSimulator is out of date. Current version (1051.54.0) is older than
build version (1051.55.0). Simulator device support disabled.
```

Xcode 26 est bien installé et compile, mais le framework CoreSimulator est en retard sur la
version attendue. La correction demande une mise à jour système ou Xcode, donc des **droits
administrateur qui ne sont pas disponibles sur cette machine**. Conséquence directe : **on ne
peut pas lancer l'app en simulateur iPhone/iPad.**

### La signature de code échoue

```
error: Signing for "mood" requires a development team.
```

Le projet n'a pas de `DEVELOPMENT_TEAM` (pas d'Apple Developer Program souscrit). Tout build
signé échoue immédiatement.

### Le contournement qui marche

Compilation **Mac Catalyst sans signature** — vérifié, `BUILD SUCCEEDED` :

```bash
xcodebuild -project mood.xcodeproj -scheme mood \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build
```

Binaire produit : `build/DerivedData/Build/Products/Debug-maccatalyst/mood.app`.

> ⚠️ Ne juge pas le résultat d'un build sur le code de sortie si tu passes la sortie dans un
> pipe (`| tail`, `| grep`) : tu récupères le code du dernier maillon, pas celui de `xcodebuild`.
> Redirige vers un fichier et cherche `** BUILD SUCCEEDED **` / `** BUILD FAILED **`.

**Ce qu'il faut retenir :** le seul chemin de test aujourd'hui est **Mac Catalyst**. Tester sur
iPhone demande soit les droits admin pour réparer les simulateurs, soit un sideload sur appareil
personnel.

---

## 4. État de la compilation

Le code compile. **6 avertissements**, dont un qui compte :

| Fichier | Ligne | Avertissement |
|---|---|---|
| `FileAttenteMessages.swift` | 63 | **`self` capturé dans du code concurrent — erreur en mode Swift 6** |
| `MatrixStore.swift` | 705 | `threadRootId` écrite mais jamais lue |
| `MatrixStore.swift` | 723-724 | `isSystem`, `systemType` jamais mutées → passer en `let` |
| `VuesAuth.swift` | 438 | `init()` déprécié sur Mac Catalyst 26 → `init(windowScene:)` |
| `VuesAuth.swift` | 514 | `UIScreen.main` déprécié → passer par le contexte de vue |

Le premier est le seul structurant : le projet est en **mode langage Swift 5**, et ce motif
deviendra une **erreur de compilation** au passage en Swift 6. Le corriger tôt évite une dette
qui grossira avec chaque nouvelle ligne concurrente.

Le `threadRootId` jamais lu mérite un regard : il suggère que le **fil de discussion (thread)
est partiellement câblé** — la valeur est calculée puis abandonnée.

---

## 5. Ce qui marche / ce qui manque

### ✅ Fonctionnel

Connexion par mot de passe, inscription (flow UIAA), SSO par redirection · restauration de
session au lancement, déconnexion automatique sur token invalide · synchronisation temps réel
avec backoff exponentiel et reprise par jeton persisté · envoi et réception de messages ·
messages privés via `m.direct`, recherche d'utilisateur · réactions, éditions, suppressions ·
indicateurs de saisie, présence, accusés de lecture, compteurs de non-lus · envoi d'images et de
fichiers · pagination de l'historique et comblement des trous de timeline · espaces Matrix
projetés en serveurs · invitations (accepter / refuser), modération (kick, ban, unban) ·
**file d'attente hors-ligne** avec echo local, reprise au retour réseau et renvoi manuel ·
3 thèmes × 6 accents · adaptation iPhone / iPad / Mac.

### ❌ Absent

**Chiffrement de bout en bout** — aucun code Olm/Megolm. Les salons chiffrés sont détectés et
affichés comme non pris en charge · **serveur Synapse** — le client pointe sur `matrix.org` ·
**persistance des messages** — tout est en mémoire, retéléchargé à chaque lancement ·
**appels** — `VueAppels.swift` est une coquille visuelle, pas de WebRTC · **notifications push**
· **tests** — les gabarits Xcode, 91 lignes sans assertion utile · **CI** · **mesh, satellite,
LoRa** · **ViewModels** — la logique est dans le store et les vues · **SSO Apple**.

---

## 6. Pièges à connaître

**`MatrixStore` pèse 1 544 lignes** et concentre sync, outbox, pagination, réactions, présence,
profils, salons et espaces. Toute nouvelle fonctionnalité tend à y atterrir par défaut. C'est le
point de tension à surveiller — extraire des services avant d'ajouter une couche majeure.

**Les identifiants d'interface sont dérivés par hachage.** `stableUUID(from: roomId)` produit un
`UUID` déterministe par SHA-256. Ne jamais fabriquer un `UUID()` aléatoire pour un salon :
SwiftUI perdrait l'identité de l'élément à chaque reconstruction.

**Le facteur d'échelle Mac Catalyst (×1.28)** est invisible sur iPhone. Une constante de taille
écrite en dur passera les tests visuels iOS et cassera la mise en page Mac. Toujours
`LayoutMetrics.*` et `Font.mood(...)`.

**`MockData` existe encore** dans `Modeles.swift` — données de démonstration héritées de la phase
de maquettage. Vérifier qu'aucune vue ne s'en nourrit encore avant de conclure qu'un écran est
branché sur de vraies données.

**L'interface suggère une protection qui n'existe pas.** Pour une app positionnée sur la
privacy, c'est le sujet le plus sensible : tant que l'E2EE n'est pas là, l'interface doit être
honnête sur ce qui n'est pas chiffré.

**Core Data est présent mais mort.** `mood.xcdatamodeld` est compilé sans qu'aucun code ne le
référence — vestige du gabarit Xcode. Ne pas en déduire qu'une couche de persistance existe.

---

## 7. Par où reprendre

Dans cet ordre — chaque étape débloque les suivantes :

1. **Sauvegarder le travail non commité** (§2). Deux fichiers ne sont dans aucun commit.
2. **Corriger l'avertissement de concurrence** `FileAttenteMessages.swift:63` avant qu'il ne
   devienne une erreur en Swift 6.
3. **Trancher le sujet E2EE.** Deux options : l'implémenter (chantier lourd, et probablement la
   première dépendance externe du projet), ou rendre l'interface explicite sur son absence. La
   seconde option est immédiate et rétablit l'honnêteté du produit ; la première est ce que la
   vision exige à terme.
4. **Écrire les premiers tests** sur les briques pures et testables sans réseau : `stableUUID`,
   la sérialisation de `MessageOutbox`, `retryDelay`, `insertSorted`.
5. **Déployer un Synapse** (Oracle Cloud Free Tier) pour sortir de la dépendance à `matrix.org`.
6. **Trancher la direction visuelle** — Apple HIG ou Discord (voir [`VISION.md`](VISION.md) §6).
   Le design restera en tension tant que ce n'est pas décidé.
7. **Extraire des ViewModels / services** de `MatrixStore` avant d'attaquer une couche majeure.
8. **POC mesh Bluetooth** en projet séparé, intégré seulement une fois qu'il tient debout seul.

---

## 8. Repères pratiques

| | |
|---|---|
| Dépôt | `github.com/demeauxa8-collab/mood` |
| Checkout local | `/Users/augustindemeaux/Documents/autre/mood` |
| Branche | `main` |
| Dernier commit | `385efcb` — *Polish user status panel with action pills…* |
| Cible | `mood` (+ `moodTests`, `moodUITests` non utilisées) |
| Bundle ID | `Mood.mood` · version 1.0 |
| Déploiement | iOS 26.2 · iPhone + iPad + Mac Catalyst |
| Mode Swift | 5.0 |
| Homeserver par défaut | `matrix.org` |
| Dépendances | aucune |

**Conventions.** Prose et noms de fichiers en français ; types, fonctions et messages de commit
en anglais. Couleurs exclusivement via `MoodTheme.*`. Dimensions via `LayoutMetrics.*`. État
avec `@Observable`, jamais `ObservableObject`.
