# Contrôle réel des fonctions Mood

Exécution : `python3 server/feature-check.py` (HTTPS public, TLS vérifié), ou `python3 server/feature-check.py --local`.

Python standard uniquement ; délai HTTP 35 s, sync bornée à 5 essais. Trois comptes par exécution, mots de passe et jetons seulement en mémoire, désactivation UIAA dans finally. Ne pas lancer deux fois dans la même minute (identifiants horodatés). Aucun service redémarré, aucune configuration changée, aucun envoi GitHub.

Date : 2026-10-16T01:00:04.245437+00:00
Cible : https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443

Résumé : PASS=137, FAIL=2, INFO=24

| Résultat | Groupe | Fonction | HTTP | errcode | Observation / action app |
|---|---|---|---|---|---|
| PASS | Compte | Versions | 200 | - |  |
| INFO | Compte | Inscription manuelle app sans jeton | 401 | - | Le serveur exige registration_token ; MatrixClient.register ne traite que dummy. Utiliser le provisioning Mood, jamais distribuer le jeton à l’app. |
| PASS | Compte | UIAA jeton a | 401 | - |  |
| PASS | Compte | Mauvais jeton refusé a | 401 | M_FORBIDDEN |  |
| PASS | Compte | Inscription a | 200 | - |  |
| PASS | Compte | Connexion a | 200 | - |  |
| PASS | Compte | Whoami a | 200 | - |  |
| PASS | Compte | UIAA jeton b | 401 | - |  |
| PASS | Compte | Mauvais jeton refusé b | 401 | M_FORBIDDEN |  |
| PASS | Compte | Inscription b | 200 | - |  |
| PASS | Compte | Connexion b | 200 | - |  |
| PASS | Compte | Whoami b | 200 | - |  |
| PASS | Compte | UIAA jeton c | 401 | - |  |
| PASS | Compte | Mauvais jeton refusé c | 401 | M_FORBIDDEN |  |
| PASS | Compte | Inscription c | 200 | - |  |
| PASS | Compte | Connexion c | 200 | - |  |
| PASS | Compte | Whoami c | 200 | - |  |
| PASS | Compte | Méthodes de connexion | 200 | - |  |
| INFO | Compte | Login token invalide (branche optionnelle) | 403 | M_FORBIDDEN | m.login.token est annoncé, mais aucun jeton SSO valide disponible : cette variante ne peut pas être prouvée en succès sans fournisseur SSO. |
| INFO | Compte | SSO et login token | 200 | - | Aucun fournisseur SSO configuré ; connexion Mood via Supabase, Matrix par mot de passe. Types annoncés : m.login.password, m.login.application_service, m.login.token |
| INFO | Compte | Redirection SSO sans fournisseur | 404 | M_UNRECOGNIZED | Branche SSO optionnelle, aucun fournisseur sur ce serveur. |
| PASS | Compte | Capacités | 200 | - |  |
| INFO | Compte | Capacité m.change_password | 200 | - | "absente" |
| INFO | Compte | Capacité m.set_displayname | 200 | - | "absente" |
| INFO | Compte | Capacité m.set_avatar_url | 200 | - | "absente" |
| INFO | Compte | Capacité m.profile_fields | 200 | - | {"enabled": true, "disallowed": []} |
| INFO | Compte | Capacité uk.tcpip.msc4133.profile_fields | 200 | - | "absente" |
| PASS | Compte | Écrire nom | 200 | - |  |
| PASS | Compte | B lit profil A | 200 | - |  |
| FAIL | Amis | C trouve A sans salon commun | 200 | - | Le serveur masque les utilisateurs sans salon commun ni salon public ; aucune clé search_all_users dans cette version. Prévoir recherche exacte par identifiant ou un salon public de découverte consenti. |
| INFO | Amis | Résultat annuaire isolé | 200 | - | results=0; limited=False |
| PASS | Amis | Créer MP is_direct | 200 | - |  |
| PASS | Amis | Invitation MP visible par B | 200 | - |  |
| PASS | Amis | B rejoint MP | 200 | - |  |
| PASS | Amis | Carte m.direct initiale absente a | 404 | M_NOT_FOUND |  |
| PASS | Amis | Écrire m.direct a | 200 | - |  |
| PASS | Amis | Lire m.direct a | 200 | - |  |
| PASS | Amis | Carte m.direct initiale absente b | 404 | M_NOT_FOUND |  |
| PASS | Amis | Écrire m.direct b | 200 | - |  |
| PASS | Amis | Lire m.direct b | 200 | - |  |
| PASS | Amis | Carte m.direct reçue via sync a | 200 | - |  |
| PASS | Amis | Carte m.direct reçue via sync b | 200 | - |  |
| INFO | Amis | Contrat app acceptInvite | 200 | - | createDM écrit m.direct côté A ; acceptInvite rejoint seulement, sans écrire m.direct côté B. Le test écrit explicitement les deux côtés : adaptation app requise. |
| PASS | Compte | Changer nom après adhésion | 200 | - |  |
| PASS | Compte | B reçoit nouveau nom membre via sync | 200 | - |  |
| PASS | Compte | B relit nouveau profil | 200 | - |  |
| INFO | Compte | À propos PUT v3 | 200 | - |  |
| INFO | Compte | À propos GET v3 | 200 | - |  |
| INFO | Compte | À propos conservé v3 | 200 | - | Valeur relue identique : True. L’app peut stocker À propos via ce champ si True. |
| INFO | Compte | À propos PUT uk.tcpip.msc4133 | 200 | - |  |
| INFO | Compte | À propos GET uk.tcpip.msc4133 | 200 | - |  |
| INFO | Compte | À propos conservé uk.tcpip.msc4133 | 200 | - | Valeur relue identique : True. L’app peut stocker À propos via ce champ si True. |
| PASS | Médias | Upload PNG | 200 | - |  |
| PASS | Compte | Écrire avatar | 200 | - |  |
| PASS | Compte | B lit avatar | 200 | - |  |
| PASS | Médias | Download authentifié avatar | 200 | - |  |
| PASS | Médias | Thumbnail authentifié scale | 200 | - |  |
| INFO | Médias | Ancien média non authentifié download | 403 | M_FORBIDDEN | L’ancien resolveMediaURL de ce checkout utilise cette route ; remplacer par client/v1 avec Bearer (piste G). |
| INFO | Médias | Ancien média non authentifié thumbnail | 403 | M_FORBIDDEN | L’ancien resolveMediaURL de ce checkout utilise cette route ; remplacer par client/v1 avec Bearer (piste G). |
| PASS | Médias | Plus de 25 Mio refusé | 413 | M_TOO_LARGE |  |
| PASS | Compte | Présence online | 200 | - |  |
| PASS | Compte | B lit présence online | 200 | - |  |
| PASS | Compte | Présence unavailable | 200 | - |  |
| PASS | Compte | B lit présence unavailable | 200 | - |  |
| PASS | Compte | Présence offline | 200 | - |  |
| PASS | Compte | B lit présence offline | 200 | - |  |
| PASS | Compte | Appareils | 200 | - |  |
| PASS | Compte | Renommer appareil | 200 | - |  |
| PASS | Compte | Relire appareil | 200 | - |  |
| PASS | Compte | Règles push | 200 | - |  |
| PASS | Compte | Sourdine PUT | 200 | - |  |
| PASS | Compte | Sourdine relue | 200 | - |  |
| PASS | Compte | Sourdine DELETE | 200 | - |  |
| PASS | Compte | Override absent accepté par app | 404 | M_NOT_FOUND |  |
| PASS | Messages | Envoyer texte riche mention | 200 | - |  |
| PASS | Messages | B reçoit contenu texte riche | 200 | - |  |
| PASS | Messages | Même txnId même event_id | 200 | - |  |
| PASS | Messages | Modification m.replace | 200 | - |  |
| PASS | Messages | B reçoit modification | 200 | - |  |
| PASS | Messages | Réponse m.in_reply_to | 200 | - |  |
| PASS | Messages | A reçoit réponse | 200 | - |  |
| PASS | Messages | Réaction m.annotation | 200 | - |  |
| PASS | Messages | A reçoit réaction | 200 | - |  |
| PASS | Messages | Retirer réaction | 200 | - |  |
| PASS | Messages | Retirer réaction reçu par autre compte | 200 | - |  |
| PASS | Messages | Supprimer message | 200 | - |  |
| PASS | Messages | Supprimer message reçu par autre compte | 200 | - |  |
| PASS | Messages | Épingler | 200 | - |  |
| PASS | Messages | Épingle relue par B | 200 | - |  |
| PASS | Messages | Saisie PUT | 200 | - |  |
| PASS | Messages | B voit saisie | 200 | - |  |
| PASS | Messages | Arrêter saisie | 200 | - |  |
| PASS | Messages | Accusé m.read | 200 | - |  |
| PASS | Messages | Accusé m.read.private | 200 | - |  |
| PASS | Messages | A voit accusé public de B | 200 | - |  |
| PASS | Messages | Marqueurs publics | 200 | - |  |
| PASS | Messages | Marqueurs privés | 200 | - |  |
| PASS | Messages | B relit fully_read via sync | 200 | - |  |
| PASS | Messages | Historique arrière | 200 | - |  |
| INFO | Messages | Context (hors app) | 200 | - |  |
| INFO | Messages | Relations (hors app) | 404 | M_UNRECOGNIZED |  |
| PASS | Messages | Recherche serveur app | 200 | - | Si refusé : recherche locale, ne pas afficher une recherche serveur fonctionnelle. |
| FAIL | Messages | Notifications app | 404 | M_UNRECOGNIZED | Route non implémentée dans cette version : alimenter la boîte de mentions depuis sync/cache local, masquer le contrôle si aucun repli. |
| PASS | Messages | Envoi m.image | 200 | - |  |
| PASS | Messages | B reçoit m.image | 200 | - |  |
| PASS | Messages | Envoi m.file | 200 | - |  |
| PASS | Messages | B reçoit m.file | 200 | - |  |
| INFO | Messages | En-têtes limite débit | 200 | - | Aucun en-tête de limite observé ; aucune rafale destructive effectuée. |
| PASS | Compte | Bloquer A | 200 | - |  |
| PASS | Compte | Blocage relu | 200 | - |  |
| PASS | Compte | Blocage filtre sync | 200 | - | Vérifie le filtrage serveur des messages de A ; le client doit aussi filtrer notifications et affichage. |
| PASS | Compte | Débloquer A | 200 | - |  |
| PASS | Serveurs | Créer espace | 200 | - |  |
| PASS | Serveurs | Créer salon enfant | 200 | - |  |
| PASS | Serveurs | m.space.child | 200 | - |  |
| PASS | Serveurs | m.space.parent | 200 | - |  |
| PASS | Serveurs | Hiérarchie | 200 | - |  |
| PASS | Serveurs | Inviter B espace | 200 | - |  |
| PASS | Serveurs | B voit invitation espace | 200 | - |  |
| PASS | Serveurs | B rejoint espace | 200 | - |  |
| PASS | Serveurs | Inviter B salon | 200 | - |  |
| PASS | Serveurs | B voit invitation salon | 200 | - |  |
| PASS | Serveurs | B rejoint salon | 200 | - |  |
| PASS | Serveurs | Écrire m.room.name | 200 | - |  |
| PASS | Serveurs | B relit m.room.name | 200 | - |  |
| PASS | Serveurs | Écrire m.room.topic | 200 | - |  |
| PASS | Serveurs | B relit m.room.topic | 200 | - |  |
| PASS | Serveurs | Membres app | 200 | - |  |
| PASS | Serveurs | État complet app | 200 | - |  |
| PASS | Serveurs | Promouvoir B | 200 | - |  |
| PASS | Serveurs | B relit pouvoir 50 | 200 | - |  |
| PASS | Serveurs | Rétrograder B | 200 | - |  |
| PASS | Serveurs | B relit pouvoir 0 | 200 | - |  |
| PASS | Serveurs | kick | 200 | - |  |
| PASS | Serveurs | Vérifier adhésion après kick | 200 | - |  |
| PASS | Serveurs | ban | 200 | - |  |
| PASS | Serveurs | Vérifier adhésion après ban | 200 | - |  |
| PASS | Serveurs | unban | 200 | - |  |
| PASS | Serveurs | Vérifier adhésion après unban | 200 | - |  |
| PASS | Serveurs | Réinviter B | 200 | - |  |
| PASS | Serveurs | B rejoint après déban | 200 | - |  |
| PASS | Serveurs | B quitte | 200 | - |  |
| PASS | Serveurs | Annuaire salons publics app | 200 | - |  |
| INFO | Serveurs | Créer alias (hors app) | 200 | - |  |
| INFO | Serveurs | Résoudre alias (hors app) | 200 | - |  |
| PASS | Serveurs | Retirer alias test | 200 | - |  |
| PASS | Amis | Salon test rendu public pour découverte | 200 | - |  |
| PASS | Amis | C trouve A membre salon public sans salon commun | 200 | - |  |
| PASS | Amis | Restaurer salon test privé | 200 | - |  |
| PASS | Serveurs | Retirer salon de espace app | 200 | - |  |
| PASS | Serveurs | Quitter salon test | 200 | - |  |
| PASS | Serveurs | Quitter salon test | 200 | - |  |
| PASS | Serveurs | Quitter salon test | 200 | - |  |
| PASS | Serveurs | Quitter salon test | 200 | - |  |
| PASS | Serveurs | Quitter salon test | 200 | - |  |
| PASS | Compte | Déconnexion C | 200 | - |  |
| PASS | Compte | Jeton déconnecté refusé | 401 | M_UNKNOWN_TOKEN |  |
| PASS | Nettoyage | Désactivation featcheck-a-202610160259 | 200 | - |  |
| PASS | Nettoyage | Connexion compte désactivé refusée | 403 | M_USER_DEACTIVATED |  |
| PASS | Nettoyage | Désactivation featcheck-b-202610160259 | 200 | - |  |
| PASS | Nettoyage | Connexion compte désactivé refusée | 403 | M_USER_DEACTIVATED |  |
| PASS | Nettoyage | Désactivation featcheck-c-202610160259 | 200 | - |  |
| PASS | Nettoyage | Connexion compte désactivé refusée | 403 | M_USER_DEACTIVATED |  |

## Lecture des résultats

PASS exige le code prévu et, lorsque précisé, le contenu attendu. INFO correspond aux routes hors app, capacités déclarées et constats. FAIL garde un code de sortie non nul même si le serveur répond HTTP 200 avec un résultat insuffisant.

Le répertoire de cette version filtre en dur dans `~/mood-server/src/src/api/client/user_directory.rs` : salon commun OU utilisateur membre d’un salon dont `join_rule=public`. La recherche dans `src/core/config/mod.rs` ne révèle aucune option pour chercher tous les utilisateurs. `allow_public_room_directory_over_federation` et `lockdown_public_room_directory` concernent les salons, pas ce filtre. Ne pas proposer une clé inexistante : identifiant exact, salon public de découverte consenti, ou évolution serveur nécessaire.

Le checkout utilise encore les médias `/media/v3` sans Bearer ; la piste G doit utiliser `/client/v1/media` avec Bearer. L’inscription manuelle de MatrixClient ne sait traiter que `m.login.dummy` ; le provisioning Mood est le chemin autorisé pour l’inscription par jeton. SSO n’est pas configuré ; m.login.token est annoncé, mais faute de fournisseur/jeton SSO valide, seul le rejet d’un faux jeton est sondé (succès non prouvé). Les capacités m.change_password / m.set_displayname / m.set_avatar_url sont absentes de la réponse : ce n’est pas un refus ; les écritures de nom et avatar sont prouvées séparément.

La preuve m.direct des deux comptes est explicite dans le banc. `MatrixStore.acceptInvite` ne met pas à jour la carte du destinataire ; ajouter cette écriture dans l’app. Le stockage MSC4133, s’il est accepté, ne signifie pas qu’un écran À propos existe déjà.

Limites : ces tests prouvent le contrat HTTP, pas le rendu SwiftUI ni les notifications système. Les salons et médias de test peuvent rester dans la base Matrix ; les trois comptes sont désactivés et les salons quittés. Aucun autre compte manipulé.

## Inventaire exhaustif des chemins du checkout

Chaque chemin littéral MatrixClient / PushRules ci-dessous est exercé par les familles du tableau ; les variantes SSO sans fournisseur et token sans jeton valide sont INFO, leur succès n’est pas prouvé. /context, /relations, /directory/room, /capabilities, /hierarchy et MSC4133 sont des sondes complémentaires.

```swift
return try await post("/_matrix/client/v3/login", body: body, authenticated: false)
return try await post("/_matrix/client/v3/login", body: body, authenticated: false)
let path = "/_matrix/client/v3/login/sso/redirect/\(pathEscape(idpId))"
let url = try buildURL(encodedPath: "/_matrix/client/v3/login")
let url = try buildURL(encodedPath: "/_matrix/client/v3/register")
let response: MatrixWhoamiResponse = try await get("/_matrix/client/v3/account/whoami")
try await postNoResponse("/_matrix/client/v3/logout", body: [:])
let url = try buildURL(encodedPath: "/_matrix/client/v3/sync", query: queryItems)
let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/redact/\(pathEscape(eventId))/\(pathEscape(txnId))"
let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/send/m.reaction/\(pathEscape(txnId))"
let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/typing/\(pathEscape(userId))"
let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/receipt/m.read/\(pathEscape(eventId))"
let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/read_markers"
let path = "/_matrix/client/v3/presence/\(pathEscape(userId))/status"
return try await get("/_matrix/client/v3/presence/\(pathEscape(userId))/status")
encodedPath: "/_matrix/media/v3/upload",
return try await post("/_matrix/client/v3/createRoom", body: body)
return try await post("/_matrix/client/v3/join/\(pathEscape(roomIdOrAlias))", body: [:])
try await postNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/invite", body: ["user_id": userId])
try await postNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/leave", body: [:])
try await postNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/kick", body: body)
try await postNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/ban", body: body)
try await postNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/unban", body: ["user_id": userId])
return try await get("/_matrix/client/v3/profile/\(pathEscape(userId))")
try await putJSONNoResponse("/_matrix/client/v3/profile/\(pathEscape(userId))/displayname", body: ["displayname": displayName])
try await putJSONNoResponse("/_matrix/client/v3/profile/\(pathEscape(userId))/avatar_url", body: ["avatar_url": avatarUrl])
let path = "/_matrix/client/v3/user/\(pathEscape(userId))/account_data/m.direct"
let path = "/_matrix/client/v3/user/\(pathEscape(userId))/account_data/m.ignored_user_list"
let path = "/_matrix/client/v3/user/\(pathEscape(userId))/account_data/m.direct"
return try await post("/_matrix/client/v3/user_directory/search", body: body)
return try await post("/_matrix/client/v3/publicRooms", body: body)
return try await get("/_matrix/client/v3/rooms/\(pathEscape(roomId))/members")
let url = try buildURL(encodedPath: "/_matrix/client/v3/rooms/\(pathEscape(roomId))/messages", query: queryItems)
return try await get("/_matrix/client/v3/rooms/\(pathEscape(roomId))/state")
try await putJSONNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/state/m.room.name", body: ["name": name])
try await putJSONNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/state/\(pathEscape(type))/\(pathEscape(stateKey))", body: content)
try await putJSONNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/state/m.room.pinned_events", body: ["pinned": eventIds])
try await putJSONNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/state/m.room.topic", body: ["topic": topic])
let path = "/_matrix/client/v3/rooms/\(pathEscape(spaceRoomId))/state/m.space.child/\(pathEscape(childRoomId))"
let path = "/_matrix/client/v3/rooms/\(pathEscape(spaceRoomId))/state/m.space.child/\(pathEscape(childRoomId))"
let url = try buildURL(encodedPath: "/_matrix/client/v3/search", query: query)
let url = try buildURL(encodedPath: "/_matrix/client/v3/notifications", query: query)
let response: MatrixDevicesResponse = try await get("/_matrix/client/v3/devices")
let response: MatrixWhoamiResponse = try await get("/_matrix/client/v3/account/whoami")
let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/receipt/m.read.private/\(pathEscape(eventId))"
let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/read_markers"
let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/send/m.room.message/\(pathEscape(txnId))"
encodedPath: "/_matrix/media/v3/upload",
for path in ["/_matrix/client/v1/media/config", "/_matrix/media/v3/config"] {
let response: AccountServerVersions = try await get("/_matrix/client/versions")
let fields: [String: AnyCodable] = try await get("/_matrix/client/v3/profile/\(pathEscape(userId))")
try await putJSONNoResponse("/_matrix/client/v3/profile/\(pathEscape(userId))/\(pathEscape(field))", body: [field: value])
try await putJSONNoResponse("/_matrix/client/v3/directory/room/\(pathEscape(alias))", body: ["room_id": roomId])
return try await post("/_matrix/client/v3/createRoom", body: [
try await get("/_matrix/client/v3/rooms/\(pathEscape(roomId))/context/\(pathEscape(eventId))")
let url = try buildURL(encodedPath: "/_matrix/client/v3/rooms/\(pathEscape(roomId))/messages", query: query)
try await get("/_matrix/client/v3/rooms/\(pathEscape(roomId))/event/\(pathEscape(eventId))")
let url = try buildURL(encodedPath: "/_matrix/client/v1/media/preview_url",
let url = try buildURL(encodedPath: "/_matrix/client/v1/rooms/\(pathEscape(roomId))/threads", query: query)
try await putJSONNoResponse("/_matrix/client/v3/user/\(pathEscape(userId))/rooms/\(pathEscape(roomId))/account_data/\(type)", body: ["unread": unread])
try await postNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/receipt/\(receipt)/\(pathEscape(eventId))", body: ["thread_id": root])
static let allRulesPath = "/_matrix/client/v3/pushrules/"
"/_matrix/client/v3/pushrules/global/room/\(escape(roomId))"
"/_matrix/client/v3/pushrules/global/override/\(escape(roomId))"
```

## Endpoints app refusés ou contrats incomplets

- Inscription manuelle app sans jeton : HTTP 401, -. Le serveur exige registration_token ; MatrixClient.register ne traite que dummy. Utiliser le provisioning Mood, jamais distribuer le jeton à l’app.
- Login token invalide (branche optionnelle) : HTTP 403, M_FORBIDDEN. m.login.token est annoncé, mais aucun jeton SSO valide disponible : cette variante ne peut pas être prouvée en succès sans fournisseur SSO.
- Redirection SSO sans fournisseur : HTTP 404, M_UNRECOGNIZED. Branche SSO optionnelle, aucun fournisseur sur ce serveur.
- C trouve A sans salon commun : HTTP 200, -. Le serveur masque les utilisateurs sans salon commun ni salon public ; aucune clé search_all_users dans cette version. Prévoir recherche exacte par identifiant ou un salon public de découverte consenti.
- Ancien média non authentifié download : HTTP 403, M_FORBIDDEN. L’ancien resolveMediaURL de ce checkout utilise cette route ; remplacer par client/v1 avec Bearer (piste G).
- Ancien média non authentifié thumbnail : HTTP 403, M_FORBIDDEN. L’ancien resolveMediaURL de ce checkout utilise cette route ; remplacer par client/v1 avec Bearer (piste G).
- Relations (hors app) : HTTP 404, M_UNRECOGNIZED.
- Notifications app : HTTP 404, M_UNRECOGNIZED. Route non implémentée dans cette version : alimenter la boîte de mentions depuis sync/cache local, masquer le contrôle si aucun repli.

### Routes effectivement refusées au client de ce checkout

- `GET /_matrix/client/v3/notifications` : 404 M_UNRECOGNIZED ; reconstruire les mentions depuis sync/cache ou masquer la boîte.
- `GET /_matrix/media/v3/download/{server}/{id}` et `/thumbnail/{server}/{id}` sans Bearer : 403 M_FORBIDDEN ; utiliser les médias authentifiés client/v1 (PASS).
- `GET /_matrix/client/v3/login/sso/redirect/{idp}` : 404 M_UNRECOGNIZED ; ne proposer aucun fournisseur SSO Matrix absent.
- `POST /_matrix/client/v3/register` sans étape registration_token : 401 UIAA attendu ; inscription Mood via provisioning, inscription Matrix manuelle incompatible ici.

`POST /user_directory/search` n’est pas refusé (200), mais retourne results=[] sans salon commun/public. `POST /search` fonctionne. Le rejet du faux login token et le 404 de la carte m.direct initiale sont attendus, pas des pannes. `/relations` est hors app et non implémenté.
