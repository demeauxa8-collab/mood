# Brief E — Edge Function `matrix-session` (Claude)

Branche `claude/edge-matrix-session`. Lis `docs/BACKEND-PLAN.md` §1 (décisions) et §2 (**contrat d'API,
à respecter à la lettre** : la piste F code l'app contre lui en parallèle).

## À faire
1. `supabase/functions/matrix-session/index.ts` (Deno, `Deno.serve`, aucune dépendance npm lourde) :
   - authentifie l'appelant : lire `Authorization: Bearer`, valider via
     `GET {SUPABASE_URL}/auth/v1/user` (avec `apikey`) — ne fais pas confiance à un `user_id` envoyé ;
   - `localpart = "m" + userId.replaceAll("-","").slice(0,12)` ; mot de passe =
     `base64url(HMAC-SHA256(MATRIX_PASSWORD_PEPPER, userId))` (WebCrypto) ;
   - essaie `POST /_matrix/client/v3/login` (`m.login.password`, identifiant `m.id.user`,
     `device_id`, `initial_device_display_name`) ; si `M_FORBIDDEN`/utilisateur inconnu →
     inscription `POST /_matrix/client/v3/register` : 1er appel sans `auth` → récupère `session`
     (401 UIAA), 2e appel avec `auth: {type: "m.login.registration_token", token, session}`,
     `username`, `password`, `device_id`, `initial_device_display_name`, puis `PUT /profile/{id}/displayname` ;
   - met à jour `public.profiles` (`matrix_user_id`, `matrix_homeserver`) avec la clé `service_role`
     (variable `SUPABASE_SERVICE_ROLE_KEY`, fournie par Supabase aux fonctions) ;
   - réponses et codes d'erreur exactement comme le contrat ; timeouts (8 s) → `503`.
   - ne journalise **jamais** de jeton, mot de passe ou pepper.
2. `supabase/functions/matrix-session/README.md` : variables d'environnement, déploiement, tests.
3. Tests Deno (`deno test`) sur la logique pure : dérivation du localpart, du mot de passe (vecteur
   fixe), construction des corps de requête, mapping des erreurs Matrix → contrat.
4. Script `scripts/test-matrix-session.sh` : appelle la fonction déployée avec un jeton Supabase de
   test passé en argument et affiche le résultat **sans** le jeton.
5. Pas de déploiement toi-même : Claude (session principale) déploie via le MCP Supabase et Augustin
   colle les secrets.

## Vérification
Pas de xcodebuild ici. `deno` peut ne pas être installé sur le MacBook : écris des tests corrects, ils
seront lancés sur le Studio (`/opt/homebrew/bin/deno test`). Rien sur GitHub.
