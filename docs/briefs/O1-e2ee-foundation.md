# Brief O1 — Chiffrement de bout en bout, phase 1 : la fondation (Codex)

Branche `codex/e2ee-foundation`, dossier `~/mood-codex-O1` (worktree de `~/mood-codex-merge`, partant de
`codex/pixel-merge`). **Ne commite pas dans `~/mood-codex-merge` et ne change pas sa branche.**
Lis `AGENTS.md`, `docs/PRIVACY-PLAN.md` (le plan, piste O), `docs/BACKEND.md`, `docs/FEATURE-CHECK.md`.
Deux pistes N1 / N2 modifient la messagerie en parallèle : **phase 1 = n'intègre pas encore dans
`MatrixStore` / l'envoi** (zones à toi plus bas).

## But de la phase 1
Disposer, dans le dépôt, d'une **bibliothèque de chiffrement Matrix officielle et auditée** utilisable par
l'app sur iPhone (appareil + simulateur) et Mac Catalyst, et prouver qu'elle marche, **sans écrire de
cryptographie nous-mêmes**.

1. **Choisir et épingler la source** : `matrix-org/matrix-rust-sdk`, crate `bindings/matrix-sdk-crypto-ffi`
   (OlmMachine, basé sur `vodozemac`, liaisons UniFFI Swift ; c'est ce qu'utilisait Element iOS via
   « MatrixSDKCrypto »). Prends la **dernière version taguée stable** de `matrix-sdk-crypto-ffi` (note le
   tag et le commit exacts). Regarde le script Apple fourni par le dépôt (`bindings/apple/…`) et suis-le.
2. **Chaîne de compilation isolée** : le Rust Homebrew (`/opt/homebrew/bin/cargo`) sert à compiler le
   serveur Continuwuity : **ne le modifie pas et ne casse pas son PATH**. Installe `rustup` **dans ton
   coin** (`RUSTUP_HOME=~/mood-toolchains/rustup CARGO_HOME=~/mood-toolchains/cargo`, `--no-modify-path`)
   avec la toolchain demandée par le dépôt et les cibles `aarch64-apple-ios`, `aarch64-apple-ios-sim`,
   `aarch64-apple-ios-macabi` (Mac Catalyst ; `x86_64` inutile, le Studio est Apple Silicon).
3. **Produire** `MatrixSDKCrypto.xcframework` (appareil iPhone, simulateur, Mac Catalyst) + le fichier Swift
   généré (UniFFI). Range-les dans `mood/Vendor/MatrixSDKCrypto/` (ajoute le framework au projet Xcode
   correctement : le groupe racine est synchronisé, mais un xcframework doit être lié à la cible `mood`
   et intégré ; documente exactement ce que tu changes dans `project.pbxproj`). Si le binaire est trop
   gros pour le dépôt (> 50 Mo), garde-le hors git (`.gitignore`) et fournis `scripts/build-crypto.sh` qui
   le reconstruit à l'identique (tag épinglé), plus une somme SHA-256 attendue.
4. **Pont Swift minimal** `mood/Core/Crypto/CryptoEngine.swift` : crée une OlmMachine pour un
   `userId`/`deviceId` avec un stockage dans `Application Support/Mood/crypto/<userId>/` (passphrase du
   stockage : générée aléatoirement, gardée dans `KeychainHelper` — trousseau sur build signé, fichier
   privé sinon ; écris-le clairement), expose `identityKeys`, `outgoingRequests()`,
   `receiveSyncChanges(...)`, `markRequestAsSent(...)`, `encrypt(roomId:content:)`, `decrypt(event:)`. Aucune
   utilisation dans l'app pour l'instant.
5. **Preuves** (tests Swift Testing, hors réseau) : deux OlmMachines (Alice, Bob) en mémoire → clés
   générées, échange des requêtes de clés simulé entre elles, session Megolm partagée, Alice chiffre
   « bonjour » → Bob déchiffre « bonjour » ; un tiers ne peut pas. Le tout compile pour Mac Catalyst **et**
   iPhone. Puis une preuve **en direct** côté serveur avec deux comptes Matrix jetables (`o1check-*`,
   jeton d'inscription lu dans le processus seulement, rien affiché, comptes désactivés à la fin) :
   upload des clés d'appareil, `keys/query`, `keys/claim`, to-device, message chiffré `m.room.encrypted`
   envoyé par l'un et déchiffré par l'autre via un petit exécutable ou script de test (pas l'app).

## Zones
À toi : `mood/Vendor/`, `mood/Core/Crypto/`, `scripts/build-crypto.sh`, `server/e2ee-check.*`, tests,
`project.pbxproj` (liaison du framework uniquement). **Pas à toi en phase 1** : `MatrixStore`,
`MatrixClient`, la barre de saisie, l'outbox (N1/N2 y travaillent ; l'intégration sera la phase 2).

## Contraintes
- **Ne réimplémente aucune primitive cryptographique.** Pas de « chiffrement maison ». Bibliothèque
  officielle seulement, version épinglée, sources vérifiées (tag signé ou commit noté).
- Aucun secret affiché ni commité (clés privées, passphrases, jeton d'inscription, jetons d'accès).
- **Ne lance aucune app Mac**, n'utilise pas le simulateur « iPhone 18 Pro » (crée « Mood O1 iPhone »).
  Ne touche pas au serveur Continuwuity (config, binaire, Rust Homebrew), ni à Supabase. Rien sur GitHub.
- `Config.xcconfig` : copie-le depuis `~/mood-codex-merge/Config.xcconfig`.
- Si une étape est bloquée (version Rust, cible macabi, taille), **n'abandonne pas en silence** : écris
  précisément le blocage, ce que tu as essayé et la meilleure alternative (ex. vodozemac seul via son
  propre binding) dans le rapport.

## Livrables
Builds Mac Catalyst + iPhone `** BUILD SUCCEEDED **` avec le framework lié, `moodTests` verts sur
« Mood O1 iPhone » (dont les tests Alice/Bob), preuve en direct, rapport `docs/E2EE-PHASE1.md` (français :
version exacte, taille, comment reconstruire, ce qui est prouvé, plan détaillé de la phase 2 :
points d'accroche exacts dans `MatrixStore`/`MatrixClient`, ordre des requêtes, stockage, migration des
salons, UI). Commits petits, en anglais, dernière ligne `Co-Authored-By: Codex <noreply@openai.com>`.
