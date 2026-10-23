# Mood — checklist de démo (rendez-vous du 16 octobre 2026)

## La veille / le matin (Claude ou Augustin, 10 minutes)
- [ ] Studio au calme : aucun Codex ni build en cours pendant le rendez-vous (`pgrep -fl "codex exec"` vide).
      Une machine surchargée a déjà fait tomber Tailscale Funnel le 15/10 au soir.
- [ ] Serveur public joignable : `curl -s -o /dev/null -w "%{http_code}\n" https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443/_matrix/client/versions` → `200`, depuis le MacBook **et** depuis l'iPhone en 4G (Safari, même adresse).
- [ ] `python3 server/feature-check.py` (137 PASS, 2 FAIL connus) et `python3 server/dm-sync-check.py` (tout PASS).
- [ ] Mac : Mood (icône deux « o » entrelacés) ouvert et connecté sur le compte ADM.
- [ ] iPhone : Mood ouvert, connecté sur le 2e compte (`demeauxa@icloud.com`). Profil gratuit = 7 jours : réinstallé le 16/10 à 03:00 (`65a5ea2`), OK jusqu'au 23/10.
- [ ] Une conversation privée ADM ↔ demeauxa avec quelques messages récents, un serveur avec 2–3 salons.
- [ ] Notifications de l'iPhone autorisées, mode Concentration coupé.
- [ ] `Mood.dmg` (28 Mo) prêt à montrer / donner : `build/Release-dmg/Mood.dmg`.

Version de démo : **`65a5ea2`** sur `codex/pixel-merge` (Mac du Studio, simulateur, iPhone, `Mood.dmg`).
La candidate S + O2 (`codex/candidate-t`) n'est **pas** installée : à décider après le rendez-vous.

## Le parcours à montrer (5 minutes)
1. **Le look** : l'app Mac et l'iPhone côte à côte — même produit, Discord sur Mac, natif + verre sur iPhone.
2. **Message en direct** : écrire sur le Mac → il arrive sur l'iPhone (et l'inverse). Réponse, réaction, modifier.
3. **Médias** : envoyer une photo, un GIF, un vocal depuis l'iPhone.
4. **Hors ligne** : mettre l'iPhone en mode Avion, écrire un message (il attend), remettre le réseau → il part tout seul.
   C'est la démonstration de la file d'envoi (outbox), la base du Mood « indestructible ».
5. **Serveurs** : créer un salon, inviter, épingler un message, ouvrir un fil, chercher.
6. **Compte** : changer son statut / sa photo. Mot de passe oublié par code à 6 chiffres **seulement si** les
   modèles d'e-mail Supabase ont été mis à jour (`docs/PASSWORD-RESET.md`), sinon ne pas le montrer.
7. **Vie privée** (à raconter, plan dans `docs/PRIVACY-PLAN.md`) : serveur à nous, comptes séparés des messages,
   sauvegardes chiffrées, chiffrement de bout en bout en cours d'intégration (moteur Matrix audité, pas de crypto maison).

## À ne pas montrer (pas prêt)
- Appels audio/vidéo : prochaine étape (WebRTC + serveur TURN, le tunnel actuel ne passe pas l'UDP).
- Chiffrement de bout en bout : ne pas dire « c'est chiffré de bout en bout » aujourd'hui. Il est en
  intégration (interrupteur `MoodE2EE` coupé par défaut).
- Connexion avec Discord (l'app Discord n'est pas encore créée).

## Si ça coince pendant la démo
| Symptôme | Réponse |
|---|---|
| « Les serveurs de Mood sont injoignables » | Sur le Studio (Terminal, sans sudo) : `tailscale down && tailscale up --accept-routes`, attendre 30 s, puis Réessayer dans l'app. |
| Un message ne part pas | Il est dans la file d'envoi : il partira au retour du réseau. Relancer l'app si besoin (la session reste). |
| L'iPhone dit que l'app n'est plus disponible | Profil gratuit expiré : rebrancher, `scripts/install-iphone.sh` sur le Studio. |
| Le Mac ne s'ouvre pas depuis le .dmg | App non notarisée : clic droit › Ouvrir, ou `xattr -dr com.apple.quarantine /Applications/Mood.app`. |
