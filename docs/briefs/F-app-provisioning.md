# Brief F — App : session Matrix automatique (Codex)

Branche `codex/app-provisioning`, dossier `~/mood-codex-F`. Lis `AGENTS.md`, `docs/BACKEND-PLAN.md`
(§2 = **contrat d'API** de `matrix-session`, écrit en parallèle par la piste E ; code contre lui).

## À faire
1. `SupabaseAuthClient.matrixSession(deviceId:deviceName:)` → `POST functions/v1/matrix-session`
   (même `request` que le reste, bearer = jeton Supabase valide), décode la réponse du contrat,
   erreurs `401/503/500` → messages français clairs.
2. `device_id` stable par appareil : généré une fois (`"MOOD" + 12 caractères`), stocké dans
   `UserDefaults` (ce n'est pas un secret).
3. `MatrixStore.login(accessToken:userId:homeserver:deviceId:)` : nouvelle méthode, sans mot de passe :
   règle le client, `whoami` pour vérifier, sauvegarde comme les autres connexions, démarre la sync
   (réutilise le code de `login(username:password:homeserver:)`). Modification **minimale** de
   `MatrixStore` (une autre piste y travaille en parallèle : ajoute ton code dans la section Auth).
4. Parcours : après connexion Mood (e-mail ou Discord) ou restauration de session → `matrixSession`
   → `MatrixStore.login(accessToken…)` → l'app. **Supprimer l'écran « Relie ton compte Matrix »** du
   parcours normal ; le garder dans Paramètres › Mon compte › Avancé : « Utiliser un autre compte
   Matrix ». Pendant l'appel : écran de chargement propre (« Connexion à Mood… »), et en cas de
   `503` : « Le serveur Mood est injoignable » + bouton Réessayer.
5. Inscription par e-mail : passer `email_redirect_to = mood://auth-callback` au signup ; gérer le
   retour (`onOpenURL`) pour finir la connexion ; message clair « Confirme ton e-mail, puis reviens ».
6. Le homeserver par défaut vient de la réponse (`homeserver`), plus de `matrix.org` en dur dans le
   parcours Mood (la connexion Matrix manuelle avancée peut garder un champ homeserver).
7. Tests Swift Testing : décodage de la réponse du contrat, mapping d'erreurs, génération du
   `device_id`.

## Vérification
Build Mac Catalyst + iPhone (derivedDataPath `build/DerivedData`) jusqu'à `** BUILD SUCCEEDED **`,
`moodTests` verts. Quand la fonction E est déployée et le serveur D en ligne, test réel : créer un
compte Mood de test → arriver dans l'app sans question Matrix ; capture dans
`docs/screenshots/provisioning/`. Ne crée **aucun compte sans** e-mail de test fourni par Augustin ;
en attendant, simule la réponse de la fonction dans un test. Rien sur GitHub, aucun secret.
