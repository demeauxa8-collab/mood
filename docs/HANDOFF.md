# Handoff — Mood

## État au 14 octobre 2026 — backend en ligne, l'app sert vraiment

Mood fonctionne de bout en bout avec de **vrais comptes** : compte Mood (Supabase) → fonction
`matrix-session` → serveur Matrix Continuwuity `mood.local` sur le Mac Studio, public sur
`https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443`. Augustin a échangé des messages entre
deux comptes (Mac ↔ iPhone simulé) le 14/10 au soir.

- **À lire d'abord** : [BACKEND.md](BACKEND.md) (architecture, config, exploitation, sécurité, preuves,
  bugs trouvés en vrai) et [MODE-EMPLOI.md](MODE-EMPLOI.md) (utiliser Mood, en français simple).
- Rapports des pistes : [SERVER-SETUP.md](SERVER-SETUP.md), [OPS.md](OPS.md),
  [MATRIX-SESSION-STATUS.md](MATRIX-SESSION-STATUS.md), [PROVISIONING-F.md](PROVISIONING-F.md),
  [FEATURE-CHECK.md](FEATURE-CHECK.md), [ACCOUNT-FEATURES.md](ACCOUNT-FEATURES.md),
  [MESSAGING-SERVERS.md](MESSAGING-SERVERS.md), [FINISH-BASICS.md](FINISH-BASICS.md).
- **Code** : branche `codex/pixel-merge` du clone `~/mood-codex-merge` sur le Studio (pistes D → L
  fusionnées + correctifs). **Rien n'est poussé sur GitHub** (attendre le oui d'Augustin).
- **App en service** : `~/mood-codex-merge/build/DerivedData/Build/Products/Debug-maccatalyst/mood.app`
  (« Mood Merge ») et le simulateur « iPhone 18 Pro » (`6AB9444A-…`, via DeviceHub). Mise à jour :
  `~/mood-logs/build-all.sh <tag>` (Mac + iPhone + tests), puis relancer. Les sessions survivent aux
  relances (fichier privé en attendant la signature).
- Contrôles serveur réutilisables : `python3 server/feature-check.py`, `python3 server/dm-sync-check.py`.

En attente : piste M (« Mot de passe oublié ? » + confirmation par code, `~/mood-codex-M`), app Discord
à créer par Augustin, FileVault sur le Studio, push GitHub, renommage « Mood Merge » → « Mood »,
signature de l'app (trousseau, vrai iPhone), chiffrement de bout en bout.

## Mise à jour du 15 octobre 2026 (soir)

- **Mood tourne sur le vrai iPhone d'Augustin** (« iPhone de ADM », équipe personnelle gratuite
  `ABMR854J9L`, identifiant `com.demeauxa8.mood` pour les builds appareil). Le profil expire tous les
  7 jours : `scripts/install-iphone.sh` réinstalle **via Xcode** (la signature par SSH échoue,
  `errSecInternalComponent`) ; Xcode doit être ouvert sur `~/mood-codex-merge/mood.xcodeproj`,
  destination « iPhone de ADM ».
- Fusionnés : **P** (sauvegardes chiffrées `age`, surveillance, rotation — la clé privée doit quitter le
  Studio, voir `docs/SERVER-HARDENING.md`), **O1** (chiffrement de bout en bout phase 1 :
  `matrix-sdk-crypto-ffi-0.17.0`, `mood/Vendor/MatrixSDKCrypto` **hors git**, 301 Mo, reconstruit par
  `scripts/build-crypto.sh` ; à recopier dans tout nouveau clone), **N2** (médias, vocaux, GIF, emoji,
  brouillons), plus les correctifs du test réel (noms des auteurs, feuilles iPhone statut et serveur).
  150 tests verts.
- Plan vie privée : [PRIVACY-PLAN.md](PRIVACY-PLAN.md). File de nuit sur le Studio
  (`~/mood-patches/night-queue.sh`, journal `~/mood-logs/night-queue.log`) : **O2** (chiffrement phase 2,
  `~/mood-codex-O2`, interrupteur `MoodE2EE` coupé tant que la validation ne passe pas) puis reprise de
  **N1** (conversation, `~/mood-codex-N1`, coupé par la limite ChatGPT).

## Nuit du 15 au 16 octobre 2026 — version de démo

- Rendez-vous du 16/10 : suivre [DEMO.md](DEMO.md) (préparation, parcours de 5 minutes, ce qu'on ne montre
  pas, quoi faire si ça coince). **Studio au calme pendant la démo** : la surcharge du 15/10 au soir (3 Codex
  + builds, charge 57) a coupé Tailscale Funnel ; `tailscale down && tailscale up --accept-routes` l'a rétabli.
- Fusionnés : **N1** (fils, transférer, non lus, liens de message, recherche), **R partie 1** (écrans iPhone
  natifs), nouvelle icône + nom « Mood » + `Mood.dmg` (`scripts/make-dmg.sh`, voir [RELEASE.md](RELEASE.md)).
- Revue des 51 écrans iPhone (`~/mood-patches/capture-review.py after`, simulateur de revue) et correctifs
  `502dadd` : heures « Aujourd'hui à », « Salons textuels », texte de saisie entier, flèche retour dans les
  feuilles à étapes (`MobileSheet(onBack:)`), fil de discussion natif, barre audio des vocaux.
- **R** fini et fusionné (`65a5ea2`) : réglages du serveur iPhone en listes natives, brouillon de pièce
  jointe en carte. **Version de démo = `65a5ea2`**, installée partout (Mac, simulateur, iPhone via
  `scripts/install-iphone.sh` = build Xcode + `devicectl`), `Mood.dmg` refait.
- **S** (sécurité locale) et **O2** (chiffrement phase 2) finis, fusionnés par Codex **T** dans la candidate
  `codex/candidate-t` (`~/mood-codex-T`, + R) : builds verts, 189 tests, 9/9 MP, 11/11 chiffrement,
  migration sans déconnexion testée ; `MoodE2EE` et verrou coupés par défaut, masquage du contenu des
  notifications **activé** par défaut (à confirmer). Rapport : `~/mood-codex-T/docs/MERGE-T.md`.
  **Pas installée** : à valider par Augustin après le rendez-vous, puis `git merge codex/candidate-t`.
- Contrôles serveur (16/10, 03:00) : feature-check 137 PASS / 2 FAIL connus, dm-sync-check 9/9.

## Priorité actuelle — 7 octobre 2026

La priorité n°1 des travaux UI desktop est la fidélité pixel par pixel, en
commençant par conserver et généraliser les séparateurs validés de la page Amis.
Lire [UI-DESKTOP-PIXEL-PERFECT.md](UI-DESKTOP-PIXEL-PERFECT.md) et `../AGENTS.md`.
Tous les essais restent dans le laboratoire « Mood Pixels » ; la version clean
du Mac Studio reste intacte. Aucun commit ni envoi GitHub sans autorisation.
Cette règle prime sur toute recommandation historique de commit ci-dessous.

Passe « Pixels 2 » locale : `DesktopPixelRule` centralise les traits d’un pixel
physique et 41 séparateurs ont été migrés. Build signé ad hoc et 16 tests réussis.
Le paquet installé reste `/Users/Adm/Applications/Mood Pixels.app`, en mode démo.
Les glyphes ne sont pas encore identiques : l’essai `-pixelTextMasks` reste
désactivé par défaut car il dégrade un des quatre libellés comparés.
Prochaine priorité : rasterisation des lettres, puis symboles non mesurés,
paramètres et autres états/densités. Ne pas annoncer toutes les pages validées.

## Archive historique

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
