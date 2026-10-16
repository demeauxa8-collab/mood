# Brief H — Notifications, sourdine, paramètres réels (Claude)

Branche `claude/notifications`. Lis `AGENTS.md` et `docs/BACKEND-PLAN.md`.
(Reprend l'ancienne piste C4, coupée le 7 octobre par la limite d'usage.)

## À faire
1. `mood/Core/Notifications/NotificationService.swift` : notifications **locales**
   (`UNUserNotificationCenter`) déclenchées par la sync pour les **nouveaux** messages (pas le rejeu du
   cache, pas les miens, pas le salon ouvert quand l'app est au premier plan, pas les utilisateurs
   bloqués, pas les salons en sourdine) ; titre = auteur (+ « · #salon » pour un serveur) ; corps = texte ;
   clic → ouvre la conversation. Autorisation demandée quand l'utilisateur active l'option.
2. Badge de l'icône = mentions + MP non lus (`setBadgeCount`).
3. **Sourdine réelle** = règle push Matrix : `PUT /_matrix/client/v3/pushrules/global/room/{roomId}`
   `{"actions":[]}` / `DELETE` ; lecture des règles au démarrage (`GET /pushrules/`) ; entrée
   « Rendre muet / Rétablir le son » dans les menus contextuels des salons et des MP ; salons muets
   affichés estompés comme Discord.
4. Paramètres › Notifications : activer, sons, badge (persistés par compte). Paramètres ›
   Confidentialité : accusés de lecture (sinon `m.read.private`), indicateur « est en train d'écrire ».
   Paramètres › Appareils : `GET /devices`, déconnecter un appareil (`DELETE /devices/{id}` avec UIAA
   mot de passe… **sur notre serveur le mot de passe est dérivé et inconnu de l'utilisateur** : afficher
   l'appareil, et proposer « Se déconnecter de cet appareil » uniquement pour l'appareil courant).
5. Retirer les derniers textes « prochaine version » / options sans effet dans les Paramètres
   (clé de récupération, chiffrement : panneau honnête « pas encore de chiffrement de bout en bout »).
6. Tests Swift Testing : décision « notifier ou non », chemins des règles push, calcul du badge.

## Contraintes
Ne touche pas aux écrans Auth ni à « Mon compte » (piste F) ni au pipeline d'envoi/médias (piste G).
Ajouts dans `MatrixStore`/`MatrixClient` en fin de classe sous `// MARK: - Notifications & push rules`.
Vérification = `swiftc -typecheck` (commande des briefs), **n'ouvre aucune app sur le MacBook**.
Rien sur GitHub.
