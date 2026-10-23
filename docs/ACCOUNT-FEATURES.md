# Fonctions compte — piste J

Travail local du 14 octobre 2026, branche `codex/account-features`, worktree `~/mood-codex-J`.
« Corrigé » décrit le code et les vérifications locales ; ce n’est pas une validation avec un vrai compte.
Aucun compte réel, aucune inscription, aucun mot de passe saisi, aucun envoi GitHub.

| Point du brief | État | Preuve et portée |
|---|---|---|
| 1. Nom d’affichage | Corrigé | `updateDisplayName` rafraîchit `currentUser` et les membres des salons chargés ; les modèles sont reconstruits immédiatement. Le popout résout l’utilisateur courant au lieu de conserver sa copie ancienne. Les auteurs des messages sont reconstruits à la sync suivante. |
| 2. Avatar | Corrigé, rendu réservé à G | Choix du fichier → upload existant → profil → état courant et membres rafraîchis. Le type MIME correspond à l’extension du fichier, plutôt que déclarer tout fichier JPEG. Aucun changement au transport média de `MatrixClient`, à `AuthenticatedImage`, à l’outbox ou au rendu des images. Le téléchargement authentifié reste la piste G. |
| 3. Statut | Corrigé | Mapping online/unavailable/offline ; statut et texte persistés par compte. `/sync` transmet `set_presence` pour ne plus annuler Invisible. `NotificationDecision` coupe les bannières en DND. Statut personnalisé accessible sur iPhone ; l’éditeur reste ouvert en cas d’échec. Tests de mapping, persistance isolée, DND et échec sans session. |
| 4. Bio, pronoms, bannière | Branché / masqué | Bio et pronoms : `mood.bio` et `mood.pronouns` via profil étendu v3, lecture au chargement et écriture séparée de chaque champ. Affichage du formulaire seulement si `/versions` annonce ≥1.16 ou MSC4133 ; lecture des champs dans le popout. Le serveur local annonce v1.16–v1.18 et ses sources possèdent les routes. Aucun éditeur de bannière : masqué, les aplats décoratifs existants ne représentent pas une bannière enregistrée. Tests du contrôle de compatibilité. Aucun PUT réel effectué. |
| 5. Compte Mood | Branché / masqué | E-mail de session affiché ; PUT `/auth/v1/user` pour e-mail/mot de passe ; GET `/auth/v1/reauthenticate` et `nonce`. Message de confirmation, aucune adresse annoncée comme changée avant la réponse serveur. Requêtes testées avec URLProtocol, entièrement simulées. Déconnexion iPhone passe aussi par Supabase ; Matrix et cache suivent les chemins existants. Suppression du compte masquée, aucun chemin serveur ajouté. |
| 6. Amis | Corrigé, modèle Matrix explicite | « Ajouter » recherche les noms via l’annuaire et affiche des résultats sélectionnables, sans fabriquer un identifiant à partir du texte. Invitations reçues : accepter/refuser ; refus conservé en cas d’erreur. Acceptation d’un MP enregistrée dans `m.direct`. Retirer = quitter le MP. Bloquer/débloquer écrit `m.ignored_user_list` ; messages déjà chargés masqués aussi, y compris après une modification reçue en sync. Tests du filtre et des notifications. Les amis sont les interlocuteurs de MP individuels, pas un graphe d’amitié Discord indépendant. |
| 7. MP et groupes | Corrigé / ajouté | Réutilisation d’un MP seulement s’il a exactement le bon interlocuteur ; le repli `m.direct` applique aussi ce filtre. Appels concurrents pour un interlocuteur regroupés. Groupes : choix de plusieurs personnes, nom, création privée, inscription dans `m.direct`, titre de groupe et action « Quitter le groupe » dans le menu de la liste MP. Test du refus de réutiliser un groupe comme MP individuel. |
| 8. Popout | Corrigé | Nom/statut actualisés ; bio/pronoms lus du profil, rôles du serveur fourni. Bouton « Envoyer un message » ouvre un MP et déclenche la navigation même sans callback fourni par le parent. Navigation « Modifier le profil » depuis Mon compte corrigée sur iPhone. Boutons factices ellipsis/application/ajout de rôle retirés ; fausse date « membre depuis » retirée. |
| 9. Boutons et erreurs | Corrigé / masqué | Erreurs de recherche et présence visibles ; pas de faux succès d’enregistrement. Actions sans implémentation retirées du popout. Les fonctions authentifiées sont désactivées ou échouent clairement en démo. Les appels restent masqués pour un vrai compte suivant la règle existante. |
| 10. État sans relance | Corrigé | Profil/statut mis à jour après succès ; blocage immédiatement répercuté sur les messages existants ; demandes supprimées seulement après succès. Profil étendu partiellement écrit : chaque champ réussi est reflété même si le suivant échoue. Tests de validation et d’absence de faux changement sans session. |

## Vérifications locales

**Mac Catalyst : BUILD SUCCEEDED. iPhone : BUILD SUCCEEDED. Swift Testing : TEST SUCCEEDED, 71 tests réussis, dont 9 nouveaux.**

Les logs restent dans `build/` (ignoré par Git), sans compte réel :
- Mac Catalyst : `build/account-mac-final.log`.
- iPhone privé : `build/account-iphone-final.log`.
- Swift Testing : `build/account-tests-final.log` et le `.xcresult` indiqué dedans.
- Capacité publique sans jeton : GET local `http://127.0.0.1:6167/_matrix/client/versions`, réponse conservée dans `build/account-versions.json`.

Le simulateur utilisé porte le nom **Mood J iPhone**, UUID `E3DE2F8E-5FEE-4B02-8F34-3C5E74FF2DB1`.
Les tests Xcode emploient son clone privé. Aucun contrôle du simulateur personnel « iPhone 18 Pro ».
Les captures dans `screenshots/account-features/` sont des données de démo, jamais une preuve réseau.

| Capture inspectée | Écran |
|---|---|
| `iphone-profile-settings.png` | Nom, choix d’avatar, bio et pronoms |
| `iphone-account-credentials.png` | Compte et formulaire e-mail/mot de passe, sans saisie |
| `iphone-group-dm.png` | Création de MP de groupe, sans invitation |
| `iphone-profile-popup.png` | Carte de profil et rôles de démonstration |
| `iphone-profile.png` | Statut et accès au statut personnalisé sur iPhone |
Aucune app Catalyst lancée pour les captures : **Mood Merge est restée intacte**.
La validation pixel par pixel desktop n’est donc pas revendiquée ; les mesures de base n’ont pas été changées.

## À tester par Augustin avec ses comptes

1. Sur Mac et iPhone : modifier nom et avatar, vérifier panneau utilisateur, membres, profil, puis auteurs après sync et après relance. Tester un PNG et un JPEG ; attendre la piste G pour certifier leur affichage authentifié.
2. Choisir Invisible, attendre plusieurs syncs puis relancer : reste invisible. DND : un second compte envoie un MP, aucune bannière ; revenir En ligne, vérifier le retour des notifications. Le DND reste local : Matrix publie « online » aux autres, car il n’a pas de présence DND native.
3. Enregistrer bio/pronoms, fermer/réouvrir les réglages, lire le profil depuis le second compte. Tester une coupure réseau entre les deux écritures.
4. Changer le mot de passe, éventuellement demander un code et le saisir, puis se reconnecter. Changer l’e-mail et suivre les confirmations de l’ancienne et/ou nouvelle adresse selon la configuration Supabase. Vérifier l’adresse affichée après confirmation et reconnexion.
5. Déconnecter : retour à la connexion, cache et messages non envoyés vidés. Hors ligne, la révocation serveur reste une tentative ; la suppression locale n’attend pas un succès Matrix.
6. Rechercher un nom, sélectionner le bon résultat si plusieurs personnes ont le même nom. Accepter/refuser une invitation ; couper le réseau lors du refus : la demande doit rester affichée.
7. Ouvrir deux fois un MP depuis amis/profil ; vérifier qu’il reste unique. Bloquer un interlocuteur : ses messages chargés disparaissent ; débloquer et vérifier les nouveaux messages. Les anciens messages masqués reviennent lors d’un rechargement d’historique, pas par restauration immédiate en mémoire.
8. Créer un groupe avec deux invités et un nom ; accepter depuis les autres comptes, relancer, vérifier nom et classement dans les MP. Quitter depuis le menu contextuel de la liste.

## Limites connues

- Aucun parcours authentifié de bout en bout testé : c’est volontaire et imposé par le brief.
- Pas d’amitié Discord indépendante des MP ; « En attente » liste les invitations reçues, pas un suivi des demandes sortantes.
- Champs bio/pronoms propres à Mood : un autre client peut ne pas les présenter.
- Aucune bannière personnalisée ni suppression de compte ; aucun backend privilégié ajouté.
- La durée d’un statut personnalisé utilise le minuteur existant tant que l’app est ouverte ; l’échéance n’est pas conservée après fermeture. Le texte et le choix de présence, eux, sont conservés.
- En cas de création de groupe réussie puis d’échec d’enregistrement de `m.direct`, l’erreur est visible, mais le salon peut déjà exister côté serveur : vérifier les invitations avant de réessayer.
- Mac non signé : persistance de session limitée par le trousseau (limite existante). Notifications iPhone seulement tant que Mood est ouvert ; pas d’APNs.

Contrat Supabase vérifié dans les sources officielles : [mise à jour utilisateur](https://supabase.com/docs/reference/swift/auth-updateuser), [réauthentification](https://supabase.com/docs/reference/swift/auth-reauthentication).
