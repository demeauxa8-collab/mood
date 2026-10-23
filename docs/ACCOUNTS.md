# Comptes Mood

Mood utilise Supabase Auth pour les comptes Mood et Matrix pour les messages. Aucune migration n'est exécutée par l'application.

## Configurer Discord dans Supabase

1. Créer une application dans le [Discord Developer Portal](https://discord.com/developers/applications).
2. Dans OAuth2, ajouter cette URL de redirection :
   `https://jxpgyblzymshyzbkgmat.supabase.co/auth/v1/callback`
3. Dans Supabase, ouvrir **Authentication → Providers → Discord**, activer le fournisseur et saisir le Client ID et le Client Secret Discord.
4. Dans **Authentication → URL Configuration**, ajouter `mood://auth-callback` aux URL de redirection autorisées.
5. Copier `Config.example.xcconfig` vers `Config.xcconfig` et renseigner `SUPABASE_URL` et `SUPABASE_ANON_KEY`.
6. Ouvrir `mood.xcodeproj`, sélectionner le schéma `mood`, puis compiler.

Le bouton Discord est masqué tant que l'URL et la clé anon ne sont pas fournies. La connexion Matrix directe reste disponible. La migration `supabase/migrations/20261007000000_profiles.sql` est un fichier à examiner et appliquer séparément par l'administrateur.

## Données importées

L'import des serveurs Discord copie uniquement le nom et l'icône vers des espaces Matrix. Discord ne fournit pas de liste d'amis ou de messages à une application OAuth ordinaire; Mood ne tente pas de les lire.

## Précisions de configuration

- Garder la forme `https:/$()/…` du fichier exemple : `//` seul est interprété comme un commentaire par Xcode.
- Les configurations Debug et Release chargent `Config.defaults.xcconfig`, qui inclut le fichier local s'il existe. Sans configuration, Mood reste un client Matrix direct.
- Utiliser uniquement la clé publique/anon, jamais une clé `service_role` ou secrète.
- Faire examiner puis appliquer séparément la migration fournie avant de tester les comptes. Elle ajoute les profils, les imports, les droits PostgREST et les règles d'accès au propriétaire. Mood ne l'exécute jamais.
- Si la confirmation email est activée, confirmer l'adresse avant de revenir à la connexion. Pour associer un compte email existant à Discord, utiliser la même adresse vérifiée.
- « Synchroniser » redemande la connexion Discord si son autorisation a expiré. « Délier » retire l'identité Auth et les champs Discord du profil ; Supabase exige un autre moyen de connexion pour éviter de bloquer le compte. Vérifier les options de liaison d'identités dans Supabase si le serveur refuse cette action.
- Les imports déjà enregistrés sont désactivés. Chaque import conserve l'identifiant réel de l'espace Matrix. Aucun salon, membre, message ou ami Discord n'est copié.

Références : [PKCE Supabase](https://supabase.com/docs/guides/auth/sessions/pkce-flow), [Discord](https://supabase.com/docs/guides/auth/social-login/auth-discord), [liaison et déliaison](https://supabase.com/docs/guides/auth/auth-identity-linking).

L’icône Discord embarquée provient de [Simple Icons](https://github.com/simple-icons/simple-icons/blob/develop/icons/discord.svg) (CC0).

## Validation du 7 octobre 2026

- Reprise du commit WIP sur `codex/accounts-supabase`, sans dépendance externe.
- Mac Catalyst et iPhone 18 Pro : `** BUILD SUCCEEDED **`, avec les commandes d'AGENTS.md et `build/DerivedData`.
- `moodTests` : `** TEST SUCCEEDED **`, 19 tests, dont PKCE RFC 7636, URL OAuth, expiration des tokens, configuration absente et décodage des réponses Auth/Discord.
- Captures prises et inspectées sur un iPhone 18 Pro isolé : [connexion Matrix sans Supabase](../screenshots/accounts-iphone-matrix.png), [connexion Mood/Discord](../screenshots/accounts-iphone-discord.png), [accueil en démo](../screenshots/accounts-iphone-preview.png).
- La capture Discord utilise une copie locale de l'app avec une URL et une clé factices, uniquement pour vérifier l'affichage ; aucun login n'a été envoyé. Le simulateur reçoit ensuite la version compilée normale.
- À valider après configuration par Augustin : OAuth Discord réel, confirmation email, liaison Matrix, règles SQL et import d'un serveur réel. La migration et la configuration du fournisseur n'ont pas été exécutées sur Supabase.
