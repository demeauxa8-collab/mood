# Mot de passe oublié et confirmation par code

La connexion Mood propose « Mot de passe oublié ? » sous le mot de passe, sur Mac et iPhone.
Le parcours demande l’adresse e-mail, puis le code à six chiffres et deux saisies du nouveau mot
de passe (au moins huit caractères). Un lien de récupération ouvert sur le même appareil passe
directement au nouveau mot de passe. Le code peut donc être lu sur un autre appareil.

La confirmation d’inscription accepte maintenant le code. Le lien, la vérification automatique
toutes les 15 secondes (pendant 20 minutes) et « J’ai confirmé mon e-mail » restent disponibles.
Les boutons d’envoi sont désactivés pendant les requêtes. Les erreurs de code expiré/invalide,
de limitation des tentatives et de mot de passe sont expliquées en français.

La session de récupération reste uniquement en mémoire jusqu’au changement du mot de passe.
 Après succès, Mood emprunte le parcours de connexion et de provisioning Matrix existant.
 Aucun mot de passe du parcours n’est enregistré sur disque.

## Modèles d’e-mail à coller par Augustin

Dans Supabase → Authentication → Email Templates, remplacer le corps des deux modèles par les
 textes HTML suivants. **Sans cette modification manuelle, les e-mails par défaut ne montrent
 que le lien et le parcours par code n’est pas utilisable.** La configuration n’a pas été modifiée
 par l’assistant.

### Reset Password

```html
<p>Pour changer ton mot de passe Mood, entre ce code dans l’application :</p>
<p><strong>{{ .Token }}</strong></p>
<p>Tu peux aussi <a href="{{ .ConfirmationURL }}">changer ton mot de passe avec ce lien</a> sur l’appareil où Mood est installé.</p>
<p>Si tu n’as rien demandé, ignore cet e-mail.</p>
```

### Confirm signup

```html
<p>Bienvenue sur Mood ! Entre ce code dans l’application pour confirmer ton adresse :</p>
<p><strong>{{ .Token }}</strong></p>
<p>Tu peux aussi <a href="{{ .ConfirmationURL }}">confirmer ton adresse avec ce lien</a>.</p>
```

## Vérification locale

Build Mac Catalyst : **BUILD SUCCEEDED**. Build iPhone : **BUILD SUCCEEDED**.
Tests sur « Mood M iPhone » (clone de test Xcode) : **TEST SUCCEEDED**, 0 tests réussis, dont 6 nouveaux tests de récupération/confirmation.
Journaux locaux : `build/password-reset/mac.log`, `iphone.log`, `tests.log`. Les requêtes des tests sont
 interceptées par URLProtocol et utilisent uniquement des adresses `.invalid`, des codes et
identifiants synthétiques. Les nouveaux tests ne lisent ni n’écrivent le trousseau.

Cinq captures examinées visuellement : connexion, demande de code, code + nouveau mot de passe,
lien confirmé + nouveau mot de passe, confirmation d’inscription. Champs et boutons visibles,
sans texte coupé. Les contrôles sont volontairement désactivés dans ces captures de démonstration.
Captures : `docs/screenshots/password-reset/`. Le mode `-authPreview login|recover|code|link|signup`
affiche des états déterministes, ne restaure aucune session, ne charge pas les fournisseurs et
désactive les interactions. Il sert uniquement aux captures ; il est inaccessible depuis l’interface.
L’ajustement de `MoodApp.swift` permet ce mode et affiche aussi la récupération lorsqu’un lien
arrive pendant une session déjà ouverte. Aucun fichier Matrix n’a été modifié.

## Ce qu’Augustin doit tester ensuite

1. Coller les deux modèles ci-dessus dans Supabase, puis utiliser lui-même son compte.
2. Depuis Mac et iPhone : demander un code, le lire sur un autre appareil, choisir un nouveau mot
   de passe, vérifier l’arrivée dans Mood et l’accès aux conversations.
3. Vérifier qu’un ancien code, un code incorrect et un mot de passe trop court sont refusés ;
   renvoyer le code et réessayer. Vérifier les limitations réelles d’envoi Supabase.
4. Ouvrir le lien de récupération sur l’appareil où Mood est installé : seul le nouveau mot de passe
   doit être demandé. Annuler puis recommencer si nécessaire.
5. Lors d’une inscription, vérifier le code, le lien sur un autre appareil, la connexion automatique
   et le bouton « J’ai confirmé mon e-mail ».

Ces parcours réels et la livraison effective des e-mails ne sont pas validés ici : aucun compte
réel, aucun e-mail réel et aucun appel d’authentification réel n’ont été utilisés. Aucun lancement d’app Mac,
 aucune action sur Mood Merge, aucun usage du simulateur nommé « iPhone 18 Pro », aucune
publication GitHub.
