# Audit technique — Pal 1.0.1

Date : 6 novembre 2026  
Base analysée : archive source `Llama-IOS-1.0.1.zip` fournie dans la conversation.

## Résultat exécutif

Pal possède déjà une base fonctionnelle intéressante : application SwiftUI, moteur llama.cpp, bibliothèque GGUF, conversations persistantes, personas, skills manuelles, recherche Web, téléchargements Hugging Face, synthèse vocale et diagnostics de performances.

La bonne stratégie est une évolution progressive, et non une réécriture totale. La compilation iOS réelle reste à effectuer sur macOS avec Xcode et le XCFramework llama.cpp correspondant.

## Corrections appliquées dans cette copie de travail

1. **Réglage mmap réellement appliqué** — `Engine.load` recevait le booléen `mmap` mais ne le transmettait pas à `llama_model_params`. Le réglage `Lecture mmap` de l'interface n'avait donc aucun effet. La valeur est maintenant affectée à `modelParams.use_mmap`.
2. **Jeton Hugging Face** — suppression du repli permanent vers `UserDefaults`, qui stockait le jeton en clair. Les anciens jetons sont migrés vers le trousseau iOS lorsque l'écriture sécurisée réussit ; l'ancien emplacement est ensuite supprimé. En cas d'échec, le jeton n'est pas conservé en clair et l'interface reçoit un statut d'erreur.
3. **Validation GGUF** — un téléchargement n'est plus accepté si le fichier ne peut pas être ouvert pour vérifier sa signature. La signature `GGUF` doit être lue et correspondre exactement.
4. **Documentation** — le README décrit maintenant le téléchargeur Hugging Face déjà présent et documente la release `deps-1` attendue par le workflow.
5. **Exemples de skills** — ajout des deux fichiers Markdown annoncés dans le README mais absents de l'archive initiale.

## Vérifications effectuées

- `swiftc -frontend -parse Sources/*.swift` : réussi, aucune erreur de syntaxe Swift détectée.
- Analyse YAML du workflow GitHub Actions avec PyYAML : réussie.
- Inspection de l'archive : 20 entrées initiales, environ 224 Ko de sources et configuration.
- **Pas de compilation Xcode** : cet environnement ne possède ni Xcode ni SDK iOS. La présence, la compatibilité d'architecture et la signature du XCFramework ne sont donc pas certifiées.

## Points bloquants ou risques à traiter ensuite

### Priorité 0 — obtenir une compilation reproductible

- Le workflow attend une release `deps-1` dans le dépôt, avec l'asset exact `llama-b12130-xcframework.zip`. Cet asset n'est pas inclus dans l'archive source. Sans cette release, le workflow s'arrête avant XcodeGen.
- Vérifier que le XCFramework correspond exactement à l'API llama.cpp utilisée par `Engine.swift` et contient les tranches iOS appareil requises.
- Lancer le workflow GitHub Actions et corriger les erreurs de compilation/linkage réelles avant d'ajouter des fonctionnalités lourdes.

### Priorité 1 — robustesse du moteur et de la mémoire

- L'historique complet est reformatté et retokenisé à chaque tour. Quand le prompt dépasse le contexte, la génération échoue ; il n'existe pas encore de stratégie de réduction, de résumé ou de sélection des souvenirs.
- Ajouter un budget de contexte calculé en tokens, une conservation des derniers tours et un résumé optionnel contrôlé par l'utilisateur.
- Clarifier le comportement d'une erreur de décodage pendant la génération : le moteur interrompt actuellement la boucle et peut traiter une sortie partielle comme une réponse terminée.
- Mesurer séparément le coût du chargement, le préremplissage du prompt, la génération, la mémoire physique et la mémoire disponible.
- Valider sur appareil les profils CPU/GPU : le profil « Max » demande 99 couches GPU et 2048 tokens de contexte ; il ne doit pas être présenté comme sûr pour chaque appareil.

### Priorité 2 — skills et apprentissage assisté

- Les skills actuelles sont des instructions ajoutées au prompt, activées manuellement. Elles ne modifient pas les poids du GGUF.
- Ajouter une sélection automatique des skills pertinentes, avec score de pertinence, budget strict, priorité utilisateur et explication des skills retenues.
- Ajouter une fonction « proposer une skill depuis cette conversation » : Pal rédige un brouillon, l'utilisateur le vérifie et l'enregistre. Aucune modification silencieuse des skills ou du modèle.
- Prévoir versionnage, export, import, déduplication et validation des skills.

### Priorité 3 — recherche et outils

- La recherche DuckDuckGo dépend de la structure HTML de la page et ne lit pas automatiquement le contenu complet des pages sources.
- Créer une couche de fournisseurs de recherche interchangeable, avec délais, annulation, déduplication, cache et affichage de provenance.
- Introduire un registre d'outils explicite : description, paramètres, validation, permissions et confirmation avant toute action externe ou destructive.
- Traiter tout contenu web, document ou skill importé comme donnée non fiable ; ne jamais exécuter une instruction simplement parce qu'elle apparaît dans une source.

### Priorité 4 — vision et multimodal

- Le lien `mmproj` est mémorisé, mais le pipeline vision n'est pas implémenté. Ne pas afficher la vision comme fonction disponible avant l'encodage d'image et le passage des embeddings au modèle.
- Implémenter la vision seulement après compilation stable, en vérifiant la compatibilité architecture/modèle et le coût RAM sur iPhone XR.

## Principes d'architecture retenus

- Préserver SwiftUI et le moteur llama.cpp existants tant qu'ils sont validés.
- Séparer moteur, mémoire, skills, recherche, outils et interface par petites étapes.
- Garder le fonctionnement local comme comportement par défaut ; le réseau est optionnel et explicite.
- Aucun fine-tuning prétendu : « apprendre » signifie d'abord acquérir, organiser et réutiliser des skills et souvenirs vérifiés.
- Toute fonctionnalité lourde doit pouvoir être désactivée et respecter un budget mémoire.

## État de cette livraison

Cette archive est une **copie de développement avec corrections statiques**, pas une IPA compilée ni une version validée sur iPhone. Le prochain jalon doit être le premier build Xcode réussi, puis un test sur appareil avant d'élargir l'architecture.


## Mise à jour 1.0.3-dev — portée et limites

### Ajouts dans cette copie
- Archivage des conversations (champ optionnel rétrocompatible), vues Actives/Archivées, désarchivage, export TXT/Markdown via feuille de partage iOS.
- Saisie agrandie et fermeture du clavier à l'envoi ; liste de voix élargie à toutes les voix que `AVSpeechSynthesisVoice` expose.
- Réglage de taille générale de l'interface distinct de la taille des messages, personnalisation des bulles, profil Ultra, sauvegarde/restauration de Perso, valeurs libres par pas pour le contexte, réglage batch, réinitialisations ciblées.
- Mode sans réflexion par instruction et `/no_think` sur Qwen3 ; bouton Continuer après atteinte de la limite de tokens.
- Import de PDF/texte/RTF et tentative Word ; OCR Vision local sur image.
- Capteurs : taille du fichier modèle et tokens du contexte/KV.

### Non implémenté / non certifiable sans la dépendance native
- Le modèle reçoit actuellement le texte OCR, pas les pixels : la vraie vision nécessite l'intégration de l'API mtmd/mmproj compatible avec le `llama.xcframework` livré au build. Le simple fichier mmproj ne suffit pas.
- Flash Attention et choix des types K/V du cache ne sont pas exposés par le code Swift présent ; impossible de relier correctement ces options sans les en-têtes et la version du framework. Le cache KV actuel est vidé puis reconstruit à chaque tour.
- Les voix internes de Siri ne sont sélectionnables que si iOS les expose dans `AVSpeechSynthesisVoice.speechVoices()` ; l'app ne peut pas forcer l'accès aux voix privées du système.
- L'extraction Word dépend des formats que la version iOS supporte via `NSAttributedString`; DOCX n'est donc pas garantie.
- Pas de compilation ni test sur appareil : Xcode et `llama.xcframework` restent absents du conteneur d'audit.


## Mise à jour 1.0.4-dev — améliorations à faible risque

- Fermeture automatique du clavier au début de la génération et au démarrage de la lecture vocale.
- Détection automatique de la langue pour l'OCR Apple Vision local.
- Aucun ajout de framework tiers ni de modèle vision obligatoire : l'application conserve le chemin de compilation existant.

La fonction image est un OCR (texte extrait de l'image), pas encore une vision multimodale native du LLM. L'intégration MTMD n'est pas activée dans le code Swift tant que la compatibilité réelle du XCFramework et de ses symboles n'a pas été vérifiée.

### Correctif de compilation 1.0.5
- Compatibilité avec le XCFramework fourni : suppression de l'accès à `llama_model_params.use_mmap`, absent de ses en-têtes. Le moteur conserve le comportement mmap par défaut de cette version ; le réglage de l'interface est conservé pour compatibilité, mais ne peut pas forcer ce paramètre avec ce binaire.
- Ajout du champ `Conversation.archived` optionnel afin que les anciennes conversations JSON sans ce champ restent décodables.
