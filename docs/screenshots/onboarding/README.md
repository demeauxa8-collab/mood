# Captures d’onboarding — piste U

Aucune capture n’a été produite pendant cette session : l’instruction directe du 23 octobre interdit les apps Mac et tout simulateur, y compris celui de la piste U. L’autorisation de capture du brief ne prime pas sur cette instruction. Aucun ancien rendu n’est présenté comme une capture de l’app intégrée.

Passe 3 : la capture de revue existante `/Users/Adm/mood-logs/uv/U-avatar.png` a été examinée pour diagnostiquer le chevauchement du bouton photo. Un espacement qui grandit avec la taille du texte a été ajouté sous le sous-titre. Les nouvelles captures `avatar` et `avatar` avec `-onboardingLargeText` restent à réaliser après autorisation de lancer un simulateur ; aucune image corrigée n'est annoncée comme validée.

La route de revue est prête pour une future vérification autorisée sur un simulateur réservé à cette piste. Ne pas utiliser l’iPhone 18 Pro ni remplacer la version de démonstration.

Arguments de l’app, à combiner avec `-onboardingPreview` :

| Argument | Effet |
|---|---|
| `-onboardingStep <étape>` | `welcome`, `email`, `account` (mot de passe seul), `confirmation`, `displayName`, `username`, `trust`, `server`, `notifications`, `friends`, `avatar`, `signIn`. |
| `-onboardingFilled` | Saisies synthétiques, e-mail sous `.invalid`, mot de passe d’exemple et code factice pour les écrans concernés. |
| `-onboardingTaken` | La recherche du nom renvoie « pris » ; utiliser avec l’étape `username` remplie. |
| `-onboardingOffline` | Les actions de revue renvoient une erreur réseau ; à `username` rempli, l’erreur apparaît après la vérification. |
| `-onboardingLongText` | Nom affiché et nom de serveur longs, nom d’utilisateur de 32 caractères. |
| `-onboardingLargeText` | Taille de texte d’accessibilité (`accessibility3`). |
| `-onboardingHomeEmpty` | Le composant d’accueil vide ; Ajouter des amis ouvre l’étape de recherche simulée. |

Ces arguments n’ouvrent aucune session réelle, ne font aucun appel au service et ne demandent pas la permission système de notification. Le composant d’accueil isolé ne remplace pas une capture de ses deux vraies racines.

À vérifier avant livraison visuelle : 393 × 852 sur iPhone, clavier logiciel et matériel, erreurs et attente, photos/emoji, navigation et chemins Passer, puis carte Catalyst à 1280 × 800 et après redimensionnement. Regarder les captures, corriger et recapturer. Compléter par VoiceOver et le contraste mesuré. Éteindre le simulateur réservé après cette future revue.
