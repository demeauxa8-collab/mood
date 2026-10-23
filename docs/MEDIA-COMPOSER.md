# Médias et barre de saisie — N2

15 octobre 2026 · branche locale `codex/messaging-media` · worktree `/Users/Adm/mood-codex-N2`.

## État de livraison

Le composeur partagé est maintenant raccordé aux salons desktop (`ChatArea`), aux MP
(`DMChatArea`) et aux conversations iPhone (`MobileChatScreen`, salons et MP).
Les autorisations micro, caméra et photothèque sont déclarées en français, sans entitlement ajouté.
Les bulles utilisent déjà le rendu partagé vidéo/audio/GIF et les aperçus de liens.
L’autorisation de raccordement a été donnée explicitement le 15 octobre.

Les preuves distinguent compilation, tests de logique, contrats serveur et rendu de démonstration.
Aucun enregistrement micro physique, prise de vue, compte Mood réel ou lancement Mac n’est revendiqué.
Le raccourci de réaction rapide des menus N1 reste « 👍 » : ces menus sont explicitement exclus des
modifications autorisées. Le sélecteur complet et ses récents sont partagés desktop/iPhone/réactions.

## Les huit points

| Point | État | Preuve et limite réelle |
|---|---|---|
| 1. Jusqu’à 10 pièces jointes | Ajouté et raccordé | Politique de sélection/dédoublonnage/limite et retrait individuel, sélecteur multiple, dépôt de plusieurs URL dans `MediaComposer`. Préparation de tout le lot avant mise en file pour éviter les doublons après une erreur sur le dernier fichier. Un événement par fichier, plus le texte, dans la file persistante existante. Test de logique et contrôle HTTP réel de 10 images + texte. Les trois hôtes utilisent maintenant la sélection multiple partagée. |
| 2. Photos et vidéos iPhone | Ajouté et raccordé | `MediaAttachmentPicker` : PhotosPicker images/vidéos, transfert de fichiers copié dans la portée temporaire, import multiple et appareil photo si disponible. `MediaPreparation` produit durée, dimensions et miniature JPEG des vidéos. Vrais MP4/AAC utilisés dans les tests. Permissions déclarées ; caméra cachée si l’appareil ne la propose pas (notamment le simulateur). |
| 3. Lecture vidéo/audio/GIF | Corrigé et ajouté dans les bulles partagées | `PlayableMedia` télécharge via `MediaLoader` avant AVPlayer, propose plein écran vidéo, contrôles audio et forme d’onde des événements vocaux. Choix actuel du lecteur par extension de nom : les médias sans extension connue restent des fichiers à télécharger. GIF : conservation des frames à la préparation, téléchargement original dans la bulle, animation UIKit. Les grandes animations sont sous-échantillonnées avec budget de décodage de 24 Mio et durée conservée ; les avatars utilisent aussi ce décodeur. Captures de composants isolés, tests ImageIO et AVFoundation ; interaction réelle à vérifier par Augustin. |
| 4. Vocaux | Ajouté et activé | `VoiceRecorderButton` : maintien, glisser à gauche pour annuler, permission au premier usage, protection contre relâchement pendant la demande de permission, métrage, minimum 300 ms, limite 2 min, arrêt à la disparition. `sendVoice` persiste durée et forme d’onde ; outbox ajoute `org.matrix.msc3245.voice` et `org.matrix.msc1767.audio`. Contrat serveur relu exactement et test de sérialisation. Clé micro présente, contrôle activé dans les trois hôtes. Arrêt sans envoi au passage en arrière-plan. Aucun enregistrement micro réel validé. |
| 5. Aperçus de liens | Ajouté dans la bulle partagée | Requête Bearer `client/v1/media/preview_url`, cache mémoire borné, carte titre/description/image mxc, chargement asynchrone sans bloquer l’envoi. Échec silencieux : le lien reste utilisable. GitHub autorisé et example.com refusé vérifiés en vrai. Pas de changement serveur. Cache actuel : succès seulement ; refus non mémorisés, à améliorer si les rechargements de lignes deviennent nombreux. |
| 6. Emoji complet | Ajouté aux sélecteurs desktop/iPhone/réactions | 3 944 emoji pleinement qualifiés Unicode 17.0, catégories, recherche française CLDR 48 insensible à la casse/aux accents, récents persistants (32), tons de peau comme entrées distinctes. `EmojiPicker` réutilise `MediaEmojiPicker`. `MobileEmojiPicker` utilise le même catalogue et les mêmes récents. Réaction rapide « 👍 » de N1 conservée, conformément à l’interdiction de modifier ses menus. Sources/licence dans `Resources/EmojiCatalog-LICENSE.txt`. |
| 7. Brouillons par salon | Ajouté et raccordé | `ComposerDrafts` persiste texte et événement de réponse, clés séparées par compte et identifiant stable du salon, effacement après envoi. Tests de relance du stockage, isolation compte/salon et suppression. Utilisé dans les conversations affichées. Identité du composeur séparée par compte/salon ; instantané local à la disparition et garde empêchant un envoi ancien d’effacer le texte du nouvel écran. Les fichiers joints non envoyés ne sont pas persistés comme brouillons ; une fois envoyés ils le sont via l’outbox. |
| 8. Barre de saisie | Raccordé ; vérifications gestuelles restantes | `MessageReturnKey` conservé. Sélecteur existant : suggestion insère le nom lisible au lieu de l’identifiant technique ; le formateur existant résout ce nom en mention. Emoji désactivé en conversation désactivée et erreurs d’import/collage visibles. Compteur 4 000 et collage existants conservés. Nouveau composeur : compteur, Entrée/Maj+Entrée, mentions lisibles, collage Cmd+V et état désactivé. Collage tactile iPhone ajouté via PasteButton ; raccordement terminé, raccourci ↑ d’édition conservé. Gestes clavier et collage réels à vérifier sur appareil. |

## Zones réellement modifiées

- `MessageComposer.swift` et `AttachmentDraftPreview.swift` ; nouveaux fichiers de composants médias et
  logique dans `Features/Chat/`, catalogue et petites fixtures déterministes dans `Resources/`.
- `MediaLoader`, `AuthenticatedImage`, `MediaPreparation`, données d’outbox.
- `MatrixClient` et `MatrixStore` : nouveaux points d’entrée en fin de classe sous le repère N2. Une
  substitution dans la livraison de l’outbox appelle `attachment.eventContent()` pour ajouter les deux
  champs vocaux en dehors de `info` (leur emplacement dans le protocole).
- `ChatArea.swift` : rendu média existant et remplacement local de l’appel au composeur ; aucun changement de liste, menus, fils, recherche ou transfert.
- `DirectMessages.swift`, `MobileChatScreen.swift` : remplacement local des composeurs, bindings texte/réponse et saisie en cours conservés ; `MobileEmojiPicker.swift` raccordé au catalogue partagé.
- `Mood-Info.plist` : trois descriptions de permission françaises uniquement.
- Tests Swift de logique et `server/media-check.py`, qui réutilise le transport et le nettoyage de
  `feature-check.py` sans modifier ce dernier.

## Vérifications

Les résultats définitifs et empreintes sont dans `screenshots/media/validation.json`. Le détail des
contrôles serveur est dans `screenshots/media/server-validation.json`.

- Builds finaux Mac Catalyst et iPhone : `** BUILD SUCCEEDED **` ; journaux locaux
  `/tmp/mood-n2-mac-final.log` et `/tmp/mood-n2-ios-tests-delivery.log`. Aucun lancement Mac.
- Suite complète : **148 tests réussis, 0 échec**, sur « Mood N2 iPhone » ; résultat final détaillé dans `validation.json`.
- Captures de la conversation réellement raccordée et de la galerie démo dans `screenshots/media/`.
  Images ouvertes et contrôlées ; elles ne prouvent pas une interaction physique ni un envoi de compte réel.
  Le contrôle visuel a fait retirer les boutons d’envoi redondants des aperçus : retrait individuel par croix, envoi unique dans la barre principale.


`python3 server/media-check.py --local` : **47 PASS, 0 FAIL**. Deux comptes `n2check-*` créés pour chaque
exécution, dans un salon isolé, secrets uniquement en mémoire. MP4 H.264, AAC et GIF animés réels : upload
puis téléchargement authentifié comparé octet par octet ; événements vidéo/audio/voix relus exactement.
Dix images et texte envoyés séparément. Aperçus GitHub autorisé/example.com refusé. Salon quitté,
comptes désactivés en `finally`, reconnexion des comptes désactivés refusée. Les salons/médias de test
peuvent rester stockés sur le serveur. Aucun compte préexistant touché.

Mode démo : `-uiPreview -uiPreviewScreen chat -messagingPreview attachment -mediaPreview`, avec
`-emojiPreview` pour le catalogue. La galerie s’ouvre depuis l’aperçu de démonstration. Le mode `-uiPreview -uiPreviewScreen chat -composerPreview` affiche aussi deux fichiers locaux dans le composeur réellement raccordé. Aucun de ces modes ne connecte un compte.

Aucune app Mac lancée. Seul l’UUID `320F3D8B-0CAF-4F8F-94C0-AF9AAA77FF90` (« Mood N2 iPhone ») est utilisé
pour les commandes de simulateur ; Xcode crée ses propres clones de ce simulateur pour les tests.
Aucun compte Mood/Supabase, aucun mot de passe saisi dans une app, aucun secret imprimé, aucun changement
de configuration serveur/Supabase, aucun push, PR ni changement GitHub. `Config.xcconfig` copié depuis le worktree
de fusion sans afficher son contenu ; fichier ignoré par git. Aucun changement du worktree de fusion.

## Raccordements terminés et limites

Les identifiants de salon réels et les membres sont transmis aux composeurs. Une conversation réelle
sans identifiant exploitable et une conversation chiffrée désactivent la saisie. La réponse est conservée
par identifiant d’événement, même hors historique chargé. Une erreur de préparation conserve les fichiers
et affiche l’erreur dans le composeur. Les utilisateurs en train d’écrire restent affichés.
Les pièces jointes non envoyées ne sont pas des brouillons persistants ; l’outbox persiste après Envoi.

Le bouton rapide « 👍 » reste dans le périmètre N1, non modifié. Les médias entrants sans extension
reconnue restent téléchargeables mais n’obtiennent pas encore le lecteur intégré. Ces deux limites
empêchent de revendiquer une parité Discord exhaustive. La validation gestuelle et matérielle ci-dessous
reste nécessaire ; les comptes réels et le lancement Mac sont interdits pour cette mission.

## Ce qu’Augustin doit tester sur appareil

1. Sur Mac et iPhone : dix fichiers mixtes + texte, retrait du 4e, ajout du 11e refusé ; dépôt multiple,
   fichier inaccessible et trop volumineux. Vérifier ordre, texte unique et absence de doublons.
2. Couper Internet après Envoyer, relancer puis reconnecter : fichiers présents, reprise sans doublon ;
   annuler/réessayer pendant upload. Changer de salon pendant la préparation et pendant l’envoi.
3. Photothèque photo/vidéo, prise photo/vidéo et refus de permission ; vérifier orientation, durée,
   miniature, taille et lecture chez le destinataire. Vérifier aussi fichier sans extension.
4. Lecture vidéo dans le chat et en plein écran, audio avec contrôles, GIF réellement animé ; vérifier
   erreurs de téléchargement, défilement et arrêt de lecture à la disparition de la vue.
5. Vocal : première demande micro, refus, maintien/relâchement, glisser-annuler, vocal trop court,
   interruption/app en arrière-plan et limite de 2 min ; forme d’onde reçue et lecture chez l’autre.
6. Lien GitHub et lien example.com : carte ou lien simple, sans délai d’envoi. Recherche emoji « fête »,
   tons de peau et récents communs aux réactions. Clavier Entrée/Maj+Entrée, Cmd+V et collage tactile.
7. Deux salons portant le même nom : texte et réponse distincts, relance puis retour dans chacun ;
   déconnexion/reconnexion et autre compte : aucune contamination de brouillons.

## Proposition d’élargissement des aperçus — décision d’Augustin

Conserver la liste blanche actuelle est le choix par défaut. Pour un domaine supplémentaire réellement
utile, ajouter **uniquement ce domaine** à `url_preview_domain_explicit_allowlist`, après vérification de
ses redirections et de son contenu, plutôt que d’autoriser tous les sites. Le brief identifie le fichier
`~/mood-server/continuwuity.toml` ; il n’a pas été modifié ni affiché pendant cette mission.

Risques : le site distant apprend que le serveur a consulté le lien, traces éventuelles d’URL privées ou
à jeton, consommation réseau/CPU et stockage de miniatures, contenu hostile, redirections et rebinding
DNS vers des adresses internes (SSRF). Garder le blocage des IP privées, les délais/limites de taille et
la liste explicite ; ne jamais autoriser les domaines de fichiers privés ou des URL de connexion. Une
ouverture globale n’est pas proposée. Le serveur conserve le dernier mot ; l’app reste utilisable quand
l’aperçu est refusé.
