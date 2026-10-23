# Brief M — « Mot de passe oublié ? » et confirmation par code (Codex)

Branche `codex/password-reset`, dossier `~/mood-codex-M` (worktree de `~/mood-codex-merge`, partant de
`codex/pixel-merge`). **Ne commite pas dans `~/mood-codex-merge` et ne change pas sa branche.**
Lis `AGENTS.md`, `docs/BACKEND.md`, `docs/MODE-EMPLOI.md`, `mood/Core/Account/` et `mood/Features/Auth/`.

## Problème
Un vrai test a montré qu'un utilisateur qui oublie son mot de passe est bloqué : l'écran de connexion
Mood n'a **aucun « Mot de passe oublié ? »** (`loginForgotPassword` n'existe que pour la connexion Matrix
avancée). Et les liens des e-mails Supabase (`mood://auth-callback`) ne rouvrent l'app que si l'e-mail est
lu sur le même appareil : la plupart du temps ils mènent à une page qui ne marche pas.

## À faire
1. **Mot de passe oublié** sur l'écran de connexion Mood (Mac + iPhone), sous le champ mot de passe :
   - saisir l'e-mail → `POST {SUPABASE}/auth/v1/recover` `{email}` (avec `?redirect_to=mood%3A%2F%2Fauth-callback`) ;
   - écran « Entre le code reçu par e-mail » + « Nouveau mot de passe » (+ confirmation) →
     `POST /auth/v1/verify` `{type: "recovery", email, token}` → session → `PUT /auth/v1/user` `{password}`
     → connecté (même parcours que `signIn` ensuite : `AccountStore` + provisioning Matrix) ;
   - si le lien de l'e-mail rouvre l'app (`mood://auth-callback#…&type=recovery`), afficher directement
     « Nouveau mot de passe » ;
   - « Renvoyer le code », messages français clairs (code invalide/expiré, trop de tentatives,
     mot de passe trop court), boutons désactivés pendant l'envoi (aucun double appui).
2. **Confirmation d'inscription par code** : sur l'écran « Vérifie ta boîte mail » existant
   (`SignupView.confirmationPanel`, `AccountStore.pendingConfirmationEmail`), ajouter un champ « Code à
   6 chiffres » → `POST /auth/v1/verify` `{type: "signup", email, token}` → connecté. Garder la connexion
   automatique toutes les 15 s et le bouton « J'ai confirmé ».
3. Réutilise `SupabaseAuthClient.request` et `frenchMessage(for:)` (ajoute les messages utiles). Aucun mot
   de passe stocké en dehors de la mémoire du parcours.
4. Tests Swift Testing : corps des requêtes `recover` / `verify` / `PUT user` (via `URLProtocol` intercepté,
   valeurs synthétiques), validation du code (6 chiffres) et du mot de passe, mapping d'erreurs.

## Important : e-mails Supabase
Les modèles d'e-mail par défaut ne contiennent **que le lien**. Le code `{{ .Token }}` doit être ajouté par
Augustin dans Supabase › Authentication › Email Templates (« Reset Password » et « Confirm signup »).
Écris dans ton rapport le texte exact à coller (français, court, avec `{{ .Token }}` bien visible et le lien
`{{ .ConfirmationURL }}` gardé en second). **Ne modifie pas la configuration Supabase toi-même.**

## Contraintes
- Zone : `mood/Features/Auth/`, `mood/Core/Account/`, tests. Ne touche pas à `MatrixStore` / `MatrixClient`
  sauf nécessité absolue (alors en fin de classe sous `// MARK: - Password reset`).
- `AGENTS.md` (couleurs, tailles, animations Discord). **Aucun compte réel**, aucun mot de passe tapé,
  aucun e-mail envoyé à une vraie adresse, aucun secret.
- Simulateur : le tien, `xcrun simctl create "Mood M iPhone" "iPhone 18 Pro"` ; pas « iPhone 18 Pro », ne
  ferme pas et ne relance pas l'app Mac ouverte, ne lance pas d'app Mac.
- `Config.xcconfig` (ignoré par git) : copie-le depuis `~/mood-codex-merge/Config.xcconfig`. Rien sur GitHub.

## Vérification
Builds Mac Catalyst + iPhone `** BUILD SUCCEEDED **`, `moodTests` verts sur « Mood M iPhone », captures
démo des nouveaux écrans dans `docs/screenshots/password-reset/` (regarde-les), rapport
`docs/PASSWORD-RESET.md` (français) avec les textes de modèles d'e-mail à coller et ce qu'Augustin doit
tester. Commits petits, en anglais, dernière ligne `Co-Authored-By: Codex <noreply@openai.com>`.
