# Llama-IOS IA locale iOS

Pal est une application iOS SwiftUI construite autour de `llama.cpp` et de modèles GGUF locaux.

## Fonctionnalités présentes dans cette version

- Inférence locale via llama.cpp.
- Sélection de GGUF dans l'app Fichiers avec signets de sécurité iOS : les gros modèles ne sont pas copiés dans le conteneur Pal.
- Chat persistant, génération en streaming, arrêt et régénération.
- Rendu Markdown natif de base et export de conversation en `.md`.
- Réglages d'échantillonnage, prompt système, thème, couleur, taille du texte et profils mémoire.
- Panneau de diagnostic : mémoire, thermique, batterie, vitesse et contexte.
- **Inspiré de PocketPal AI** : benchmark intégré (pp / tg / 1er token / RAM, dans le panneau jauge), modification du dernier message, régénération, métriques en direct, alerte « RAM juste » avant chargement d'un gros modèle.
- **Pal Skills** : compétences intégrées, création dans l'application, import de fichiers `.md` / `.txt`, activation et suppression.
- Les Skills actives sont ajoutées au prompt système avec une limite de taille pour contenir l'usage du contexte.
- **Pal Research** : recherche Web DuckDuckGo, affichage de titres/extraits/liens, ouverture des sources et insertion des résultats dans le champ de chat.
- **Téléchargements Hugging Face** : recherche de dépôts GGUF, navigation dans les fichiers, jeton facultatif dans le trousseau iOS, téléchargement en arrière-plan, reprise et contrôle de signature GGUF.
- Les résultats Web sont signalés au modèle comme contenu externe non fiable ; aucune instruction récupérée n'est exécutée.

## Skills : ce que signifie « apprendre »

Une Skill est un paquet d'instructions et de méthodes réutilisables. Elle oriente le modèle à chaque requête pertinente. **Elle ne modifie pas les poids du GGUF et n'effectue pas de fine-tuning.** Les connaissances importées ne deviennent pas automatiquement des faits vérifiés.

Exemples disponibles dans `Examples/Skills/` :
- `mathematiques-l1.md`
- `revue-code.md`

Pour ajouter une Skill, ouvre l'onglet étincelles dans Pal, puis crée une compétence ou importe un fichier texte/Markdown. Les compétences importées sont stockées dans les préférences locales de l'application. Une limite de 64 Ko est appliquée à l'import et le prompt transmis au modèle est plafonné.

## Recherche Web et confidentialité

- La recherche nécessite une connexion Internet.
- Les requêtes sont envoyées à DuckDuckGo par HTTPS. Elles ne sont pas envoyées au moteur llama.cpp local.
- Pal n'utilise pas de clé API ni de serveur personnel pour cette fonction.
- La page HTML de recherche peut évoluer ou limiter les requêtes ; dans ce cas, la recherche peut échouer et devra être adaptée.
- Vérifie les pages originales avant de te fier aux extraits. Les pages Web peuvent contenir des erreurs ou des instructions malveillantes.
- Une fois les résultats insérés dans le chat, la génération du résumé reste locale.

## Compilation cloud

1. Déposer tout le contenu du dépôt, y compris le dossier caché `.github/`, à la racine de GitHub.
2. Vérifier que ce dépôt possède une release nommée `deps-1` contenant exactement `llama-b12130-xcframework.zip` (archive contenant `llama.xcframework`). Cette dépendance n'est pas incluse dans le ZIP source.
3. Ouvrir **Actions** et lancer **Build Pal IPA (unsigned)**.
4. Télécharger l'artefact `Pal-ipa-unsigned`.
4. L'IPA produit est **non signé** : il faut le signer avec une méthode iOS autorisée avant installation.

Le workflow télécharge le XCFramework iOS llama.cpp depuis la dernière release llama.cpp qui en contient un, puis génère le projet avec XcodeGen et lance Xcode sur un runner macOS.

## Limites connues et prochaine étape

- La compilation Xcode réelle n'a pas été exécutée dans cet environnement ; seule l'analyse syntaxique Swift et la validation YAML ont été effectuées.
- La recherche DuckDuckGo repose sur l'analyse de sa page HTML : ce format peut changer, ce n'est pas une API contractuelle.
- La recherche ne télécharge pas et n'analyse pas automatiquement l'intégralité des pages ; elle fournit des extraits et des liens.
- Plusieurs conversations sont prises en charge. Le téléchargement Hugging Face est présent dans le code, mais doit encore être validé sur appareil et avec les réponses réelles de l'API.
- L'association `mmproj` est mémorisée, mais le pipeline vision n'est pas implémenté.
- Le rendu Markdown natif couvre le formatage courant ; tableaux complexes et blocs de code avec coloration nécessitent un moteur dédié.
- Les fichiers iCloud doivent être téléchargés localement pour une utilisation hors ligne.
- Les Skills consomment du contexte ; sur un iPhone XR, active seulement celles qui sont utiles.

## Plateforme

- Déploiement minimum déclaré : iOS 16.
- Bundle ID : `com.local.pal`.
- SwiftUI + llama.cpp.


## Pal 1.0.3-dev — améliorations de confort

- Archivage/désarchivage des discussions et export individuel en TXT/Markdown.
- Zone de saisie agrandie, masquage du clavier à l'envoi, choix de toutes les voix exposées par iOS.
- Réglage distinct de la taille générale de l'interface et de la taille des messages ; styles/couleurs de bulles.
- Profil Ultra expérimental au-delà de Max, sauvegarde du profil Perso, réglages de contexte et batch personnalisables, réinitialisation par paramètre et par groupe.
- Bascule de génération sans réflexion (directive système et `/no_think` pour Qwen3), bouton Continuer après limite de tokens.
- Import de PDF, texte et RTF ; tentative d'import Word via le lecteur Foundation disponible sur l'appareil.
- Import d'image avec OCR local (extraction du texte visible). Ce n'est pas encore une vision multimodale native du modèle.
- Capteurs supplémentaires : taille du fichier modèle et occupation du contexte/cache KV en tokens.

Les options Flash Attention, types/quantification du cache KV, envoi d'images pixels au modèle via mmproj, et compilation Xcode restent conditionnés à la version exacte du `llama.xcframework` et à un environnement iOS de compilation. Elles ne sont pas activées artificiellement dans cette version.


## Mise à jour 1.0.4-dev

- Le champ de saisie perd automatiquement le focus au début d'une génération.
- Le clavier se ferme également lorsque la lecture vocale automatique commence.
- L'OCR local Apple Vision détecte automatiquement la langue du texte dans une image, sans téléchargement de modèle ni dépendance native supplémentaire.
- L'archivage des conversations et les exports TXT/Markdown restent inclus.

**Limite multimodale :** cette version propose l'OCR local (extraction de texte). Elle ne transmet pas encore les pixels au LLM pour décrire une scène, reconnaître des objets ou interpréter un graphique. Cette vraie vision nécessite une intégration MTMD complète et un XCFramework qui expose réellement les symboles MTMD, puis un test sur iPhone.

### Correctif de compilation 1.0.5
- Compatibilité avec le XCFramework fourni : suppression de l'accès à `llama_model_params.use_mmap`, absent de ses en-têtes. Le moteur conserve le comportement mmap par défaut de cette version ; le réglage de l'interface est conservé pour compatibilité, mais ne peut pas forcer ce paramètre avec ce binaire.
- Ajout du champ `Conversation.archived` optionnel afin que les anciennes conversations JSON sans ce champ restent décodables.
