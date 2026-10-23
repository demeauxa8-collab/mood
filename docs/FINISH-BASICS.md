# Finitions des bases — piste L

Travail local sur `codex/finish-basics`, dans `/Users/Adm/mood-codex-L`.
Aucun compte réel utilisé, aucune saisie de mot de passe, aucune publication GitHub.
`Config.xcconfig` copié depuis le worktree de fusion sans afficher son contenu ; il reste ignoré par Git.
Mood Merge et le simulateur personnel « iPhone 18 Pro » n’ont pas été contrôlés.

## Les cinq points

| Point | État | Preuve et fonctionnement |
|---|---|---|
| 1. Nom d’utilisateur | Implémenté ; échange réel à valider | `AccountStore.setUsername` valide le format avant tout appel, envoie uniquement `{username}` par PATCH, puis recharge le profil. HTTP 409 ou code `23505` : « Ce nom d'utilisateur est déjà pris ». `23514` : règle de format. Mon compte expose le nom et Modifier sur les deux interfaces. Le profil personnel et sa carte l’affichent sous le nom d’affichage. Ajouter un ami recherche le nom Mood exact, y compris sans salon commun ; absence et panne donnent des messages distincts. Tests de validation et du PATCH intercepté localement. |
| 2. Invitations iPhone et anciens MP | Implémenté ; transport réel à valider | Invitations MP et serveurs au-dessus de la liste Messages, boutons Accepter/Refuser, badge dans la barre Accueil et sur l’entrée MP. Les actions attendent la réponse et bloquent les doubles pressions. Au premier sync, réparation des salons absents de `m.direct` : état complet pour vérifier deux membres rejoints, preuve `is_direct` dans l’état ou dans l’ancienne invitation personnelle, puis fusion avec le `m.direct` serveur existant. Échec réseau : nouvel essai après un sync ultérieur. Tests excluant salons ordinaires, groupes et espaces. |
| 3. Mentions | Implémenté depuis sync et cache | Les événements du cache alimentent l’onglet Mentions desktop et une section Mentions sur iPhone : `m.mentions.user_ids`, mention de salon, ancien texte `@room`, nom d’affichage ou nom Mood. Pas de mention sur mes messages, utilisateurs bloqués ou texte cité. Les modifications/suppressions sont prises en compte ; déduplication par événement. `/notifications` complète ces données uniquement en cas de succès ; un 404 / `M_UNRECOGNIZED` désactive les appels suivants pour la session, sans vider la liste locale. Tests du filtre, des éditions et de la sérialisation du cache. |
| 4. Discord | Condition appliquée | Toutes les actions de la section Discord sont sous `isSignedIn && discordEnabled`. Mon compte recharge les fournisseurs via la méthode existante, puis l’identité Discord seulement si activé. En démo, aucun appel fournisseur. La capture Compte montre son absence. |
| 5. Textes du parcours normal | Nettoyés | Compte, erreurs d’envoi, annuaire, permissions et regroupement des salons parlent de Mood ou de salons. `Matrix` / `matrix.org` restent dans la connexion avancée, les identifiants techniques, commentaires et contrats de protocole. Les métriques, palettes et réglages de calibration desktop sont conservés. |

## Vérifications

- **Mac Catalyst : `** BUILD SUCCEEDED **`. iPhone : `** BUILD SUCCEEDED **`.** Aucune app Mac lancée.
- **Swift Testing : `** TEST SUCCEEDED **`, 131 tests réussis, 0 échec**, dont 7 tests L. Le `.xcresult` confirme les compteurs et le simulateur dédié. Le test HTTP intercepte toutes les requêtes vers `.invalid` ; les valeurs sont synthétiques et restent en mémoire.
- Simulateur créé pour cette mission : **Mood L iPhone**, UUID `3A979591-99E9-4373-ACC1-D4E6761FBCFB`. Xcode utilise son clone privé pour les tests.
- Journaux locaux ignorés par Git : `build/finish-basics/mac-build.log`, `iphone-build.log`, `tests.log`. Résultats Xcode dans `build/DerivedData/Logs/Test/`.
- Les sept captures ci-dessous ont été ouvertes et inspectées. La première version des invitations tronquait le texte : une ligne mobile dédiée le rend désormais complet, avec boutons nommés ; le composant desktop garde ses dimensions.
- Empreintes SHA-256, commit source et résumé des vérifications : [validation.json](screenshots/finish-basics/validation.json).

| Capture inspectée | État montré |
|---|---|
| [Invitations](screenshots/finish-basics/iphone-invitations.png) | MP « Veut discuter avec toi », serveur, Accepter/Refuser, badge 2 dans Accueil |
| [Mon compte](screenshots/finish-basics/iphone-account.png) | Nom `augustin`, Modifier, section Discord absente |
| [Modifier le nom](screenshots/finish-basics/iphone-username-editor.png) | Champ initialisé, règle complète, Enregistrer désactivé sans session |
| [Profil complet](screenshots/finish-basics/iphone-profile.png) | Nom Mood sous le nom d’affichage |
| [Carte de profil](screenshots/finish-basics/iphone-profile-popup.png) | Nom Mood personnel dans le popout |
| [Ajouter un ami](screenshots/finish-basics/iphone-add-friend.png) | Champ Nom d’utilisateur et aide Mood, aucun exemple d’identifiant technique |
| [Mentions](screenshots/finish-basics/iphone-mentions.png) | Mention de démo affichée dans Notifications |

Commits de code locaux : `620570a` (compte et noms), `60c1f6d` (MP, invitations et mentions), `27422c3` (textes).

## Choix et limites

- Aucun nouveau RPC, aucun droit ni schéma serveur modifié. Pour le profil d’une autre personne, le nom Mood est masqué quand il est inconnu ; aucun identifiant technique n’est présenté comme son nom Mood. Le nom d’affichage reste visible.
- La boîte locale couvre les événements encore conservés par `SyncCache` (150 événements bruts par salon). Ce n’est pas un historique illimité de notifications. Un objet `m.mentions` explicite vide désactive les heuristiques de texte, conformément à son rôle dans les réponses.
- L’état lu/non lu local utilise les compteurs du salon et les marqueurs locaux ; il n’est pas un accusé individuel pour chaque mention historique.
- La réparation demande une preuve : un salon ordinaire à deux personnes reste un salon. Si le serveur ne rend pas l’ancienne invitation ou a supprimé le drapeau, l’app n’invente pas son statut MP. Elle lit l’historique filtré des événements d’adhésion avec pagination ; aucun message n’est réécrit.
- Captures de démo : elles prouvent le rendu, pas l’échange authentifié. Les boutons qui demandent une session réelle sont désactivés en démo. Aucune app Mac lancée : aucune validation visuelle desktop revendiquée.

## À tester en vrai — Augustin

1. Sur Mac et iPhone : ouvrir Mon compte, modifier le nom avec une valeur valide, vérifier sa carte et son profil puis relancer. Essayer un nom déjà pris et un format interdit : message français, aucune fausse réussite. Avec un autre compte sans salon commun, rechercher ce nom exact et ouvrir le MP ; essayer un nom inexistant et une panne réseau.
2. Envoyer un MP à un compte iPhone qui ne l’a pas encore rejoint, et une invitation à un serveur. Vérifier le badge, les deux demandes et Accepter/Refuser. Couper Internet pendant l’action : la demande reste présente et l’erreur est lisible. Après acceptation, vérifier l’historique envoyé avant l’entrée.
3. Relancer un compte ayant un ancien MP à deux membres absent de `m.direct`. Vérifier qu’il revient dans Messages, sans doublon, puis relancer encore. Un salon ordinaire à deux membres et un groupe doivent garder leur classement.
4. Envoyer une mention personnelle, `@room`, un ancien message contenant le nom, une réponse avec citation et un message sans mention. Vérifier Mentions sur Mac et iPhone, ouvrir le message, le modifier puis le supprimer. Relancer avec puis sans réseau : les mentions conservées doivent rester disponibles malgré le 404 de `/notifications`.
5. Tant que Discord est désactivé dans les fournisseurs, vérifier l’absence de sa section dans Mon compte après reconnexion et restauration de session. Quand Augustin active le fournisseur, vérifier son apparition et les quatre actions avec son compte.
