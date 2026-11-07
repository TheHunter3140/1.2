# CHANGELOG — Pal

(L'historique de la 1.1.0 est dans `CHANGELOG-PAL.md`.)

## 1.2.0 — fiabilité, accès aux modèles, profils cohérents

Chaque modification porte un identifiant (C-xx) à citer dans tout retour de test.

| ID | Modification | Fichiers |
|---|---|---|
| C-01 | Le rappel de fin de téléchargement est branché dès le lancement de l'app (sans activer la session réseau). | `VM.swift` |
| C-02 | Un fichier plus petit que la taille annoncée est refusé comme « incomplet ». | `Downloads.swift` |
| C-03 | Après un téléchargement, le moteur vérifie le GGUF (chargement du vocabulaire seul) avant de le déclarer reconnu. Menu « Vérifier la compatibilité » sur les modèles du dossier Pal. En cas d'échec de chargement, le message distingue « modèle non reconnu » de « mémoire insuffisante ». | `Advisor.swift` (nouveau), `VM.swift`, `ModelsUI.swift` |
| C-04 | Plus aucune copie silencieuse d'un modèle : si l'accès en place échoue, l'alerte propose explicitement « Copier dans Pal ». | `ModelsUI.swift` |
| C-05 | iCloud Drive : un modèle non téléchargé est demandé au système, avec un message clair. | `VM.swift` |
| C-06 | Max et Ultra ne forcent plus le GPU sur un appareil non éligible ; Max repasse à un cache K/V f16 (les mesures montraient un préremplissage ralenti avec q8 + Flash Attention forcé). Les réglages Max/Ultra de la 1.1.0 sont migrés. | `VM.swift` |
| C-07 | Profil Éco : priorité de tâche basse et rafraîchissement du flux à 150 ms. iOS n'autorise pas une app à activer le mode économie d'énergie : Pal réduit seulement sa propre consommation. | `VM.swift` |
| C-08 | Réflexion désactivée : le moteur pré-remplit un bloc `<think>` vide (modèles dont le template contient des balises `<think>`). Plus de `/no_think` dans le message, plus de phrase ajoutée au prompt. Interrupteur dans les actions de la discussion et dans les réglages rapides. | `Engine.swift`, `VM.swift`, `UI.swift` |
| C-09 | Prompt système vide par défaut. L'ancienne phrase par défaut est retirée une fois ; un texte personnalisé est conservé. | `VM.swift` |
| C-10 | Bouton « Réglages rapides » dans la barre de la discussion (réflexion, performance, paramètres, prompt, mémoire, apparence). | `UI.swift` |
| C-11 | Messages neutres (plus de mention de l'appareil). Section « Recommandations » (Réglages › Performance) fondée sur la RAM, le stockage, le thermique, le mode économie d'énergie et les benchmarks enregistrés. Tuiles « RAM totale » et « Instr. CPU » dans le panneau de statistiques. | `Advisor.swift`, `SettingsUI.swift`, `UI.swift`, `VM.swift` |
| C-12 | Apparence par défaut alignée sur les captures de référence : police à empattements, accent cyan, tailles de texte au minimum. L'affichage en texte simple pendant la génération devient une option désactivée par défaut. Les réglages déjà enregistrés par l'utilisateur sont conservés. | `VM.swift`, `Library.swift`, `SettingsUI.swift` |
| C-13 | Correction d'un défaut de la 1.1.0 : les migrations de réglages n'étaient pas enregistrées (les observateurs ne s'exécutent pas dans `init`). Elles sont maintenant persistées. | `VM.swift` |

### Rectification de diagnostic
Le rapport d'audit désignait un rappel `onFinished` non branché comme explication principale du Qwen 3.5 non ajouté. Après relecture, l'app rescanne déjà le dossier au retour au premier plan : cette cause est peu probable. La cause la plus probable est un échec de chargement (architecture non prise en charge). C-03 sert précisément à le déterminer.

### Non modifié volontairement
`Engine.swift` n'a reçu que des ajouts ciblés (aucune réécriture). Aucune fonctionnalité supprimée.
