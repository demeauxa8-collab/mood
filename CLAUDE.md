# CLAUDE.md — Mood (à lire en premier par toute session Claude)

Mood = messagerie façon Discord (SwiftUI, Mac Catalyst + iPhone) sur Matrix, comptes Supabase.
Produit d'**Augustin** (13 ans, designer, ne code pas ligne à ligne). Lis aussi `AGENTS.md`,
`docs/HANDOFF.md` (en tête : l'état du jour), `docs/BACKEND.md`, `docs/MODE-EMPLOI.md`, `docs/PRIVACY-PLAN.md`.

## Règles non négociables
- **Répondre en français**, direct ; code, commentaires et commits en anglais. Il veut de la vitesse et
  des points d'étape courts (« alors ? » = fais le point en 5 lignes).
- **Rien sur GitHub** (ni push ni PR) sans son « oui » explicite. Commits locaux OK.
- **Jamais de secret** dans git, le chat, les journaux, les captures (jeton d'inscription, pepper,
  clés Supabase secrètes, clé privée des sauvegardes `age`, mots de passe). Les secrets, c'est lui qui les
  colle/déplace. Ne jamais taper de mot de passe, ne pas créer de compte Mood/Supabase.
- **Ne jamais lancer d'app de test sur son MacBook.** Tout se passe sur le **Mac Studio**.
- **Demander « go » avant de réinstaller** une app qu'il utilise (Mac Mood, simulateur, son iPhone).
- **Regarder une capture avant de livrer une interface** (voir « Captures »). Il rejette : cartes
  d'ordinateur posées dans une feuille iPhone, changements de look non demandés, textes coupés, jargon
  (`@m…:mood.local`, « Matrix »). Modèle iPhone validé : `MobileCustomStatusSheet`,
  `MobileUserProfileSheet`, barre de saisie en capsule de verre (`mobileGlassCapsule`).
- **Priorité produit : vie privée / chiffrement** avant le reste. Pas de crypto maison.
- Gros travail → **Codex sur le Studio** (son forfait Claude est limité) ; Claude orchestre, fusionne,
  vérifie.

## Où est quoi
| Quoi | Où |
|---|---|
| Code de référence | Studio `~/mood-codex-merge`, branche **`codex/pixel-merge`** |
| Pistes Codex | worktrees `~/mood-codex-<X>`, branches `codex/…`, fiches `docs/briefs/<X>-*.md` |
| Framework chiffrement (301 Mo, **hors git**) | `mood/Vendor/MatrixSDKCrypto/` — à recopier dans tout nouveau worktree (`rsync -a mood/Vendor/ <wt>/mood/Vendor/`), ou `scripts/build-crypto.sh` |
| `Config.xcconfig` (URL + clé publique Supabase, ignoré par git) | à copier dans chaque worktree |
| Serveur Matrix | Continuwuity 26.9.1, `~/mood-server`, `mood.local`, 127.0.0.1:6167, public `https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443` (Funnel 8443 ; **443 = API ClipFactory, ne pas toucher**) |
| Supabase | projet `jxpgyblzymshyzbkgmat` ; fonction `matrix-session` (verify_jwt false) ; tables `profiles` (+ `username`), RPC `find_user_by_username` |
| Comptes réels | `demeauxa8@gmail.com` → `@mb222b6fe1674` (nom « ADM », username `demeauxa8`) ; `demeauxa@icloud.com` → `@md88cc4dfa1b7` (`demeauxa`) |
| Son iPhone | « iPhone de ADM », UDID `00008150-00160388118A401C`, équipe perso gratuite `ABMR854J9L`, bundle appareil `com.demeauxa8.mood` (profil 7 jours) |
| Simulateur d'Augustin | « iPhone 18 Pro » `6AB9444A-24EF-4B74-A69B-3DECE6084DA7` (ne pas l'utiliser pour les tests d'agents) |
| Simulateur de revue (captures) | « Mood Mobile Review » `FBDA9CEF-15BC-40CD-9039-A84596EC3278` |

## Accès au Studio (depuis le MacBook)
`ssh -o HostName=192.168.1.10 -o HostKeyAlias=mac-studio-de-charlesmacstudio.local studio '<cmd>'` (mDNS
instable : toujours l'IP). rsync : `-e "ssh -o HostName=192.168.1.10 -o HostKeyAlias=mac-studio-de-charlesmacstudio.local"`.
Toujours `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (Xcode 27 ; le simulateur
s'appelle **DeviceHub**). Git sur le MacBook : `/Applications/Xcode.app/Contents/Developer/usr/bin/git`.
⚠️ Pas d'apostrophe dans une commande SSH entre `'…'` : écrire un script dans un fichier, rsync, l'exécuter.

## Construire, tester, installer
- Tout (Mac + iPhone + tests) : `nohup scripts/build-all.sh <tag> & (copie : ~/mood-logs/build-all.sh)` → `~/mood-logs/<tag>-{mac,ios,test}.log`,
  fin = `~/mood-logs/<tag>-done`. Juger sur `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **`.
- App Mac (Studio) : `pkill -f "Debug-maccatalyst/mood.app/Contents/MacOS/mood"; open ~/mood-codex-merge/build/DerivedData/Build/Products/Debug-maccatalyst/mood.app`
- Simulateur : `xcrun simctl install <udid> …/Debug-iphonesimulator/mood.app && xcrun simctl launch <udid> Mood.mood`
- **Son iPhone** : `scripts/install-iphone.sh` : Xcode (ouvert sur le projet, destination « iPhone de ADM ») compile et
  signe par AppleScript (la signature par SSH échoue, `errSecInternalComponent`), puis `xcrun devicectl device
  install app` installe par SSH. Jamais « Run » : il attend sans fin un iPhone verrouillé et l'app meurt quand Xcode s'arrête.
- Les sessions survivent aux réinstallations (trousseau, ou `Application Support/Mood/credentials.json`
  sur build non signé).
- **.dmg** : `scripts/make-dmg.sh` (voir `docs/RELEASE.md`).

## Captures (obligatoire avant de livrer une UI)
`xcrun simctl launch FBDA9CEF-… Mood.mood -uiPreview -uiPreviewScreen <écran>` puis
`xcrun simctl io FBDA9CEF-… screenshot out.png`. Écrans : `chat`, `profile`, `custom-status`, `create-server`,
`join-server`, `server`, `notifications`, `account`, `new-dm`, `profile-popup`… (voir `MobileRootView`).
L'app Mac ne peut pas être capturée par SSH (TCC) ; pour piloter l'écran du Studio il faut qu'Augustin ouvre le
partage d'écran sur le MacBook (`open vnc://192.168.1.10`) puis computer-use sur « Partage d'écran ».

## Codex
- Lancer dans une **fenêtre Terminal visible du Studio** :
  `osascript -e 'tell application "Terminal" to do script "~/mood-patches/run-job.sh <X>"'`
  (`run-job.sh` : `codex exec -m gpt-6.1-sol -c model_reasoning_effort=high|medium`, reprise automatique après
  la limite d'usage ChatGPT). Le `config.toml` du Studio est en `gpt-6-luna` / `low` : **toujours forcer le
  modèle et l'effort**. Journal : `~/mood-logs/night-queue.log`, sorties `~/codex-<X>-run<N>.log`,
  résumé `~/codex-<X>-last.md`.
- Chaque fiche impose : son worktree, ses zones, aucun compte réel, aucun secret, ne lancer aucune app Mac,
  son propre simulateur, rien sur GitHub, commits fréquents.
- Fusion : `git merge --no-ff codex/<branche>` dans `~/mood-codex-merge`. Conflits typiques = fins de classe
  de `MatrixStore` / `MatrixClient` → **garder les deux blocs** (attention aux blocs qui ferment la classe
  puis déclarent un type : mettre l'autre bloc avant). Puis build-all, captures, commit.

## Diagnostiquer sans voir l'écran
- Supabase MCP `query_logs` : `function_logs` (`matrix_session ok|…`, `path register|login`),
  `auth_logs` (`Invalid login credentials`, `user_repeated_signup`…). `execute_sql` pour `profiles`.
- Profils Matrix publics : `curl …:8443/_matrix/client/v3/profile/%40<id>%3Amood.local`.
- Rejouer côté serveur avec des comptes jetables : `python3 server/feature-check.py`,
  `python3 server/dm-sync-check.py` (jeton lu dans le processus, comptes désactivés à la fin).

## Pièges déjà rencontrés (ne pas les refaire)
Entrée avalée par un champ multi-lignes sur Catalyst (→ `MessageReturnKey`) ; trousseau refusé sans signature
(→ fichier privé) ; modale coupée dans une colonne étroite (→ `WindowModalHost`) ; carte de bureau dans une
feuille iPhone (→ feuille native) ; membres chargés à la demande = noms bruts (→ `peerProfiles`) ; salon
rejoint sans historique (`limited`) (→ fillGap) ; MP accepté non rangé (→ `m.direct`) ; recherche Matrix qui
cache les inconnus (→ noms d'utilisateur Mood) ; `/notifications` et `/relations` absents de Continuwuity ;
un seul MP par personne ; `simctl screenshot` peut échouer (code 72) → relancer ; MaxFilter PIL géant = très lent.

## Ce qui n'existe pas encore
Appels audio/vidéo (WebRTC + TURN/LiveKit ; Funnel ne passe pas l'UDP), chiffrement activé par défaut (O2,
interrupteur `MoodE2EE`), vérification des appareils + sauvegarde des clés (phase 3), push app fermée (APNs),
connexion Discord (app Discord à créer par Augustin), signature Developer ID / TestFlight (99 €/an).
