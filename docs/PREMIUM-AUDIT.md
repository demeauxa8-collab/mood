# Audit premium — piste X

Idée maîtresse : **une conversation ne doit jamais s’arrêter**. Les états prolongent les composants existants, sans nouvelle direction graphique.

## Inventaire initial (23 octobre 2026)

| Parcours / surface | Présent | Écart observé |
|---|---|---|
| Inscription, connexion, confirmation, récupération | Étapes dédiées, attente, validation, brouillon non sensible, renvoi | Avertissement réseau propre à l’accueil, sans action à cet endroit |
| Envoi texte / photo / vocal, MP et salons | File durable, identifiants de transaction stables, reprise automatique | Simple roue d’envoi, aucun nombre ni distinction réseau / serveur ; erreur de fil sans Supprimer |
| Réception | Historique en cache, pagination, lecture | Panne de synchronisation silencieuse ; aucune indication que les nouveaux messages n’arrivent plus |
| Suppression de message | Confirmation puis suppression immédiate | Pas d’annulation ; une erreur peut disparaître au bout de cinq secondes |
| Serveurs : création, salon, rejoindre, invitation | Attente, erreurs locales, reprise partielle, copie effective | Plusieurs textes d’erreur seuls ; quitter ferme le menu avant la réponse |
| Compte, profil, nom | Validation, enregistrement, erreurs, confirmation déconnexion | Erreurs seules ou mélangées aux succès ; actions de reprise dispersées |
| Notifications / micro / photos | Refus notification expliqué ; micro expliqué sous son bouton ; PhotosPicker système | Pas de bouton Réglages pour notifications / micro ; erreur micro élargit la capsule |
| Listes vides, début de MP / salon | États natifs et actions de premier accueil U/V | À conserver ; ne jamais affirmer qu’une liste est vide pendant une panne de chargement |
| Recherche, historique, appareils | Chargement, vide, réessai déjà disponibles | Formes d’erreur divergentes |
| Bannières globales | ErrorBanner et variante iPhone | Texte limité à trois lignes, fermeture automatique ; risque de masquer le rattrapage |

## Contrats de la passe

- Même composant d’information : titre, explication, action explicite ; erreurs persistantes jusqu’à correction/fermeture.
- Même statut de livraison dans les salons, MP et fils : Envoi en cours / En attente / Échec de l’envoi, Renvoyer et Supprimer.
- Réseau coupé, serveur injoignable et session expirée sont distincts. Le cache et la file restent utilisables ; aucune promesse de réception pendant une panne.
- Suppression : cinq secondes pour Annuler, puis requête réelle ; en cas de refus, le message revient et Réessayer est disponible.
- Permissions : le refus n’enferme personne ; Réglages ou autre fichier, sans demande de permission implicite.

Les résultats et limites vérifiés seront consignés dans `PREMIUM-PASS.md`.

## Corrections livrées

| Situation | Composant / comportement commun | Surfaces |
|---|---|---|
| Échec avec une action de reprise | `MoodNotice` : titre, explication, action ; aucun délai de disparition | Accueil réseau, connexion classique, création/rejoindre, salons, recherche, lecture audio/vidéo, compte et profil, nom d’utilisateur, appareils |
| Panne de réseau ou du service | `ConversationConnectionNotice` ; distinction hors ligne / connexion / serveur injoignable / session expirée | Racines iPhone/Mac, conversation et fil iPhone |
| Message refusé | `MessageDeliveryStatus`, **Renvoyer / Supprimer** | Salon, MP, fil ; menu local sans commandes réseau inactives |
| Message qui attend | Horloge, **En attente**, suppression locale, compteur de file | Texte, photo et vocal empruntent la même file ; les envois refusés ne gonflent pas ce compteur |
| Reprise après panne | Confirmation des seuls messages effectivement acceptés, dédoublonnée entre réponse HTTP et réception | Confirmation du nombre envoyé, quatre secondes ; transition du message sur 100 ms, désactivée avec Reduce Motion |
| Suppression | `MessageDeletionNotices`, **Annuler** pendant cinq secondes, puis état en cours ; message rétabli au refus | Salon, MP et fil ; requête réelle seulement après l’échéance |
| Création partielle | Étapes réussies mémorisées par compte ; réessai sur le même serveur/salon, même après relancement | Création de serveur, salon et modèles d’accueil |
| Quitter un serveur | Confirmation avec conséquence, attente explicite ; fermeture seulement après réussite ; reprise d’une sortie partielle | Menu serveur, rail, réglages |
| Invitation | **Envoi… / Invité**, génération du code en cours, pas de double demande par personne | iPhone et Mac |
| Micro / notifications refusés | `MoodPermissionNotice` avec **Ouvrir Réglages**, alternatives explicites | Saisie et réglages ; le micro ne déforme plus la capsule |
| Photo indisponible / trop lourde | Erreur conservée, **Choisir un fichier**, sélection et texte conservés ; préparation visible | Pièces jointes et saisie ; le sélecteur ne se ferme plus sur un import entièrement échoué |
| Liste non chargée pendant une panne | `ConversationCacheEmptyState` ; aucune affirmation de compte vide | MP iPhone/Mac, accueil desktop, notifications iPhone |

Les erreurs réseau ne montrent plus le texte technique renvoyé par le service. Les erreurs de champ restent sous leur champ : adresse invalide, nom déjà pris, longueur maximale, code de confirmation refusé. Leur formulaire fournit l’action de correction et conserve la saisie autorisée. Les états de chargement utilisent les ProgressView et libellés d’opération existants ; les vides connus gardent les états natifs U/V, leurs actions et leur hiérarchie.

Les réglages de compte distinguent désormais l’échec d’un changement, le changement réellement enregistré et une simple demande d’e-mail de confirmation. Une demande de code n’est jamais présentée comme un changement effectué.

## Points trouvés lors de la vérification

- Un bandeau ajouté autour de la navigation iPhone masquait son en-tête. Il est maintenant placé dans le contenu, sous l’en-tête ; les captures ont été refaites.
- Une expiration de session effaçait les messages en attente. Elle conserve maintenant session locale, cache et file, suspend les envois et propose la reconnexion.
- Les fichiers des messages refusés étaient perdus au prochain lancement. Les échecs et leurs fichiers font maintenant partie du même instantané durable ; le réessai garde la transaction d’origine. La file est isolée par propriétaire.
- Un écho de réception peut précéder la réponse à l’envoi : le compteur de reprise n’est incrémenté qu’une fois.
- Les premières captures montraient le démarrage ou une alerte système d’ouverture de lien. Elles ont été remplacées, après inspection, par des lancements directs du simulateur dédié.

- Un serveur créé dont le premier salon échouait pouvait être recréé au réessai. Un point de reprise est maintenant enregistré après chaque réponse de création réussie et conservé jusqu’au rattachement terminé ; un test intercepte le refus du rattachement et prouve que seuls deux appels de création sont faits avant et après relancement. Si la réponse initiale de création elle-même est perdue, le client ne peut pas connaître l’identifiant créé : cette ambiguïté du service ne permet pas une garantie d’idempotence complète.

## Relecture visuelle — passe 2 (23 octobre)

Comparaison avec les six planches U : surfaces sombres, espaces, boutons violets en capsule ; les états servent la conversation sans changer la barre de saisie ni les listes validées.

| Écart de la première passe | Correction |
|---|---|
| Grande carte réseau en haut et lien bleu | Fine capsule de verre centrée sous l’en-tête ; appui → détails défilants, compteur et bouton Mood Réessayer ; barre fine desktop au-dessus du fil |
| « En ligne - 4 » pendant une panne | Sous-titre Hors ligne / Mood injoignable / Connexion en cours / Session expirée ; aucun point vert trompeur |
| Grande carte d’échec sous le message | Texte rouge doux, petite alerte et ligne **Renvoyer · Supprimer**, commune aux MP, salons et fils ; même mot dans le menu du message |
| Envoi figuré par une roue | Message grisé et horloge ; « En attente · partira tout seul » pendant la panne ; les pièces jointes attendent aussi visiblement |
| Suppression présentée en carte haute | Capsule de verre **Message supprimé · Annuler**, au-dessus de la saisie, barre des cinq secondes ; place réservée pour ne pas recouvrir le dernier message |
| Reprise présentée seulement dans un bandeau | Passage gris → normal en 100 ms, coche Envoyé pendant deux secondes, une seule fois ; aucun effet de boucle ; Reduce Motion conserve le changement d’état sans interpolation |
| Liens bleus de récupération | Boutons Mood violets / secondaires neutres, retour d’appui et état désactivé communs ; cartes plus arrondies sur iPhone |
| Aperçus des permissions présentés en haut | Aperçus près de la saisie comme le refus micro réel ; mêmes composants que le produit |
| Deux feuilles successives pour la reconnexion | Attendre la fermeture des détails avant de présenter la connexion ; la feuille ne se perd plus pendant la transition |

La logique de file, de réessai et d’annulation reste celle de la première passe. Les seules additions de logique sont les textes singulier/pluriel de la capsule et la progression bornée de la barre de temps, avec tests dédiés. Le scénario `premium-recovered` fait maintenant évoluer les vrais états de deux messages synthétiques ; il ne simule pas une réussite sur un vrai service.
