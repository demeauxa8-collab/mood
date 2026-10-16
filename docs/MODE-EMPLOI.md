# Mood — mode d'emploi (14 octobre 2026)

Ce qu'il faut savoir pour **commencer à utiliser Mood**, sans jargon. Le détail technique est dans
`docs/BACKEND.md`.

## Où tourne Mood aujourd'hui

| Quoi | Où |
|---|---|
| Le serveur Mood (où vivent les messages) | le **Mac Studio**, allumé en permanence, joignable sur Internet |
| L'app Mac (« Mood Merge » pour l'instant) | sur le Mac Studio, en partage d'écran (`vnc://192.168.1.10`) |
| L'app iPhone | dans le simulateur du Mac Studio (app **DeviceHub**) |
| **Ton vrai iPhone** | installé depuis le Studio avec ton compte Apple gratuit : **à réinstaller tous les 7 jours** (demande à Claude, ou dans Xcode sur le Studio : destination « iPhone de ADM » → ▶) |
| Les comptes | Supabase (projet « mood ») |

⚠️ **Si le Studio est éteint, Mood ne marche pas** : rien ne part et rien n'arrive. Les messages que tu
écris restent en attente et partent au retour du serveur.

## Ton compte

- **Un seul compte Mood** : e-mail + mot de passe. Pas de compte Matrix à créer, l'app s'en charge.
- Ton **nom d'utilisateur** (comme sur Discord) : `demeauxa8`. Tu peux le changer dans
  **Paramètres › Mon compte › Nom d'utilisateur**. C'est ce nom que tes amis tapent pour t'ajouter.
- Ton **nom d'affichage** (ce que les autres voient) : **Paramètres › Profil**. Photo, bio et pronoms aussi.
- Statut : en ligne, inactif, ne pas déranger (coupe les notifications), invisible, + statut personnalisé.
- Tu **restes connecté** après une relance ou une mise à jour.

### Créer un compte (pour un ami ou un 2e compte de test)
1. « Créer un compte » → e-mail + mot de passe.
2. L'app affiche « Vérifie ta boîte mail ». Clique le lien de l'e-mail **sur n'importe quel appareil**.
3. L'app se connecte **toute seule** quelques secondes après (ou bouton « J'ai confirmé mon e-mail »).
   La page web qui s'ouvre après le clic peut afficher une erreur : ce n'est pas grave, le compte est confirmé.

Astuce : `demeauxa8+test1@gmail.com`, `demeauxa8+test2@gmail.com`… arrivent tous dans ton Gmail normal.
Supabase limite l'envoi d'e-mails à quelques-uns par heure.

## Ajouter un ami et discuter

1. **Amis › Ajouter un ami** → tape son **nom d'utilisateur** exact → choisis-le dans les résultats →
   ouvre la conversation et écris-lui.
2. Chez lui : **Amis › En attente** (sur iPhone : en haut de la liste des messages, avec un badge) →
   Accepter. La conversation arrive dans ses MP, avec les messages déjà envoyés.
3. MP de groupe : nouveau MP → choisir plusieurs personnes + un nom.

Dans une conversation : Entrée = envoyer, Maj+Entrée = nouvelle ligne, **gras** / *italique* / `code`,
`@nom` avec suggestions, flèche ↑ = modifier ton dernier message, réactions, répondre, épingler,
supprimer. Images et fichiers jusqu'à **25 Mo** (bouton +, glisser-déposer ou coller).

## Serveurs

- **Créer un serveur** (bouton + à gauche) : nom + icône, `#général` créé tout seul.
- **Inviter** : « Inviter des amis » → **code** ou lien `mood://invite/…` à envoyer à ton ami ;
  il le colle dans « Rejoindre un serveur ». Ou invite directement quelqu'un par son nom.
- Salons : créer, renommer, sujet, ordre (monter / descendre), salon privé sur invitation.
- Rôles : propriétaire, admin, modérateur, membre ; expulser, bannir, débannir.

## Notifications

Paramètres › Notifications → activer. Un salon ou un MP se met en sourdine par clic droit
(appui long sur iPhone) → « Rendre muet ». **Pas encore de notification quand l'app est fermée.**

## Ce qui ne marche pas encore (et pourquoi)

| Quoi | Pourquoi / quoi faire |
|---|---|
| Connexion avec Discord | il faut que tu crées l'app « Mood » sur discord.com/developers (checklist : `docs/ACCOUNTS-SETUP-STATUS.md`) ; le bouton apparaîtra tout seul |
| Chiffrement de bout en bout | pas encore : le serveur peut lire les messages. Les échanges sont chiffrés sur le réseau (HTTPS). Active **FileVault** sur le Studio pour protéger le disque |
| Notifications app fermée | demande un compte Apple Developer (APNs) |
| App sur ton vrai iPhone | ✅ installée le 15/10 ; expire tous les 7 jours (compte Apple gratuit) ; le compte Apple Developer (99 €/an) supprimerait l'expiration |
| Supprimer son compte, bannière de profil, catégories de salons | masqués exprès (pas encore de vrai chemin côté serveur) |
| Codes d'invitation | ne s'expirent pas encore ; un code rend le serveur ouvert à quiconque l'a |

## Si quelque chose coince

- « Le serveur Mood est injoignable » : le Studio est éteint, endormi ou sans Internet. Rallume-le,
  ouvre la session, attends 1 minute.
- Un message reste grisé : il attend le réseau ; « Réessayer » ou « Supprimer » à côté.
- Tout le reste : dis-le à Claude avec une capture, il regarde les journaux du serveur et de Supabase.
