# Brief P — Solidité et confidentialité du serveur (Codex)

Branche `codex/server-hardening`, dossier `~/mood-codex-P` (worktree de `~/mood-codex-merge`, partant de
`codex/pixel-merge`). **Ne commite pas dans `~/mood-codex-merge` et ne change pas sa branche.**
Lis `AGENTS.md`, `docs/PRIVACY-PLAN.md` (pistes P et couches 3–4), `docs/SERVER-SETUP.md`, `docs/OPS.md`,
`docs/BACKEND.md`, `server/*`.

## Contexte
Le serveur Matrix Mood (Continuwuity 26.9.1, `~/mood-server`, LaunchAgents `app.mood.server`,
`app.mood.healthcheck`, `app.mood.backup`) est **en service** : Augustin et ses comptes l'utilisent en ce
moment. Les sauvegardes (`~/Backups/mood-server/AAAA-MM-JJ`) sont **en clair** et contiennent la base, les
médias **et les secrets**. FileVault est désactivé sur le Studio (c'est Augustin qui l'activera).

## À faire
1. **Sauvegardes chiffrées** avec `age` (installe-le via Homebrew si absent) :
   - génère une paire de clés `age` ; la **clé publique** va dans `server/backup-recipient.txt` (suivi par
     git, ce n'est pas un secret) ; la **clé privée** est écrite une seule fois dans
     `~/mood-server/backup-identity.age-key` (600) **et ne doit jamais être affichée, journalisée ni
     commitée** ;
   - `server/backup.sh` : après la copie à froid existante et la vérification du manifeste, produit une
     archive `tar` **chiffrée** `AAAA-MM-JJ.tar.age` dans `~/Backups/mood-server/`, vérifie qu'elle se
     déchiffre (avec la clé privée, en mémoire / vers un dossier temporaire privé, comparé au manifeste),
     puis **supprime la copie en clair** ; garde 7 jours ; ne casse pas la reprise du service ;
   - `server/restore-test.py` (ou un nouveau script) sait restaurer depuis une archive `.age` dans la copie
     isolée sur le port 6168 (comme aujourd'hui), et tu fais **une restauration de test réelle** ;
   - documente dans `docs/OPS.md` la procédure pour qu'**Augustin range la clé privée hors du Studio**
     (gestionnaire de mots de passe / clé USB), puis la retire du Studio, et comment restaurer ensuite.
     Tant qu'il ne l'a pas fait, les sauvegardes chiffrées ne protègent pas d'un vol du Studio : écris-le.
   - Convertis les sauvegardes en clair existantes en archives chiffrées (puis supprime le clair) après
     vérification.
2. **Surveillance** : `server/healthcheck.sh` vérifie aussi l'espace disque (alerte sous 10 Go), la taille
   des journaux, l'âge de la dernière sauvegarde réussie (> 36 h = alerte) et l'URL publique `:8443` ;
   les alertes vont dans un fichier `~/Library/Logs/MoodServer/alerts.log` lisible et dans une notification
   macOS locale (`osascript -e 'display notification …'` si ça marche depuis le LaunchAgent).
3. **Rotation des journaux** `~/Library/Logs/MoodServer/*` (taille max, 7 fichiers), sans redémarrer le serveur.
4. **Réglages Continuwuity à proposer** (ne les applique **pas** : redémarrage nécessaire pendant
   qu'Augustin l'utilise) : `new_user_displayname_suffix = ""`, rétention des médias, limites de débit,
   aperçus de liens (le brief N2 en parle). Prépare `server/continuwuity.proposed.toml.diff` avec, pour
   chaque ligne, le pourquoi et le risque.
5. **Contrôle régulier** : un LaunchAgent quotidien (ou intégré à la santé) qui lance
   `python3 server/feature-check.py --local` et écrit seulement le résumé (PASS/FAIL) dans les journaux.

## Contraintes
- **Ne redémarre pas** `app.mood.server` sauf si `backup.sh` le fait déjà (sauvegarde à froid de 04 h 15) :
  pour tester la sauvegarde, utilise la même mécanique **une seule fois**, en vérifiant que le serveur
  revient (`/_matrix/client/versions` en local et en public) en moins d'une minute.
- Ne touche pas au Funnel 443 (API ClipFactory), Minecraft, Redis, Ollama, aux apps lancées, aux comptes.
- **Aucun secret affiché** (clé privée age, jeton d'inscription, pepper, `.env`) : n'utilise jamais `cat`
  sur ces fichiers, pas de `set -x`.
- Rien sur GitHub. Ne modifie pas Supabase.

## Livrables
Scripts et plist mis à jour dans `server/`, installés (`server/install.sh`), une sauvegarde chiffrée réelle
+ restauration de test réussie, `docs/OPS.md` et `docs/SERVER-SETUP.md` à jour, rapport
`docs/SERVER-HARDENING.md` (français : ce qui est fait, preuves, ce qu'Augustin doit faire avec la clé
privée). Commits petits, en anglais, dernière ligne `Co-Authored-By: Codex <noreply@openai.com>`.
