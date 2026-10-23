# Mood — plan vie privée et chiffrement (15 octobre 2026)

**Objectif d'Augustin :** avant d'être « indestructible », Mood doit être **le plus privé possible**.

## Le principe (à lire avant tout)

Être privé, ce n'est pas empiler plusieurs chiffrements sur la même chose : chiffrer deux fois un message
avec deux algorithmes n'apporte presque rien et multiplie les bugs. Ce qui protège vraiment, c'est de
**couvrir chaque menace par une couche solide, auditée et standard**, et de **ne jamais inventer sa propre
cryptographie**. Mood superpose donc des couches qui protègent **contre des menaces différentes** :

```
 Ton appareil ──(1) chiffrement de bout en bout : seul le destinataire peut lire ─────────► Son appareil
      │                                                                                       │
      │  (2) transport chiffré (TLS 1.3, certificat Tailscale)                                │
      ▼                                                                                       ▼
   Serveur Mood (Studio) : ne voit que du chiffré (3) disque chiffré (4) sauvegardes chiffrées
   Supabase : e-mail + profil seulement, jamais de message (5)
   Appareils : (6) données locales protégées, verrou de l'app
   Partout : (7) le moins de métadonnées possible
```

## Menaces et couches

| Menace | Couche qui protège | État au 15/10 |
|---|---|---|
| Quelqu'un écoute le réseau (Wi-Fi public, opérateur) | (2) HTTPS/TLS jusqu'au Studio | ✅ |
| Quelqu'un accède au serveur, à sa base ou à ses journaux (pirate, panne, **nous-mêmes**) | **(1) chiffrement de bout en bout** Olm/Megolm (standard Matrix, bibliothèque `vodozemac` auditée) : le serveur ne stocke que du chiffré, pièces jointes comprises | ❌ **piste O** |
| Vol du Mac Studio ou de son disque | (3) **FileVault** | ❌ à activer par Augustin |
| Fuite d'une sauvegarde | (4) sauvegardes chiffrées (`age`) avant d'être écrites | ❌ piste P |
| Fuite de Supabase | (5) données minimales (e-mail, nom), RLS, aucun message, aucune clé | ✅ |
| Téléphone ou Mac volé / fouillé | (6) protection de données iOS ; cache local chiffré ; verrou Face ID / code dans l'app ; aperçu masqué dans le sélecteur d'apps | ⚠️ partiel — piste Q (le trousseau demande une app **signée**) |
| Faux appareil glissé dans un compte, homme du milieu sur les clés | vérification des appareils (émojis à comparer, QR), signature croisée | ❌ piste O (phase 3) |
| Perte de toutes ses clés (nouveau téléphone) | sauvegarde des clés chiffrée par une **clé de récupération** que seul l'utilisateur connaît | ❌ piste O (phase 3) |
| Métadonnées (qui parle à qui, quand) | (7) fédération coupée ✅, identifiants pseudonymes `@m<hex>` ✅, présence / « en train d'écrire » / accusés désactivables ✅, journaux serveur minimaux ✅, **aperçus de liens coupés dans les salons chiffrés** (sinon le serveur voit les liens), notifications push sans contenu (plus tard) | ⚠️ |
| Messages qui doivent disparaître | messages éphémères (suppression automatique après X) | plus tard |

Limites honnêtes : Matrix ne cache pas au serveur **qui** écrit dans **quel** salon ni **quand** ; le
post-quantique n'est pas encore dans le standard (Olm/Megolm = Curve25519 + AES-256 + HMAC-SHA-256) ;
tant que l'app n'est pas signée, le Mac ne peut pas utiliser le trousseau pour protéger les clés locales.

## Pistes

### O — Chiffrement de bout en bout (priorité n°1, Codex)
On n'écrit **pas** de crypto : on intègre **`matrix-sdk-crypto-ffi`** (projet officiel `matrix-rust-sdk`,
basé sur `vodozemac`), conçu pour les clients qui ont leur propre couche réseau comme Mood :
l'« OlmMachine » reçoit les réponses de `/sync` et rend les requêtes à envoyer (clés, to-device…).
Exception assumée à la règle « zéro dépendance » : un **xcframework compilé depuis les sources sur le
Studio**, version épinglée, sans gestionnaire de paquets.
1. **Phase 1** : chaîne de compilation (rustup isolé, cibles iPhone / simulateur / Mac Catalyst),
   `MatrixSDKCrypto.xcframework` + liaisons Swift, test : clés d'appareil générées, chiffrer → déchiffrer.
2. **Phase 2** : intégration — envoi des clés d'appareil, suivi des appareils, chiffrement Megolm des
   salons `m.room.encryption`, déchiffrement, **pièces jointes chiffrées**, chiffrement **activé par défaut**
   pour les MP et les nouveaux salons privés ; badge « chiffré » seulement quand c'est vrai.
3. **Phase 3** : vérification (émojis, QR), signature croisée, sauvegarde des clés + clé de récupération,
   arrivée sur un nouvel appareil.

### P — Solidité et confidentialité du serveur (Codex)
Sauvegardes chiffrées (`age`), surveillance du disque et alertes, rotation des journaux, réglages
Continuwuity (suffixe des nouveaux noms vide, rétention des médias, aperçus de liens), contrôles
`feature-check` réguliers, procédure de restauration testée sur sauvegarde chiffrée.

### Q — Appareils (après signature de l'app)
Verrou de l'app (Face ID / code), cache local chiffré (clé dans le trousseau), aperçu masqué dans le
sélecteur d'apps, notifications push sans contenu.

### À faire par Augustin
FileVault sur le Studio ; signature de l'app (identifiant Apple dans Xcode) ; décider des aperçus de liens.
