# Vision — Mood

> ⚠️ **Ce document décrit une cible, pas un état.**
> Rien ici ne doit être lu comme « c'est codé ». Pour ce qui existe réellement, voir
> [`ARCHITECTURE.md`](ARCHITECTURE.md) et [`HANDOFF.md`](HANDOFF.md).
> Ce document est une **boussole** pour les décisions d'architecture, pas un inventaire.

---

## 1. La promesse

**Une conversation ne s'arrête jamais.**

Ni quand le réseau tombe. Ni quand un opérateur coupe. Ni quand un État censure. Ni dans un
tunnel, un festival bondé, une vallée sans antenne, une zone sinistrée.

Toutes les messageries grand public partagent la même hypothèse silencieuse : *il y a
internet*. Quand cette hypothèse tombe, elles tombent avec. Mood part de l'hypothèse inverse —
l'accès réseau est un privilège intermittent, et le transport doit s'adapter en silence.

## 2. Le positionnement

Mood est le projet phare d'**AX Studio**. Deux axes le distinguent :

**Résilience.** C'est le différenciateur central, pas une fonctionnalité bonus. Signal, iMessage
et WhatsApp chiffrent très bien — mais tous meurent hors ligne. Mood vise le terrain où ils
s'arrêtent.

**Privacy par construction.** Protocole ouvert (Matrix), fédéré, auto-hébergeable. Pas de silo
propriétaire, pas de numéro de téléphone comme identité, chiffrement de bout en bout par défaut
à terme.

Et une exigence transverse : **l'app doit sentir Apple**. Interface native, HIG, SF Pro,
animations spring, dark mode de premier ordre. La résilience ne justifie pas une UI d'outil de
survie.

## 3. L'architecture cible : le routage multi-couches

C'est le cœur de la proposition de valeur. L'utilisateur écrit un message ; **le transport se
choisit tout seul**, du plus capable au plus dégradé, sans jamais demander à l'utilisateur de
comprendre ce qui se passe.

| Priorité | Couche | Technologie visée | Terrain d'usage |
|---|---|---|---|
| 1 | **Internet** | Matrix / Synapse | Cas nominal |
| 2 | **Mesh Bluetooth** | Multipeer Connectivity (approche type Bridgefy) | Foule dense, manifestation, concert, zone blanche avec des pairs à proximité |
| 3 | **Satellite** | API Messages via satellite (iOS 18+) | Isolement total, urgence |
| 4 | **Radio LoRa** | Module externe relié en BLE à l'iPhone | Longue portée hors réseau, usage avancé |

Le principe directeur : **dégradation gracieuse**. Une couche indisponible n'est pas une erreur
affichée à l'utilisateur, c'est une bascule silencieuse vers la suivante. Le message part quand
il peut partir ; l'interface dit honnêtement où il en est.

> **Statut réel : aucune de ces couches n'est implémentée hors de la n°1** — et la n°1 elle-même
> tourne aujourd'hui contre `matrix.org`, sans serveur dédié. La file d'attente hors-ligne
> existante (voir `FileAttenteMessages.swift`) est la première brique concrète de cette logique :
> elle garde les messages et les rejoue au retour du réseau.

## 4. Stack cible

| Domaine | Choix visé | Où on en est |
|---|---|---|
| Interface | SwiftUI, iOS 17+ | ✅ SwiftUI, cible iOS 26.2 |
| Architecture | MVVM strict (Views → ViewModels → Services → Models) | ❌ Pas de ViewModels ; la logique vit dans `MatrixStore` et dans les vues |
| Protocole | Matrix client-server API | ✅ Client HTTP maison |
| Serveur | Synapse auto-hébergé sur Oracle Cloud Free Tier (ARM Ampere A1) | ❌ Rien de déployé |
| Authentification | Matrix natif, puis SSO Apple | ✅ Login / register / SSO Matrix — ⚠️ SSO Apple non fait |
| Chiffrement | Olm / Megolm natif Matrix | ❌ Rien. Les salons chiffrés sont détectés, pas déchiffrés |
| Stockage | CoreData / SwiftData | ❌ Tout est en mémoire (+ `UserDefaults` pour la file d'attente) |

## 5. Structure de fichiers cible

L'organisation visée à terme, à comparer avec le tout-à-plat actuel :

```
Mood/
├── App/                  Point d'entrée, cycle de vie
├── Features/             Une feature = un dossier
│   └── Chat/{Views,ViewModels,Models}
├── Core/
│   ├── Matrix/           SDK Matrix, wrappers Synapse
│   ├── Networking/       Routeur multi-couches
│   ├── Crypto/           Wrappers Olm / Megolm
│   └── Storage/          CoreData / SwiftData
├── DesignSystem/         Composants réutilisables, tokens
└── Resources/            Assets, localisations
```

> **Statut réel :** les 20 fichiers Swift sont à plat dans `mood/`. Ni `Features/`, ni `Core/`,
> ni `DesignSystem/`. Cette réorganisation est un chantier ouvert, pas un acquis.

## 6. L'écart assumé entre la vision et le code

Deux écarts méritent d'être nommés explicitement, parce qu'ils reviendront dans toutes les
discussions d'architecture :

**L'écart visuel.** La vision produit est *Apple HIG / Liquid Glass*. Le code actuel est un
**clone assez fidèle de Discord** — palette hexadécimale reprise à l'identique, barre de
serveurs, catégories de salons, panneaux de threads et de membres. Ce clone a servi de gabarit
de travail efficace pour structurer une interface de chat riche. Reste une décision produit à
trancher : **converger vers l'esthétique Apple, ou assumer le langage visuel Discord.** Tant que
ce n'est pas arbitré, le design reste en tension.

**L'écart de sécurité.** L'interface évoque la protection des échanges, alors qu'**aucun
chiffrement de bout en bout n'est implémenté**. C'est l'écart le plus sensible du projet : pour
une app qui se positionne sur la privacy, tout élément d'interface qui suggère un chiffrement
inexistant est une promesse non tenue. À corriger en priorité, soit par le code, soit par
l'honnêteté de l'interface — idéalement les deux, dans cet ordre.

## 7. Ordre de bataille

Ce que la vision implique comme séquence, du plus fondateur au plus spéculatif :

1. **Rendre le MVP 1-to-1 irréprochable** — envoi, réception, hors-ligne, historique.
2. **Implémenter l'E2EE** — sans quoi le positionnement privacy ne tient pas.
3. **Déployer un Synapse** — sans quoi il n'y a pas de produit, seulement un client.
4. **Trancher la direction visuelle** — Apple ou Discord, mais choisir.
5. **Sortir la structure MVVM** de `MatrixStore` avant qu'il ne devienne ingérable.
6. **POC mesh Bluetooth en projet séparé**, intégré seulement une fois qu'il tient debout seul.
7. Satellite, puis LoRa — horizon lointain, à ne pas laisser polluer les décisions d'aujourd'hui.

## 8. Contraintes à garder en tête

- **Pas d'Apple Developer Program** (~99 €/an, non souscrit) : ni TestFlight, ni provisioning
  App Store. Les tests se font en simulateur ou par sideload sur appareil personnel.
- **Budget contraint** : toute solution retenue doit avoir un palier gratuit crédible. Oracle
  Cloud Free Tier est choisi pour cette raison.
- **Pas de dépendances lourdes** : le projet n'a aujourd'hui aucune dépendance externe, et c'est
  un atout à préserver. Pas de Firebase, pas de React Native, pas de Flutter. Matrix reste le
  protocole — il n'est pas à remplacer.
