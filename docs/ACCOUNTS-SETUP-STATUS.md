# Configuration des comptes Mood — 9 octobre 2026

Projet Supabase : **mood**, `jxpgyblzymshyzbkgmat`.
Configuration réalisée dans Chrome avec les sessions existantes. Aucun compte créé et aucune connexion effectuée dans Mood. Aucun secret saisi, révélé ou copié. Aucun push GitHub.

## Fait et vérifié

- **Migration appliquée** dans SQL Editor : contenu strictement identique à `supabase/migrations/20261007000000_profiles.sql` (comparaison intégrale vérifiée). Résultat : « Success. No rows returned ». [Capture](../screenshots/accounts-setup/migration.jpg).
- **Tables présentes** dans Table Editor : `public.profiles` et `public.discord_guilds_import`, vides, chacune avec trois politiques RLS. [Profiles](../screenshots/accounts-setup/tables.jpg), [imports](../screenshots/accounts-setup/import-table.jpg).
- **RLS activé** : Policies affiche « Disable RLS » pour les deux tables. Politiques SELECT, INSERT et UPDATE pour `authenticated`, avec les six noms du fichier SQL. [Capture](../screenshots/accounts-setup/policies.jpg).
- **Triggers présents** dans Database → Triggers : `on_auth_user_created_profile` sur `auth.users`, AFTER INSERT, fonction `create_profile_for_auth_user`; `on_profile_updated` sur `public.profiles`, BEFORE UPDATE, fonction `touch_profile_updated_at`. [Trigger Auth](../screenshots/accounts-setup/trigger.jpg). Leur comportement avec un compte réel n'a pas été testé.
- **Redirection ajoutée** : Authentication → URL Configuration affiche `mood://auth-callback`, Total URLs: 1 et le succès d'enregistrement. Site URL conservée. [Capture](../screenshots/accounts-setup/redirect.jpg).
- **Email activé**, confirmation email activée. Discord actuellement désactivé. [Capture](../screenshots/accounts-setup/providers.jpg).
- **Configuration locale réelle** : URL du projet et clé publique existante `publishable` récupérées du dashboard, écrites dans `Config.xcconfig`. La clé n'est pas reproduite dans ce document. `git check-ignore -v Config.xcconfig` confirme `.gitignore:25`. Fichier non ajouté au commit.
- **Data API activée** dans Integrations → Data API; URL visible `https://jxpgyblzymshyzbkgmat.supabase.co/rest/v1/`. [Capture](../screenshots/accounts-setup/api-url.jpg). Table Editor indique les tables exposées via Data API; aucun changement supplémentaire de permissions effectué.
- **Build iPhone réussi** : `** BUILD SUCCEEDED **` dans `build/accounts-setup/iphone.log`, destination iPhone 18 Pro, commandes AGENTS.md, sans signature.
- App compilée installée et lancée sur le simulateur dédié existant **Mood B accounts verification**. [Capture inspectée](../screenshots/accounts-setup/iphone-discord.png) : bouton **Se connecter avec Discord** visible avec la vraie configuration publique. Aucun bouton de connexion actionné. Ceci ne valide pas OAuth.

## Blocages et état Discord

Discord Developer Portal montre seulement ClipFactory, claw et Hermes Agent : aucune application Mood. La création est préparée avec le nom **Mood**, mais pas soumise : la boîte de dialogue exige d'accepter les Conditions d'utilisation et la Politique pour les développeurs. Une confirmation a été demandée à Augustin et aucune réponse n'a été reçue au moment du rapport. [Écran de création](../screenshots/accounts-setup/discord-create.jpg).

Supabase → Authentication → Sign In / Providers → Discord exige **Client ID** et **Client Secret**. Aucun champ modifié, fournisseur laissé désactivé. [Écran de relais](../screenshots/accounts-setup/discord-provider.jpg). Le Client ID n'existe donc pas encore et n'a pas pu être reporté. Le secret doit être manipulé uniquement par Augustin.

## CHECKLIST restante pour Augustin

1. [Discord Developer Portal](https://discord.com/developers/applications) → **Nouvelle application** → nom **Mood**. Lire et accepter personnellement les conditions, puis **Créer**. Ne modifier aucune autre application.
2. Dans **Mood → OAuth2**, section **Redirects / Redirections** → **Add Redirect / Ajouter une redirection**. Coller exactement `https://jxpgyblzymshyzbkgmat.supabase.co/auth/v1/callback`, puis **Save Changes / Enregistrer les modifications**.
3. Dans **Mood → OAuth2**, copier le **Client ID** public. Ouvrir [Supabase → Sign In / Providers](https://supabase.com/dashboard/project/jxpgyblzymshyzbkgmat/auth/providers) → **Discord** → coller cet identifiant dans **Client ID**.
4. Augustin uniquement : récupérer le **Client Secret** de l'application Mood dans Discord OAuth2, puis le coller directement dans le champ **Client Secret** du fournisseur Discord de Supabase. Si Discord demande un mot de passe, une validation ou un reset de secret, effectuer cette étape soi-même. Ne jamais envoyer le secret dans le chat, le dépôt, une capture ou `Config.xcconfig`.
5. Dans le même panneau Supabase, activer **Discord enabled**, conserver **Allow users without an email** désactivé, puis **Save**. Vérifier que Discord affiche **Enabled**.
6. La migration, la redirection Mood et la configuration locale sont déjà faites : ne pas réexécuter aveuglément la migration (les créations de politiques et du trigger public ne sont pas idempotentes).
7. Augustin uniquement, après activation : tester volontairement la connexion Discord depuis Mood et le retour à l'application. Vérifier qu'un profil propre au compte est créé, puis la liaison Matrix et l'import d'un serveur. Ces tests restent entièrement non effectués. Pour Email, confirmer l'adresse avant connexion.
8. Vérifier ensuite les accès RLS entre deux comptes de test distincts (aucun accès aux données de l'autre). Aucun compte de test n'a été créé par l'agent.

Les onglets Chrome Discord création et Supabase fournisseur Discord sont laissés ouverts pour le relais.
